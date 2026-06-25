extends GutTest

## tick 147 regression: BestiaryMenu UI uses the `defeated` field
## to gate intel reveal (seen-but-not-killed shows "???"), AND
## the new `defeated_monsters` game_constants key roundtrips
## through save/load cleanly.
##
## Without the UI gate the bestiary would show full stats on first
## encounter, defeating the discover → defeat → unlock progression
## the tick-146 split was meant to enable.
##
## Without the save roundtrip pin, defeated state would silently
## reset on every save/load (encounter would resume tracking
## correctly via mark_seen, but kill credit would be lost).

const BESTIARY_MENU := "res://src/ui/BestiaryMenu.gd"
const GAME_STATE := "res://src/meta/GameState.gd"
const MARKER_SEEN := "tick_147_seen_only"
const MARKER_KILLED := "tick_147_killed"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func before_each() -> void:
	for d_key in ["seen_monsters", "defeated_monsters"]:
		if GameState.game_constants.has(d_key):
			(GameState.game_constants[d_key] as Dictionary).erase(MARKER_SEEN)
			(GameState.game_constants[d_key] as Dictionary).erase(MARKER_KILLED)


func after_each() -> void:
	before_each()


# ── BestiaryMenu UI gates intel on defeated flag ─────────────────────────

func _detail_body() -> String:
	# Find the function that owns the _detail_stats.text assignment by
	# walking the file's func headers and selecting the last one before
	# the assignment.
	var src := _read(BESTIARY_MENU)
	var stats_idx: int = src.find("_detail_stats.text =")
	assert_gt(stats_idx, -1, "_detail_stats.text assignment must exist")
	var best_fn_idx: int = -1
	var cursor: int = 0
	while true:
		var fn_idx: int = src.find("\nfunc ", cursor)
		if fn_idx < 0 or fn_idx >= stats_idx:
			break
		best_fn_idx = fn_idx + 1
		cursor = fn_idx + 1
	assert_gt(best_fn_idx, -1, "containing function must exist")
	var next_fn: int = src.find("\nfunc ", best_fn_idx)
	return src.substr(best_fn_idx, next_fn - best_fn_idx) if next_fn > -1 else src.substr(best_fn_idx)


func test_detail_reads_defeated_field() -> void:
	# Pin: the rebuild reads entry.defeated to gate stat reveal.
	var body := _detail_body()
	assert_true(body.contains("entry.get(\"defeated\", false)"),
		"detail rebuild must read entry.defeated to gate intel reveal")


func test_undefeated_shows_question_marks_for_stats() -> void:
	# Pin: the not-defeated branch sets stats text to ??? form,
	# NOT the full HP/MP numbers.
	var body := _detail_body()
	assert_true(body.contains("HP ???   MP ???   ATK ???   DEF ???   MAG ???   SPD ???"),
		"un-defeated stats line must show ??? — not real numbers")
	assert_true(body.contains("Weak: ???"),
		"un-defeated weaknesses must be ???")
	assert_true(body.contains("Resist: ???"),
		"un-defeated resistances must be ???")
	assert_true(body.contains("EXP: ???   Gold: ???"),
		"un-defeated rewards must be ???")
	assert_true(body.contains("Drops: ???   (defeat to unlock)"),
		"un-defeated drops must show unlock hint")


func test_defeated_branch_still_shows_full_intel() -> void:
	# Negative regression: don't accidentally break the full-intel
	# render path for defeated entries.
	var body := _detail_body()
	assert_true(body.contains("HP %d   MP %d   ATK %d   DEF %d   MAG %d   SPD %d"),
		"defeated branch must still render full stat numbers")
	assert_true(body.contains("_format_drops("),
		"defeated branch must still call _format_drops for the drop table")


func test_list_row_dims_undefeated_entries() -> void:
	# Pin: _highlight_row reads defeated and applies a dimmer color
	# / "?" prefix for un-defeated entries.
	var src := _read(BESTIARY_MENU)
	var idx: int = src.find("func _highlight_row")
	assert_gt(idx, -1, "_highlight_row must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("entry.get(\"defeated\", false)"),
		"row builder must read entry.defeated")
	assert_true(body.contains("\"? \" + entry.name"),
		"un-defeated rows must prefix name with '? '")
	# Dim color path present.
	assert_true(body.contains("TEXT_COLOR.r * 0.55"),
		"un-defeated rows must use ~55% brightness dim color")


