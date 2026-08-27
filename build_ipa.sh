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
FFMPEG_KIT_DIR="$BUILD_DIR/ffmpeg-kit-next"
FFMPEG_KIT_XCF="$BUILD_DIR/ffmpeg-kit-xcframeworks"
# v8.1.x tags are Nix-only (no ios.sh). v9.0.0+ ships the classic ios.sh entrypoint.
FFMPEG_KIT_TAG="${FFMPEG_KIT_TAG:-v9.0.0}"

mkdir -p "$BUILD_DIR"

if [ ! -d "$FFMPEG_KIT_XCF" ]; then
    echo "Building ffmpeg-kit-next ($FFMPEG_KIT_TAG)..."
    if [ ! -d "$FFMPEG_KIT_DIR" ]; then
        echo "    Cloning ffmpeg-kit-next..."
        git clone --depth 1 --branch "$FFMPEG_KIT_TAG" \
            https://github.com/arthenica/ffmpeg-kit-next.git "$FFMPEG_KIT_DIR"
    fi
    cd "$FFMPEG_KIT_DIR"
    if [ ! -f ./ios.sh ]; then
        echo "    ERROR: ios.sh missing in ffmpeg-kit-next @$FFMPEG_KIT_TAG"
        echo "    Use a tag that includes the classic build scripts (v9.0.0+), or nix-ios.sh."
        exit 1
    fi
    if ! command -v gsed >/dev/null 2>&1; then
        echo "    Installing build dependencies..."
        brew install gnu-sed pkg-config autoconf automake libtool
    fi
    # One -x invocation builds device + simulator into a single XCFramework.
    # Separate ios.sh runs recreate the output directory and drop the earlier
    # slice, which breaks device IPA linking. Disable unused default arches.
    echo "Building arm64 device + simulator XCFrameworks..."
    SED=gsed ./ios.sh -x --spm --enable-lib-openssl \
        --disable-arm64e \
        --disable-arm64-mac-catalyst \
        --disable-x86-64 \
        --disable-x86-64-mac-catalyst \
        || { echo "    FAILED: ffmpeg-kit XCFramework build"; exit 1; }
    echo "Copying xcframeworks..."
    cp -R "$FFMPEG_KIT_DIR/prebuilt/bundle-apple-xcframework-ios-12.1" "$FFMPEG_KIT_XCF"
    echo "ffmpeg-kit-next build complete."
    cd "$WORKING_LOCATION"
fi

cd "$BUILD_DIR"

XCODEBUILD_ACTION="${XCODEBUILD_ACTION:-build}"
if [ "${CLEAN_BUILD:-0}" = "1" ]; then
    XCODEBUILD_ACTION="clean build"
fi

SKIP_SWIFTLINT=YES
# shellcheck disable=SC2086
xcodebuild -project "$WORKING_LOCATION/$PROJECT_NAME.xcodeproj" \
    -scheme "$APPLICATION_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination 'generic/platform=iOS' \
    $XCODEBUILD_ACTION \
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
