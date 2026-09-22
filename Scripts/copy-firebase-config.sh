#!/bin/sh
set -eu
destination="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"
if [ "${CONFIGURATION}" = "CloudDevelopment" ] || [ "${CONFIGURATION}" = "TestFlight" ]; then
  source="${SRCROOT}/${QUEEP_FIREBASE_CONFIG}"
  test -f "$source" || { echo "error: Missing development Firebase configuration"; exit 1; }
  /bin/cp "$source" "$destination"
else
  # Never carry the development Firebase project into a production build.
  /bin/rm -f "$destination"
fi
