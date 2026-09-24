extends GutTest

## .482 made battle read the party's one item bag, so a Cleric's "potion > 0" rule fires on the
## leader's potions. The grid editor's Simulate still copied only the Cleric's own inventory, which is
## empty because every grant lands on the leader. The preview called that rule dead while the battle
## fired it. The probe now carries the bag of the party the edited character belongs to.

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const _STUB_GAMELOOP := "extends Node\nvar party: Array = []\n"

var _stub: Node = null


func after_each() -> void:
	if _stub != null and is_instance_valid(_stub):
		if _stub.get_parent() != null:
			_stub.get_parent().remove_child(_stub)
		_stub.free()
	_stub = null


func _pc(pc_name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": pc_name, "max_hp": 100, "max_mp": 40, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func _party_loop(party: Array) -> void:
	var script := GDScript.new()
	script.source_code = _STUB_GAMELOOP
	script.reload()
	_stub = Node.new()
	_stub.set_script(script)
	_stub.name = "GameLoop"
	_stub.party = party
	get_tree().root.add_child(_stub)


func _potion_rule_fires(editor: Node) -> bool:
	var rules: Array = [
		{"enabled": true,
		 "conditions": [{"type": "hp_percent", "op": "<", "value": 50},
			{"type": "item_count", "item_id": "potion", "op": ">", "value": 0}],
		 "actions": [{"type": "item", "id": "potion", "target": "self"}]},
		{"enabled": true, "conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}]},
	]
	for line in editor._simulate_report(rules):
		if str(line).contains("rule 1 fires"):
			return true
	return false


func _editor_for(pc: Combatant) -> Node:
	var e: Node = load(EDITOR).new()
	e.character_id = "bag_probe"
	e.character_name = pc.combatant_name
	add_child_autofree(e)
	e.combatant = pc
	return e


func test_a_member_without_potions_sees_the_leaders_bag() -> void:
	var leader := _pc("Fighter")
	var cleric := _pc("Cleric")
	leader.add_item("potion", 3)
	_party_loop([leader, cleric])
	assert_eq(cleric.get_item_count("potion"), 0, "CONTROL: the Cleric carries none; the bag is the leader's")
	assert_true(_potion_rule_fires(_editor_for(cleric)),
		"Simulate called the Cleric's potion rule dead while battle fires it on the party's bag")


func test_control_a_character_outside_any_party_keeps_its_own_inventory() -> void:
	var loner := _pc("Loner")
	_party_loop([_pc("Someone Else")])
	assert_false(_potion_rule_fires(_editor_for(loner)),
		"CONTROL: nothing in the loner's bag, so the rule must not fire — otherwise the arm above proves nothing")
	loner.add_item("potion", 1)
	assert_true(_potion_rule_fires(_editor_for(loner)), "CONTROL: its own potion still counts")


func test_decoy_the_probe_never_writes_back_to_the_party() -> void:
	var leader := _pc("Fighter")
	var cleric := _pc("Cleric")
	leader.add_item("potion", 3)
	_party_loop([leader, cleric])
	_potion_rule_fires(_editor_for(cleric))
	assert_eq(leader.get_item_count("potion"), 3, "Simulate spent the leader's potion — it must be pure")
	assert_eq(cleric.get_item_count("potion"), 0, "Simulate wrote the bag into the real Cleric")
