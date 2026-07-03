#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
WORKING_LOCATION="$(pwd)"
APPLICATION_NAME=Trop
PROJECT_NAME=Trop
BUILD_DIR="$WORKING_LOCATION/build"
DERIVED_DATA_PATH="$BUILD_DIR/DerivedDataApp"
OUTPUT_APP_PATH="$BUILD_DIR/$APPLICATION_NAME.app"
PAYLOAD_DIR="$BUILD_DIR/Payload"
IPA_PATH="$BUILD_DIR/$APPLICATION_NAME.ipa"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

SKIP_SWIFTLINT=YES
xcodebuild -project "$WORKING_LOCATION/$PROJECT_NAME.xcodeproj" \
    -scheme "$APPLICATION_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination 'generic/platform=iOS' \
    clean build \
    SKIP_SWIFTLINT=YES \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED="NO"

DD_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release-iphoneos/$APPLICATION_NAME.app"

if [ ! -d "$DD_APP_PATH" ]; then
    echo "Error: built app not found at $DD_APP_PATH"
    exit 1
fi

rm -rf "$OUTPUT_APP_PATH"
cp -r "$DD_APP_PATH" "$OUTPUT_APP_PATH"

codesign --remove "$OUTPUT_APP_PATH" || true
rm -rf "$OUTPUT_APP_PATH/_CodeSignature"
rm -rf "$OUTPUT_APP_PATH/embedded.mobileprovision"

rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR"
cp -r "$OUTPUT_APP_PATH" "$PAYLOAD_DIR/$APPLICATION_NAME.app"

if [ -f "$PAYLOAD_DIR/$APPLICATION_NAME.app/$APPLICATION_NAME" ]; then
    strip "$PAYLOAD_DIR/$APPLICATION_NAME.app/$APPLICATION_NAME"
fi

cd "$BUILD_DIR"
zip -vr "$IPA_PATH" "Payload"

rm -rf "$PAYLOAD_DIR"

echo "IPA created at $IPA_PATH"