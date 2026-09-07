extends GutTest

## Regression for F3 (struktured ruling 2026-07-08): save_point_only items
## (Tent) authored the flag but NO code enforced it — usable anywhere. Rule:
## free outside dungeons; inside a dungeon only beside a save crystal.
## Enforced by ItemSystem.save_point_gate_reason + field_use_blocked_reason,
## keyed off MapSystem.DUNGEON_MAP_IDS and SavePoint.player_at_any.


func _tent() -> Dictionary:
	return ItemSystem.get_item("tent")


func test_gate_matrix_for_save_point_only_item() -> void:
	var tent := _tent()
	assert_false(tent.is_empty(), "tent must exist in items.json")
	assert_ne(ItemSystem.save_point_gate_reason(tent, true, false), "",
		"dungeon + no crystal must BLOCK a save_point_only item")
	assert_eq(ItemSystem.save_point_gate_reason(tent, true, true), "",
		"dungeon + at crystal must allow")
	assert_eq(ItemSystem.save_point_gate_reason(tent, false, false), "",
		"outside dungeons must always allow (F3: overworld/village free use)")


func test_gate_ignores_items_without_the_flag() -> void:
	var potion := ItemSystem.get_item("potion")
	assert_false(potion.is_empty(), "potion must exist in items.json")
	assert_eq(ItemSystem.save_point_gate_reason(potion, true, false), "",
		"items without save_point_only are never location-gated")


func test_dungeon_classifier_known_ids() -> void:
	for id in MapSystem.DUNGEON_MAP_IDS:
		assert_true(MapSystem.is_dungeon_map(id), "%s must classify as dungeon" % id)
	for id in ["overworld", "harmonia_village", "tavern_interior", "suburban_overworld", ""]:
		assert_false(MapSystem.is_dungeon_map(id), "%s must NOT classify as dungeon" % id)


func test_every_dungeon_script_id_is_registered() -> void:
	# Scans src/maps/dungeons for cave_id assignments so a NEW dungeon can't
	# silently ship outside the gate (the flag-without-enforcement bug class).
	var rx := RegEx.new()
	rx.compile("cave_id\\s*=\\s*\"([a-z0-9_]+)\"")
	var dir := DirAccess.open("res://src/maps/dungeons")
	assert_not_null(dir, "dungeons dir must open")
	var found := 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string("res://src/maps/dungeons/" + f)
		for m in rx.search_all(text):
			var id := m.get_string(1)
			if id == "dragon_cave":
				continue  # abstract base default, never a live map id
			found += 1
			assert_true(id in MapSystem.DUNGEON_MAP_IDS,
				"dungeon script %s declares cave_id '%s' missing from MapSystem.DUNGEON_MAP_IDS — the F3 Tent gate won't cover it" % [f, id])
	assert_gt(found, 8, "sanity: the cave_id scan should find the dungeon roster")
	assert_true("whispering_cave" in MapSystem.DUNGEON_MAP_IDS,
		"whispering_cave has no cave_id var but IS a dungeon — must stay registered")


func test_save_point_player_at_any_tracks_zone_flag() -> void:
	var sp := SavePoint.new()
	add_child_autofree(sp)
	sp._player_in_zone = false
	assert_false(SavePoint.player_at_any(get_tree()),
		"no crystal has the player in zone -> false")
	sp._player_in_zone = true
	assert_true(SavePoint.player_at_any(get_tree()),
		"player inside a crystal zone -> true")


func test_field_use_fails_open_without_gameloop() -> void:
	# Headless tests have no GameLoop node — the runtime wrapper must allow
	# rather than block (menus only exist inside a running game).
	assert_eq(ItemSystem.field_use_blocked_reason("tent"), "",
		"no GameLoop context must fail open")


func test_tent_data_authored_to_match_the_rule() -> void:
	var tent := _tent()
	assert_true(bool(tent.get("effects", {}).get("save_point_only", false)),
		"tent must keep the save_point_only flag")
	assert_true("dungeon" in str(tent.get("description", "")).to_lower(),
		"tent description must state the dungeon-only restriction (F3 description fix)")
