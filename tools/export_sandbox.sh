#!/usr/bin/env bash
# Build a sandbox an EXPORT can run in: a redirected data root that still resolves export
# templates. Prints the path; the caller passes it as XDG_DATA_HOME.
#
# WHY THIS EXISTS
# ---------------
# `--export-release` was the last deploy invocation writing struktured's real profile, and it was
# exempt on a premise that is true of a BARE sandbox and false in general:
#
#     XDG_DATA_HOME relocates godot's whole data root, and export templates live under it at
#     ~/.local/share/godot/export_templates/4.4.1.stable — so a sandboxed export fails.
#
# Measured 2026-09-16, both directions, on a real Linux export:
#
#     bare sandbox        ERROR: No export template found at the expected path:
#                         <sandbox>/godot/export_templates/4.4.1.stable/linux_debug.x86_64
#                         -> produced NOTHING
#     sandbox + symlink   exported 318,140,832 bytes, exit 0
#                         his .recovery_mode_lock UNCHANGED at 12:22:04
#                         the export's user:// writes landed in <sandbox>/godot/app_userdata/
#
# The templates are READ-ONLY to an export, so a symlink is all it takes. That is the whole trick,
# and it turns a documented exemption into a fixed line.
#
# ⛔ WHAT IT COST BEFORE THIS. v3.33.360-alpha published with the boot gate and both imports
# sandboxed — his user://logs/ came through a full three-channel publish byte-identical for the
# first time that day — and his .recovery_mode_lock still moved 10:40:04 -> 12:22:04, stamped by
# the web export one second after the (sandboxed) staged import finished. The fix was real and
# incomplete, and check_user_data_sandboxed.py reported the export as `declared`, which reads as
# handled. A declaration is a licence not to fix something; this one was issued on a premise that
# held only for the sandbox nobody had tried to fix.
#
# Usage:  XDG_DATA_HOME="$(tools/export_sandbox.sh "$PWD/tmp/export_xdg")" godot ... --export-release ...
#         tools/export_sandbox.sh --selftest
# Exit:   0 printed a usable sandbox path · 2 refused (unsafe path, or templates not found)
set -uo pipefail

REAL_TEMPLATES="${EXPORT_TEMPLATES_DIR:-$HOME/.local/share/godot/export_templates}"

_die() { echo "[export-sandbox] REFUSED: $*" >&2; exit 2; }

build() {
    local dir="$1"
    [ -n "$dir" ] || _die "no sandbox path given."
    # Must be a sandbox. Linking templates into a real profile would be a write to the thing
    # this exists to protect.
    case "$dir" in
        */tmp/*|*/tmp) : ;;
        *) _die "${dir} is not under a tmp/ path. Refusing to build a data root anywhere that could be a real profile." ;;
    esac
    [ -d "$REAL_TEMPLATES" ] || _die "no export templates at ${REAL_TEMPLATES} — a sandboxed export would fail with 'No export template found', and an unsandboxed one would write his profile. Neither is acceptable silently."

    mkdir -p "${dir}/godot" || _die "could not create ${dir}/godot"
    local link="${dir}/godot/export_templates"
    # An earlier run may have left a real directory here (godot creates an empty one when it
    # looks for templates and finds none) — that is exactly the state that makes an export fail
    # confusingly, so replace it rather than leaving it.
    if [ -L "$link" ]; then
        :
    elif [ -e "$link" ]; then
        rmdir "$link" 2>/dev/null || _die "${link} exists and is not an empty directory; refusing to delete it."
    fi
    [ -L "$link" ] || ln -s "$REAL_TEMPLATES" "$link" || _die "could not link templates into ${link}"

    # VERIFY IT RESOLVES, rather than assuming the link is enough. A dangling symlink produces
    # the identical "No export template found" failure the link exists to prevent.
    local n; n="$(find -L "$link" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)"
    [ "${n:-0}" -gt 0 ] || _die "${link} resolves to no version directories — the export would fail exactly as it does with no link at all."
    printf '%s\n' "$dir"
}

