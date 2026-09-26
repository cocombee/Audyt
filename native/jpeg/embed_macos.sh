#!/bin/sh
set -eu
source_dir="$PROJECT_DIR/../native/jpeg"
mkdir -p "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Third Party Notices"
cp "$source_dir/prebuilt/macos/libaudyt_jpeg.dylib" "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/"
cp "$source_dir/mozjpeg/LICENSE.md" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Third Party Notices/MozJPEG License.md"
cp "$source_dir/mozjpeg/README.ijg" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Third Party Notices/Independent JPEG Group.txt"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
 /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/libaudyt_jpeg.dylib"
fi
