#!/usr/bin/env bash
# Checks the public DNS records SES sending depends on: DKIM, custom MAIL FROM (MX + SPF), root SPF
# and DMARC. Read-only (dig).
#   check-dns.sh <domain> [--mail-from mail.example.com] [--region eu-west-1] [--dkim tok1,tok2,tok3]
# DKIM tokens come from the SES console or check-account.sh (their record names are random).
set -uo pipefail
usage() { echo "usage: $0 <domain> [--mail-from <subdomain>] [--region <region>] [--dkim tok1,tok2,tok3]" >&2; exit 2; }
[ $# -ge 1 ] || usage
DOMAIN=$1; shift; MAILFROM=""; REGION=""; DKIM=""
while [ $# -gt 0 ]; do
  case $1 in
    --mail-from) MAILFROM=$2; shift 2 ;; --region) REGION=$2; shift 2 ;; --dkim) DKIM=$2; shift 2 ;; *) usage ;;
  esac
done
command -v dig >/dev/null || { echo "dig not found" >&2; exit 2; }
NFAIL=0; NWARN=0
pass() { echo "PASS  $*"; }; warn() { echo "WARN  $*"; NWARN=$((NWARN + 1)); }; fail() { echo "FAIL  $*"; NFAIL=$((NFAIL + 1)); }; info() { echo "INFO  $*"; }
txt() { dig +short TXT "$1" | sed 's/" "//g; s/^"//; s/"$//'; }

echo "# SES DNS check: $DOMAIN"
echo; echo "## DKIM"
if [ -z "$DKIM" ]; then
  info "no --dkim tokens given: can't look the records up (their names are random). Get them from the SES console or check-account.sh"
else
  for t in $(echo "$DKIM" | tr ',' ' '); do
    got=$(dig +short CNAME "$t._domainkey.$DOMAIN" | sed 's/\.$//')
    if [ "$got" = "$t.dkim.amazonses.com" ]; then pass "$t._domainkey → $got"
    elif [ -z "$got" ]; then fail "$t._domainkey.$DOMAIN has no CNAME (expected $t.dkim.amazonses.com)"
    else fail "$t._domainkey.$DOMAIN → $got (expected $t.dkim.amazonses.com)"; fi
  done
fi

echo; echo "## Custom MAIL FROM"
if [ -z "$MAILFROM" ]; then
  info "no --mail-from given. Without a custom MAIL FROM, SPF aligns to amazonses.com, not your domain, so DMARC relies on DKIM alone (fine if DKIM passes, but set one up)"
else
  mx=$(dig +short MX "$MAILFROM" | sed 's/\.$//')
  if [ -z "$mx" ]; then fail "$MAILFROM has no MX (SES expects 10 feedback-smtp.<region>.amazonses.com)"
  else
    echo "$mx" | grep -q 'feedback-smtp\.[a-z0-9-]*\.amazonses\.com' && pass "$MAILFROM MX → $mx" || fail "$MAILFROM MX → $mx (not an SES feedback host)"
    if [ -n "$REGION" ]; then
      echo "$mx" | grep -q "feedback-smtp.$REGION.amazonses.com" && pass "MX region matches $REGION" || fail "MX points at another region than $REGION: SES marks the MAIL FROM as failed"
    fi
  fi
  spf=$(txt "$MAILFROM" | grep -i '^v=spf1')
  if [ -z "$spf" ]; then fail "$MAILFROM has no SPF record (expected \"v=spf1 include:amazonses.com ~all\")"
  elif echo "$spf" | grep -q 'include:amazonses.com'; then pass "$MAILFROM SPF: $spf"
  else fail "$MAILFROM SPF doesn't include amazonses.com: $spf"; fi
fi

echo; echo "## Root SPF"
n=$(txt "$DOMAIN" | grep -ci '^v=spf1')
root=$(txt "$DOMAIN" | grep -i '^v=spf1')
if [ "$n" -gt 1 ]; then fail "$DOMAIN has $n SPF records: receivers treat that as an error. Merge them into one"
elif [ "$n" = 0 ]; then info "$DOMAIN has no SPF record (fine for SES with a custom MAIL FROM; other mail from the domain may need one)"
else
  info "$DOMAIN SPF: $root"
  if [ -z "$MAILFROM" ] && ! echo "$root" | grep -q amazonses; then info "SES isn't in the root SPF; that's expected (SES mail uses its own MAIL FROM domain)"; fi
  echo "$root" | grep -q '+all' && fail "root SPF ends in +all: anyone may send as $DOMAIN"
fi

echo; echo "## DMARC"
dmarc=$(txt "_dmarc.$DOMAIN" | grep -i '^v=DMARC1')
if [ -z "$dmarc" ]; then warn "no DMARC record at _dmarc.$DOMAIN. Add at least \"v=DMARC1; p=none; rua=mailto:<you>\" and tighten later"
else
  policy=$(echo "$dmarc" | sed -nE 's/.*p=([a-z]+).*/\1/p')
  case $policy in
    reject|quarantine) pass "DMARC p=$policy: unauthenticated mail is rejected or sent to spam, so DKIM must pass" ;;
    none) info "DMARC p=none (monitoring only). Move to quarantine once reports show DKIM passing" ;;
    *) warn "DMARC record without a valid p= tag: $dmarc" ;;
  esac
  echo "$dmarc" | grep -q 'rua=' || info "DMARC has no rua= address, so you get no aggregate reports"
fi

echo; echo "# Summary: $NFAIL fail, $NWARN warn"
[ $NFAIL = 0 ]
