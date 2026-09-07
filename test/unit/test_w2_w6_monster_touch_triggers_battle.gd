extends GutTest

## tick 86 regression: every W2-W6 overworld scene that uses
## MonsterSpawner must connect spawner.monster_touched → a handler
## that triggers a battle. Pre-fix, only W1 OverworldScene wired
## this signal. W2-W6 added MonsterSpawner to spawn visible roaming
## monsters but never listened to its touched signal, so bumping
## into a roaming monster in W2-W6 did literally nothing — the
## monsters were decorative-only.
##
## Step-based encounters are also disabled in W2-W6
## (controller.encounter_enabled = false), so without the
## monster_touched wiring there is NO way to start a battle in
## those worlds via normal exploration.

const OVERWORLDS: Array[Array] = [
	["res://src/exploration/SuburbanOverworld.gd",    "W2 Suburban"],
	["res://src/exploration/SteampunkOverworld.gd",   "W3 Steampunk"],
	["res://src/exploration/IndustrialOverworld.gd",  "W4 Industrial"],
	["res://src/exploration/FuturisticOverworld.gd",  "W5 Futuristic"],
	["res://src/exploration/AbstractOverworld.gd",    "W6 Abstract"],
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_every_w2_w6_connects_monster_touched() -> void:
	for entry in OVERWORLDS:
		var path: String = entry[0]
		var label: String = entry[1]
		var src := _read(path)
		assert_true(src.contains("monster_spawner.monster_touched.connect(_on_roaming_monster_touched)"),
			"%s must connect monster_spawner.monster_touched to _on_roaming_monster_touched — otherwise roaming monsters are decorative" % label)


func test_every_w2_w6_defines_handler() -> void:
	for entry in OVERWORLDS:
		var path: String = entry[0]
		var label: String = entry[1]
		var src := _read(path)
		assert_true(src.contains("func _on_roaming_monster_touched(monster_id: String, _monster_types: Array)"),
			"%s must define _on_roaming_monster_touched(monster_id, _monster_types) handler" % label)


func test_handler_delegates_through_on_battle_triggered() -> void:
	# Each handler must build an enemies array and route through
	# _on_battle_triggered so each world's terrain selection stays in
	# one place.
	for entry in OVERWORLDS:
		var path: String = entry[0]
		var label: String = entry[1]
		var src := _read(path)
		var idx: int = src.find("func _on_roaming_monster_touched")
		assert_gt(idx, -1, "%s handler must exist" % label)
		var next_fn: int = src.find("\nfunc ", idx + 1)
		var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
		assert_true(body.contains("_on_battle_triggered(enemies)"),
			"%s handler must call _on_battle_triggered(enemies) — keeps terrain selection in one place" % label)
		assert_true(body.contains("enemies.append(monster_id)"),
			"%s handler must build the enemies array from monster_id" % label)
		assert_true(body.contains("randi_range(0, 2)"),
			"%s handler must add 0-2 extra duplicates for variety — matches W1 OverworldScene._on_roaming_monster_touched pattern" % label)


func test_connect_precedes_setup_so_first_touch_fires() -> void:
	# Ordering: the .connect must come BEFORE setup(). setup() can
	# call _try_spawn_monster → adds monsters with touch handlers.
	# A touch firing while we're still mid-setup with no listener
	# loses the signal silently.
	for entry in OVERWORLDS:
		var path: String = entry[0]
		var label: String = entry[1]
		var src := _read(path)
		var connect_idx: int = src.find("monster_spawner.monster_touched.connect")
		var setup_idx: int = src.find("monster_spawner.setup(")
		assert_gt(connect_idx, -1, "%s must have monster_touched.connect" % label)
		assert_gt(setup_idx, -1, "%s must have monster_spawner.setup" % label)
		assert_lt(connect_idx, setup_idx,
			"%s: monster_touched.connect must precede setup() so the FIRST wave of monsters has a listener" % label)


func test_w1_overworld_handler_still_present() -> void:
	# Don't regress the original W1 wiring while adding W2-W6.
	var src := _read("res://src/exploration/OverworldScene.gd")
	assert_true(src.contains("monster_spawner.monster_touched.connect(_on_roaming_monster_touched)"),
		"W1 OverworldScene must still connect monster_touched")
	assert_true(src.contains("func _on_roaming_monster_touched"),
		"W1 OverworldScene must still define _on_roaming_monster_touched")
