#!/bin/bash
# make_ipa.sh — builds a distributable IPA for jailbroken devices (AppSync + Filza)
# Usage: ./make_ipa.sh
# Output: YTLite_<version>_<build>.ipa in the project root

set -e

APP_NAME="YTLite"
PROJECT="YTLite.xcodeproj"
SCHEME="YTVLite"
RELEASE_BUNDLE_ID="com.verback.YTLite"
SOURCE_JSON="source/apps.json"

echo "▶ Building Release for device..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -sdk iphoneos \
  -configuration Release \
  -destination "generic/platform=iOS" \
  build \
  2>&1 | grep -E "error:|warning:|Build succeeded|Build FAILED" | tail -5

BUILD_SETTINGS=$(xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -sdk iphoneos \
  -configuration Release \
  -showBuildSettings 2>/dev/null)

BUILD_DIR=$(echo "$BUILD_SETTINGS" | grep "^ *BUILT_PRODUCTS_DIR" | head -1 | awk -F' = ' '{print $2}')
VERSION=$(echo "$BUILD_SETTINGS" | grep "^ *MARKETING_VERSION" | head -1 | awk -F' = ' '{print $2}')
BUILD=$(git -C "$(dirname "$0")" rev-list --count HEAD 2>/dev/null || echo "0")
OUTPUT="${APP_NAME}_${VERSION}_${BUILD}.ipa"

APP_PATH="$BUILD_DIR/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
  echo "❌ Build failed or app not found at: $APP_PATH"
  exit 1
fi

echo "▶ Replacing bundle ID for release: $RELEASE_BUNDLE_ID"
plutil -replace CFBundleIdentifier -string "$RELEASE_BUNDLE_ID" "$APP_PATH/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_PATH/Info.plist"

echo "▶ Replacing dev cert with ad-hoc signature..."
codesign -f -s - --deep --preserve-metadata=entitlements "$APP_PATH" 2>/dev/null \
  && echo "  codesign: ok" \
  || echo "  codesign: skipped (app will still install via AppSync)"

echo "▶ Packaging IPA..."
TMP=$(mktemp -d)
mkdir "$TMP/Payload"
cp -r "$APP_PATH" "$TMP/Payload/"
(cd "$TMP" && zip -qr "$OLDPWD/$OUTPUT" Payload)
rm -rf "$TMP"

IPA_SIZE=$(stat -f%z "$OUTPUT" 2>/dev/null || stat -c%s "$OUTPUT" 2>/dev/null)
DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
REPO_URL="https://github.com/verback2308/YTLite"
DOWNLOAD_URL="$REPO_URL/releases/download/${VERSION}_${BUILD}/${OUTPUT}"

echo "▶ Updating source: $SOURCE_JSON"
python3 -c "
import json, sys

with open('$SOURCE_JSON', 'r') as f:
    data = json.load(f)

app = data['apps'][0]
app['version'] = '$VERSION'
app['versionDate'] = '$DATE'
app['versionDescription'] = 'See release notes on GitHub'
app['downloadURL'] = '$DOWNLOAD_URL'
app['size'] = $IPA_SIZE

app['versions'] = [{
    'version': '$VERSION',
    'date': '$DATE',
    'localizedDescription': 'See release notes on GitHub',
    'downloadURL': '$DOWNLOAD_URL',
    'size': $IPA_SIZE,
    'minOSVersion': '12.0'
}]

with open('$SOURCE_JSON', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f'  Updated: {app[\"name\"]} v{app[\"version\"]}')
"

SIZE=$(du -sh "$OUTPUT" | cut -f1)
echo "✅ $OUTPUT ($SIZE) — ready to share"
echo "   Install: copy to device, open in Filza, tap Install"
