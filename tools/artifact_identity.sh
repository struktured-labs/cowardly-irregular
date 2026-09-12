#!/usr/bin/env bash
# Print a one-line identity for an exported binary: format, size, content hash.
#
# WHY THIS EXISTS
# ---------------
# deploy_desktop.sh runs a boot smoke for BOTH platforms and asserts "[GAME] Started" in
# tmp/<plat>_boot.log. Measured on v3.33.316-alpha's archived logs, those two files are
# indistinguishable by CONTENT:
#
#     [GAME] Started            present in both
#     "Godot Engine v4.4.1.stable.official.49a5bc7b6"   byte-identical banner in both
#     any wine / drive-letter / prefix path             absent from both
#
# The platform identity of that evidence is carried ENTIRELY BY THE FILENAME. The chain is
# correct today -- `cd build/windows && wine ./cowardly-irregular.exe`, and the Linux binary is
# not in that directory -- but if BOOT_RUNNER or ARTIFACT were ever mis-wired, the logs would
# look exactly the same and no archived evidence could show it. The Windows boot smoke is the
# only thing proving the .exe runs at all, so "it looks like it passed" is not good enough.
#
# Format is read from MAGIC BYTES rather than `file`, so this needs no extra dependency and the
# selftest can build fixtures byte-exactly.
#
# Usage:  tools/artifact_identity.sh <path>
#         tools/artifact_identity.sh --selftest
set -uo pipefail

_fmt() {
    local f="$1" head4
    head4=$(head -c4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')
    case "$head4" in
        7f454c46*) printf 'ELF'      ;;   # \x7f E L F
        4d5a*)     printf 'PE/COFF'  ;;   # M Z
        cffaedfe*|cefaedfe*) printf 'Mach-O' ;;
        "")        printf 'EMPTY'    ;;
        *)         printf 'unknown(%s)' "${head4:0:8}" ;;
    esac
}

_identity() {
    local f="$1"
    [ -e "$f" ] || { echo "artifact_identity: no such file: $f" >&2; return 2; }
    [ -s "$f" ] || { echo "artifact_identity: empty file: $f" >&2; return 2; }
    printf '%s · %s bytes · sha256 %s\n' \
        "$(_fmt "$f")" "$(stat -c%s "$f")" "$(sha256sum "$f" | cut -c1-16)"
}

case "${1:-}" in
    --selftest) ;;
    "")  echo "usage: $0 <path> | --selftest" >&2; exit 2 ;;
    *)   _identity "$1"; exit $? ;;
esac

# ── selftest ─────────────────────────────────────────────────────────────────────────────
pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %-50s %s\n' "$1" "$2";
        else fail=$((fail+1)); printf '  FAIL  %-50s got %s want %s\n' "$1" "$2" "$3"; fi; }

mkdir -p tmp
T="$(mktemp -d "$(pwd)/tmp/artid.XXXXXX")"; trap 'rm -rf "$T"' EXIT
printf '\x7fELF\x02\x01\x01\x00padding' > "$T/linuxish"
printf 'MZ\x90\x00\x03\x00\x00\x00pad'  > "$T/winish"
printf 'notamagic'                      > "$T/other"
: > "$T/empty"

# 1/2 — the two platforms must come out DIFFERENT. A helper that printed one label for
#       everything would pass either arm alone; it needs both to mean anything.
chk "ELF magic reports ELF"      "$("$0" "$T/linuxish" | cut -d' ' -f1)" "ELF"
chk "MZ magic reports PE/COFF"   "$("$0" "$T/winish"   | cut -d' ' -f1)" "PE/COFF"
chk "the two labels differ"      "$([ "$("$0" "$T/linuxish" | cut -d' ' -f1)" != "$("$0" "$T/winish" | cut -d' ' -f1)" ] && echo yes || echo no)" "yes"

# 3 — an unrecognised format is NAMED, not silently called one of the two.
chk "unknown magic is reported as unknown" "$("$0" "$T/other" | cut -d' ' -f1)" "unknown(6e6f7461)"

# 4 — size and hash actually track the file, so the line cannot go stale.
sz=$(stat -c%s "$T/winish")
chk "size is the real byte count" "$("$0" "$T/winish" | awk '{print $3}')" "$sz"
printf 'MZ\x90\x00\x03\x00\x00\x00DIFFERENT' > "$T/winish2"
chk "different content -> different hash" \
    "$([ "$("$0" "$T/winish" | awk '{print $NF}')" != "$("$0" "$T/winish2" | awk '{print $NF}')" ] && echo yes || echo no)" "yes"

# 5 — refuse rather than emit a confident line about nothing.
"$0" "$T/empty" >/dev/null 2>&1;    chk "empty file exits 2"   "$?" "2"
"$0" "$T/absent" >/dev/null 2>&1;   chk "missing file exits 2" "$?" "2"
"$0" >/dev/null 2>&1;               chk "no argument exits 2"  "$?" "2"

echo; echo "selftest: ${pass} passed, ${fail} failed"; [ "$fail" -eq 0 ]