selftest() {
    local pass=0 fail=0
    _eq() {
        if [ "$2" = "$3" ]; then printf '  ok    %-56s %s\n' "$1" "$2"; pass=$((pass+1))
        else printf '  FAIL  %-56s got %s want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
    }
    mkdir -p "$HOME/.cache"
    local d; d="$(mktemp -d "$HOME/.cache/exportsb.XXXXXX")"
    local fake="$d/templates"; mkdir -p "$fake/4.4.1.stable"

    local sb="$d/lane/tmp/export_xdg" out ec
    out="$(EXPORT_TEMPLATES_DIR="$fake" bash "$SELF" "$sb" 2>&1)"; ec=$?
    _eq "builds a sandbox under tmp/"                     "$ec" "0"
    _eq "  ...and prints the path"                        "$out" "$sb"
    _eq "  ...and the templates link RESOLVES"            "$(find -L "$sb/godot/export_templates" -maxdepth 1 -mindepth 1 -type d | wc -l)" "1"

    # idempotent: running twice must not fail or double-link
    out="$(EXPORT_TEMPLATES_DIR="$fake" bash "$SELF" "$sb" 2>&1)"; ec=$?
    _eq "a second run is idempotent"                      "$ec" "0"

    # the empty directory godot leaves behind must be REPLACED, not tripped over
    rm -f "$sb/godot/export_templates"; mkdir -p "$sb/godot/export_templates"
    out="$(EXPORT_TEMPLATES_DIR="$fake" bash "$SELF" "$sb" 2>&1)"; ec=$?
    _eq "an empty leftover dir is replaced by the link"   "$ec" "0"
    _eq "  ...and it is a symlink afterwards"             "$([ -L "$sb/godot/export_templates" ] && echo yes || echo no)" "yes"

    # a NON-empty directory there is someone else's data — refuse rather than delete
    rm -f "$sb/godot/export_templates"; mkdir -p "$sb/godot/export_templates/something"
    out="$(EXPORT_TEMPLATES_DIR="$fake" bash "$SELF" "$sb" 2>&1)"; ec=$?
    _eq "a NON-empty dir there is REFUSED, not deleted"   "$ec" "2"
    _eq "  ...and the contents survive"                   "$([ -d "$sb/godot/export_templates/something" ] && echo yes || echo no)" "yes"
    rm -rf "$sb/godot/export_templates"

    # a destination outside tmp/ is refused
    out="$(EXPORT_TEMPLATES_DIR="$fake" bash "$SELF" "$d/not-a-sandbox" 2>&1)"; ec=$?
    _eq "a path outside tmp/ is REFUSED"                  "$ec" "2"
    _eq "  ...and nothing was created there"              "$([ -e "$d/not-a-sandbox" ] && echo present || echo absent)" "absent"

    # missing templates: refuse loudly rather than build a sandbox the export will fail in
    out="$(EXPORT_TEMPLATES_DIR="$d/no-such-templates" bash "$SELF" "$d/lane/tmp/x" 2>&1)"; ec=$?
    _eq "absent templates are REFUSED"                    "$ec" "2"

    # a DANGLING link is the failure the link exists to prevent — it must not pass
    local sb2="$d/lane/tmp/dangling"; mkdir -p "$sb2/godot"
    ln -s "$d/gone" "$sb2/godot/export_templates"
    out="$(EXPORT_TEMPLATES_DIR="$fake" bash "$SELF" "$sb2" 2>&1)"; ec=$?
    _eq "a DANGLING templates link is REFUSED"            "$ec" "2"
    case "$out" in *"resolves to no version directories"*) _eq "  ...and says why" yes yes ;;
                   *) _eq "  ...and says why" no yes ;; esac

    # no argument
    out="$(EXPORT_TEMPLATES_DIR="$fake" bash "$SELF" "" 2>&1)"; ec=$?
    _eq "no path argument is REFUSED"                     "$ec" "2"

    rm -rf "$d"
    printf '\nselftest: %s passed, %s failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ]
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    *) build "${1:-}"; exit $? ;;
esac
