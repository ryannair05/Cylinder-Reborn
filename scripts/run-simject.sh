#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly SIMJECT_DIR="/opt/simject"
readonly LOG_PREFIX="[CylinderSimject]"

# preferenceloader-sim normally reads bundles from the simulator runtime, which needs sudo to write. This
# build is patched to read them from PL_ROOT instead.
readonly PL_ROOT="$SIMJECT_DIR/PreferenceLoaderRoot"
readonly PL_REPO="https://github.com/PoomSmart/preferenceloader-sim.git"
readonly PL_COMMIT="c21d9e21d3404b3b1f827ac3cc2693e92928eed8"
readonly PL_SOURCE="${XDG_CACHE_HOME:-$HOME/Library/Caches}/CylinderSimject/preferenceloader-sim"
# Simulator binaries are signed ad hoc, which never needs a keychain identity.
readonly SIGN_FLAGS="--sign -"

print_command() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'
}

run() {
    print_command "$@"
    "$@"
}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

[[ -d "$SIMJECT_DIR" ]] || fail "$SIMJECT_DIR does not exist; complete Simject setup manually first"
[[ -f "$SIMJECT_DIR/simject.dylib" ]] || fail "$SIMJECT_DIR/simject.dylib is missing"
[[ -f "$SIMJECT_DIR/simject.plist" ]] || fail "$SIMJECT_DIR/simject.plist is missing"
command -v resim >/dev/null || fail "resim is not installed or not in PATH"
command -v jq >/dev/null || fail "jq is required to select an iPhone Simulator"

tweak_name="$(awk '$1 == "TWEAK_NAME" { print $3; exit }' "$REPO_ROOT/Makefile")"
[[ "$tweak_name" =~ ^[A-Za-z0-9._-]+$ ]] || fail "could not determine a safe TWEAK_NAME from Makefile"
[[ "$tweak_name" != "simject" ]] || fail "refusing to overwrite Simject's loader"

filter_plist="$REPO_ROOT/$tweak_name.plist"
[[ -f "$filter_plist" ]] || fail "matching filter plist not found: $filter_plist"
filter_bundle="$(/usr/libexec/PlistBuddy -c 'Print :Filter:Bundles:0' "$filter_plist" 2>/dev/null || true)"
[[ -n "$filter_bundle" ]] || fail "$filter_plist does not contain Filter:Bundles:0"

case "$(uname -m)" in
    arm64)
        simulator_target="simulator:clang::12.0"
        simulator_arch="arm64"
        ;;
    x86_64)
        simulator_target="simulator:clang::7.0"
        simulator_arch="x86_64"
        ;;
    *)
        fail "unsupported Mac architecture: $(uname -m)"
        ;;
esac

installed_dylib="$SIMJECT_DIR/$tweak_name.dylib"
installed_plist="$SIMJECT_DIR/$tweak_name.plist"
[[ "$installed_dylib" != "$SIMJECT_DIR/simject.dylib" ]] || fail "refusing to replace simject.dylib"
[[ "$installed_plist" != "$SIMJECT_DIR/simject.plist" ]] || fail "refusing to replace simject.plist"

printf 'Repository: %s\n' "$REPO_ROOT"
printf 'Tweak: %s\n' "$tweak_name"
printf 'Filter: %s -> %s\n' "$filter_plist" "$filter_bundle"
printf 'Simulator build: TARGET=%s ARCHS=%s\n' "$simulator_target" "$simulator_arch"

install_preferenceloader() {
    local installed="$SIMJECT_DIR/PreferenceLoader.dylib"
    if [[ -f "$installed" ]]; then
        grep -q "$PL_ROOT" "$installed" ||
            fail "$installed does not read from $PL_ROOT; remove it to let this script rebuild it"
        return
    fi

    printf 'Building preferenceloader-sim %s\n' "$PL_COMMIT"
    if [[ ! -d "$PL_SOURCE/.git" ]]; then
        run mkdir -p "$(dirname "$PL_SOURCE")"
        run git clone --quiet "$PL_REPO" "$PL_SOURCE"
    fi
    run git -C "$PL_SOURCE" fetch --quiet origin "$PL_COMMIT"
    run git -C "$PL_SOURCE" checkout --quiet --force "$PL_COMMIT"
    run sed -i '' "s|\[UISystemRootDirectory() stringByAppendingPathComponent:path\]|[@\"$PL_ROOT\" stringByAppendingPathComponent:path]|" "$PL_SOURCE/prefs.h"

    # Its .xm files compile as Objective-C++, and current SDKs' libc++ needs at least iOS 15. Preferences.framework
    # is in the simulator runtime but not its SDK, so its classes resolve when Settings loads the tweak.
    run make -C "$PL_SOURCE" clean all TARGET=simulator:clang::15.0 ARCHS="$simulator_arch" FINALPACKAGE=1 \
        PreferenceLoader_PRIVATE_FRAMEWORKS= PreferenceLoader_LDFLAGS=-Wl,-undefined,dynamic_lookup \
        TARGET_CODESIGN_FLAGS="$SIGN_FLAGS"

    run install -m 755 "$PL_SOURCE/.theos/obj/iphone_simulator/PreferenceLoader.dylib" "$installed"
    run install -m 644 "$PL_SOURCE/PreferenceLoader.plist" "$SIMJECT_DIR/PreferenceLoader.plist"
    run codesign -f $SIGN_FLAGS "$installed"
}

