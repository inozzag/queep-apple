#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export QUEEP_PRIVACY_URL=https://example.test/privacy QUEEP_TERMS_URL=https://example.test/terms
export QUEEP_FIREBASE_PROJECT_ID=queep-dev-hstlx QUEEP_API_URL=https://isolated.example.test
for config in Release TestFlight; do
  if CONFIGURATION=$config QUEEP_REVENUECAT_PUBLIC_KEY=test_fixture sh Scripts/verify-billing-config.sh >/dev/null 2>&1; then
    echo "FAIL: $config accepted Test Store"; exit 1
  fi
  if CONFIGURATION=$config QUEEP_REVENUECAT_PUBLIC_KEY= sh Scripts/verify-billing-config.sh >/dev/null 2>&1; then
    echo "FAIL: $config accepted a missing key"; exit 1
  fi
  CONFIGURATION=$config QUEEP_REVENUECAT_PUBLIC_KEY=appl_fixture sh Scripts/verify-billing-config.sh
  if CONFIGURATION=$config QUEEP_REVENUECAT_PUBLIC_KEY=appl_fixture QUEEP_TERMS_URL= sh Scripts/verify-billing-config.sh >/dev/null 2>&1; then
    echo "FAIL: $config accepted missing terms"; exit 1
  fi
done
if CONFIGURATION=TestFlight QUEEP_REVENUECAT_PUBLIC_KEY=appl_fixture QUEEP_API_URL=https://queep-api-721281571441.southamerica-east1.run.app sh Scripts/verify-billing-config.sh >/dev/null 2>&1; then
  echo 'FAIL: TestFlight accepted shared development API'; exit 1
fi
echo 'Billing distribution guards passed.'
