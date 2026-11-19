#!/usr/bin/env bash
# Reads a private bucket's configuration back and tests it from the outside. Everything is read-only
# except --roundtrip, which writes, reads and permanently deletes one small test object.
#
#   check-bucket.sh <bucket> [--region eu-west-1] [--profile admin] [--origin https://app.example.com]...
#                   [--app-profile app] [--roundtrip staging/check/]
#
#   --profile      identity that can read bucket settings (admin); without it, settings aren't read
#   --origin       browser origins that must be allowed to PUT (a foreign origin is tested as well)
#   --app-profile  the app's own keys: they must NOT be able to read bucket settings
#   --roundtrip    with --app-profile: put / get by version / delete that version under this prefix
set -uo pipefail
usage() { echo "usage: $0 <bucket> [--region r] [--profile p] [--origin url]... [--app-profile p] [--roundtrip prefix/]" >&2; exit 2; }
[ $# -ge 1 ] || usage
BUCKET=$1; shift; REGION=eu-west-1; ADMIN=(); APP=(); ORIGINS=(); ROUNDTRIP=""
while [ $# -gt 0 ]; do
  case $1 in
    --region) REGION=$2; shift 2 ;; --profile) ADMIN=(--profile "$2"); shift 2 ;; --app-profile) APP=(--profile "$2"); shift 2 ;;
    --origin) ORIGINS+=("$2"); shift 2 ;; --roundtrip) ROUNDTRIP=$2; shift 2 ;; *) usage ;;
  esac
done
NFAIL=0; NWARN=0
pass() { echo "PASS  $*"; }; warn() { echo "WARN  $*"; NWARN=$((NWARN + 1)); }; fail() { echo "FAIL  $*"; NFAIL=$((NFAIL + 1)); }; info() { echo "INFO  $*"; }
ERR=$(mktemp); trap 'rm -f "$ERR"' EXIT
adm() { aws ${ADMIN[@]+"${ADMIN[@]}"} --region "$REGION" s3api "$@" --bucket "$BUCKET" 2>"$ERR"; }
missing() { grep -Eq "$1" "$ERR"; }
HOST="$BUCKET.s3.$REGION.amazonaws.com"

echo "# Bucket check: s3://$BUCKET ($REGION)"

