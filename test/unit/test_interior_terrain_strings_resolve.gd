extends GutTest

## tick 67 regression: every terrain string GameLoop._get_terrain_for_map
## returns for an interior must be a key BattleBackground.set_terrain_from_string
## actually handles. Otherwise the case falls through to TerrainType.PLAINS
## (the default case) and the interior battle backdrop is wrong — silent
## bug, no warning.
##
## Original bug (tick 65→67): node_prime_daemon_lounge returned 'futuristic'
## but the resolver only knows 'digital'/'cyber'/'neon'. Player would have
## gotten a plains backdrop in a daemon-lounge battle.

const GAME_LOOP := "res://src/GameLoop.gd"
const BATTLE_BACKGROUND := "res://src/battle/BattleBackground.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


## Terrains GameLoop returns for the 12 interiors (tick 34 — 66).
## When this list grows (new interior), the test verifies the new
## key resolves too.
const INTERIOR_TERRAINS: Array[String] = [
	"village",      # 4× — harmonia_chapel, harmonia_library, tavern_interior, harmonia_village
	"forest",       # eldertree_hollow
	"ice",          # frosthold_warden_hut
	"desert",       # sandrift_glassmaker
	"swamp",        # grimhollow_witch_hut
	"volcanic",     # ironhaven_watchtower
	"suburban",     # maple_heights_arcade
	"steampunk",    # brasston_clockwork_loft
	"industrial",   # rivet_row_union_hall
	"digital",      # node_prime_daemon_lounge (was 'futuristic' — bug)
	"abstract",     # vertex_threshold
]


func test_battle_background_handles_every_interior_terrain() -> void:
	# Pull the resolver's match arms out of the source and verify
	# every interior terrain has a matching case.
	var src := _read(BATTLE_BACKGROUND)
	var idx := src.find("func set_terrain_from_string")
	assert_gt(idx, -1, "BattleBackground.set_terrain_from_string must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	var body := src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	for terrain in INTERIOR_TERRAINS:
		var quoted: String = "\"" + terrain + "\""
		assert_true(body.contains(quoted),
			"set_terrain_from_string must handle '%s' — otherwise the interior falls through to PLAINS backdrop. (If you added a new interior with a new terrain key, add it to set_terrain_from_string OR use an existing canonical key from the resolver.)" % terrain)


func test_game_loop_interior_terrain_strings_match_resolver_keys() -> void:
	# Negative assertion: prove 'futuristic' is GONE from the
	# interior-terrain dispatch (canonical is 'digital'). A future
	# refactor must NOT silently reintroduce a non-resolver key.
	#
	# Anchor on `return "digital"` near `node_prime_daemon_lounge` —
	# GameLoop has the map_id mentioned in two places (scene route +
	# terrain mapping); the terrain dispatch is the one with
	# `return "..."` adjacent.
	var src := _read(GAME_LOOP)
	# Find the terrain-mapping occurrence specifically by looking for
	# the `return "digital"` immediately after the map_id.
	# 2026-07-10: arm grouped with node_prime_cache — both Node Prime interiors.
	var idx := src.find("\"node_prime_daemon_lounge\", \"node_prime_cache\":\n\t\t\treturn ")
	assert_gt(idx, -1, "interior terrain map must include node_prime_daemon_lounge with a return arm")
	var window: String = src.substr(idx, 120)
	assert_false(window.contains("\"futuristic\""),
		"interior must NOT return 'futuristic' — canonical W5 terrain key is 'digital' (see set_terrain_from_string in BattleBackground.gd)")
	assert_true(window.contains("\"digital\""),
		"interior must return 'digital' for W5")
