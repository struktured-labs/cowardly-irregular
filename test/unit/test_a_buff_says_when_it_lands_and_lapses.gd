extends GutTest

## cowir-adhoc 24006: a buff or debuff appearing or wearing off played nothing, because Combatant said nothing.
## `buff_changed(stat, direction, added)` fires once when one appears and once when its turns run out; a refresh is silent.

var _seen: Array = []


func _heard(stat: String, direction: int, added: bool) -> void:
	_seen.append([stat, direction, added])


func _unit() -> Combatant:
	var c: Combatant = Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": "Unit", "max_hp": 500, "max_mp": 50, "attack": 40, "defense": 40, "magic": 40, "magic_defense": 40, "speed": 10})
	_seen = []
	c.buff_changed.connect(_heard)
	return c


func test_a_new_buff_and_a_new_debuff_each_say_so_once() -> void:
	var c := _unit()
	c.add_buff("Praesidium", "defense", 1.5, 3)
	assert_eq(_seen, [["defense", 1, true]], "a buff that appears: its stat, up, added")
	c.add_debuff("Armor Break", "attack", 0.7, 3)
	assert_eq(_seen.size(), 2, "a debuff that appears says so too")
	assert_eq(_seen[-1], ["attack", -1, true], "its stat, down, added")


func test_a_refresh_says_nothing() -> void:
	var c := _unit()
	c.add_buff("Praesidium", "defense", 1.5, 3)
	c.add_debuff("Armor Break", "attack", 0.7, 3)
	_seen = []
	c.add_buff("Praesidium", "defense", 1.8, 3)
	c.add_debuff("Armor Break", "attack", 0.5, 3)
	assert_eq(c.active_buffs.size(), 1, "CONTROL: the second cast refreshed the buff rather than adding one")
	assert_eq(_seen, [], "a refresh is not an arrival")


func test_running_out_says_so_once_and_only_when_it_runs_out() -> void:
	var c := _unit()
	c.add_buff("Praesidium", "defense", 1.5, 2)
	c.add_debuff("Armor Break", "attack", 0.7, 1)
	_seen = []
	c.update_buff_durations()
	assert_eq(_seen, [["attack", -1, false]], "the one-turn debuff lapses; the two-turn buff has not yet")
	c.update_buff_durations()
	assert_eq(_seen.size(), 2, "the buff lapses a turn later")
	assert_eq(_seen[-1], ["defense", 1, false], "its stat, up, gone")
	c.update_buff_durations()
	assert_eq(_seen.size(), 2, "and nothing lapses twice")


func test_a_dispel_is_not_a_lapse() -> void:
	var c := _unit()
	c.add_buff("Praesidium", "defense", 1.5, 3)
	_seen = []
	assert_gt(c.dispel(), 0, "CONTROL: the dispel removed the buff")
	assert_eq(_seen, [], "stripped is not wore-off: the dispel's own effect is that moment's beat")
