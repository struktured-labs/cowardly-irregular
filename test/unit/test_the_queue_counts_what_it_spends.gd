extends GutTest

## Advance queued any action while the queue had room. It never added up what the queued actions
## would SPEND, so with 12 MP you could queue two 10-MP Fires, or two Potions from a bag holding one.
## The second one reached _execute_ability's can_use_ability gate (or _execute_item's count check),
## logged "can't use that right now", and the Advance AP it cost was gone. The menu now keeps a
## resource budget (MP, and each item's count) supplied by BattleCommandMenu, and refuses a queue
## entry the budget left after the earlier entries cannot cover.

const FIRE := {"ability_id": "fire", "target_idx": 0, "target_type": "enemy"}
const POTION := {"item_id": "potion", "target_idx": 0, "target_type": "ally"}


func _root(budget: Dictionary) -> Win98Menu:
	var m := Win98Menu.new()
	m.is_root_menu = true
	add_child_autofree(m)
	m.set_max_queue_size(5)
	## Stand-in for BattleCommandMenu._queued_cost: Fire is 10 MP, a Potion is one potion.
	m.set_queue_budget(budget, func(data):
		if data is Dictionary and str(data.get("ability_id", "")) == "channel":
			return {"mp_gain": 6}
		if data is Dictionary and data.has("ability_id"):
			return {"mp": 10}
		if data is Dictionary and data.has("item_id"):
			return {"item:" + str(data["item_id"]): 1}
		return {})
	return m


func _queue(m: Win98Menu, data: Dictionary) -> void:
	m._queue_current_action({"id": "row", "data": data, "label": "row"})


func test_a_second_spell_the_mp_cannot_cover_is_refused() -> void:
	var m := _root({"mp": 12})
	_queue(m, FIRE)
	assert_eq(m._queued_actions.size(), 1, "CONTROL: the first 10-MP Fire fits a 12-MP budget")
	_queue(m, FIRE)
	assert_eq(m._queued_actions.size(), 1,
		"12 MP covers one 10-MP Fire; queuing a second spends Advance AP on a cast that cannot happen")


func test_a_potion_the_bag_does_not_hold_is_refused() -> void:
	var m := _root({"item:potion": 1})
	_queue(m, POTION)
	_queue(m, POTION)
	assert_eq(m._queued_actions.size(), 1, "one potion in the bag queues once")


func test_undo_gives_the_budget_back() -> void:
	var m := _root({"mp": 12})
	_queue(m, FIRE)
	m._undo_last_action()
	_queue(m, FIRE)
	assert_eq(m._queued_actions.size(), 1, "after undoing the first Fire, its 10 MP is available again")


func test_a_menu_with_no_budget_is_unchanged() -> void:
	var m := Win98Menu.new()
	m.is_root_menu = true
	add_child_autofree(m)
	m.set_max_queue_size(5)
	_queue(m, FIRE)
	_queue(m, FIRE)
	assert_eq(m._queued_actions.size(), 2,
		"no budget set (field menus, other callers) must keep the old size-only rule")


func test_the_battle_menu_prices_actions_as_the_engine_charges() -> void:
	var c := Combatant.new()
	c.initialize({"name": "Caster", "max_hp": 100, "max_mp": 99, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	var cmd = BattleCommandMenu.new(null)
	assert_eq(cmd._queued_cost(FIRE, c), {"mp": JobSystem.get_ability_mp_cost(c, "fire")},
		"the queue must price a spell at get_ability_mp_cost, the number _execute_ability spends")
	assert_eq(cmd._queued_cost(POTION, c), {"item:potion": 1}, "an item costs one of itself")
	assert_eq(cmd._queued_cost({"action": "defer"}, c), {}, "anything else costs nothing")


const CHANNEL := {"ability_id": "channel"}


func test_channel_queued_first_pays_for_the_spell_after_it() -> void:
	## cowir-main: Channel is the Mage's free move and "Channel, then the spell it pays for" is the
	## Advance combo the game teaches. It executes first, so it must count.
	var m := _root({"mp": 5, "mp_max": 99})
	_queue(m, CHANNEL)
	_queue(m, FIRE)
	assert_eq(m._queued_actions.size(), 2, "5 MP + Channel's 6 covers a 10-MP Fire queued after it")


func test_channel_queued_after_does_not_pay_for_the_spell_before_it() -> void:
	var m := _root({"mp": 5, "mp_max": 99})
	_queue(m, FIRE)
	assert_eq(m._queued_actions.size(), 0, "the Fire runs first, on 5 MP, before any Channel")


func test_a_restore_is_capped_at_max_mp_like_the_executor() -> void:
	var m := _root({"mp": 8, "mp_max": 9})
	_queue(m, CHANNEL)
	_queue(m, FIRE)
	assert_eq(m._queued_actions.size(), 1, "Channel on 8/9 MP restores 1, not 6, so 10 MP is never there")


func test_the_battle_menu_credits_channel_at_the_executors_amount() -> void:
	var c := Combatant.new()
	c.initialize({"name": "Mage", "max_hp": 100, "max_mp": 99, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	var cmd = BattleCommandMenu.new(null)
	var channel: Dictionary = JobSystem.get_ability("channel")
	assert_eq(str(channel.get("type", "")), "mp_restore", "CONTROL: channel must be an mp_restore")
	assert_eq(cmd._queued_cost(CHANNEL, c).get("mp_gain", -1), BattleManager._mp_restore_amount(channel),
		"a queued Channel must credit exactly what _execute_mp_restore_ability restores")
