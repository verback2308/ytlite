#!/bin/bash
# make_ipa.sh — builds a distributable IPA for jailbroken devices (AppSync + Filza)
# Usage: ./make_ipa.sh
# Output: YTVLite.ipa in the project root

set -e

APP_NAME="YTVLite"
PROJECT="YTVLite.xcodeproj"
SCHEME="YTVLite"
OUTPUT="$APP_NAME.ipa"

echo "▶ Building Release for device..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -sdk iphoneos \
  -configuration Release \
  -destination "generic/platform=iOS" \
  build \
  2>&1 | grep -E "error:|warning:|Build succeeded|Build FAILED" | tail -5

BUILD_DIR=$(xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -sdk iphoneos \
  -configuration Release \
  -showBuildSettings 2>/dev/null \
  | grep "^ *BUILT_PRODUCTS_DIR" | head -1 | awk -F' = ' '{print $2}')

APP_PATH="$BUILD_DIR/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
  echo "❌ Build failed or app not found at: $APP_PATH"
  exit 1
fi

echo "▶ Replacing dev cert with ad-hoc signature..."
# Ad-hoc ("-") works with AppSync on any jailbroken device without certificate expiry
codesign -f -s - --deep --preserve-metadata=entitlements "$APP_PATH" 2>/dev/null \
  && echo "  codesign: ok" \
  || echo "  codesign: skipped (app will still install via AppSync)"

echo "▶ Packaging IPA..."
TMP=$(mktemp -d)
mkdir "$TMP/Payload"
cp -r "$APP_PATH" "$TMP/Payload/"
(cd "$TMP" && zip -qr "$OLDPWD/$OUTPUT" Payload)
rm -rf "$TMP"

SIZE=$(du -sh "$OUTPUT" | cut -f1)
echo "✅ $OUTPUT ($SIZE) — ready to share"
echo "   Install: copy to device, open in Filza, tap Install"
