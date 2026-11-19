#!/usr/bin/env bash
# Creates or re-applies a private S3 bucket's configuration: ACLs disabled, all public access blocked,
# versioning, SSE-S3, a TLS-only bucket policy, lifecycle rules and (optionally) CORS for browser
# uploads. Idempotent: re-running re-applies the same settings. Run check-bucket.sh afterwards.
#
#   setup-bucket.sh <bucket> [--region eu-west-1] [--profile admin] [--origin https://app.example.com]...
#                   [--lifecycle file.json] [--dry-run]
#
# Needs an identity allowed to create and configure buckets (an admin profile), never the app's keys.
set -Eeuo pipefail   # -E: the ERR trap also fires inside functions
HERE="$(cd "$(dirname "$0")" && pwd)"; TPL="$HERE/../templates"
usage() { echo "usage: $0 <bucket> [--region r] [--profile p] [--origin url]... [--lifecycle file] [--dry-run]" >&2; exit 2; }
[ $# -ge 1 ] || usage
BUCKET=$1; shift; REGION=eu-west-1; PROFILE=(); ORIGINS=(); LIFECYCLE="$TPL/lifecycle.json"; DRY=0
while [ $# -gt 0 ]; do
  case $1 in
    --region) REGION=$2; shift 2 ;; --profile) PROFILE=(--profile "$2"); shift 2 ;;
    --origin) ORIGINS+=("$2"); shift 2 ;; --lifecycle) LIFECYCLE=$2; shift 2 ;; --dry-run) DRY=1; shift ;; *) usage ;;
  esac
done
TMP=$(mktemp -d); STEP="start"
trap 'rm -rf "$TMP"' EXIT
trap 'echo "✗ step \"$STEP\" failed — nothing after it was applied. Fix the cause and re-run (it is idempotent)." >&2' ERR
aws_() { if [ $DRY = 1 ]; then echo "  [dry-run] aws ${PROFILE[*]-} --region $REGION $*"; else aws ${PROFILE[@]+"${PROFILE[@]}"} --region "$REGION" "$@"; fi; }
step() { STEP=$1; echo "→ $1"; }

step "bucket s3://$BUCKET in $REGION"
# head-bucket is read-only, so the dry run checks it too.
if aws ${PROFILE[@]+"${PROFILE[@]}"} --region "$REGION" s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then echo "  exists"
elif [ "$REGION" = us-east-1 ]; then aws_ s3api create-bucket --bucket "$BUCKET" --object-ownership BucketOwnerEnforced
else aws_ s3api create-bucket --bucket "$BUCKET" --object-ownership BucketOwnerEnforced --create-bucket-configuration "LocationConstraint=$REGION"; fi

step "ACLs disabled (BucketOwnerEnforced)"
aws_ s3api put-bucket-ownership-controls --bucket "$BUCKET" --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'

step "block all public access"
aws_ s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

step "versioning on"
aws_ s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled

step "default encryption (SSE-S3)"
aws_ s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

step "bucket policy (deny non-TLS requests)"
sed "s/__BUCKET__/$BUCKET/g" "$TPL/bucket-policy.json" > "$TMP/policy.json"
aws_ s3api put-bucket-policy --bucket "$BUCKET" --policy "file://$TMP/policy.json"

step "lifecycle rules ($(basename "$LIFECYCLE"))"
aws_ s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" --lifecycle-configuration "file://$LIFECYCLE"

if [ ${#ORIGINS[@]} -gt 0 ]; then
  step "CORS for browser PUT uploads from: ${ORIGINS[*]}"
  json=$(printf '"%s",' "${ORIGINS[@]}")
  sed "s|\"__ORIGINS__\"|${json%,}|" "$TPL/cors.json" > "$TMP/cors.json"
  aws_ s3api put-bucket-cors --bucket "$BUCKET" --cors-configuration "file://$TMP/cors.json"
else
  echo "→ CORS skipped (no --origin): fine if browsers never upload directly. An existing CORS config is left as it is."
fi

STEP="done"
echo "✓ s3://$BUCKET configured. Next: check-bucket.sh $BUCKET --region $REGION ${PROFILE[*]-} $(printf -- '--origin %s ' ${ORIGINS[@]+"${ORIGINS[@]}"})"
