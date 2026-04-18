#!/usr/bin/env python3
"""Scans all overworld and village .gd files for _create_npc calls,
then counts dialogue lines (strings in the 4th arg array) per NPC.

Reports NPCs with <=3 lines so we know where to expand.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

TARGETS = [
    *SRC.glob("exploration/*Overworld.gd"),
    *SRC.glob("maps/villages/*.gd"),
    *SRC.glob("maps/interiors/*.gd"),
]

CREATE_NPC_RE = re.compile(
    r'_create_npc\s*\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,',
    re.DOTALL,
)


def find_opening_bracket(text: str, start: int) -> int:
    """Scan forward from start, skipping balanced () — return index of the
    first top-level `[` that opens the dialogue array."""
    paren_depth = 0
    i = start
    in_string = False
    while i < len(text):
        c = text[i]
        if in_string:
            if c == '\\':
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            i += 1
            continue
        if c == '(':
            paren_depth += 1
        elif c == ')':
            paren_depth -= 1
        elif c == '[' and paren_depth == 0:
            return i + 1
        i += 1
    return -1


def count_strings_in_array(text: str, start: int) -> tuple[int, int]:
    """Starting just after the opening [ at position `start`, count top-level
    string literals until matching ]. Returns (count, end_pos_after_bracket).
    """
    depth = 1
    count = 0
    i = start
    in_string = False
    while i < len(text) and depth > 0:
        c = text[i]
        if in_string:
            if c == '\\':
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            count += 1  # Only top-level strings (inside array, depth==1)
            if depth != 1:
                count -= 1
            i += 1
            continue
        if c == '[':
            depth += 1
        elif c == ']':
            depth -= 1
            if depth == 0:
                return count, i + 1
        i += 1
    return count, i


def main() -> None:
    results: list[tuple[str, str, str, int]] = []  # (file, npc, type, lines)

    for f in sorted(TARGETS):
        text = f.read_text()
        for m in CREATE_NPC_RE.finditer(text):
            npc_name, npc_type = m.group(1), m.group(2)
            bracket = find_opening_bracket(text, m.end())
            if bracket < 0:
                continue
            count, _ = count_strings_in_array(text, bracket)
            results.append((f.relative_to(ROOT).as_posix(), npc_name, npc_type, count))

    results.sort(key=lambda r: (r[3], r[0], r[1]))

    print(f"Total NPCs: {len(results)}")
    print()
    print("NPCs with ≤3 dialogue lines (expansion targets):")
    print(f"{'file':<45} {'npc':<32} {'type':<12} lines")
    print("-" * 95)
    for f, name, ntype, count in results:
        if count <= 3:
            print(f"{f:<45} {name:<32} {ntype:<12} {count}")

    print()
    print("Distribution:")
    from collections import Counter
    dist = Counter(r[3] for r in results)
    for n in sorted(dist):
        print(f"  {n} lines: {dist[n]} NPCs")


if __name__ == "__main__":
    main()
