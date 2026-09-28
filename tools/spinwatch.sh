#!/usr/bin/env bash
# Runs a command unchanged; if a godot it starts spins its audio mix thread, writes a gdb stack to tmp/. Contract and usage: tools/spinwatch.py.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/spinwatch.py" "$@"
