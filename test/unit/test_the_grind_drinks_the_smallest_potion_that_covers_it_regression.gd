extends GutTest

## Between fights, and on Heal Party, the grind drank HEAL_PARTY_ITEM_ORDER in fixed order, Hi-Potion first. Measured on a
## watched grind 2026-09-28: Hi-Potions (2000) healed 35 and 88 HP, all 7 healing items were gone by about battle 6, and
## about 23% of their healing was used. It now drinks the smallest item that covers the gap, else the strongest.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindState.restore(_ag)


func _member(max_hp: int, missing: int, potions: int = 3, hi: int = 3) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Drinker", "max_hp": max_hp, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_hp = max_hp - missing
	if potions > 0:
		c.add_item("potion", potions)
	if hi > 0:
		c.add_item("hi_potion", hi)
	return c


func _first(c: Combatant) -> String:
	var order: Array = AutogrindSystem.heal_items_by_preference(c, [c])
	return str(order[0]) if order.size() > 0 else ""


func test_the_heal_amounts_are_what_this_file_assumes() -> void:
	var c := _member(5000, 4000)
	assert_eq(ItemSystem.estimate_item_heal("potion", c), 500, "CONTROL: a Potion heals 500 here")
	assert_eq(ItemSystem.estimate_item_heal("hi_potion", c), 2000, "CONTROL: a Hi-Potion heals 2000 here")


func test_a_scratch_takes_a_potion_not_a_hi_potion() -> void:
	assert_eq(_first(_member(3000, 35)), "potion", "a 35-HP gap must not spend a 2000-HP Hi-Potion")


func test_a_gap_only_a_hi_potion_covers_takes_the_hi_potion() -> void:
	assert_eq(_first(_member(3000, 1500)), "hi_potion", "a 1500-HP gap is covered only by the Hi-Potion")


func test_a_gap_nothing_covers_takes_the_strongest() -> void:
	assert_eq(_first(_member(5000, 3000)), "hi_potion", "when nothing covers the gap, drink the strongest")


func test_an_empty_slot_is_skipped() -> void:
	assert_eq(_first(_member(3000, 35, 0, 2)), "hi_potion", "with no Potion left the Hi-Potion is the only choice")


func test_the_between_battle_heal_spends_the_potion() -> void:
	var gl: Node = load("res://src/GameLoop.gd").new()
	add_child_autofree(gl)
	var c := _member(3000, 35)
	var typed: Array[Combatant] = [c]
	gl.party = typed
	gl._autogrind_heal_member(c)
	assert_eq(c.current_hp, 3000, "CONTROL: the drink must land")
	assert_eq(c.get_item_count("potion"), 2, "the automatic between-fight heal must spend a Potion on a scratch")
	assert_eq(c.get_item_count("hi_potion"), 3, "and keep every Hi-Potion")


func test_heal_party_spends_the_potion() -> void:
	var sys = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(sys)
	sys._test_disable_persistence = true
	var holder := _member(3000, 0)
	var hurt := _member(1000, 300, 0, 0)
	var typed: Array[Combatant] = [holder, hurt]
	sys.grind_party = typed
	sys.apply_autogrind_actions([{"type": "heal_party"}])
	assert_eq(hurt.current_hp, 1000, "CONTROL: the 70%% ally must be healed")
	assert_eq(holder.get_item_count("potion"), 2, "Heal Party must spend a Potion on a 300-HP gap")
	assert_eq(holder.get_item_count("hi_potion"), 3, "and keep every Hi-Potion")
