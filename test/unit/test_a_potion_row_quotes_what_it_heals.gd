extends GutTest

## An ability heal's ally row reads "Mender (40/900 HP) ~+1300"; an item heal's row read only
## "Mender (40/900 HP)". Same action, same target list, and the potion's number was nowhere, so a
## player choosing between Cure and a Potion could compare one of them. Item heals go through
## Combatant.heal(), so the quote comes from heal_preview: curse and the healing dial move it too.

class FakeScene extends Node2D:
	var party_members: Array = []
	var party_sprite_nodes: Array = []
	var test_enemies: Array = []
	var enemy_sprite_nodes: Array = []

const ITEM := "potion"
const DIAL := "healing_multiplier"

var _saved_dial: float = 1.0
var _saved_inv: Dictionary = {}


func before_each() -> void:
	_saved_dial = float(GameState.game_constants.get(DIAL, 1.0))


func after_each() -> void:
	GameState.game_constants[DIAL] = _saved_dial


func _member() -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Mender", "max_hp": 100000, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_hp = 40
	return c


## The quote on the potion's row for this member, or -1 if the row carries none.
func _quoted(user: Combatant) -> int:
	var scene := FakeScene.new()
	add_child_autofree(scene)
	scene.party_members = [user]
	var row: Dictionary = BattleCommandMenu.new(scene)._item_ally_row(ITEM, user, 0)
	var label: String = str(row.get("label", ""))
	if not label.contains("~+"):
		return -1
	return label.split("~+")[1].to_int()


func _delivered(user: Combatant) -> int:
	user.current_hp = 40
	var before := user.current_hp
	ItemSystem._apply_item_effects(user, user, ItemSystem.get_item(ITEM))
	return user.current_hp - before


func test_the_potion_heals_something_to_quote() -> void:
	var e: Dictionary = ItemSystem.get_item(ITEM).get("effects", {})
	assert_gt(int(e.get("heal_hp", 0)), 0,
		"CONTROL: %s must author heal_hp, or the row has nothing to quote" % ITEM)


func test_the_row_quotes_what_the_potion_delivers() -> void:
	var user := _member()
	var rows: Array = [
		{"what": "a plain target", "dial": 1.0, "curse": false},
		{"what": "the healing dial at 2.0", "dial": 2.0, "curse": false},
		{"what": "a cursed target", "dial": 1.0, "curse": true},
	]
	var wrong: Array[String] = []
	for row in rows:
		GameState.game_constants[DIAL] = float(row["dial"])
		user.remove_status("curse")
		if bool(row["curse"]):
			user.add_status("curse", 99)
		var q := _quoted(user)
		var d := _delivered(user)
		if q != d:
			wrong.append("%s: row reads %s, potion heals %d" % [row["what"], "no number" if q < 0 else "~+%d" % q, d])
	user.remove_status("curse")
	assert_eq(wrong, [], "an item's ally row must quote what the item heals: %s" % str(wrong))
