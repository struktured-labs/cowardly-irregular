extends GutTest

## Dead-field audit 2026-07-02: mage_prismatic_construct authored
## weakness_cycle [fire, ice, lightning] / weakness_cycle_turns 1 —
## the duel's designed gimmick — with ZERO consumers: all three
## weaknesses sat permanently active, making the duel easier and
## flavor-dead. BattleManager now rotates one live element per cycle
## step at round start. Also: smoke_bomb's "guarantee escape" promise
## now honors the authored guaranteed_escape field.

var _saved_ep: Array
var _saved_round: int


func before_each() -> void:
	_saved_ep = BattleManager.enemy_party.duplicate()
	_saved_round = BattleManager.current_round
	BattleManager.enemy_party.clear()


func after_each() -> void:
	BattleManager.enemy_party.clear()
	for e in _saved_ep:
		BattleManager.enemy_party.append(e)
	BattleManager.current_round = _saved_round


func _construct() -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": "Prismatic Construct", "max_hp": 280, "max_mp": 120,
		"attack": 22, "defense": 28, "magic": 34, "speed": 14})
	c.set_meta("monster_type", "mage_prismatic_construct")
	c.elemental_weaknesses.append("fire")
	c.elemental_weaknesses.append("ice")
	c.elemental_weaknesses.append("lightning")
	BattleManager.enemy_party.append(c)
	return c


func test_cycle_activates_one_element_per_round() -> void:
	var c := _construct()
	BattleManager.current_round = 1
	BattleManager._apply_weakness_cycles()
	assert_eq(c.elemental_weaknesses.size(), 1, "only ONE cycled weakness may be live")
	assert_eq(c.elemental_weaknesses[0], "fire", "round 1 = first cycle element")
	BattleManager.current_round = 2
	BattleManager._apply_weakness_cycles()
	assert_eq(c.elemental_weaknesses[0], "ice", "round 2 rotates to the second element")
	BattleManager.current_round = 4
	BattleManager._apply_weakness_cycles()
	assert_eq(c.elemental_weaknesses[0], "fire", "cycle wraps (round 4 → element 1 of 3)")


func test_non_cycling_enemies_untouched() -> void:
	var c := Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": "Goblin", "max_hp": 50, "max_mp": 0,
		"attack": 10, "defense": 5, "magic": 2, "speed": 8})
	c.set_meta("monster_type", "goblin")
	c.elemental_weaknesses.append("holy")
	BattleManager.enemy_party.append(c)
	BattleManager.current_round = 3
	BattleManager._apply_weakness_cycles()
	assert_eq(c.elemental_weaknesses, ["holy"] as Array[String],
		"enemies without weakness_cycle keep their static weaknesses")


func test_round_start_applies_the_cycle() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var fn: int = src.find("func _start_new_round")
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_true(body.contains("_apply_weakness_cycles()"),
		"the cycle must rotate at round start or the gimmick stays dead data")


func test_guaranteed_escape_is_honored() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(src.contains("ability.get(\"guaranteed_escape\", false)"),
		"smoke_bomb's description promises a guarantee — the roll must honor it")
