extends GutTest

## Regression tests for W1 progression flow:
## - Rat King (mid-boss) sets only rat_king_defeated, NOT w1_boss_defeated.
## - Castle Harmonia (Mordaine, final boss) sets w1_boss_defeated + unlock_world=2.
## - Mordaine defeat plays world1_mordaine_defeat cutscene via DragonCave base.
## - OverworldScene registers per-element cave spawn aliases + castle_entrance.
## - OverworldScene._apply_zone_encounters reads enemy_pools.json.
## - HarmoniaVillage suburban portal is gated on w1_boss_defeated.
## - TeleportMenu labels dragon caves as W1 (not W2).
## - CastleHarmonia floor row widths match MAP_WIDTH (20).


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "file should exist: %s" % path)
	var t = f.get_as_text()
	f.close()
	return t


func test_whispering_cave_does_not_set_w1_boss_defeated() -> void:
	var text = _read("res://src/maps/dungeons/WhisperingCave.gd")
	var idx = text.find("func _trigger_boss_battle")
	var body = text.substr(idx, 1500)
	assert_true(body.find("rat_king_defeated") != -1,
		"Rat King spec must still write rat_king_defeated")
	assert_false(body.find("w1_boss_defeated") != -1,
		"Rat King is mid-boss now — must NOT write w1_boss_defeated (Mordaine does)")
	# Should not unlock world either
	assert_false(body.find("\"unlock_world\": true") != -1,
		"Rat King is mid-boss — must NOT unlock W2")


func test_castle_harmonia_sets_w1_final_boss_flags() -> void:
	var text = _read("res://src/maps/dungeons/CastleHarmonia.gd")
	assert_true(text.find("unlock_story_flag = \"w1_boss_defeated\"") != -1,
		"CastleHarmonia must set unlock_story_flag to w1_boss_defeated")
	assert_true(text.find("unlock_world = 2") != -1,
		"CastleHarmonia must declare unlock_world = 2")
	assert_true(text.find("cutscene_flag_world1_mordaine_defeated") != -1,
		"CastleHarmonia must push the cutscene completion flag")
	assert_true(text.find("defeat_cutscene = \"world1_mordaine_defeat\"") != -1,
		"CastleHarmonia must reference the world1_mordaine_defeat cutscene id")


func test_dragon_cave_plays_defeat_cutscene() -> void:
	var text = _read("res://src/maps/dungeons/DragonCave.gd")
	assert_true(text.find("var defeat_cutscene") != -1,
		"DragonCave must declare a defeat_cutscene field")
	var idx = text.find("func _on_boss_defeated")
	var next_func = text.find("\nfunc ", idx + 1)
	var body = text.substr(idx, next_func - idx)
	assert_true(body.find("defeat_cutscene") != -1,
		"_on_boss_defeated must consume the defeat_cutscene field")
	assert_true(body.find("play_cutscene") != -1,
		"_on_boss_defeated must call play_cutscene on the director")


func test_mordaine_defeat_cutscene_file_exists() -> void:
	assert_true(FileAccess.file_exists("res://data/cutscenes/world1_mordaine_defeat.json"),
		"world1_mordaine_defeat.json must exist on disk for CastleHarmonia to play it")


func test_overworld_registers_cave_entrance_aliases() -> void:
	var text = _read("res://src/exploration/OverworldScene.gd")
	var idx = text.find("func _register_spawn_point")
	var next_func = text.find("\nfunc ", idx + 1)
	var body = text.substr(idx, next_func - idx)
	assert_true(body.find("ice_cave_entrance") != -1,
		"OverworldScene must register ice_cave_entrance alias for IceDragonCave exits")
	assert_true(body.find("fire_cave_entrance") != -1,
		"OverworldScene must register fire_cave_entrance alias")
	assert_true(body.find("shadow_cave_entrance") != -1,
		"OverworldScene must register shadow_cave_entrance alias")
	assert_true(body.find("lightning_cave_entrance") != -1,
		"OverworldScene must register lightning_cave_entrance alias")
	assert_true(body.find("castle_entrance") != -1,
		"OverworldScene must register castle_entrance for CastleHarmonia exits")


func test_overworld_castle_portal_gated_on_rat_king() -> void:
	var text = _read("res://src/exploration/OverworldScene.gd")
	var idx = text.find("func _setup_transitions")
	var next_func = text.find("\nfunc ", idx + 1)
	var body = text.substr(idx, next_func - idx)
	assert_true(body.find("\"castle_harmonia\"") != -1,
		"OverworldScene must wire an AreaTransition to castle_harmonia")
	assert_true(body.find("rat_king_defeated") != -1,
		"Castle portal must be gated on rat_king_defeated story flag")


func test_overworld_apply_zone_encounters_reads_json() -> void:
	var text = _read("res://src/exploration/OverworldScene.gd")
	var idx = text.find("func _apply_zone_encounters")
	var next_func = text.find("\nfunc ", idx + 1)
	var body = text.substr(idx, next_func - idx)
	# Old hardcoded pools (e.g., ["wolf", "spider", "goblin"]) must be gone.
	assert_false(body.find("\"wolf\", \"spider\", \"goblin\"") != -1,
		"_apply_zone_encounters must not hardcode the forest pool; read enemy_pools.json instead")
	assert_true(body.find("_load_zone_pool") != -1,
		"_apply_zone_encounters must delegate pool lookup to _load_zone_pool")


func test_overworld_load_zone_pool_returns_authored_monsters() -> void:
	# Make sure the JSON pools include the authored monsters the regression cited.
	var f := FileAccess.open("res://data/enemy_pools.json", FileAccess.READ)
	var pools = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true("fungoid" in pools.get("overworld_forest", []),
		"overworld_forest pool must include fungoid (authored)")
	assert_true("ice_wolf" in pools.get("overworld_ice", []),
		"overworld_ice pool must include ice_wolf (authored)")
	assert_true("viper" in pools.get("overworld_desert", []),
		"overworld_desert pool must include viper (authored)")


func test_harmonia_suburban_portal_gated_on_w1_boss() -> void:
	var text = _read("res://src/maps/villages/HarmoniaVillage.gd")
	var idx = text.find("SuburbanPortal")
	assert_gt(idx, -1, "SuburbanPortal block must still exist")
	# Walk backward 600 chars to find the gating predicate
	var window_start = max(0, idx - 600)
	var window = text.substr(window_start, idx - window_start + 200)
	assert_true(window.find("w1_boss_defeated") != -1,
		"Suburban portal must be gated on w1_boss_defeated (was unconditional)")


func test_castle_harmonia_floor_rows_match_map_width() -> void:
	# Floor layout row widths must equal MAP_WIDTH (20) — otherwise the rightmost
	# column drops off invisibly per DragonCave._generate_map_for_floor.
	var script = load("res://src/maps/dungeons/CastleHarmonia.gd")
	var inst = script.new()
	inst._init()
	for floor_num in inst.floor_layouts:
		var rows = inst.floor_layouts[floor_num]
		for i in range(rows.size()):
			assert_eq(rows[i].length(), 20,
				"CastleHarmonia floor %d row %d width must equal MAP_WIDTH=20" % [floor_num, i])
	inst.free()


func test_teleport_menu_dragon_caves_labelled_w1() -> void:
	var text = _read("res://src/ui/TeleportMenu.gd")
	assert_false(text.find("# --- Dragon caves (W2 sub-dungeons) ---") != -1,
		"TeleportMenu must not label dragon caves as W2 — they live on W1 overworld")
	assert_true(text.find("Dragon Caves (W1)") != -1,
		"TeleportMenu section header must indicate W1 for dragon caves")
