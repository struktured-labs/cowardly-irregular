extends GutTest

## tick 87 regression: every terrain string W2-W6 overworld battles
## emit must resolve to a real TerrainType in
## BattleBackground.set_terrain_from_string. Otherwise the match's
## default arm returns PLAINS — a silent fallback that hides the
## intended world-specific backdrop.
##
## Also pins the W2 park-zone fix: tick 87 audit found that
## SuburbanOverworld._get_terrain_for_zone had two branches both
## returning "suburban" while the comment said "Park/playground
## zone (leftmost third) → forest". Dead-code bug — the park-zone
## branch now returns "forest" as intended.

const BATTLE_BG := "res://src/battle/BattleBackground.gd"
const SUBURBAN_OW := "res://src/exploration/SuburbanOverworld.gd"


## Every terrain string the W2-W6 _on_battle_triggered /
## _get_terrain_for_zone paths emit.
const W2_W6_TERRAIN_STRINGS: Array[String] = [
	"suburban",    # W2 residential/strip mall zones
	"forest",      # W2 park zone (tick 87 fix)
	"steampunk",   # W3 SteampunkOverworld
	"industrial",  # W4 IndustrialOverworld
	"digital",     # W5 FuturisticOverworld
	"void",        # W6 AbstractOverworld
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_every_w2_w6_terrain_string_resolves_in_set_terrain_from_string() -> void:
	# Pin source-level coverage: each string must appear as a match
	# arm key (not as a fall-through to PLAINS).
	var src := _read(BATTLE_BG)
	var idx: int = src.find("func set_terrain_from_string")
	assert_gt(idx, -1, "set_terrain_from_string must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	for s in W2_W6_TERRAIN_STRINGS:
		var quoted: String = "\"" + s + "\""
		assert_true(body.contains(quoted),
			"set_terrain_from_string must have a match arm for '%s' — otherwise W2-W6 battles fall through to PLAINS default" % s)


func test_w2_park_zone_returns_forest_not_suburban() -> void:
	# Pin the tick 87 fix: leftmost third returns "forest", not the
	# dead-code "suburban". Regression check so future refactors
	# don't silently revert to "suburban" in both branches.
	var src := _read(SUBURBAN_OW)
	var idx: int = src.find("func _get_terrain_for_zone")
	assert_gt(idx, -1, "_get_terrain_for_zone must exist in W2")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	# Both branch return values must be present.
	assert_true(body.contains("return \"forest\""),
		"W2 _get_terrain_for_zone leftmost-third branch must return 'forest' — was 'suburban' (dead code)")
	assert_true(body.contains("return \"suburban\""),
		"W2 _get_terrain_for_zone non-park branch must still return 'suburban'")
	# Pin the conditional that determines which branch runs.
	assert_true(body.contains("if tile_x < MAP_WIDTH / 3:"),
		"W2 _get_terrain_for_zone must gate on tile_x < MAP_WIDTH / 3 — the park-zone boundary")


func test_w2_branches_differ() -> void:
	# Ensure the two branches don't return the same value — defensive
	# against a future copy-paste accident.
	var src := _read(SUBURBAN_OW)
	var idx: int = src.find("func _get_terrain_for_zone")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	# Count how many distinct return strings exist.
	var has_forest: bool = body.contains("return \"forest\"")
	var has_suburban: bool = body.contains("return \"suburban\"")
	assert_true(has_forest and has_suburban,
		"W2 _get_terrain_for_zone must have BOTH 'forest' and 'suburban' branches — pre-fix both branches returned 'suburban' (dead code)")


func test_default_arm_still_returns_plains() -> void:
	# Sanity: the catch-all `_:` arm must still exist so unknown
	# strings degrade to PLAINS rather than crashing.
	var src := _read(BATTLE_BG)
	var idx: int = src.find("func set_terrain_from_string")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	# Look for the underscore default arm
	assert_true(body.contains("_:\n\t\t\tset_terrain(TerrainType.PLAINS)"),
		"set_terrain_from_string must keep its catch-all `_:` → PLAINS arm — defensive default for unknown strings")
