extends GutTest

## The manual menu's Advance queue now refuses what the turn can't pay for (.546). Autobattle was
## the same hole one layer down: _process_grid_autobattle converts each of a rule's actions on its
## own against the full MP and bag, so "Fire, Fire, Fire" on 12 MP queued all three and "Potion x3"
## on one potion queued three. Every extra one reached _execute_ability / _execute_item, logged
## "can't use that right now", and cost its Advance AP. The converted actions now go through an
## in-order budget: MP spent by each cast, credited by a restore that reaches the caster (Channel),
## capped at max MP, and each item counted against the party bag.

var _saved_party: Array = []


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()


func after_each() -> void:
	var keep: Array = []
	for c in _saved_party:
		if is_instance_valid(c):
			keep.append(c)
	BattleManager.player_party.assign(keep)


func _caster(mp: int, max_mp: int = 99) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Scripted", "max_hp": 100, "max_mp": max_mp, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_mp = mp
	c.inventory = {}
	BattleManager.player_party.assign([c] as Array[Combatant])
	return c


func _ids(actions: Array) -> Array:
	var out: Array = []
	for a in actions:
		out.append(str(a.get("ability_id", a.get("item_id", a.get("type", "")))))
	return out


func test_fire_is_the_price_this_file_assumes() -> void:
	var c := _caster(99)
	assert_eq(JobSystem.get_ability_mp_cost(c, "fire"), 8,
		"CONTROL: the arms below size their MP around fire's cost; update them if this moves")


func test_a_second_cast_the_mp_cannot_cover_is_dropped() -> void:
	var c := _caster(12)
	var kept: Array = BattleManager._affordable_advance(c, [
		{"type": "ability", "ability_id": "fire"},
		{"type": "ability", "ability_id": "fire"},
	])
	assert_eq(_ids(kept), ["fire"], "12 MP pays for one 8-MP Fire; the second would fail and cost AP")


func test_attacks_cost_nothing_and_always_stay() -> void:
	var c := _caster(0)
	var kept: Array = BattleManager._affordable_advance(c, [
		{"type": "attack"}, {"type": "ability", "ability_id": "fire"}, {"type": "attack"},
	])
	assert_eq(_ids(kept), ["attack", "attack"], "a 0-MP caster keeps both swings and drops the cast")


func test_a_potion_the_bag_does_not_hold_twice_is_dropped() -> void:
	var c := _caster(99)
	c.inventory = {"potion": 1}
	var kept: Array = BattleManager._affordable_advance(c, [
		{"type": "item", "item_id": "potion"}, {"type": "item", "item_id": "potion"},
	])
	assert_eq(_ids(kept), ["potion"], "one potion in the bag is one potion in the queue")


func test_channel_first_pays_for_the_cast_after_it() -> void:
	var c := _caster(2)
	var kept: Array = BattleManager._affordable_advance(c, [
		{"type": "ability", "ability_id": "channel"}, {"type": "ability", "ability_id": "fire"},
	])
	assert_eq(_ids(kept), ["channel", "fire"], "2 MP + Channel's restore covers a Fire queued after it")


func test_the_grid_path_filters_its_advance() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var at := src.find("func _process_grid_autobattle(")
	assert_gt(at, -1, "_process_grid_autobattle must exist")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_true(body.contains("_affordable_advance(combatant, advance_actions)"),
		"the grid path must filter its converted actions through the budget before queuing an Advance")
