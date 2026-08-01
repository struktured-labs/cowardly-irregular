#!/usr/bin/env bash
# setup_android_sdk.sh — install the Android SDK pieces Godot needs for an APK export.
#
# WHY THIS EXISTS AS A SCRIPT
#   Everything here is automatable except one thing: accepting Google's SDK
#   licence, which is a legal act and has to be struktured's. Rather than hand
#   him four commands to paste, this is one command he runs inline, and the only
#   interactive moment is the licence prompt itself.
#
# WHAT GODOT ACTUALLY NEEDS (measured from the export's own error, not guessed):
#     Invalid Android SDK path in Editor Settings. Missing 'platform-tools'!
#     Unable to find Android SDK platform-tools' adb command.
#     Invalid Android SDK path in Editor Settings. Missing 'build-tools'!
#     Unable to find Android SDK build-tools' apksigner command.
#   So: platform-tools (adb) + build-tools (apksigner). Godot signs the APK with
#   apksigner even for a template export, so the SDK is required even though we
#   are NOT doing a custom Gradle build.
#
# ALREADY DONE, so this script does not redo it:
#   * debug keystore generated at ~/.local/share/godot/keystores/debug.keystore
#   * editor settings point at it (they previously pointed at a dead VS Code snap path)
#   * java_sdk_path -> JDK 17 ; JDK 17 and 21 are both installed
#   * the Android export preset exists in export_presets.cfg
#   * import_etc2_astc is on in project.godot (Android needs it; it came free with macOS)
#
# Usage:   ./tools/setup_android_sdk.sh
#          ./tools/setup_android_sdk.sh --check      report state, change nothing
set -euo pipefail

SDK="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
CLT="$SDK/cmdline-tools"
# Pinned rather than "latest" so a rerun months from now installs what was tested.
CLT_ZIP="commandlinetools-linux-11076708_latest.zip"
CLT_URL="https://dl.google.com/android/repository/${CLT_ZIP}"
BUILD_TOOLS="34.0.0"
PLATFORM="android-34"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

_have() { command -v "$1" >/dev/null 2>&1; }

_state() {
    echo "[android] SDK root: $SDK"
    printf "  %-16s %s\n" "cmdline-tools" "$([ -x "$CLT/latest/bin/sdkmanager" ] && echo present || echo ABSENT)"
    printf "  %-16s %s\n" "platform-tools" "$([ -x "$SDK/platform-tools/adb" ] && echo present || echo ABSENT)"
    printf "  %-16s %s\n" "build-tools" "$(ls "$SDK/build-tools" 2>/dev/null | tr '\n' ' ' || echo ABSENT)"
    printf "  %-16s %s\n" "apksigner" "$(ls "$SDK"/build-tools/*/apksigner 2>/dev/null | head -1 || echo ABSENT)"
    printf "  %-16s %s\n" "keystore" "$([ -f "$HOME/.local/share/godot/keystores/debug.keystore" ] && echo present || echo ABSENT)"
    printf "  %-16s %s\n" "java" "$(_have java && java -version 2>&1 | head -1 || echo ABSENT)"
}

if [ "$CHECK_ONLY" = "1" ]; then _state; exit 0; fi

echo "[android] === before ==="; _state; echo

# ── fetch the command-line tools, if absent ─────────────────────────────────
if [ -x "$CLT/latest/bin/sdkmanager" ]; then
    echo "[android] cmdline-tools already present — skipping download"
else
    _have curl || { echo "[android] BLOCKED: curl not found" >&2; exit 2; }
    _have unzip || { echo "[android] BLOCKED: unzip not found" >&2; exit 2; }
    mkdir -p "$CLT"
    TMPZ="$(mktemp -d)/$CLT_ZIP"
    echo "[android] downloading $CLT_ZIP (~150 MB)"
    curl -fL --progress-bar -o "$TMPZ" "$CLT_URL"
    # A truncated download unzips to a partial tree that fails later and confusingly.
    # Assert the archive is intact BEFORE unpacking it.
    unzip -tq "$TMPZ" || { echo "[android] BLOCKED: archive is corrupt — re-run" >&2; exit 2; }
    rm -rf "$CLT/latest" "$CLT/cmdline-tools"
    unzip -q "$TMPZ" -d "$CLT"
    # The zip unpacks as cmdline-tools/; sdkmanager REQUIRES it to sit at
    # <sdk>/cmdline-tools/latest/ or it refuses with an unhelpful path error.
    mv "$CLT/cmdline-tools" "$CLT/latest"
    rm -f "$TMPZ"
    [ -x "$CLT/latest/bin/sdkmanager" ] || {
        echo "[android] BLOCKED: sdkmanager missing after unpack — layout changed upstream" >&2; exit 2; }
fi

SDKMGR="$CLT/latest/bin/sdkmanager"

# ── the one part that is genuinely yours ────────────────────────────────────
echo
echo "[android] ── LICENCE ─────────────────────────────────────────────────"
echo "[android] Google's SDK terms. This is the only interactive step and the"
echo "[android] only reason this script is not fully automated. Read and accept."
echo
"$SDKMGR" --sdk_root="$SDK" --licenses

# ── install exactly what the export error named, nothing more ───────────────
echo
echo "[android] installing platform-tools · build-tools;${BUILD_TOOLS} · platforms;${PLATFORM}"
"$SDKMGR" --sdk_root="$SDK" "platform-tools" "build-tools;${BUILD_TOOLS}" "platforms;${PLATFORM}"

# ── verify by the two binaries Godot actually looks for ─────────────────────
echo
echo "[android] === after ==="; _state; echo
FAIL=0
[ -x "$SDK/platform-tools/adb" ] || { echo "[android] adb MISSING" >&2; FAIL=1; }
ls "$SDK"/build-tools/*/apksigner >/dev/null 2>&1 || { echo "[android] apksigner MISSING" >&2; FAIL=1; }
if [ "$FAIL" = "1" ]; then
    echo "[android] BLOCKED: the SDK installed but Godot's two required binaries are not there." >&2
    echo "        Nothing further will work; do not treat the export error as a Godot bug." >&2
    exit 3
fi

echo "[android] ✅ adb and apksigner both present."
echo "[android] Tell cowir-deploy and it will point editor settings at ${SDK}"
echo "[android] and run the first APK export. Nothing publishes without your word."
