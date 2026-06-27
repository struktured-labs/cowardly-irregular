extends GutTest

## tick 279: BaseVillage._ready now ratchets a `visited_<short>`
## story_flag where short = area_id minus the "_village" suffix.
##
## Pre-fix: 4 overworld scripts (SuburbanOverworld, SteampunkOverworld,
## IndustrialOverworld, FuturisticOverworld) read these flags to
## switch the objective arrow from "go to <village>" → "head to
## the forward portal". NOTHING set them. The arrow stayed pointed
## at the village forever — including after the player had been there.
##
## Pattern audit:
##   visited_brasston       (W3, SteampunkOverworld:140)
##   visited_maple_heights  (W2, SuburbanOverworld:142)
##   visited_node_prime     (W5, FuturisticOverworld:143)
##   visited_rivet_row      (W4, IndustrialOverworld:138)
##
## Derived flag = area_id.replace("_village", "") so all of those
## just work with no other changes (BrasstonVillage area_id is
## "brasston_village" → flag = "visited_brasston").

const BASE_VILLAGE := "res://src/maps/villages/BaseVillage.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── BaseVillage._ready sets the flag ──────────────────────────────

func test_ready_sets_visited_flag() -> void:
	var src := _read(BASE_VILLAGE)
	assert_true(src.contains("set_story_flag(\"visited_\" + aid.replace(\"_village\", \"\"), true)"),
		"BaseVillage._ready must ratchet visited_<short> via set_story_flag")


func test_ready_guards_on_area_id_suffix() -> void:
	# Only villages whose area_id ends in "_village" get the flag.
	# Catches a regression where BaseVillage's default returns "village"
	# (which would set "visited_" — useless / noisy).
	var src := _read(BASE_VILLAGE)
	assert_true(src.contains("if aid.ends_with(\"_village\")"),
		"BaseVillage must guard on '_village' suffix so the base default doesn't ratchet 'visited_'")


# ── Cross-pin: each W2-W5 reader's flag is now writable ────────────

func test_each_reader_flag_matches_a_real_village_area_id() -> void:
	# For each "visited_X" the overworlds read, there must be a village
	# whose area_id is "X_village" so the BaseVillage ratchet actually
	# fires that flag.
	const FLAG_TO_VILLAGE_AREA_ID := {
		"visited_maple_heights": "maple_heights_village",
		"visited_brasston":      "brasston_village",
		"visited_rivet_row":     "rivet_row_village",
		"visited_node_prime":    "node_prime_village",
	}
	var dir := DirAccess.open("res://src/maps/villages")
	assert_ne(dir, null, "villages dir must exist")
	dir.list_dir_begin()
	var area_ids: Array[String] = []
	while true:
		var entry: String = dir.get_next()
		if entry == "":
			break
		if not entry.ends_with(".gd"):
			continue
		var src: String = FileAccess.get_file_as_string("res://src/maps/villages/" + entry)
		# Extract whatever the `_get_area_id` function returns.
		var rx := RegEx.new()
		rx.compile("func _get_area_id\\(\\)[^\"]+\"([a-z0-9_]+)\"")
		var m := rx.search(src)
		if m != null:
			area_ids.append(m.get_string(1))
	dir.list_dir_end()
	var missing: Array[String] = []
	for flag in FLAG_TO_VILLAGE_AREA_ID:
		var expected_area: String = FLAG_TO_VILLAGE_AREA_ID[flag]
		if not (expected_area in area_ids):
			missing.append("%s expects area_id %s" % [flag, expected_area])
	assert_eq(missing.size(), 0,
		"each overworld 'visited_X' read must have a village whose area_id is 'X_village': %s" % str(missing))


# ── Behavioral: setting up a village via _ready writes the flag ──

func test_setting_up_a_village_ratchets_visited_flag() -> void:
	# Use MapleHeightsVillage as the fixture (area_id =
	# maple_heights_village → expected flag = visited_maple_heights).
	GameState.story_flags.erase("visited_maple_heights")
	assert_false(GameState.get_story_flag("visited_maple_heights"),
		"precondition: flag must start unset")
	var script: GDScript = load("res://src/maps/villages/MapleHeightsVillage.gd")
	var inst: Node = script.new()
	# add_child triggers _ready in GUT. We don't actually need the
	# full scene built — _ready will run its hooks (some may push
	# warnings on missing texture/spawn paths in headless, that's OK).
	add_child_autofree(inst)
	# Give the deferred ratchet time to land.
	await get_tree().process_frame
	assert_true(GameState.get_story_flag("visited_maple_heights"),
		"after MapleHeightsVillage._ready, visited_maple_heights must be set (was dead pre-tick-279)")
	GameState.story_flags.erase("visited_maple_heights")