if [ ${#ADMIN[@]} -gt 0 ]; then
  echo; echo "## Settings (read with ${ADMIN[1]})"
  v=$(adm get-bucket-versioning --query Status --output text)
  [ "$v" = Enabled ] && pass "versioning Enabled" || fail "versioning is '${v:-never enabled}': replaced or deleted objects can't be recovered"
  if v=$(adm get-public-access-block --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' --output text); then
    [ "$(echo $v)" = "True True True True" ] && pass "all public access blocked" || fail "public access block not complete: $v"
  else fail "no public access block on the bucket"; fi
  if v=$(adm get-bucket-encryption --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text); then pass "default encryption $v"; else fail "no default encryption"; fi
  if v=$(adm get-bucket-ownership-controls --query 'OwnershipControls.Rules[0].ObjectOwnership' --output text); then
    [ "$v" = BucketOwnerEnforced ] && pass "ACLs disabled (BucketOwnerEnforced)" || warn "object ownership $v: ACLs still apply"
  else warn "no ownership controls (ACLs may apply)"; fi
  if v=$(adm get-bucket-policy --query Policy --output text); then
    echo "$v" | grep -q 'aws:SecureTransport' && pass "bucket policy denies non-TLS requests" || warn "bucket policy has no aws:SecureTransport deny"
    echo "$v" | grep -Eq '"Principal" *: *"\*"' && echo "$v" | grep -q '"Allow"' && fail "bucket policy allows Principal \"*\": check it isn't public"
  elif missing NoSuchBucketPolicy; then fail "no bucket policy (setup stopped before this step?)"; else fail "bucket policy: $(head -c 200 "$ERR")"; fi
  if v=$(adm get-bucket-lifecycle-configuration --query 'Rules[].[ID,Status]' --output text); then
    pass "lifecycle rules: $(echo "$v" | tr '\t\n' ': ' | sed 's/ $//')"
    adm get-bucket-lifecycle-configuration --output json | grep -q AbortIncompleteMultipartUpload || warn "no rule aborting incomplete multipart uploads (abandoned parts are billed forever)"
  elif missing NoSuchLifecycleConfiguration; then fail "no lifecycle rules (old versions and abandoned uploads are kept and billed forever)"; else fail "lifecycle: $(head -c 200 "$ERR")"; fi
  if v=$(adm get-bucket-cors --query 'CORSRules[].[AllowedMethods[0],join(`,`,AllowedOrigins)]' --output text); then info "CORS: $(echo "$v" | tr '\t\n' '  ')"
  elif missing NoSuchCORSConfiguration; then
    [ ${#ORIGINS[@]} -gt 0 ] && fail "no CORS configuration, but browser origins were given" || info "no CORS configuration (fine if browsers never upload directly)"
  else fail "CORS: $(head -c 200 "$ERR")"; fi
else
  echo; info "no --profile: bucket settings not read (only the outside checks below)"
fi

echo; echo "## From outside (no credentials)"
s=$(curl -s -o /dev/null -w '%{http_code}' "https://$HOST/"); [ "$s" = 403 ] && pass "anonymous listing refused (403)" || fail "anonymous listing returned $s"
s=$(curl -s -o /dev/null -w '%{http_code}' "https://$HOST/check-bucket-probe"); case $s in 403|404) pass "anonymous object read refused ($s)" ;; *) fail "anonymous object read returned $s" ;; esac
s=$(curl -s -o /dev/null -w '%{http_code}' "http://$HOST/check-bucket-probe"); [ "$s" = 403 ] && pass "plain HTTP refused (403)" || warn "plain HTTP returned $s (expected 403 from the TLS-only policy)"
preflight() { curl -s -o /dev/null -D - -X OPTIONS "https://$HOST/staging/probe?partNumber=1&uploadId=x" -H "Origin: $1" -H "Access-Control-Request-Method: PUT" -H "Access-Control-Request-Headers: content-type" | tr -d '\r'; }
for o in ${ORIGINS[@]+"${ORIGINS[@]}"}; do
  h=$(preflight "$o"); code=$(echo "$h" | head -1 | awk '{print $2}')
  if [ "$code" = 200 ] && echo "$h" | grep -qi "^access-control-allow-origin: $o$"; then
    echo "$h" | grep -qi '^access-control-expose-headers:.*etag' && pass "browser PUT from $o allowed, ETag readable" || fail "PUT from $o allowed but ETag not exposed (multipart completion needs it)"
  else fail "browser PUT from $o refused ($code): add it with setup-bucket.sh --origin"; fi
done
h=$(preflight https://check-bucket.invalid); code=$(echo "$h" | head -1 | awk '{print $2}')
[ "$code" = 403 ] && pass "foreign origin refused (403)" || fail "foreign origin got $code: CORS is too open"

if [ ${#APP[@]} -gt 0 ]; then
  echo; echo "## App identity (${APP[1]})"
  arn=$(aws "${APP[@]}" sts get-caller-identity --query Arn --output text 2>/dev/null | sed -E 's/::[0-9]+:/::<account>:/')
  info "keys belong to ${arn:-unknown}"
  if aws "${APP[@]}" --region "$REGION" s3api get-bucket-cors --bucket "$BUCKET" >/dev/null 2>"$ERR" || missing NoSuchCORSConfiguration; then
    warn "the app's keys can read bucket settings: broader than an app needs (attach only the least-privilege policy)"
  elif missing AccessDenied; then pass "the app's keys can't read bucket settings (restricted)"
  else warn "couldn't tell: $(head -c 200 "$ERR")"; fi
  if [ -n "$ROUNDTRIP" ]; then
    key="${ROUNDTRIP%/}/check-bucket-$(date +%s)"
    if vid=$(echo check | aws "${APP[@]}" --region "$REGION" s3api put-object --bucket "$BUCKET" --key "$key" --body /dev/stdin --query VersionId --output text 2>"$ERR") \
      && aws "${APP[@]}" --region "$REGION" s3api get-object --bucket "$BUCKET" --key "$key" --version-id "$vid" /dev/null >/dev/null 2>>"$ERR" \
      && aws "${APP[@]}" --region "$REGION" s3api delete-object --bucket "$BUCKET" --key "$key" --version-id "$vid" >/dev/null 2>>"$ERR"; then
      pass "app round trip under $ROUNDTRIP: put, get by version, delete that version (cleaned up)"
    else fail "app round trip under $ROUNDTRIP failed at $key: $(tail -c 200 "$ERR")"; fi
  fi
fi

echo; echo "# Summary: $NFAIL fail, $NWARN warn"
[ $NFAIL = 0 ]
