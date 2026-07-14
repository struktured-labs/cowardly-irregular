extends GutTest

## tick 307: GameLoop._set_current_map_id syncs MapSystem.current_map_id
## so bestiary, world map, save serialize, and autogrind dashboard all
## see the actual location instead of a stale "overworld" / "" value.
##
## Pre-fix _current_map_id was a private GameLoop var with FOUR direct
## assignments (new game, game-over restart, scene transition, autogrind
## region advance). MapSystem.current_map_id was only set by
## MapSystem.load_map, which is bypassed by GameLoop's direct scene
## routing for every village / dungeon / interior. Result: a monster
## defeated in fire_dragon_cave was bestiary-logged as defeated in
## "overworld" (BattleScene.gd:4581, BattleManager.gd:312,
## HeadlessBattleResolver.gd:46,759 all use MapSystem.current_map_id
## as the location string). WorldMapMenu, save serializer, and the
## autogrind dashboard read the same stale field.
##
## Same silent-fail class as tick 245's mark_seen empty-id guard.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: setter exists ────────────────────────────────────────

func test_setter_function_exists() -> void:
	var src := _read(GAME_LOOP_PATH)
	assert_true(src.contains("func _set_current_map_id(id: String) -> void:"),
		"_set_current_map_id helper must exist as the canonical setter")


# ── Source pin: setter actually syncs MapSystem ──────────────────────

func test_setter_writes_to_mapsystem() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _set_current_map_id")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_current_map_id = id"),
		"setter must update _current_map_id")
	assert_true(body.contains("MapSystem.current_map_id = id"),
		"setter must mirror to MapSystem.current_map_id")
	assert_true(body.contains("if MapSystem"),
		"setter must null-guard MapSystem (autoload may be absent in test envs)")


# ── Source pin: no remaining bare `_current_map_id =` assignments ────

func test_no_bare_assignments_remain() -> void:
	# Every assignment must go through the setter so MapSystem stays in
	# sync. Acceptable bare assignments are inside _set_current_map_id
	# itself.
	var src := _read(GAME_LOOP_PATH)
	# Strip the setter body so we don't false-positive on its own assignment.
	var setter_idx: int = src.find("func _set_current_map_id")
	var setter_end: int = src.find("\nfunc ", setter_idx + 1)
	var outside: String = src.substr(0, setter_idx) + src.substr(setter_end)
	var lines: Array = outside.split("\n")
	var bare_assignments: Array[String] = []
	for line in lines:
		var s: String = str(line).strip_edges()
		# Match assignment, not comparison.
		if s.begins_with("_current_map_id =") and not s.begins_with("_current_map_id =="):
			bare_assignments.append(s)
	assert_eq(bare_assignments.size(), 0,
		"All _current_map_id assignments must route through _set_current_map_id; found bare: %s" % str(bare_assignments))


# ── Behavioral: instantiate setter and verify MapSystem is updated ──

func test_behavior_setter_updates_mapsystem() -> void:
	# Real MapSystem autoload — it's a project autoload, available in GUT.
	assert_not_null(MapSystem,
		"MapSystem autoload must be reachable in tests for this regression to be meaningful")
	if MapSystem == null:
		return

	var prior: String = MapSystem.current_map_id
	# Use the GameLoop script's setter via load() — instantiating the full
	# GameLoop scene is overkill and risks tree-ordering issues. The setter
	# only touches `_current_map_id` and `MapSystem.current_map_id`, both
	# of which are accessible from a fresh instance.
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)

	gl._set_current_map_id("fire_dragon_cave")
	assert_eq(gl._current_map_id, "fire_dragon_cave",
		"setter must update private field")
	assert_eq(MapSystem.current_map_id, "fire_dragon_cave",
		"setter must mirror to MapSystem.current_map_id (the read site for bestiary/world-map/save)")

	# Restore the original so other tests aren't disturbed.
	MapSystem.current_map_id = prior


# ── Behavioral: setter is called for the 4 known sites ──────────────

func test_known_call_sites_use_setter() -> void:
	# Source-level audit — the 4 known sites (new game, game-over restart,
	# scene transition, autogrind region advance) should call the setter.
	var src := _read(GAME_LOOP_PATH)
	var setter_calls: int = src.count("_set_current_map_id(")
	# 1 self-definition + 4 call sites = 5 minimum occurrences. Tests
	# themselves don't run on GameLoop.gd, so the count is exactly the
	# script's usage.
	assert_gte(setter_calls, 5,
		"_set_current_map_id must be defined + called at all 4 known sites (new game, game-over restart, transition, autogrind advance). Found: %d" % setter_calls)
