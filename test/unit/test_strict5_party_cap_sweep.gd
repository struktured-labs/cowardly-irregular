extends GutTest

## tick 269: source-lint regression banning party-loop caps at 4.
##
## Tick 268 found the cap-at-4 bug in SaveScreen (5th party member
## silently never rendered). The bug class is "old 4-party assumption
## leaking into a strict-5 codebase". This tick swept and found 4 more
## sites:
##   - AutogrindUI.gd:482  — autogrind status panel (initial render)
##   - AutogrindUI.gd:2054 — autogrind status panel (refresh)
##   - GameLoop.gd:4389    — autogrind overlay party container
##   - GameLoop.gd:4497    — autogrind overlay party update
##
## All four silently truncated the 5th party member. slot_w was even
## already correctly derived from party.size() — leaving a sized but
## unfilled column.
##
## This test scans src/ for any remaining `range(min(<party>, 4))`
## or `range(min(<party_summary>, 4))` patterns. If a new one appears
## (refactor / new menu / new view), test fails until either:
##   - the cap is bumped to 5 (real strict-5 fix), OR
##   - the call site is added to ALLOWLIST with a documented reason
##     (e.g. a hand-coded 4-slot debug view that's intentionally
##     short).

const SRC_DIR := "res://src"

# Patterns that LOOK like the bug.
const BAD_PATTERNS: Array[String] = [
	"range(min(party.size(), 4))",
	"range(min(_party.size(), 4))",
	"range(min(party_summary.size(), 4))",
]

# Files allowed to keep the cap at 4 (documented exceptions). Empty
# for now; if a future view legitimately wants 4 slots only, add
# {file: "...", reason: "..."} here.
const ALLOWLIST: Array[String] = []


func _walk(dir: DirAccess, base: String, out: Array[String]) -> void:
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue
		var full: String = "%s/%s" % [base, entry]
		if dir.current_is_dir():
			var sub := DirAccess.open(full)
			if sub != null:
				_walk(sub, full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
	dir.list_dir_end()


# ── Audit: no cap-at-4 party loops survive ─────────────────────────

func test_no_cap_at_4_party_loops_in_src() -> void:
	var dir := DirAccess.open(SRC_DIR)
	assert_ne(dir, null, "src directory must exist")
	var files: Array[String] = []
	_walk(dir, SRC_DIR, files)
	var offenders: Array[String] = []
	for path in files:
		if path in ALLOWLIST:
			continue
		var content: String = FileAccess.get_file_as_string(path)
		var line_no: int = 0
		for line in content.split("\n"):
			line_no += 1
			var stripped: String = line.strip_edges()
			if stripped.begins_with("#"):
				continue
			for bad in BAD_PATTERNS:
				if stripped.contains(bad):
					offenders.append("%s:%d  %s" % [path, line_no, stripped])
					break
	assert_eq(offenders.size(), 0,
		"strict-5 party — cap-at-4 loops silently truncate the 5th member. Bump to 5 OR document the exception in ALLOWLIST. Offenders:\n%s" % "\n".join(PackedStringArray(offenders)))


# ── Spot-pin the 4 tick-269 fixes ──────────────────────────────────

func test_tick_269_fixes_landed() -> void:
	var save_screen: String = FileAccess.get_file_as_string("res://src/ui/SaveScreen.gd")
	assert_true(save_screen.contains("range(min(party_summary.size(), 5))"),
		"tick 268 SaveScreen fix preserved")
	var au: String = FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindUI.gd")
	var au5_count: int = au.count("range(min(_party.size(), 5))")
	assert_eq(au5_count, 2,
		"AutogrindUI must have BOTH party loops bumped (initial render + refresh)")
	var gl: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var gl5_count: int = gl.count("range(min(party.size(), 5))")
	assert_eq(gl5_count, 2,
		"GameLoop autogrind overlay must have BOTH party loops bumped (initial + update)")
