#!/bin/zsh
# Archives the app and uploads it to App Store Connect for TestFlight.
# The version stays at MARKETING_VERSION (1.0); each upload gets a new build number
# from the date and time (e.g. 2611241530), so nothing needs editing between uploads.
#
#   ios/scripts/testflight.sh                 archive and upload
#   ios/scripts/testflight.sh --archive-only  archive only, to check it builds
set -euo pipefail
cd "${0:A:h}/.."
OUT=../.build-archive
BUILD=$(date +%y%m%d%H%M)

xcodegen generate -q
rm -rf "$OUT/TravelCopilot.xcarchive" "$OUT/export"
echo "Archiving build $BUILD…"
xcodebuild archive -project TravelCopilot.xcodeproj -scheme TravelCopilot -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/TravelCopilot.xcarchive" \
  -derivedDataPath ../.build-dd-dev -allowProvisioningUpdates -quiet \
  CURRENT_PROJECT_VERSION="$BUILD"

APP="$OUT/TravelCopilot.xcarchive/Products/Applications/TravelCopilot.app"
for plist in "$APP/Info.plist" "$APP/PlugIns/TravelCopilotWidgets.appex/Info.plist"; do
  echo "  $(basename "$(dirname "$plist")"): $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist"))"
done
[[ "${1:-}" == "--archive-only" ]] && exit 0

echo "Uploading…"
xcodebuild -exportArchive -archivePath "$OUT/TravelCopilot.xcarchive" \
  -exportOptionsPlist ExportOptions.plist -exportPath "$OUT/export" -allowProvisioningUpdates 2>&1 \
  | grep -E "Upload succeeded|error|EXPORT (SUCCEEDED|FAILED)" | sort -u
echo "Build $BUILD is processing. It shows in TestFlight in 5–30 minutes."