cd "$REPO_ROOT"
install_preferenceloader
run make clean TARGET="$simulator_target" ARCHS="$simulator_arch" CYLINDER_SIMJECT=1 TARGET_CODESIGN_FLAGS="$SIGN_FLAGS"
run make all TARGET="$simulator_target" ARCHS="$simulator_arch" CYLINDER_SIMJECT=1 TARGET_CODESIGN_FLAGS="$SIGN_FLAGS"

artifact="$REPO_ROOT/.theos/obj/iphone_simulator/$tweak_name.dylib"
[[ -f "$artifact" ]] || fail "simulator artifact not found: $artifact"
file_output="$(file "$artifact")"
build_version="$(xcrun vtool -show-build "$artifact")"
printf 'Built artifact: %s\n%s\n%s\n' "$artifact" "$file_output" "$build_version"
[[ "$file_output" == *"$simulator_arch"* ]] || fail "built dylib does not contain $simulator_arch"
[[ "$build_version" == *"platform IOSSIMULATOR"* ]] || fail "built dylib is not an iOS Simulator binary"

run rm -f "$installed_dylib"
run install -m 755 "$artifact" "$installed_dylib"
run install -m 644 "$filter_plist" "$installed_plist"
run codesign -f $SIGN_FLAGS "$installed_dylib"

# Theos builds the settings into settings/.theos when that folder exists and into the top-level .theos
# otherwise, without FINALPACKAGE's layout, because the parent Makefile does not export it. The newest wins.
settings_bundle=""
for candidate in "$REPO_ROOT/.theos/obj/iphone_simulator/CylinderSettings.bundle" \
                 "$REPO_ROOT/.theos/obj/iphone_simulator/debug/CylinderSettings.bundle" \
                 "$REPO_ROOT/settings/.theos/obj/iphone_simulator/CylinderSettings.bundle" \
                 "$REPO_ROOT/settings/.theos/obj/iphone_simulator/debug/CylinderSettings.bundle"; do
    [[ -f "$candidate/CylinderSettings" ]] || continue
    if [[ -z "$settings_bundle" || "$candidate/CylinderSettings" -nt "$settings_bundle/CylinderSettings" ]]; then
        settings_bundle="$candidate"
    fi
done
[[ -n "$settings_bundle" ]] || fail "simulator settings bundle not found under .theos/obj/iphone_simulator"
printf 'Settings bundle: %s\n' "$settings_bundle"

installed_bundle="$PL_ROOT/Library/PreferenceBundles/CylinderSettings.bundle"
installed_entry="$PL_ROOT/Library/PreferenceLoader/Preferences/Cylinder.plist"
run mkdir -p "$(dirname "$installed_bundle")" "$(dirname "$installed_entry")"
run rm -rf "$installed_bundle"
run ditto "$settings_bundle" "$installed_bundle"
run codesign -f $SIGN_FLAGS "$installed_bundle"
run install -m 644 "$REPO_ROOT/settings/entry.plist" "$installed_entry"

devices_json="$(xcrun simctl list devices available -j)"
# SIMULATOR_UDID picks a device; otherwise the first booted iPhone, then the first available one.
if [[ -n "${SIMULATOR_UDID:-}" ]]; then
    selected="$(jq -r --arg udid "$SIMULATOR_UDID" '[.devices[][] | select(.udid == $udid)][0] | select(. != null) | [.name, .udid, .dataPath] | @tsv' <<<"$devices_json")"
    [[ -n "$selected" ]] || fail "SIMULATOR_UDID $SIMULATOR_UDID is not an available simulator"
else
    selected="$(jq -r '[.devices[][] | select(.state == "Booted" and (.deviceTypeIdentifier | contains(".iPhone-")))][0] | select(. != null) | [.name, .udid, .dataPath] | @tsv' <<<"$devices_json")"
