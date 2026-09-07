extends GutTest

## Regression tests for corruption/summon/signal-binding bug fixes.
## Each test protects a specific prior bug from reappearing.

const Combatant = preload("res://src/battle/Combatant.gd")

var _battle_manager: Node


func before_all() -> void:
	var tree = get_tree()
	if tree and tree.root:
		_battle_manager = tree.root.get_node_or_null("BattleManager")


func _make_enemy(name: String, speed: int) -> Combatant:
	var c = Combatant.new()
	c.combatant_name = name
	c.max_hp = 100
	c.current_hp = 100
	c.max_mp = 20
	c.current_mp = 20
	c.attack = 10
	c.defense = 5
	c.magic = 5
	c.speed = speed
	return c


## ---- Bug #3: time_distortion compounded speed each round instead of using base ----

func test_time_distortion_uses_base_speed_not_compounded() -> void:
	if _battle_manager == null:
		pending("BattleManager not available")
		return

	# Build a minimal enemy party with a corruption-tagged enemy
	var enemy = _make_enemy("Corrupted", 20)
	enemy.set_meta("corruption_effects", ["time_distortion"])
	add_child_autofree(enemy)

	# Swap in a small enemy_party for the test (save/restore original)
	var orig = _battle_manager.enemy_party.duplicate()
	_battle_manager.enemy_party = [enemy] as Array[Combatant]

	# Apply effect many times — speed should always be derived from base 20,
	# never from the previously-mutated speed. With the pre-fix bug, speed
	# would drift to 1 (floor) or massive values after ~20 rounds.
	for i in range(50):
		_battle_manager._apply_corruption_effects_on_round_start()

	assert_true(enemy.has_meta("_base_speed"),
		"Enemy should have _base_speed metadata after first tick")
	assert_eq(enemy.get_meta("_base_speed"), 20,
		"_base_speed should be the original speed (20)")

	# Speed must be within the ±30% band of BASE 20 → [14, 26]
	# (not compounded, which would escape these bounds quickly)
	assert_gte(enemy.speed, 14, "Speed should stay within ±30%% of base")
	assert_lte(enemy.speed, 26, "Speed should stay within ±30%% of base")

	_battle_manager.enemy_party = orig


## ---- Bug #5: summon signal handler bound stale index; lookup by ref fixes it ----

func test_summon_signal_lookup_by_reference_survives_array_ordering() -> void:
	var enemies: Array[Combatant] = []
	for i in range(4):
		var c = _make_enemy("E%d" % i, 10 + i)
		add_child_autofree(c)
		enemies.append(c)

	# Connect signals using the same lambda closure pattern as BattleScene:
	# lookup index via .find() at call time, not via a captured bound int.
	var events: Array = []
	for e in enemies:
		var local_ref: Combatant = e
		local_ref.hp_changed.connect(func(_o, _n):
			events.append({"name": local_ref.combatant_name, "idx": enemies.find(local_ref)}))

	# Damage a middle enemy — its index should be correct
	enemies[2].take_damage(1)

	assert_eq(events.size(), 1, "Exactly one hp_changed event")
	assert_eq(events[0]["name"], "E2", "Event came from E2")
	assert_eq(events[0]["idx"], 2, "Lookup by reference returned correct index")

	# Now simulate a summon: append a new enemy, damage it
	var summoned = _make_enemy("Summoned", 30)
	add_child_autofree(summoned)
	enemies.append(summoned)
	summoned.hp_changed.connect(func(_o, _n):
		events.append({"name": "Summoned", "idx": enemies.find(summoned)}))

	summoned.take_damage(1)

	assert_eq(events.size(), 2, "Second event for summoned")
	assert_eq(events[1]["name"], "Summoned", "Summoned event came through")
	assert_eq(events[1]["idx"], 4, "Summoned is at index 4 (appended after 4 originals)")


func test_summon_signal_lookup_after_another_enemy_dies() -> void:
	# Even when the array has a dead combatant, find() still works by reference.
	# Pre-fix bug: bind(index) would have bound the wrong index if entries were
	# inserted/removed. Here we verify the current pattern still works.
	var enemies: Array[Combatant] = []
	for i in range(3):
		var c = _make_enemy("E%d" % i, 10)
		add_child_autofree(c)
		enemies.append(c)

	var events: Array = []
	for e in enemies:
		var local_ref: Combatant = e
		local_ref.died.connect(func():
			events.append({"idx": enemies.find(local_ref), "name": local_ref.combatant_name}))

	# Kill enemies[1] first — lookup should still work for enemies[0] and [2]
	enemies[1].current_hp = 1
	enemies[1].take_damage(999)

	assert_eq(events.size(), 1)
	assert_eq(events[0]["name"], "E1")
	assert_eq(events[0]["idx"], 1, "E1 stays at index 1 (array not compacted)")

	# Kill the last — still correct
	enemies[2].current_hp = 1
	enemies[2].take_damage(999)

	assert_eq(events.size(), 2)
	assert_eq(events[1]["name"], "E2")
	assert_eq(events[1]["idx"], 2, "E2 found at index 2 by reference")


## ---- Bug #1: SaveSystem looked up player via MapSystem.get_player() and
## required `is PlayerController`, but OverworldPlayer never called set_player
## and isn't a PlayerController. Player position silently failed to save.
## Fix: OverworldPlayer joins the "player" group; SaveSystem uses
## _find_active_player() which checks the group first. ----

func test_overworld_player_joins_player_group() -> void:
	# Source-level check — this is the invariant that makes the whole save/load
	# and NPC lookup chain work.
	var src_path = "res://src/exploration/OverworldPlayer.gd"
	var file = FileAccess.open(src_path, FileAccess.READ)
	assert_not_null(file, "OverworldPlayer.gd must exist")
	if file == null:
		return
	var source = file.get_as_text()
	file.close()
	assert_true(source.contains("add_to_group(\"player\")"),
		"OverworldPlayer must call add_to_group(\"player\") so SaveSystem and NPCs can find it")


func test_save_system_has_active_player_lookup() -> void:
	# SaveSystem should prefer the group lookup, not a PlayerController type check.
	var src_path = "res://src/save/SaveSystem.gd"
	var file = FileAccess.open(src_path, FileAccess.READ)
	assert_not_null(file, "SaveSystem.gd must exist")
	if file == null:
		return
	var source = file.get_as_text()
	file.close()
	assert_true(source.contains("_find_active_player"),
		"SaveSystem must provide _find_active_player() group-based lookup")
	assert_true(source.contains("get_nodes_in_group(\"player\")"),
		"SaveSystem must resolve player via the 'player' group")
