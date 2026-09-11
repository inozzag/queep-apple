#!/bin/sh
set -eu
[ "${CONFIGURATION}" = "Release" ] || exit 0
case "${QUEEP_REVENUECAT_PUBLIC_KEY:-}" in
  appl_?*) ;;
  *) echo "error: Release requires an Apple RevenueCat public key; Test Store is forbidden."; exit 1 ;;
esac
for address in "${QUEEP_PRIVACY_URL:-}" "${QUEEP_TERMS_URL:-}"; do
  case "$address" in
    https://?*.?*) ;;
    *) echo "error: Release requires published HTTPS privacy and terms URLs."; exit 1 ;;
  esac
done