fi
if [[ -z "$selected" ]]; then
    selected="$(jq -r '[.devices[][] | select(.isAvailable == true and (.deviceTypeIdentifier | contains(".iPhone-")))][0] | select(. != null) | [.name, .udid, .dataPath] | @tsv' <<<"$devices_json")"
fi
[[ -n "$selected" ]] || fail "no available iPhone Simulator was found"

IFS=$'\t' read -r simulator_name simulator_udid simulator_data_path <<<"$selected"
printf 'Selected simulator: %s (%s)\n' "$simulator_name" "$simulator_udid"
print_command open -a Simulator
# Some Xcode installs do not ship Simulator.app; simctl still boots and drives the device headless.
open -a Simulator 2>/dev/null || printf 'Simulator.app not found; continuing without its window\n'

simulator_state="$(xcrun simctl list devices -j | jq -r --arg udid "$simulator_udid" '.devices[][] | select(.udid == $udid) | .state')"
if [[ "$simulator_state" != "Booted" ]]; then
    run xcrun simctl boot "$simulator_udid"
fi
run xcrun simctl bootstatus "$simulator_udid" -b

simulator_scripts="$simulator_data_path/Library/Cylinder"
run mkdir -p "$simulator_scripts"
run rsync -a --exclude .DS_Store --exclude run-simject.sh "$REPO_ROOT/scripts/" "$simulator_scripts/"

springboard_pid() {
    xcrun simctl spawn "$simulator_udid" launchctl print user/501/com.apple.SpringBoard 2>/dev/null |
        awk '$1 == "pid" && $2 == "=" { print $3; exit }'
}

previous_springboard_pid="$(springboard_pid)"
log_start="$(date '+%Y-%m-%d %H:%M:%S')"
run resim -i "$simulator_udid"

current_springboard_pid="$previous_springboard_pid"
for _ in $(seq 1 30); do
    current_springboard_pid="$(springboard_pid || true)"
    if [[ -n "$current_springboard_pid" && "$current_springboard_pid" != "$previous_springboard_pid" ]]; then
        break
    fi
    sleep 1
done
[[ -n "$current_springboard_pid" && "$current_springboard_pid" != "$previous_springboard_pid" ]] ||
    fail "SpringBoard did not relaunch after resim"
printf 'SpringBoard relaunched: PID %s -> %s\n' "$previous_springboard_pid" "$current_springboard_pid"

if [[ "$filter_bundle" != "com.apple.springboard" ]]; then
    print_command xcrun simctl terminate "$simulator_udid" "$filter_bundle"
    xcrun simctl terminate "$simulator_udid" "$filter_bundle" 2>/dev/null || true
    run xcrun simctl launch "$simulator_udid" "$filter_bundle"
fi

# Settings loads preference bundles once, so quit it to pick up the new build next time it opens.
print_command xcrun simctl terminate "$simulator_udid" com.apple.Preferences
xcrun simctl terminate "$simulator_udid" com.apple.Preferences 2>/dev/null || true

printf '\nInstalled artifact verification:\n'
run file "$installed_dylib"
print_command codesign -dv --verbose=4 "$installed_dylib"
codesign -dv --verbose=4 "$installed_dylib" 2>&1
run plutil -p "$installed_plist"

log_output=""
for _ in $(seq 1 15); do
    log_output="$(xcrun simctl spawn "$simulator_udid" log show --start "$log_start" --style compact --predicate 'eventMessage CONTAINS[c] "CylinderSimject"' 2>/dev/null || true)"
    [[ "$log_output" == *"Cylinder is enabled: YES"* ]] && break
    sleep 1
done

printf '\nSimulator log verification for %s:\n' "$LOG_PREFIX"
if [[ "$log_output" == *"CylinderSimject"* && "$log_output" == *"Cylinder is enabled: YES"* ]]; then
    printf '%s\n' "$log_output"
else
    [[ -n "$log_output" ]] && printf '%s\n' "$log_output"
    fail "$LOG_PREFIX did not report a successful Lua initialization after resim"
fi

printf '\nSimject workflow completed successfully.\n'
printf 'Simulator: %s (%s)\n' "$simulator_name" "$simulator_udid"
printf 'Installed dylib: %s\n' "$installed_dylib"
printf 'Installed plist: %s\n' "$installed_plist"
printf 'Installed scripts: %s\n' "$simulator_scripts"
printf 'Installed settings: %s\n' "$installed_bundle"
printf 'Target: %s\n' "$filter_bundle"
