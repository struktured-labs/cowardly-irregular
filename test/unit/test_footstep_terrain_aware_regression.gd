extends GutTest

## tick 357: OverworldPlayer footstep call is now terrain-aware.
##
## Pre-fix every step emitted:
##   sm.play_footstep()
##
## SoundManager.play_footstep defaults terrain to "grass", so every
## step in caves / deserts / ice / metal industrial floors played
## the grass footstep audio. The SFX manifest has 6 distinct
## footstep variants (grass / stone / sand / snow / metal / wood) —
## 5 of them were dead audio assets unreachable by gameplay.
##
## Symptom: "walking through the ice dungeon sounds like a meadow."
##
## Fix derives footstep terrain from GameLoop._current_terrain
## (battle-terrain vocabulary set by tick 311) via a static map.
## Falls back to "grass" when GameLoop is unavailable (test runs)
## or the terrain string is unknown, matching the historical default.

const OVERWORLD_PLAYER_PATH := "res://src/exploration/OverworldPlayer.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: helper exists ───────────────────────────────────────

func test_resolve_helper_exists() -> void:
	var src := _read(OVERWORLD_PLAYER_PATH)
	assert_true(src.contains("func _resolve_footstep_terrain()"),
		"_resolve_footstep_terrain helper must exist")
	assert_true(src.contains("const _FOOTSTEP_TERRAIN_MAP"),
		"_FOOTSTEP_TERRAIN_MAP const must define the battle-terrain → footstep-terrain mapping")


# ── Source pin: call site passes the resolved terrain ───────────────

func test_play_footstep_call_uses_resolver() -> void:
	var src := _read(OVERWORLD_PLAYER_PATH)
	assert_true(src.contains("sm.play_footstep(_resolve_footstep_terrain())"),
		"play_footstep must be called with the resolved terrain — pre-fix it was bare and defaulted to grass")
	# The bare sm.play_footstep() call must be gone.
	assert_false(src.contains("sm.play_footstep()"),
		"bare sm.play_footstep() call must be gone")


# ── Source pin: map covers all expected battle terrains ─────────────

func test_map_covers_canonical_battle_terrains() -> void:
	var src := _read(OVERWORLD_PLAYER_PATH)
	# Canonical battle-terrain strings produced by
	# GameLoop._get_terrain_for_map (tick 311). At least the major
	# world terrains must be in the map.
	var canonical_terrains := ["plains", "cave", "ice", "desert", "industrial", "digital", "steampunk", "void", "suburban"]
	for terrain in canonical_terrains:
		assert_true(src.contains("\"%s\":" % terrain),
			"_FOOTSTEP_TERRAIN_MAP must include the '%s' battle-terrain key" % terrain)


# ── Behavioral: resolver returns mapped values ──────────────────────

func test_resolver_maps_terrain_correctly() -> void:
	# Need a real OverworldPlayer instance — instantiate via load.
	var player_script: GDScript = load(OVERWORLD_PLAYER_PATH)
	var player: Object = player_script.new()
	add_child_autofree(player)

	# When GameLoop autoload isn't reachable from the test root, the
	# resolver falls back to "grass". To test the mapping, stub
	# GameLoop with the required field.
	# Use the actual real GameLoop autoload if available; otherwise
	# fall back to checking the map structure via source.
	var gl = get_tree().root.get_node_or_null("GameLoop")
	if gl == null or not ("_current_terrain" in gl):
		# Source-pin only. Verify the resolver reads _current_terrain.
		var src := _read(OVERWORLD_PLAYER_PATH)
		var fn_idx: int = src.find("func _resolve_footstep_terrain")
		var next_fn: int = src.find("\nfunc ", fn_idx + 1)
		var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
		assert_true(body.contains("_current_terrain"),
			"resolver must read GameLoop._current_terrain")
		assert_true(body.contains("_FOOTSTEP_TERRAIN_MAP.get"),
			"resolver must look up in _FOOTSTEP_TERRAIN_MAP")
		return

	# Real autoload available — drive end-to-end.
	var prior_terrain: String = str(gl._current_terrain)
	gl._current_terrain = "ice"
	assert_eq(player._resolve_footstep_terrain(), "snow",
		"ice battle-terrain must map to 'snow' footstep terrain")
	gl._current_terrain = "desert"
	assert_eq(player._resolve_footstep_terrain(), "sand",
		"desert battle-terrain must map to 'sand' footstep terrain")
	gl._current_terrain = "industrial"
	assert_eq(player._resolve_footstep_terrain(), "metal",
		"industrial battle-terrain must map to 'metal' footstep terrain")
	gl._current_terrain = "__unknown_terrain__"
	assert_eq(player._resolve_footstep_terrain(), "grass",
		"unknown battle-terrain must fall back to 'grass'")
	# Restore.
	gl._current_terrain = prior_terrain


# ── Behavioral: no GameLoop → fallback to grass (no crash) ──────────

func test_no_gameloop_returns_grass() -> void:
	# Direct verification of fallback when GameLoop is unavailable
	# (or doesn't expose _current_terrain).
	var player_script: GDScript = load(OVERWORLD_PLAYER_PATH)
	var player: Object = player_script.new()
	add_child_autofree(player)
	# We can't easily remove the real GameLoop. Pin via source that
	# null-check exists.
	var src := _read(OVERWORLD_PLAYER_PATH)
	var fn_idx: int = src.find("func _resolve_footstep_terrain")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if gl == null"),
		"resolver must null-check GameLoop")
	assert_true(body.contains("return \"grass\""),
		"resolver must return 'grass' fallback when GameLoop unreachable")
