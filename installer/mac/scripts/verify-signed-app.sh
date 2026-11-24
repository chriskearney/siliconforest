#!/bin/bash
# Verifies the installer app's helper/recovery layout and signatures.
# Usage: verify-signed-app.sh [--developer-id] <SiliconForest Installer.app>
#
# Always: codesign --verify --deep --strict on the app, --strict on the helper
# and recovery binary; LaunchDaemon plist and recovery payload present;
# identifiers match SFIdentity; no get-task-allow or library-validation
# exception entitlements.
# --developer-id also requires Developer ID Application (team Z642ZK8JK4),
# the hardened runtime, and a secure timestamp.
set -euo pipefail

developer_id=false
if [[ "${1:-}" == "--developer-id" ]]; then
  developer_id=true
  shift
fi
if [[ $# -ne 1 ]]; then
  echo "usage: verify-signed-app.sh [--developer-id] <SiliconForest Installer.app>" >&2
  exit 2
fi
APP="$1"
if [[ ! -d "$APP" ]]; then
  echo "not an application bundle: $APP" >&2
  exit 2
fi
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"

TEAM="Z642ZK8JK4"
APP_ID="org.siliconforest.installer"
HELPER_ID="org.siliconforest.installer.helper"
RECOVERY_ID="org.siliconforest.recovery"
HELPER="$APP/Contents/MacOS/SFHelper"
RECOVERY="$APP/Contents/Helpers/SFRecovery"
PLIST="$APP/Contents/Library/LaunchDaemons/${HELPER_ID}.plist"
PAYLOAD="$APP/Contents/Resources/RecoveryPayload"

fail=0
err() { echo "✗ $*" >&2; fail=1; }

[[ -x "$APP/Contents/MacOS/SiliconForest Installer" ]] || err "missing app executable"
[[ -f "$HELPER" && -x "$HELPER" ]] || err "missing helper at Contents/MacOS/SFHelper"
[[ -f "$RECOVERY" && -x "$RECOVERY" ]] || err "missing recovery binary at Contents/Helpers/SFRecovery"
[[ -f "$PLIST" ]] || err "missing LaunchDaemon plist"
[[ -f "$PAYLOAD/sf-launcher" ]] || err "missing RecoveryPayload/sf-launcher"
[[ -f "$PAYLOAD/sf-step2.sh" ]] || err "missing RecoveryPayload/sf-step2.sh"
# Payload copies are resources for later assembly, not nested executables.
if [[ -x "$PAYLOAD/sf-launcher" || -x "$PAYLOAD/sf-step2.sh" ]]; then
  err "RecoveryPayload scripts must not be executable inside the installer app; unsigned nested code breaks codesign --verify --deep"
fi

if [[ -f "$PLIST" ]]; then
  label="$(plutil -extract Label raw "$PLIST" 2>/dev/null || true)"
  prog="$(plutil -extract BundleProgram raw "$PLIST" 2>/dev/null || true)"
  associated="$(plutil -extract AssociatedBundleIdentifiers.0 raw "$PLIST" 2>/dev/null || true)"
  mach="$(plutil -extract "MachServices.${HELPER_ID}" raw "$PLIST" 2>/dev/null || true)"
  [[ "$label" == "$HELPER_ID" ]] || err "LaunchDaemon Label is '${label}', expected ${HELPER_ID}"
  [[ "$prog" == "Contents/MacOS/SFHelper" ]] || err "LaunchDaemon BundleProgram is '${prog}'"
  [[ "$associated" == "$APP_ID" ]] || err "LaunchDaemon AssociatedBundleIdentifiers[0] is '${associated}'"
  [[ "$mach" == "true" || "$mach" == "1" ]] || err "LaunchDaemon MachServices.${HELPER_ID} is missing"
fi

info_of() { codesign -dvv "$1" 2>&1; }

ident_of() { info_of "$1" | awk -F= '/^Identifier=/{print $2; exit}'; }

has_forbidden_entitlements() {
  local path="$1"
  local ents
  ents="$(codesign -d --entitlements :- "$path" 2>/dev/null || true)"
  [[ -n "$ents" ]] || return 1
  echo "$ents" | grep -E -q 'get-task-allow|disable-library-validation|allow-unsigned-executable-memory|allow-dyld-environment-variables|disable-executable-page-protection'
}

verify_bin() {
  local path="$1"
  local expected_id="$2"
  if ! codesign --verify --strict --verbose=2 "$path"; then
    err "codesign --verify --strict failed: $path"
    return
  fi
  local ident info
  ident="$(ident_of "$path")"
  [[ "$ident" == "$expected_id" ]] || err "$path Identifier=${ident}, expected ${expected_id}"
  info="$(info_of "$path")"
  if $developer_id; then
    if echo "$info" | grep -q 'Signature=adhoc'; then
      err "$path is ad hoc; Developer ID Application is required"
    fi
    echo "$info" | grep -F -q "Authority=Developer ID Application: Chris Kearney (${TEAM})" \
      || err "$path is not signed with Developer ID Application: Chris Kearney (${TEAM})"
    echo "$info" | grep -F -q "TeamIdentifier=${TEAM}" \
      || err "$path TeamIdentifier is not ${TEAM}"
    echo "$info" | grep -E -q 'flags=.*runtime' \
      || err "$path is not signed with the hardened runtime"
    echo "$info" | grep -q '^Timestamp=' \
      || err "$path is missing a secure timestamp"
  fi
  if has_forbidden_entitlements "$path"; then
    err "$path has a forbidden entitlement (get-task-allow or a library-validation exception)"
  fi
}

echo "▸ codesign --verify --deep --strict $APP"
if ! codesign --verify --deep --strict --verbose=2 "$APP"; then
  err "codesign --verify --deep --strict failed on the app"
fi

verify_bin "$APP" "$APP_ID"
verify_bin "$HELPER" "$HELPER_ID"
verify_bin "$RECOVERY" "$RECOVERY_ID"

if [[ "$fail" -ne 0 ]]; then
  echo "signed-app verification failed" >&2
  exit 1
fi
echo "✓ $APP"
echo "  helper:    $HELPER"
echo "  recovery:  $RECOVERY"
echo "  launchd:   $PLIST"
