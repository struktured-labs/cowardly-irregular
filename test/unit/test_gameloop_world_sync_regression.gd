extends GutTest

## tick 310: GameLoop._set_current_map_id syncs GameState.current_world
## from the map_id so GameOverScreen, LLMContext, and any other reader
## sees the correct world during normal exploration.
##
## Pre-fix GameState.current_world was set ONLY by GameLoop._on_autogrind_
## region_advanced (autogrind crossing world boundaries). Normal walking
## from World 1 to World 2 to World 3 never touched it — current_world
## stayed at 1 forever for non-autogrind players. Symptom: dying in
## suburban_overworld showed the W1 game-over title; LLM context tagged
## a W3 boss fight as W1.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: setter syncs GameState.current_world ────────────────

func test_setter_writes_current_world() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _set_current_map_id")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("GameState.current_world = w"),
		"_set_current_map_id must update GameState.current_world from the derived world number")
	assert_true(body.contains("_get_world_for_map(id)"),
		"_set_current_map_id must call _get_world_for_map for the derivation")


# ── Source pin: world helper has all 6 world arms ───────────────────

## 2026-09-12: was a SOURCE-SHAPE pin — it required the literal text `return 2` … `return 6`
## inside the function body. That is a claim about how the helper is WRITTEN, and it redded
## on a refactor that changed nothing about what the helper ANSWERS: the arms became one
## prefix table so the resolver and `_map_id_declares_its_world` could not drift apart.
## A guard that reds on correct work is how suppression entries get written, so this now
## asserts the same claim against the table both functions read.
func test_helper_covers_all_six_worlds() -> void:
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	var worlds := {}
	for entry in gl.WORLD_PREFIXES:
		worlds[int(entry[1])] = true
	for w in [1, 2, 3, 4, 5, 6]:
		assert_true(worlds.has(w),
			"no map-id prefix resolves to World %d — that world's ids would fall to the W1 default" % w)
	# W1 must be REACHABLE BY NAME, not only as the fallback. That is the distinction the
	# interior fix turns on: `scriptura_guild -> 1` used to be the default firing, which is
	# indistinguishable from "this id names no world at all".
	assert_true(gl._map_id_declares_its_world("harmonia_chapel"),
		"a named World 1 room must MATCH, not default — otherwise W1 and 'unknown' are the same answer")
	assert_false(gl._map_id_declares_its_world("inn_interior"),
		"a room reused across eleven villages must name no world, or it stops borrowing its village's")
	# The old contract survives for callers that only want a number.
	assert_eq(gl._get_world_for_map("__nonsense_id__"), 1,
		"an unrecognised id still answers W1")
	gl.free()


# ── Behavioral: known per-world map_ids map correctly ───────────────

func test_per_world_map_resolution() -> void:
	# Load the script directly so we can invoke the helper without bringing
	# up the full GameLoop scene tree.
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)

	# W1 — Medieval (all defaults + dragon caves + side villages)
	for w1_id in [
		"overworld", "harmonia_village", "whispering_cave", "castle_harmonia",
		"fire_dragon_cave", "ice_dragon_cave", "lightning_dragon_cave", "shadow_dragon_cave",
		"frosthold_village", "sandrift_village", "ironhaven_village", "grimhollow_village",
		"eldertree_village", "tavern_interior", "harmonia_chapel",
	]:
		assert_eq(gl._get_world_for_map(w1_id), 1,
			"W1 map_id '%s' must resolve to world 1 (the medieval default)" % w1_id)

	# W2 — Suburban
	for w2_id in ["suburban_overworld", "suburban_underground", "maple_heights_village", "maple_heights_arcade"]:
		assert_eq(gl._get_world_for_map(w2_id), 2,
			"W2 map_id '%s' must resolve to world 2" % w2_id)

	# W3 — Steampunk
	for w3_id in ["steampunk_overworld", "steampunk_mechanism", "brasston_village", "brasston_clockwork_loft"]:
		assert_eq(gl._get_world_for_map(w3_id), 3,
			"W3 map_id '%s' must resolve to world 3" % w3_id)

	# W4 — Industrial
	for w4_id in ["industrial_overworld", "rivet_row_village", "assembly_core", "rivet_row_union_hall"]:
		assert_eq(gl._get_world_for_map(w4_id), 4,
			"W4 map_id '%s' must resolve to world 4" % w4_id)

	# W5 — Futuristic
	for w5_id in ["futuristic_overworld", "node_prime_village", "root_process", "node_prime_daemon_lounge"]:
		assert_eq(gl._get_world_for_map(w5_id), 5,
			"W5 map_id '%s' must resolve to world 5" % w5_id)

	# W6 — Abstract
	for w6_id in ["abstract_overworld", "vertex_village", "null_chamber", "vertex_threshold"]:
		assert_eq(gl._get_world_for_map(w6_id), 6,
			"W6 map_id '%s' must resolve to world 6" % w6_id)


# ── Behavioral: setter mutates GameState.current_world ──────────────

func test_setter_changes_gamestate_current_world() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)

	var prior: int = GameState.current_world

	# Setting to a W3 map should set current_world to 3.
	gl._set_current_map_id("steampunk_overworld")
	assert_eq(GameState.current_world, 3,
		"setting current_map_id to a W3 id must update GameState.current_world to 3")

	# Setting to a W1 map should reset to 1.
	gl._set_current_map_id("overworld")
	assert_eq(GameState.current_world, 1,
		"setting current_map_id to a W1 id must update GameState.current_world to 1")

	# Restore for downstream tests.
	GameState.current_world = prior


# ── Unknown map_id falls back to W1 (no crash) ──────────────────────

func test_unknown_map_id_falls_back_to_w1() -> void:
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)
	# Garbage id should still return W1 — graceful default, no crash.
	assert_eq(gl._get_world_for_map("__nonsense_id__"), 1,
		"Unknown map_id must fall back to W1 (medieval default)")
	assert_eq(gl._get_world_for_map(""), 1,
		"Empty map_id must fall back to W1")
