extends GutTest

## Castle Harmonia multi-floor redesign (v3.33.147 playtest, msg 2525).
## Pins: 4-floor arc (Great Hall → Antechamber → Corrupted Throne Room →
## Inner Sanctum), stair/boss marker placement, encounter escalation +
## empty boss pool, layout walkability from D→U on each traversal floor,
## the boss-cutscene-director bug fix (all 5 W1 boss intros were silently
## falling back to console print), and the throne-approach threshold
## cutscene wiring on F4 entry.

const CASTLE_PATH := "res://src/maps/dungeons/CastleHarmonia.gd"
const DRAGON_PATH := "res://src/maps/dungeons/DragonCave.gd"


# ── Layout shape ────────────────────────────────────────────────────

func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


## Parse a floor's map_data literal out of the source (source-level so we
## don't have to instantiate the scene / init the tile generator).
func _parse_floor(floor_num: int) -> Array:
	var src := _read(CASTLE_PATH)
	# Look for the "N: [" opener followed by 16 quoted rows, with N == floor_num.
	var re := RegEx.create_from_string("(?ms)\\b" + str(floor_num) + ":\\s*\\[\\s*(.*?)\\s*\\]")
	var m := re.search(src)
	assert_not_null(m, "floor %d block present" % floor_num)
	var rows: Array = []
	var row_re := RegEx.create_from_string("\"([^\"]+)\"")
	for r in row_re.search_all(m.get_string(1)):
		rows.append(r.get_string(1))
	return rows


func test_all_four_floors_present() -> void:
	for f in [1, 2, 3, 4]:
		var rows := _parse_floor(f)
		assert_eq(rows.size(), 16, "floor %d has 16 rows" % f)
		for i in range(rows.size()):
			assert_eq(rows[i].length(), 20,
				"floor %d row %d is 20 chars wide (got '%s')" % [f, i, rows[i]])


func test_stair_markers_wire_the_arc() -> void:
	# F1: D (overworld exit) + U (to F2)
	# F2: D (to F1) + U (to F3)
	# F3: D (to F2) + U (to F4)
	# F4: D (to F3) + B (Mordaine), NO U
	for f in [1, 2, 3]:
		var rows := _parse_floor(f)
		var joined: String = ""
		for r in rows:
			joined += r
		assert_true(joined.contains("U"), "floor %d has an up-stairs marker" % f)
		assert_true(joined.contains("D"), "floor %d has a down-stairs marker" % f)
	var f4 := _parse_floor(4)
	var f4_joined: String = ""
	for r in f4:
		f4_joined += r
	assert_false(f4_joined.contains("U"), "F4 (boss floor) has no up-stairs")
	assert_true(f4_joined.contains("B"), "F4 marks the Mordaine boss position")
	assert_true(f4_joined.contains("D"), "F4 still has a down-stairs (retreat)")


func test_boss_pool_and_encounter_escalation() -> void:
	var src := _read(CASTLE_PATH)
	# Pool arms per floor, exactly the ids we have monsters.json entries for.
	for expected in ["skeleton", "specter", "shadow_knight", "meta_knight"]:
		assert_true(src.contains("\"" + expected + "\""),
			"encounter pool references '%s'" % expected)
	# Boss floor is empty pool (rate forced to 0 by DragonCave)
	assert_true(src.contains("4: [],"),
		"F4 declares an empty encounter pool (boss floor)")


## Every traversal floor must have a walkable path from the entrance
## spawn (D tile on F2+, floor_spawn_points on F1) to its U marker.
func test_each_floor_is_walkable_entrance_to_up_stairs() -> void:
	for f in [1, 2, 3]:
		var rows := _parse_floor(f)
		var start := _find_char(rows, "D")
		var goal := _find_char(rows, "U")
		assert_ne(start, Vector2i(-1, -1), "floor %d has a D marker" % f)
		assert_ne(goal, Vector2i(-1, -1), "floor %d has a U marker" % f)
		assert_true(_flood_reachable(rows, start, goal),
			"floor %d: no walkable path from D%s to U%s" % [f, str(start), str(goal)])
	# F4: entrance-D → B (boss trigger reachable)
	var f4 := _parse_floor(4)
	var d4 := _find_char(f4, "D")
	var b4 := _find_char(f4, "B")
	assert_true(_flood_reachable(f4, d4, b4),
		"F4: no walkable path from D%s to B%s" % [str(d4), str(b4)])


func _find_char(rows: Array, ch: String) -> Vector2i:
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			if row[x] == ch:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _flood_reachable(rows: Array, start: Vector2i, goal: Vector2i) -> bool:
	if start.x < 0 or goal.x < 0:
		return false
	var seen := {}
	var stack: Array = [start]
	while stack.size() > 0:
		var p: Vector2i = stack.pop_back()
		if p == goal:
			return true
		if seen.has(p):
			continue
		seen[p] = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.y < 0 or q.y >= rows.size():
				continue
			var row: String = rows[q.y]
			if q.x < 0 or q.x >= row.length():
				continue
			var ch: String = row[q.x]
			if ch == "M":  # stone wall — impassable
				continue
			stack.append(q)
	return false


