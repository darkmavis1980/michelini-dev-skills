#!/usr/bin/env bash
# Sends one test email through SES. Defaults to the SES mailbox simulator, which accepts the message
# without delivering it and doesn't affect the account's reputation (works in the sandbox too).
#   send-test.sh --from shop@example.com [--to success@simulator.amazonses.com] [--profile p] [--region r]
# Simulator addresses: success@, bounce@, complaint@, suppressionlist@ (all @simulator.amazonses.com).
set -uo pipefail
usage() { echo "usage: $0 --from <address> [--to <address>] [--profile <aws-profile>] [--region <region>]" >&2; exit 2; }
FROM=""; TO=success@simulator.amazonses.com; AWSARGS=(); REGION=${AWS_REGION:-eu-west-1}
while [ $# -gt 0 ]; do
  case $1 in --from) FROM=$2; shift 2 ;; --to) TO=$2; shift 2 ;; --profile) AWSARGS+=(--profile "$2"); shift 2 ;;
    --region) REGION=$2; shift 2 ;; *) usage ;; esac
done
[ -n "$FROM" ] || usage
case $TO in *@simulator.amazonses.com) ;; *) echo "note: $TO is a real mailbox; a real email will be delivered" >&2 ;; esac
content=$(printf '{"Simple":{"Subject":{"Data":"SES test","Charset":"UTF-8"},"Body":{"Text":{"Data":"Test message sent with send-test.sh at %s.","Charset":"UTF-8"}}}}' "$(date -u +%FT%TZ)")
if id=$(aws ${AWSARGS[@]+"${AWSARGS[@]}"} --region "$REGION" sesv2 send-email --from-email-address "$FROM" \
     --destination "ToAddresses=$TO" --content "$content" --query MessageId --output text 2>&1); then
  echo "PASS  accepted by SES, MessageId $id"
else
  echo "FAIL  $(echo "$id" | grep -v "^ *$" | tr "\n" " ")"
  case $id in
    *MessageRejected*) echo "      The From address or domain isn't verified in $REGION, or (in the sandbox) the recipient isn't verified." ;;
    *AccessDenied*) echo "      This identity lacks ses:SendEmail on the From identity (check the IAM policy's resource and ses:FromAddress condition)." ;;
  esac
  exit 1
fi
