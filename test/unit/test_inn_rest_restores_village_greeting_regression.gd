extends GutTest

## Harmonia's innkeeper opens with the Silver Harp greeting from inn_dialogue.json.
## Cancel, a paid rest, and a short purse all call _set_keeper_lines(_keeper_greeting).
## _setup_npcs stored the generic world register instead of the lines just given to
## the NPC, so the next talk was "Welcome to The Traveler's Rest!" in every village.

const INN_PATH := "res://src/maps/interiors/InnInterior.gd"

const _STUB_GAMELOOP := """
extends Node
var party: Array = []
enum LoopState { EXPLORATION }
var current_state = LoopState.EXPLORATION
func get_village_origin_id() -> String:
	return \"harmonia_village\"
"""

var _prior_gold: int = 0
var _prior_world: int = 1
var _stub: Node = null
var _parked: Node = null


func before_each() -> void:
	_prior_gold = GameState.party_gold
	_prior_world = int(GameState.current_world)
	GameState.current_world = 1
	GameState.party_gold = 500
	_install_origin_stub()


func after_each() -> void:
	GameState.party_gold = _prior_gold
	GameState.current_world = _prior_world
	_remove_origin_stub()


func _install_origin_stub() -> void:
	var existing: Node = get_tree().root.get_node_or_null("GameLoop")
	if existing != null:
		existing.name = "GameLoop_parked_inn_greeting"
		_parked = existing
	var script := GDScript.new()
	script.source_code = _STUB_GAMELOOP
	script.reload()
	var stub := Node.new()
	stub.set_script(script)
	stub.name = "GameLoop"
	get_tree().root.add_child(stub)
	_stub = stub


func _remove_origin_stub() -> void:
	if _stub != null and is_instance_valid(_stub):
		_stub.free()
	_stub = null
	if _parked != null and is_instance_valid(_parked):
		_parked.name = "GameLoop"
	_parked = null


func _joined(lines: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for line in lines:
		parts.append(str(line))
	return "\n".join(parts)


func test_a_paid_rest_puts_the_village_greeting_back() -> void:
	var inn: Node2D = load(INN_PATH).new()
	add_child_autofree(inn)
	assert_not_null(inn._keeper_npc, "the innkeeper must be in the tree before a rest can replace her lines")
	var before: String = _joined(inn._keeper_npc.dialogue_lines)
	assert_true(before.contains("Silver Harp"),
		"PRECONDITION: the first talk must be the authored Harmonia greeting, got: %s" % before)
	inn._do_rest()
	var after: String = _joined(inn._keeper_npc.dialogue_lines)
	assert_true(after.contains("Silver Harp"),
		"after paying for a room the next talk must still be the Silver Harp, got: %s" % after)
	assert_false(after.contains("Traveler's Rest"),
		"a rest must not swap in the generic world register, got: %s" % after)
	await get_tree().create_timer(1.8).timeout
