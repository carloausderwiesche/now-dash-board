#!/bin/bash
# Builds the Mac app (Release) from the current checkout and replaces
# /Applications/Nowboard.app with it. Tasks and settings aren't touched:
# they live in the Tasks folder and in the app's preferences.
#
#   apple/scripts/install-mac.sh
set -euo pipefail

cd "$(dirname "$0")/.."
build=/tmp/nowboard-release

command -v xcodegen >/dev/null && xcodegen --quiet
xcodebuild build -project Nowboard.xcodeproj -scheme Nowboard -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$build" -quiet

osascript -e 'tell application id "com.nestoririondo.nowboard.swiftui" to quit' 2>/dev/null || true
sleep 1
rm -rf /Applications/Nowboard.app
ditto "$build/Build/Products/Release/Nowboard.app" /Applications/Nowboard.app
open /Applications/Nowboard.app
echo "Installed /Applications/Nowboard.app from $(git rev-parse --abbrev-ref HEAD) ($(git rev-parse --short HEAD))"
