#!/bin/bash
set -euo pipefail

readonly expected_entitlement="com.apple.security.files.user-selected.read-write"
readonly sandbox_entitlement="com.apple.security.app-sandbox"
readonly project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly app_path="${1:-$project_root/build/macos/Build/Products/Debug/Audyt.app}"
readonly executable_path="$app_path/Contents/MacOS/Audyt"

if [[ ! -d "$app_path" ]]; then
  printf 'FAIL: app bundle does not exist: %s\n' "$app_path" >&2
  exit 1
fi
if [[ ! -x "$executable_path" ]]; then
  printf 'FAIL: app executable does not exist: %s\n' "$executable_path" >&2
  exit 1
fi

printf 'Verifying signed bundle: %s\n' "$app_path"
/usr/bin/codesign --verify --deep --strict "$app_path"

entitlements_file="$(/usr/bin/mktemp)"
trap 'rm -f "$entitlements_file"' EXIT
/usr/bin/codesign -d --entitlements :- "$app_path" >"$entitlements_file" 2>/dev/null
if [[ ! -s "$entitlements_file" ]]; then
  printf 'FAIL: signed bundle has no entitlements: %s\n' "$app_path" >&2
  exit 1
fi

printf 'Signed entitlements:\n'
/usr/bin/plutil -p "$entitlements_file"

for entitlement in "$sandbox_entitlement" "$expected_entitlement"; do
  if ! /usr/bin/plutil -p "$entitlements_file" | /usr/bin/grep -Fq "\"$entitlement\" => true"; then
    printf 'FAIL: signed bundle is missing enabled entitlement: %s\n' "$entitlement" >&2
    exit 1
  fi
  printf 'PASS: %s => true\n' "$entitlement"
done

if /usr/libexec/PlistBuddy -c 'Print :GIDClientID' "$app_path/Contents/Info.plist" >/dev/null 2>&1; then
  /usr/bin/python3 - "$entitlements_file" <<'PYVERIFY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    values = plistlib.load(source)
assert values.get('com.apple.security.network.client') is True, 'Missing network client entitlement'
groups = values.get('keychain-access-groups', [])
assert any(g.endswith('.com.google.GIDSignIn') and '$' not in g for g in groups), 'Missing expanded Google Keychain group'
assert values.get('com.apple.application-identifier'), 'Missing signed application identifier'
print('PASS: Google network, application identity and Keychain entitlements')
PYVERIFY
fi

printf 'PASS: signed Audyt.app package verification complete.\n'
