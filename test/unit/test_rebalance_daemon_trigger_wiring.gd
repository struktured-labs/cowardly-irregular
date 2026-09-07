extends GutTest

## tick 252: audit RebalanceDaemon TRIGGER_* constants for unfired
## references. Same silent-fail class as the PartyChatSystem
## event_flag_* sweep (ticks 247-251) — a constant exists, downstream
## code reads it via consider(trigger_type, ...), but no upstream
## site actually fires the trigger. The daemon would never be
## consulted for that event.
##
## Audits:
##   1. Every TRIGGER_* in the daemon is fired by ::consider() somewhere
##      OR is in KNOWN_UNFIRED (acknowledged debug-only / future use).
##   2. KNOWN_UNFIRED entries are still defined in the daemon
##      (catch deletions / renames).
##   3. Tick 252 wave: TRIGGER_AREA_ENTERED is now fired.

const DAEMON := "res://src/llm/RebalanceDaemon.gd"

## TRIGGER_* constants that are intentionally never fired by gameplay
## code. Currently just TRIGGER_MANUAL, reserved for debug-panel pokes.
const KNOWN_UNFIRED: Array[String] = [
	"TRIGGER_MANUAL",
]


func _read(p: String) -> String:
	var s: String = FileAccess.get_file_as_string(p)
	return s


func _list_trigger_constants() -> Array:
	# Scrape `const TRIGGER_FOO := "..."` declarations from the daemon.
	var content: String = _read(DAEMON)
	var rx := RegEx.new()
	rx.compile("const (TRIGGER_[A-Z_]+)\\s*:=")
	var out: Array[String] = []
	for m in rx.search_all(content):
		out.append(m.get_string(1))
	return out


# Recursively look for `RebalanceDaemonScript.<NAME>` OR
# `daemon.consider(...)` with the same string literal value. Conservative:
# any literal occurrence of the constant name in src/ outside the
# daemon's own file counts.
func _is_trigger_fired(name: String) -> bool:
	var dir := DirAccess.open("res://src")
	if dir == null:
		return false
	return _walk_for_ref(dir, "res://src", name)


func _walk_for_ref(dir: DirAccess, base: String, name: String) -> bool:
	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue
		var full: String = "%s/%s" % [base, entry]
		if dir.current_is_dir():
			var subdir := DirAccess.open(full)
			if subdir != null and _walk_for_ref(subdir, full, name):
				dir.list_dir_end()
				return true
		elif entry.ends_with(".gd") and not entry.ends_with("RebalanceDaemon.gd"):
			var content: String = FileAccess.get_file_as_string(full)
			# Match the constant reference. Don't match raw quoted
			# literals (those happen in EventLog / display code without
			# implying the daemon was actually consulted).
			if content.contains("." + name):
				dir.list_dir_end()
				return true
	dir.list_dir_end()
	return false


# ── Audit 1: every TRIGGER_* is fired or KNOWN_UNFIRED ─────────────

func test_every_trigger_constant_fired_or_acknowledged() -> void:
	var triggers: Array = _list_trigger_constants()
	assert_gt(triggers.size(), 0, "sanity: must find at least one TRIGGER_* const")
	var dead: Array[String] = []
	for t in triggers:
		if _is_trigger_fired(t):
			continue
		if t in KNOWN_UNFIRED:
			continue
		dead.append(t)
	assert_eq(dead.size(), 0,
		"TRIGGER_* constants defined but never fired via .consider() and not in KNOWN_UNFIRED: %s" % str(dead))


# ── Audit 2: KNOWN_UNFIRED entries still exist in the daemon ──────

func test_known_unfired_entries_still_defined() -> void:
	var triggers: Array = _list_trigger_constants()
	var stale: Array[String] = []
	for t in KNOWN_UNFIRED:
		if not (t in triggers):
			stale.append(t)
	assert_eq(stale.size(), 0,
		"KNOWN_UNFIRED entries with no matching const in RebalanceDaemon (renamed? deleted? clean up the list): %s" % str(stale))


# ── Audit 3: tick 252 wave — AREA_ENTERED specifically wired ──────

func test_tick_252_area_entered_fired() -> void:
	assert_true(_is_trigger_fired("TRIGGER_AREA_ENTERED"),
		"TRIGGER_AREA_ENTERED must be fired from GameLoop's area-transition handler — was defined but unfired pre-tick-252")


# ── Cross-pin: tick 41-era triggers preserved ──────────────────────

func test_existing_triggers_still_fired() -> void:
	# Sanity: ticks 247-style refactors haven't disconnected the
	# wipe/defeat/level_up handlers.
	for t in ["TRIGGER_PARTY_WIPE", "TRIGGER_BOSS_DEFEAT", "TRIGGER_LEVEL_UP"]:
		assert_true(_is_trigger_fired(t),
			"pre-existing trigger %s must still be fired (regression check)" % t)
