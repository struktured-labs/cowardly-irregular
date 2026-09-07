extends GutTest

## tick 84 regression: MonsterSpawner map dimensions must be set
## per-overworld via set_map_size, not left at the default W1
## (100x70) value. Each overworld script has its own MAP_WIDTH /
## MAP_HEIGHT constants (W2 50x40, W3 60x50, W4 60x45, W5 55x45,
## W6 40x35) — the spawner needs to know its real bounds so candidate
## spawn positions clamp to the actual playable area.
##
## Pre-fix, MAP_WIDTH / MAP_HEIGHT were `const 100 / 70`. In smaller
## worlds (especially W6 Abstract 40x35) ~50-80% of spawn attempts
## landed outside the actual map, were rejected by _is_impassable_tile
## as "no tile data", and reduced effective monster density.

const MONSTER_SPAWNER := preload("res://src/exploration/MonsterSpawner.gd")

const OVERWORLDS: Array[Array] = [
	["res://src/exploration/OverworldScene.gd",      100, 70, "W1 OverworldScene"],
	["res://src/exploration/SuburbanOverworld.gd",    50, 40, "W2 Suburban"],
	["res://src/exploration/SteampunkOverworld.gd",   60, 50, "W3 Steampunk"],
	["res://src/exploration/IndustrialOverworld.gd",  60, 45, "W4 Industrial"],
	["res://src/exploration/FuturisticOverworld.gd",  55, 45, "W5 Futuristic"],
	["res://src/exploration/AbstractOverworld.gd",    40, 35, "W6 Abstract"],
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_monster_spawner_exposes_set_map_size() -> void:
	# Pin the public API: set_map_size(w, h). Without it, callers
	# can't override the W1 default.
	var src := _read("res://src/exploration/MonsterSpawner.gd")
	assert_true(src.contains("func set_map_size(w: int, h: int) -> void"),
		"MonsterSpawner.set_map_size(w, h) must exist as a public API")


func test_monster_spawner_map_dimensions_are_per_instance_vars() -> void:
	# Pin: map_width / map_height are vars, not consts. A future
	# refactor that re-introduces `const` breaks every overworld's
	# per-instance configuration.
	var src := _read("res://src/exploration/MonsterSpawner.gd")
	assert_true(src.contains("var map_width: int"),
		"map_width must be a `var int` — per-instance, not const")
	assert_true(src.contains("var map_height: int"),
		"map_height must be a `var int` — per-instance, not const")
	assert_false(src.contains("const MAP_WIDTH:"),
		"MonsterSpawner must NOT have a const MAP_WIDTH — interferes with per-overworld override")
	assert_false(src.contains("const MAP_HEIGHT:"),
		"MonsterSpawner must NOT have a const MAP_HEIGHT — interferes with per-overworld override")


func test_each_overworld_calls_set_map_size() -> void:
	# Every overworld that adds a MonsterSpawner must follow up with
	# set_map_size(MAP_WIDTH, MAP_HEIGHT). Defaults are W1 values —
	# so W2-W6 without this call leak the wrong bounds silently.
	for entry in OVERWORLDS:
		var path: String = entry[0]
		var label: String = entry[3]
		var src := _read(path)
		assert_true(src.contains("monster_spawner.set_map_size(MAP_WIDTH, MAP_HEIGHT)"),
			"%s must call monster_spawner.set_map_size(MAP_WIDTH, MAP_HEIGHT) so the spawner clamps to the actual map" % label)


func test_set_map_size_call_precedes_setup() -> void:
	# Ordering: set_map_size MUST run BEFORE setup, because setup
	# calls _fill_monsters which calls _find_spawn_position which
	# reads map_width / map_height. Set after, and the first wave
	# of monsters spawns using the W1 defaults.
	for entry in OVERWORLDS:
		var path: String = entry[0]
		var label: String = entry[3]
		var src := _read(path)
		var size_idx: int = src.find("monster_spawner.set_map_size")
		var setup_idx: int = src.find("monster_spawner.setup(")
		assert_gt(size_idx, -1, "%s must have a set_map_size call" % label)
		assert_gt(setup_idx, -1, "%s must have a monster_spawner.setup call" % label)
		assert_lt(size_idx, setup_idx,
			"%s: set_map_size must precede setup() — otherwise _fill_monsters in setup uses the W1 default bounds for the first wave" % label)


func test_default_map_dimensions_match_w1() -> void:
	# Backward compat: the default values must keep W1's 100x70
	# so an existing caller that doesn't yet know about set_map_size
	# still produces the same behavior as pre-tick-84.
	var spawner = MONSTER_SPAWNER.new()
	assert_eq(spawner.map_width, 100,
		"default map_width must remain 100 — preserves W1 backward compat")
	assert_eq(spawner.map_height, 70,
		"default map_height must remain 70 — preserves W1 backward compat")
	spawner.queue_free()


func test_set_map_size_rejects_non_positive_values() -> void:
	# Defensive: a 0/negative dimension would cause divide-by-zero
	# or infinite spawn loops. The setter must silently keep the
	# previous value rather than crash.
	var spawner = MONSTER_SPAWNER.new()
	spawner.set_map_size(40, 35)
	assert_eq(spawner.map_width, 40)
	assert_eq(spawner.map_height, 35)
	# Bad values must be ignored — previous valid value retained.
	spawner.set_map_size(0, -1)
	assert_eq(spawner.map_width, 40,
		"set_map_size(0, _) must NOT zero out map_width — defensively keep the prior value")
	assert_eq(spawner.map_height, 35,
		"set_map_size(_, -1) must NOT make map_height negative — defensively keep the prior value")
	spawner.queue_free()
