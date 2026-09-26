extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## After every autogrind win, GameLoop drinks a Hi-Potion or Potion from the hurt member.
## That path still healed the literals 200 and 50. The items say 2000 and 500, and the
## rule-action copy of this drink was already moved onto ItemSystem. This one was not.
## A player opens the bag, reads "Restores 2000 HP", and watches the bar move by 200.

var _loop: Node
var _items: Node
var _ag: Dictionary


func before_all() -> void:
	_loop = load("res://src/GameLoop.gd").new()
	_items = get_tree().root.get_node_or_null("ItemSystem")


func after_all() -> void:
	if is_instance_valid(_loop):
		_loop.free()


func before_each() -> void:
	_ag = AutogrindState.snapshot_and_isolate()


func after_each() -> void:
	AutogrindState.restore(_ag)


func _hurt(item_id: String, qty: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Grinder", "max_hp": 9000, "max_mp": 500, "attack": 20, "defense": 15, "magic": 10, "speed": 12})
	c.current_hp = 100
	c.current_mp = 0
	if item_id != "":
		c.add_item(item_id, qty)
	return c


func _authored_hp(item_id: String) -> int:
	return int(_items.get_item(item_id).get("effects", {}).get("heal_hp", 0))


func _authored_mp(item_id: String) -> int:
	return int(_items.get_item(item_id).get("effects", {}).get("heal_mp", 0))


func test_a_potion_between_battles_heals_what_it_says() -> void:
	assert_not_null(_items, "CONTROL: ItemSystem must be present")
	var authored := _authored_hp("potion")
	assert_gt(authored, 50, "CONTROL: potion must author more than the old literal 50, or this arm cannot see the bug")
	var m := _hurt("potion", 2)
	_loop._autogrind_heal_member(m)
	assert_eq(m.current_hp - 100, authored, "a Potion between autogrind battles restored %d, and the item authors %d" % [m.current_hp - 100, authored])
	assert_eq(m.get_item_count("potion"), 1, "exactly one Potion is spent")
	m.free()


func test_a_hi_potion_is_spent_before_a_potion_and_heals_what_it_says() -> void:
	var authored := _authored_hp("hi_potion")
	assert_gt(authored, 200, "CONTROL: hi-potion must author more than the old literal 200")
	var m := _hurt("potion", 1)
	m.add_item("hi_potion", 1)
	_loop._autogrind_heal_member(m)
	assert_eq(m.get_item_count("hi_potion"), 0, "the stronger potion is the one that is spent")
	assert_eq(m.get_item_count("potion"), 1, "the ordinary potion stays in the bag")
	assert_eq(m.current_hp - 100, authored, "a Hi-Potion between autogrind battles restored %d, and the item authors %d" % [m.current_hp - 100, authored])
	m.free()


func test_an_ether_between_battles_restores_what_it_says() -> void:
	var authored := _authored_mp("ether")
	assert_gt(authored, 0, "CONTROL: ether must author a heal_mp")
	var m := _hurt("ether", 1)
	_loop._autogrind_restore_mp(m)
	assert_eq(m.current_mp, authored, "an Ether between autogrind battles restored %d, and the item authors %d" % [m.current_mp, authored])
	assert_eq(m.get_item_count("ether"), 0, "the Ether is spent")
	m.free()


func test_the_between_battle_drink_reads_the_item() -> void:
	var code := GdSource.code_of("res://src/GameLoop.gd")
	var heal_at := code.find("func _autogrind_heal_member")
	var mp_at := code.find("func _autogrind_restore_mp")
	assert_gt(heal_at, -1, "CONTROL: the between-battle heal is still in GameLoop")
	assert_gt(mp_at, heal_at, "CONTROL: the MP restore still follows the heal")
	var body := code.substr(heal_at, mp_at - heal_at + 700)
	assert_true(body.contains("use_item("), "the between-battle drink does not ask ItemSystem, so the amount is a second copy of the item")
	for stale in ['["hi_potion", 200]', '["potion", 50]', '["hi_ether", 100]', '["ether", 30]']:
		assert_false(body.contains(stale), "GameLoop still carries the literal %s" % stale)
