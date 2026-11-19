// Example storage module for a private S3 bucket (Node, AWS SDK v3): browser multipart uploads via
// presigned part URLs, server-side streaming, version-exact presigned downloads.
import { createReadStream, createWriteStream } from 'node:fs';
import type { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import {
  AbortMultipartUploadCommand,
  CompleteMultipartUploadCommand,
  CreateMultipartUploadCommand,
  DeleteObjectCommand,
  GetObjectCommand,
  NoSuchUpload,
  S3Client,
  UploadPartCommand,
} from '@aws-sdk/client-s3';
import { Upload } from '@aws-sdk/lib-storage';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

export interface UploadedPart {
  partNumber: number;
  etag: string;
}

/**
 * A private bucket behind an interface, so routes and workers can be tested with an in-memory fake;
 * `s3Storage` is the real one. Nothing here ever makes an object public: uploads and downloads go
 * through short-lived presigned URLs.
 */
export interface FileStorage {
  createMultipartUpload(key: string, contentType: string): Promise<string>;
  /** Presigned URL the browser PUTs one part to; the response's ETag header goes to `complete`. */
  presignUploadPart(key: string, uploadId: string, partNumber: number, expiresInSeconds: number): Promise<string>;
  completeMultipartUpload(key: string, uploadId: string, parts: UploadedPart[]): Promise<void>;
  /** Idempotent: an already-completed or unknown upload is not an error. */
  abortMultipartUpload(key: string, uploadId: string): Promise<void>;
  /** Streams an object to a local file. Returns the version id read. */
  downloadToFile(key: string, path: string): Promise<{ versionId: string | undefined }>;
  /** Uploads a local file (multipart for big ones). Returns the new version id. */
  uploadFile(
    key: string,
    path: string,
    opts: { contentType: string; metadata?: Record<string, string> },
  ): Promise<{ versionId: string | undefined }>;
  /** With a version id: deletes that version for good. Without: adds a delete marker (recoverable). */
  deleteObject(key: string, versionId?: string): Promise<void>;
  /**
   * Presigned GET of one exact version, served as an attachment named `filename` (keys have no
   * extension). Issue it only after the app's own access checks, with a short expiry (e.g. 300 s).
   */
  presignDownload(
    key: string,
    versionId: string,
    opts: { filename: string; contentType: string; expiresInSeconds: number },
  ): Promise<string>;
}

/** `attachment` with an ASCII fallback name plus the RFC 6266 UTF-8 form. */
export function contentDisposition(filename: string): string {
  const ascii = filename.replace(/[^\x20-\x7e]/g, '_').replace(/["\\]/g, '_');
  const utf8 = encodeURIComponent(filename).replace(/['()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
  return `attachment; filename="${ascii}"; filename*=UTF-8''${utf8}`;
}

export interface S3StorageOptions {
  bucket: string;
  region: string;
  endpoint?: string;
  forcePathStyle?: boolean;
  credentials?: { accessKeyId: string; secretAccessKey: string };
}

export function s3Storage(opts: S3StorageOptions): FileStorage {
  const client = new S3Client({
    region: opts.region,
    endpoint: opts.endpoint,
    forcePathStyle: opts.forcePathStyle,
    credentials: opts.credentials,
    // Presigned part URLs are PUT by the browser, which can't compute SDK checksums — only send a
    // checksum when an operation requires one.
    requestChecksumCalculation: 'WHEN_REQUIRED',
    responseChecksumValidation: 'WHEN_REQUIRED',
  });
  const Bucket = opts.bucket;
  // Encryption at rest is the bucket's default (SSE-S3, set by setup-bucket.sh) rather than a
  // per-request header, which some S3-compatible stores reject.

  return {
    async createMultipartUpload(key, contentType) {
      const out = await client.send(new CreateMultipartUploadCommand({ Bucket, Key: key, ContentType: contentType }));
      if (!out.UploadId) throw new Error('S3 returned no UploadId');
      return out.UploadId;
    },

    presignUploadPart(key, uploadId, partNumber, expiresInSeconds) {
      return getSignedUrl(
        client,
        new UploadPartCommand({ Bucket, Key: key, UploadId: uploadId, PartNumber: partNumber }),
        { expiresIn: expiresInSeconds },
      );
    },

    async completeMultipartUpload(key, uploadId, parts) {
      await client.send(
        new CompleteMultipartUploadCommand({
          Bucket,
          Key: key,
          UploadId: uploadId,
          MultipartUpload: { Parts: parts.map((p) => ({ PartNumber: p.partNumber, ETag: p.etag })) },
        }),
      );
    },

    async abortMultipartUpload(key, uploadId) {
      try {
        await client.send(new AbortMultipartUploadCommand({ Bucket, Key: key, UploadId: uploadId }));
      } catch (err) {
        if (!(err instanceof NoSuchUpload)) throw err;
      }
    },

    async downloadToFile(key, path) {
      const out = await client.send(new GetObjectCommand({ Bucket, Key: key }));
      if (!out.Body) throw new Error(`S3 returned no body for ${key}`);
      await pipeline(out.Body as Readable, createWriteStream(path));
      return { versionId: out.VersionId };
    },

    async uploadFile(key, path, { contentType, metadata }) {
      const upload = new Upload({
        client,
        params: {
          Bucket,
          Key: key,
          Body: createReadStream(path),
          ContentType: contentType,
          Metadata: metadata,
        },
        partSize: 16 * 1024 * 1024,
        queueSize: 4,
      });
      const out = await upload.done();
      return { versionId: out.VersionId };
    },

    async deleteObject(key, versionId) {
      await client.send(new DeleteObjectCommand({ Bucket, Key: key, VersionId: versionId }));
    },

    presignDownload(key, versionId, { filename, contentType, expiresInSeconds }) {
      return getSignedUrl(
        client,
        new GetObjectCommand({
          Bucket,
          Key: key,
          VersionId: versionId,
          ResponseContentDisposition: contentDisposition(filename),
          ResponseContentType: contentType,
        }),
        { expiresIn: expiresInSeconds },
      );
    },
  };
}