# ── Save/load roundtrip for defeated_monsters ────────────────────────────

func _json_roundtrip(d: Dictionary) -> Dictionary:
	# Simulate the real SaveSystem path: JSON.stringify on save,
	# JSON.parse on load. Gives a deep copy so test isolation is
	# real, mirroring on-disk save semantics. GameState.to_dict
	# returns shallow-copy refs to inner dicts, so a naive
	# snapshot/erase/restore against the same in-memory dict would
	# erase from the snapshot too.
	var serialized: String = JSON.stringify(d)
	var json := JSON.new()
	var err: int = json.parse(serialized)
	assert_eq(err, OK, "JSON roundtrip must parse cleanly")
	return json.data as Dictionary


func test_defeated_monsters_survives_save_load_roundtrip() -> void:
	BestiarySystem.mark_defeated(MARKER_KILLED)
	assert_true(BestiarySystem.is_defeated(MARKER_KILLED),
		"sanity: marker set before snapshot")

	var snapshot: Dictionary = _json_roundtrip(GameState.to_dict())
	# Wipe the runtime state to simulate a fresh load.
	if GameState.game_constants.has("defeated_monsters"):
		(GameState.game_constants["defeated_monsters"] as Dictionary).erase(MARKER_KILLED)
	if GameState.game_constants.has("seen_monsters"):
		(GameState.game_constants["seen_monsters"] as Dictionary).erase(MARKER_KILLED)
	assert_false(BestiarySystem.is_defeated(MARKER_KILLED),
		"sanity: marker erased pre-restore")

	GameState.from_dict(snapshot)
	assert_true(BestiarySystem.is_defeated(MARKER_KILLED),
		"defeated_monsters must survive save/load — was the silent gap before tick 147")


func test_seen_only_survives_save_load_independently() -> void:
	# Cross-check: seen-but-not-killed must also roundtrip, AND
	# stay distinct from defeated (you don't get auto-credit on
	# reload).
	BestiarySystem.mark_seen(MARKER_SEEN)
	# Confirm only seen, not defeated.
	assert_true(BestiarySystem.is_seen(MARKER_SEEN))
	assert_false(BestiarySystem.is_defeated(MARKER_SEEN))

	var snapshot: Dictionary = _json_roundtrip(GameState.to_dict())
	(GameState.game_constants["seen_monsters"] as Dictionary).erase(MARKER_SEEN)
	assert_false(BestiarySystem.is_seen(MARKER_SEEN), "sanity")

	GameState.from_dict(snapshot)
	assert_true(BestiarySystem.is_seen(MARKER_SEEN),
		"seen_monsters must roundtrip")
	assert_false(BestiarySystem.is_defeated(MARKER_SEEN),
		"seen-only state must NOT silently auto-promote to defeated on reload — invariant from tick 146")


func test_seen_entries_carry_defeated_after_reload() -> void:
	# Round-trip the entries list and verify defeated flag survives.
	# Snapshot + restore slime's pre-test state so this test doesn't
	# permanently mark slime defeated for the suite.
	var pre_seen: bool = BestiarySystem.is_seen("slime")
	var pre_def: bool = BestiarySystem.is_defeated("slime")
	BestiarySystem.mark_defeated("slime")  # using real id so monsters_cache resolves
	var entries_pre: Array = BestiarySystem.get_seen_entries_sorted()
	var slime_pre: Dictionary = {}
	for e in entries_pre:
		if e.id == "slime":
			slime_pre = e
			break
	assert_eq(bool(slime_pre.get("defeated", false)), true,
		"pre-roundtrip: slime entry shows defeated=true")

	var snapshot: Dictionary = _json_roundtrip(GameState.to_dict())
	GameState.from_dict(snapshot)

	var entries_post: Array = BestiarySystem.get_seen_entries_sorted()
	var slime_post: Dictionary = {}
	for e in entries_post:
		if e.id == "slime":
			slime_post = e
			break
	# Restore slime's pre-test state so the suite isn't polluted.
	if not pre_def and GameState.game_constants.has("defeated_monsters"):
		(GameState.game_constants["defeated_monsters"] as Dictionary).erase("slime")
	if not pre_seen and GameState.game_constants.has("seen_monsters"):
		(GameState.game_constants["seen_monsters"] as Dictionary).erase("slime")
	assert_eq(bool(slime_post.get("defeated", false)), true,
		"post-roundtrip: slime entry's defeated flag preserved")
