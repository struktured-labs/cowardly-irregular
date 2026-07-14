extends GutTest

## tick 260: BestiarySystem tracks last-known encounter location per
## monster so the bestiary detail panel can show "Last seen: <place>"
## next to the static "Found in:" line.
##
## Static enemy_pools shows EVERY pool the monster belongs to
## (completionist data). Last-seen tracks where the PLAYER actually
## encountered them last — autobattle-planning hint: "I farmed slime
## in Cave Floor 1 last time, go back there".
##
## Empty location_id leaves the prior record intact — caller has no
## map context (test fixture, Scriptweaver internal spawn).


func before_each() -> void:
	GameState.game_constants["seen_monsters"] = {}
	GameState.game_constants["defeated_monsters"] = {}
	GameState.game_constants.erase("seen_monsters_last_location")
	BestiarySystem.reload()


# ── Basic write + read ─────────────────────────────────────────────

func test_mark_seen_records_location() -> void:
	BestiarySystem.mark_seen("slime", "cave_floor_1")
	assert_eq(BestiarySystem.get_last_seen_location("slime"), "Cave Floor 1",
		"location must be stored and prettified via _titlecase")


func test_mark_defeated_records_location() -> void:
	BestiarySystem.mark_defeated("slime", "village_harmonia")
	assert_eq(BestiarySystem.get_last_seen_location("slime"), "Village Harmonia",
		"mark_defeated must forward location through to mark_seen")


# ── Empty location_id is non-destructive ──────────────────────────

func test_empty_location_does_not_overwrite_prior_record() -> void:
	BestiarySystem.mark_seen("slime", "cave_floor_1")
	# Re-mark without a location (caller has no map context).
	BestiarySystem.mark_seen("slime", "")
	assert_eq(BestiarySystem.get_last_seen_location("slime"), "Cave Floor 1",
		"empty location must leave the prior 'Cave Floor 1' record intact")


# ── Later encounter overwrites earlier ─────────────────────────────

func test_later_encounter_replaces_earlier_location() -> void:
	BestiarySystem.mark_seen("slime", "cave_floor_1")
	BestiarySystem.mark_seen("slime", "cave_floor_3")
	assert_eq(BestiarySystem.get_last_seen_location("slime"), "Cave Floor 3",
		"a later encounter must overwrite the earlier last_location")


# ── No record returns "" ───────────────────────────────────────────

func test_no_record_returns_empty_string() -> void:
	assert_eq(BestiarySystem.get_last_seen_location("never_encountered"), "",
		"unrecorded monster_id must return '' (caller gates UI line on non-empty)")


# ── Legacy save (no seen_monsters_last_location dict) ──────────────

func test_legacy_save_without_location_dict_safe() -> void:
	# Pre-tick-260 saves have no seen_monsters_last_location key in
	# game_constants. get_last_seen_location must not crash on missing.
	GameState.game_constants.erase("seen_monsters_last_location")
	BestiarySystem.mark_seen("slime", "")  # legacy mark_seen call shape
	assert_eq(BestiarySystem.get_last_seen_location("slime"), "",
		"legacy mark_seen call (no location) must produce empty result without crash")


# ── get_seen_entries_sorted exposes last_location field ────────────

func test_seen_entries_include_last_location_field() -> void:
	# Skip if 'slime' isn't in the cache.
	if BestiarySystem.get_monster_data("slime").is_empty():
		push_warning("[test] slime missing from monsters.json — skipping")
		return
	BestiarySystem.mark_seen("slime", "cave_floor_1")
	var entries: Array = BestiarySystem.get_seen_entries_sorted()
	var slime_entry: Dictionary = {}
	for e in entries:
		if e.id == "slime":
			slime_entry = e
			break
	assert_false(slime_entry.is_empty(), "slime entry must exist in sorted output")
	assert_true(slime_entry.has("last_location"),
		"entry dict must include last_location key (BestiaryMenu reads it)")
	assert_eq(slime_entry["last_location"], "Cave Floor 1",
		"last_location field carries the prettified location")


# ── BestiaryMenu wiring: 'Last seen:' line in detail ───────────────

func test_bestiary_menu_renders_last_seen_line() -> void:
	# Source pin: _refresh_detail must read last_location and append a
	# 'Last seen: ' line when non-empty.
	var src: String = FileAccess.get_file_as_string("res://src/ui/BestiaryMenu.gd")
	assert_true(src.contains("entry.get(\"last_location\", \"\")"),
		"BestiaryMenu must extract last_location from entry dict")
	assert_true(src.contains("\"Last seen: %s\""),
		"BestiaryMenu must render 'Last seen: <location>' block")
