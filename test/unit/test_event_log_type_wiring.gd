extends GutTest

## tick 253: audit EventLog TYPE_* constants for unrecorded references.
## Continues the silent-fail audit pattern from ticks 247-252.
##
## EventLog feeds the RebalanceDaemon's LLM prompt with recent gameplay
## events. A TYPE_* const that's defined but never .record()'d means
## the LLM never sees that event class — silently weakens the prompt.
##
## Audits:
##   1. Every TYPE_* in EventLog is recorded somewhere OR in
##      KNOWN_UNRECORDED (acknowledged extensibility hook).
##   2. KNOWN_UNRECORDED entries are still defined in EventLog.
##   3. Tick 253 wave: TYPE_ITEM_OBTAINED is now recorded.
##
## TYPE_CUSTOM is the documented extensibility hook — third-party /
## debug tools can record arbitrary events with it. Stays in
## KNOWN_UNRECORDED.

const EVENT_LOG := "res://src/llm/EventLog.gd"

const KNOWN_UNRECORDED: Array[String] = [
	"TYPE_CUSTOM",
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _list_type_constants() -> Array:
	var content: String = _read(EVENT_LOG)
	var rx := RegEx.new()
	rx.compile("const (TYPE_[A-Z_]+)\\s*:=")
	var out: Array[String] = []
	for m in rx.search_all(content):
		out.append(m.get_string(1))
	return out


func _is_type_recorded(name: String) -> bool:
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
		elif entry.ends_with(".gd") and not entry.ends_with("EventLog.gd"):
			var content: String = FileAccess.get_file_as_string(full)
			if content.contains("." + name):
				dir.list_dir_end()
				return true
	dir.list_dir_end()
	return false


# ── Audit 1 ────────────────────────────────────────────────────────

func test_every_type_constant_recorded_or_acknowledged() -> void:
	var types: Array = _list_type_constants()
	assert_gt(types.size(), 0, "sanity: must find at least one TYPE_* const")
	var dead: Array[String] = []
	for t in types:
		if _is_type_recorded(t):
			continue
		if t in KNOWN_UNRECORDED:
			continue
		dead.append(t)
	assert_eq(dead.size(), 0,
		"TYPE_* constants defined but never .record()'d and not in KNOWN_UNRECORDED: %s" % str(dead))


# ── Audit 2 ────────────────────────────────────────────────────────

func test_known_unrecorded_entries_still_defined() -> void:
	var types: Array = _list_type_constants()
	var stale: Array[String] = []
	for t in KNOWN_UNRECORDED:
		if not (t in types):
			stale.append(t)
	assert_eq(stale.size(), 0,
		"KNOWN_UNRECORDED entries missing from EventLog (renamed? deleted?): %s" % str(stale))


# ── Audit 3 ────────────────────────────────────────────────────────

func test_tick_253_item_obtained_recorded() -> void:
	assert_true(_is_type_recorded("TYPE_ITEM_OBTAINED"),
		"TYPE_ITEM_OBTAINED must be recorded by BattleManager's drop loop — defined but unrecorded pre-tick-253")


# ── Cross-pin: tick 41-era types preserved ────────────────────────

func test_existing_types_still_recorded() -> void:
	for t in ["TYPE_BOSS_DEFEAT", "TYPE_PARTY_WIPE", "TYPE_AREA_ENTERED",
			"TYPE_LEVEL_UP", "TYPE_STORY_FLAG"]:
		assert_true(_is_type_recorded(t),
			"pre-existing event type %s must still be recorded somewhere" % t)
