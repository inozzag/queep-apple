#!/bin/sh
# Uploads TestFlight dSYMs so the stack names the tester build.
# A missing token or CLI warns and lets the archive finish.
set -u

if [ "${CONFIGURATION}" != "TestFlight" ]; then
  exit 0
fi

if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
  echo "warning: SENTRY_AUTH_TOKEN is unset; TestFlight dSYMs were not uploaded"
  exit 0
fi

export SENTRY_ORG=gazzoni
export SENTRY_PROJECT=queep-apple

if [ "$(uname -m)" = "arm64" ]; then
  export PATH="/opt/homebrew/bin:${PATH}"
fi

cli=""
if command -v sentry-cli >/dev/null 2>&1; then
  cli="sentry-cli"
else
  cache="${HOME}/Library/Caches/queep/sentry-cli"
  if [ ! -x "${cache}" ]; then
    mkdir -p "$(dirname "${cache}")"
    curl -fsSL -o "${cache}" \
      "https://github.com/getsentry/sentry-cli/releases/download/2.53.0/sentry-cli-Darwin-universal" \
      || { echo "warning: could not download sentry-cli; TestFlight dSYMs were not uploaded"; exit 0; }
    chmod +x "${cache}"
  fi
  cli="${cache}"
fi

# The token stays in the environment. Do not print it.
"${cli}" debug-files upload "${DWARF_DSYM_FOLDER_PATH}" \
  || echo "warning: sentry-cli debug-files upload failed"
