#!/bin/bash
set -euo pipefail

readonly project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly app_path="${1:-$project_root/build/macos/Build/Products/Release/Audyt.app}"
readonly framework_path="$app_path/Contents/Frameworks/App.framework"
readonly entitlements_path="$(/usr/bin/mktemp)"
trap 'rm -f "$entitlements_path"' EXIT
# Preserve Xcode-expanded keychain groups and the application identifier.
/usr/bin/codesign -d --entitlements :- "$app_path" >"$entitlements_path" 2>/dev/null
readonly signing_identity="${AUDYT_SIGNING_IDENTITY:?Set AUDYT_SIGNING_IDENTITY to the Apple signing identity used for the build.}"

if [[ ! -d "$framework_path" ]]; then
  printf 'FAIL: Flutter framework does not exist: %s\n' "$framework_path" >&2
  exit 1
fi
if [[ ! -f "$entitlements_path" ]]; then
  printf 'FAIL: release entitlements do not exist: %s\n' "$entitlements_path" >&2
  exit 1
fi

# Retain Apple signing: Google session storage requires its keychain identity.
/usr/bin/codesign --force --sign "$signing_identity" --timestamp=none "$framework_path"
/usr/bin/codesign --force --deep --sign "$signing_identity" --timestamp=none \
  --entitlements "$entitlements_path" "$app_path"
"$project_root/tool/verify_macos_package.sh" "$app_path"