# ── Scene-level fields ──────────────────────────────────────────────

func test_scene_field_configuration() -> void:
	var src := _read(CASTLE_PATH)
	assert_true(src.contains("total_floors = 4"), "declares 4 floors")
	assert_true(src.contains("cave_id = \"castle_harmonia\""), "cave_id stable for save keys")
	assert_true(src.contains("boss_id = \"chancellor_mordaine\""), "boss id preserved")
	assert_true(src.contains("boss_cutscene_id = \"world1_mordaine_intro\""),
		"Mordaine intro cutscene id preserved")
	assert_true(src.contains("boss_flag_key = \"world1_mordaine_defeated\""),
		"defeat flag preserved")
	assert_true(src.contains("unlock_world = 2"), "victory unlocks W2")
	assert_true(src.contains("cutscene_flag_world1_mordaine_defeated"),
		"defeat cutscene flag still emitted (world1→world2 gate)")
	assert_true(src.contains("\"w1_boss_defeated\""),
		"unlock_story_flag preserved (chapter progression gate)")


func test_castle_entrance_alias_preserved() -> void:
	# Any save that stored the pre-redesign single-floor spawn name
	# ("castle_entrance") must still resolve on F1 load.
	var src := _read(CASTLE_PATH)
	assert_true(src.contains("\"castle_entrance\": Vector2(10, 14)"),
		"F1 keeps the legacy castle_entrance spawn key for save-compat")


# ── Throne-approach cutscene wiring ────────────────────────────────

func test_throne_approach_uses_gameloop_director() -> void:
	var src := _read(CASTLE_PATH)
	# Must NOT use the /root/ pattern (CutsceneDirector isn't autoloaded).
	assert_false(src.contains("/root/CutsceneDirector"),
		"CastleHarmonia must not reach for /root/CutsceneDirector (silent fallback)")
	assert_true(src.contains("game_loop.get_cutscene_director"),
		"CastleHarmonia routes through GameLoop.get_cutscene_director()")
	assert_true(src.contains("\"world1_throne_room_approach\"") \
		or src.contains("THRONE_APPROACH_ID"),
		"throne-approach cutscene wired by id")
	assert_true(src.contains("cutscene_flag_world1_throne_room_approach_complete") \
		or src.contains("THRONE_APPROACH_FLAG"),
		"throne-approach guarded by its own completion flag (no replay)")


func test_throne_approach_cutscene_exists() -> void:
	# Cherry-picked from feature/story-castle-harmonia; my scene depends on it.
	var path := "res://data/cutscenes/world1_throne_room_approach.json"
	assert_true(FileAccess.file_exists(path),
		"throne-approach cutscene JSON on disk")
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "cutscene JSON parses")
	assert_eq((parsed as Dictionary).get("id", ""), "world1_throne_room_approach")


func test_throne_approach_fires_on_both_entry_paths() -> void:
	var src := _read(CASTLE_PATH)
	# Fresh load already on F4 (save restore, dungeon_skip warp).
	assert_true(src.contains("if current_floor == total_floors"),
		"_ready checks current_floor before firing threshold cutscene")
	# Arriving via stairs.
	assert_true(src.contains("floor_changed.connect(_on_floor_changed)"),
		"listens for floor_changed to catch stair transitions")


# ── DragonCave boss-intro director fix ─────────────────────────────

func test_dragon_cave_boss_intro_uses_gameloop_director() -> void:
	# Same class of bug as TallyWall (2026-07-08): CutsceneDirector is
	# GameLoop-owned, not autoloaded, and the /root/ lookup silently
	# falls back to console print — every W1 boss intro (Mordaine +
	# 4 dragons) has been dropping to that fallback since the field
	# landed. All 5 cutscene JSONs exist on disk and were authored to
	# actually play.
	var src := _read(DRAGON_PATH)
	assert_false(src.contains("get_node_or_null(\"/root/CutsceneDirector\")"),
		"DragonCave._show_boss_intro must not use the /root/ lookup")
	# The correct routing lives inside _show_boss_intro. Anchor the
	# check to that function's body so a random elsewhere-in-file
	# match can't paper over a regression.
	var fn_idx := src.find("func _show_boss_intro")
	assert_gt(fn_idx, 0, "boss intro function exists")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("get_cutscene_director"),
		"boss intro reaches GameLoop.get_cutscene_director()")


func test_all_w1_boss_cutscenes_exist_for_the_fix_to_matter() -> void:
	# If any of these are missing, the /root/ fix is moot for that boss.
	for cid in ["world1_mordaine_intro", "world1_umbraxis_intro",
			"world1_glacius_intro", "world1_pyrroth_intro",
			"world1_voltharion_intro"]:
		var path := "res://data/cutscenes/%s.json" % cid
		assert_true(FileAccess.file_exists(path),
			"boss intro cutscene %s on disk (fix unblocks playback)" % cid)
