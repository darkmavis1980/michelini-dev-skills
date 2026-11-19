#!/usr/bin/env bash
# Reads the SES account and a domain identity: production access, quota, suppression list, DKIM and
# MAIL FROM status, and the DKIM tokens to feed check-dns.sh. Read-only.
#   check-account.sh <domain> [--profile <aws-profile>] [--region eu-west-1]
# Needs ses:GetAccount and ses:GetEmailIdentity (an app's send-only IAM user won't have them).
set -uo pipefail
usage() { echo "usage: $0 <domain> [--profile <aws-profile>] [--region <region>]" >&2; exit 2; }
[ $# -ge 1 ] || usage
DOMAIN=$1; shift; AWSARGS=(); REGION=${AWS_REGION:-eu-west-1}
while [ $# -gt 0 ]; do
  case $1 in --profile) AWSARGS+=(--profile "$2"); shift 2 ;; --region) REGION=$2; shift 2 ;; *) usage ;; esac
done
command -v aws >/dev/null || { echo "aws CLI not found" >&2; exit 2; }
ses() { aws ${AWSARGS[@]+"${AWSARGS[@]}"} --region "$REGION" sesv2 "$@" 2>"$ERR"; }
ERR=$(mktemp); trap 'rm -f "$ERR"' EXIT
denied() { grep -q 'AccessDenied' "$ERR" && { echo "FAIL  $1: access denied — this identity needs $2 (read-only). Add it to the profile you use for admin tasks, or use one that has it"; return 0; }; echo "FAIL  $1: $(head -c 300 "$ERR")"; }

echo "# SES account check ($REGION) for $DOMAIN"
echo; echo "## Account"
if out=$(ses get-account --query '[ProductionAccessEnabled, SendingEnabled, EnforcementStatus, SendQuota.Max24HourSend, SendQuota.MaxSendRate, SuppressionAttributes.SuppressedReasons]' --output text); then
  read -r prod sending enforce quota rate reasons <<<"$(echo "$out" | tr '\n\t' '  ')"
  [ "$prod" = True ] && echo "PASS  production access (out of the sandbox): $quota emails / 24 h, $rate / s" \
    || echo "FAIL  still in the sandbox: only verified recipients, $quota / 24 h. Request production access (Account dashboard)"
  [ "$sending" = True ] && echo "PASS  sending enabled" || echo "FAIL  sending is disabled for this account"
  [ "$enforce" = HEALTHY ] && echo "PASS  enforcement status HEALTHY" || echo "WARN  enforcement status $enforce: check bounce and complaint rates in the Reputation metrics"
  case "$reasons" in *BOUNCE*COMPLAINT*|*COMPLAINT*BOUNCE*) echo "PASS  account suppression list covers bounces and complaints" ;;
    *) echo "WARN  account suppression list reasons: '${reasons}'. Enable BOUNCE and COMPLAINT so SES stops sending to bad addresses" ;; esac
else denied "get-account" "ses:GetAccount"; fi

echo; echo "## Identity $DOMAIN"
if out=$(ses get-email-identity --email-identity "$DOMAIN" --query '[VerificationStatus, DkimAttributes.Status, MailFromAttributes.MailFromDomain, MailFromAttributes.MailFromDomainStatus, MailFromAttributes.BehaviorOnMxFailure]' --output text); then
  read -r verif dkim mfrom mstatus mbehav <<<"$(echo "$out" | tr '\n\t' '  ')"
  [ "$verif" = SUCCESS ] && echo "PASS  identity verified" || echo "FAIL  identity verification: $verif"
  [ "$dkim" = SUCCESS ] && echo "PASS  DKIM: SUCCESS" || echo "FAIL  DKIM: $dkim (check the three CNAMEs with check-dns.sh --dkim)"
  if [ "$mfrom" = None ] || [ -z "$mfrom" ]; then echo "WARN  no custom MAIL FROM domain (SPF won't align with $DOMAIN)"
  else
    [ "$mstatus" = SUCCESS ] && echo "PASS  MAIL FROM $mfrom: SUCCESS" || echo "FAIL  MAIL FROM $mfrom: $mstatus"
    echo "INFO  on MX failure: $mbehav"
  fi
  tokens=$(ses get-email-identity --email-identity "$DOMAIN" --query 'DkimAttributes.Tokens' --output text | tr '\t' ',')
  [ -n "$tokens" ] && echo "INFO  DKIM tokens: $tokens" && echo "INFO  next: check-dns.sh $DOMAIN --dkim $tokens${mfrom:+ --mail-from $mfrom} --region $REGION"
else denied "get-email-identity" "ses:GetEmailIdentity"; fi
