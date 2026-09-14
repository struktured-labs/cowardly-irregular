#!/usr/bin/env bash
# Web-boot smoke: executes the ACTUAL WASM build in headless chromium.
# Finds a playwright module on the machine (no project-local install needed).
#   tools/web_smoke.sh [port]
#   tools/web_smoke.sh --selftest
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

# The module is found by globbing a SIBLING project's node_modules, so it goes
# missing whenever some other lane cleans its tree. That used to be a bare
# `exit 3`, which deploy_web.sh turns into a WARNING and then publishes anyway
# -- so an unrelated tidy-up in an unrelated checkout could take the only gate
# that boots the real WASM build off the deploy, with nobody deciding to. The
# web export, its custom shell and its service worker are covered by NOTHING
# else. Skipping is still supported; it now has to be asked for out loud.
# Never fired in 116 archived publishes as of 2026-09-13 -- this closes the
# path before it does, it is not an incident report.
find_playwright() {
    local cand
    for cand in "$HOME"/projects/*/node_modules/playwright; do
        [ -d "$cand" ] && { dirname "$cand"; return 0; }
    done
    return 1
}

# 0 = found (prints the dir) · 3 = deliberate skip · 4 = blocked
resolve_playwright() {
    local dir
    if dir="$(find_playwright)"; then
        printf '%s\n' "$dir"
        return 0
    fi
    if [ "${WEB_SMOKE_OPTIONAL:-0}" = "1" ]; then
        echo "[WEB-SMOKE] SKIPPED: no playwright module found, and WEB_SMOKE_OPTIONAL=1 asked for that" >&2
        return 3
    fi
    echo "[WEB-SMOKE] BLOCKED: no playwright module under \$HOME/projects/*/node_modules/playwright" >&2
    echo "[WEB-SMOKE]   This is the only gate that boots the real WASM build. The web export, the" >&2
    echo "[WEB-SMOKE]   custom shell and the service worker are gated by nothing else, so a web" >&2
    echo "[WEB-SMOKE]   release without it is unverified." >&2
    echo "[WEB-SMOKE]   Install playwright, or set WEB_SMOKE_OPTIONAL=1 to deploy without this gate." >&2
    return 4
}

selftest() {
    local pass=0 fail=0 saw_found=0 saw_skip=0 saw_block=0
    local tmp; tmp="$(mktemp -d "$PWD/tmp/web_smoke_selftest.XXXXXX")"
    mkdir -p "$tmp/haspw/projects/sibling/node_modules/playwright" "$tmp/nopw/projects/other"

    check() { # label expected_rc actual_rc extra_desc
        local label="$1" want="$2" got="$3" extra="${4:-}"
        if [ "$want" = "$got" ]; then
            pass=$((pass + 1)); echo "  ok    ${label} -> rc ${got} ${extra}"
        else
            fail=$((fail + 1)); echo "  FAIL  ${label} -> rc ${got}, expected ${want} ${extra}" >&2
        fi
    }

    local out rc
    # 1. present: resolves, and names a real directory (not just any rc 0)
    out="$(HOME="$tmp/haspw" WEB_SMOKE_OPTIONAL=0 resolve_playwright 2>/dev/null)" && rc=0 || rc=$?
    check "playwright present" 0 "$rc"
    [ "$rc" = 0 ] && saw_found=1
    if [ "$rc" = 0 ] && [ -d "$out/playwright" ]; then
        pass=$((pass + 1)); echo "  ok    present: returned a dir that really holds playwright"
    else
        fail=$((fail + 1)); echo "  FAIL  present: returned '${out}', which has no playwright/ in it" >&2
    fi

    # 2. absent, no opt-out: BLOCKS. This is the arm the change exists for.
    out="$(HOME="$tmp/nopw" resolve_playwright 2>&1)" && rc=0 || rc=$?
    check "absent, no opt-out" 4 "$rc"
    [ "$rc" = 4 ] && saw_block=1
    case "$out" in
        *BLOCKED*WEB_SMOKE_OPTIONAL*) pass=$((pass + 1)); echo "  ok    blocked message names the opt-out" ;;
        *) fail=$((fail + 1)); echo "  FAIL  blocked message does not say how to proceed: ${out}" >&2 ;;
    esac

    # 3. absent, opted out: skips, exactly as before the change
    out="$(HOME="$tmp/nopw" WEB_SMOKE_OPTIONAL=1 resolve_playwright 2>&1)" && rc=0 || rc=$?
    check "absent, WEB_SMOKE_OPTIONAL=1" 3 "$rc"
    [ "$rc" = 3 ] && saw_skip=1

    # 4. the opt-out must not be able to CREATE a skip where the module exists
    out="$(HOME="$tmp/haspw" WEB_SMOKE_OPTIONAL=1 resolve_playwright 2>/dev/null)" && rc=0 || rc=$?
    check "present + opt-out (opt-out must not skip a working gate)" 0 "$rc"

    # 5. the real box: if this reds, the glob itself broke, not the policy
    out="$(resolve_playwright 2>/dev/null)" && rc=0 || rc=$?
    check "this machine" 0 "$rc" "(${out:-none})"

    rm -rf "$tmp"
    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$saw_found$saw_skip$saw_block" != "111" ]; then
        echo "selftest: BROKEN — outcomes seen: found=${saw_found} skip=${saw_skip} blocked=${saw_block};" >&2
        echo "          all three required, or the table is not exercising the policy" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
esac

PORT="${1:-8371}"
PW_DIR="$(resolve_playwright)" || exit $?
mkdir -p tmp
python3 tools/web_smoke_server.py "$PORT" builds/web & SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 1
PW_MODULE="file://$PW_DIR/playwright/index.mjs" node tools/web_smoke.mjs "http://127.0.0.1:$PORT"
