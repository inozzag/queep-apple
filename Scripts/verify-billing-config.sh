#!/bin/sh
set -eu
case "${CONFIGURATION}" in
  Release|TestFlight) ;;
  *) exit 0 ;;
esac
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

if [ "${CONFIGURATION}" = "TestFlight" ]; then
  [ "${QUEEP_FIREBASE_PROJECT_ID:-}" = "queep-dev-hstlx" ] || {
    echo "error: TestFlight sandbox requires the configured development Firebase project."; exit 1;
  }
  case "${QUEEP_API_URL:-}" in
    https://?*.?*) ;;
    *) echo "error: TestFlight requires an isolated HTTPS API with billing required."; exit 1 ;;
  esac
  case "${QUEEP_API_URL}" in
    *queep-api-721281571441*) echo "error: Do not use the shared development API for TestFlight billing."; exit 1 ;;
  esac
fi
