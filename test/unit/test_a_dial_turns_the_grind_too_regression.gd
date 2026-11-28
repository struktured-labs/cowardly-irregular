extends GutTest

## Scriptweaver's damage_multiplier and healing_multiplier dials were read only by a combatant in the scene tree
## (`... if is_inside_tree() else null`). Live enemies are in the tree (BattleEnemySpawner add_child), a headless
## grind's are not (GameLoop._combatant_for_headless), so a turned dial changed live battles and not the grind.
## Each arm turns one dial and asks an in-tree twin (live) and an off-tree twin (grind) for the same number.

const BASE := {"name": "Twin", "max_hp": 5000, "max_mp": 50, "attack": 40, "defense": 20, "magic": 30, "speed": 10}
var _saved: Dictionary = {}


func before_each() -> void:
	_saved = GameState.game_constants.duplicate(true)


func after_each() -> void:
	GameState.game_constants = _saved


func _twin(in_tree: bool) -> Combatant:
	var c := Combatant.new()
	if in_tree:
		add_child_autofree(c)
	else:
		autofree(c)
	c.initialize(BASE.duplicate())
	return c


func _hit(c: Combatant) -> int:
	return c.damage_preview(300)


func _mend(c: Combatant) -> int:
	return c.heal_preview(300)


func test_the_damage_dial_turns_the_grind_as_it_turns_a_live_battle() -> void:
	var live := _twin(true)
	var grind := _twin(false)
	assert_false(grind.is_inside_tree(), "CONTROL: the grind twin is off-tree, as a headless enemy is")
	GameState.game_constants["damage_multiplier"] = 1.0
	var plain := _hit(live)
	GameState.game_constants["damage_multiplier"] = 2.0
	assert_gt(_hit(live), plain, "CONTROL: the damage dial moves a live hit")
	assert_eq(_hit(grind), _hit(live), "a turned damage dial must hit the grind exactly as it hits a live battle")


func test_the_healing_dial_turns_the_grind_as_it_turns_a_live_battle() -> void:
	var live := _twin(true)
	var grind := _twin(false)
	assert_false(grind.is_inside_tree(), "CONTROL: the grind twin is off-tree, as a headless enemy is")
	GameState.game_constants["healing_multiplier"] = 1.0
	var plain := _mend(live)
	GameState.game_constants["healing_multiplier"] = 2.0
	assert_gt(_mend(live), plain, "CONTROL: the healing dial moves a live heal")
	assert_eq(_mend(grind), _mend(live), "a turned healing dial must heal the grind exactly as it heals a live battle")


func test_an_unturned_dial_leaves_both_alike() -> void:
	var live := _twin(true)
	var grind := _twin(false)
	GameState.game_constants["damage_multiplier"] = 1.0
	GameState.game_constants["healing_multiplier"] = 1.0
	assert_eq(_hit(grind), _hit(live), "at 1.0 the grind and a live battle already agreed on a hit")
	assert_eq(_mend(grind), _mend(live), "at 1.0 the grind and a live battle already agreed on a heal")


func test_no_dial_is_read_only_in_the_tree() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/Combatant.gd")
	assert_gt(src.length(), 1000, "CONTROL: Combatant's source was read")
	var gated := 0
	for line in src.split("\n"):
		var code: String = line.strip_edges()
		if not code.begins_with("#") and code.contains("\"GameState\"") and code.contains("is_inside_tree()"):
			gated += 1
	assert_eq(gated, 0, "a GameState dial read gated on is_inside_tree() is blind in the grind; use _system(\"GameState\")")
