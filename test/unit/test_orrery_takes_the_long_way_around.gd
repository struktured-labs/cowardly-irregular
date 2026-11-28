extends GutTest

## world5_long_way_around was withheld (wiring_pending): Orrery_v5 stood nowhere and nothing decrypted step 2's object.
## She now stands in Node Prime, the object is an examine point beside her, and the attendant recognises the blueprint.

const QID := "world5_long_way_around"
const GIVER := "madame_orrery_w5"
const ATTENDANT := "firewall_attendant_w5"
const DECRYPTED := "quest_world5_long_way_around_decrypted"
const DELIVERED := "quest_world5_long_way_around_delivered"
const SENT_ORIGINAL := "quest_world5_termination_condition_sent_original"
const SIGNAL_SENT := "quest_world5_termination_condition_signal_sent"

var _qs: Node
var _held: Dictionary = {}


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	_held = {"story": GameState.story_flags.duplicate(true), "consts": GameState.game_constants.duplicate(true),
		"state": GameState.quests.get(QID, null)}
	for f in [DECRYPTED, DELIVERED, SENT_ORIGINAL, SIGNAL_SENT]:
		GameState.story_flags.erase(f)


func after_each() -> void:
	GameState.story_flags = _held["story"]
	GameState.game_constants = _held["consts"]
	if _held["state"] == null:
		GameState.quests.erase(QID)
	else:
		GameState.quests[QID] = _held["state"]


func _node_prime() -> Node:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var v: Node = load("res://src/maps/villages/NodePrimeVillage.gd").new()
	vp.add_child(v)
	await get_tree().process_frame
	return v


func _npc(v: Node, id: String) -> Node:
	for n in v.npcs.get_children():
		if n.has_method("get_npc_id") and n.get_npc_id() == id:
			return n
	return null


func _decrypt_point(v: Node) -> Node:
	for n in v.npcs.get_children():
		if n.get("quest_id") == QID and n.get("flag") == DECRYPTED:
			return n
	return null


func _cell(n: Node) -> Vector2i:
	return Vector2i(floori(n.position.x / 32.0), floori(n.position.y / 32.0))


func test_the_quest_is_offered_by_an_orrery_who_stands_in_node_prime() -> void:
	var q: Dictionary = _qs.get_quest(QID)
	assert_false(bool(q.get("wiring_pending", false)), "the quest is offered to players")
	assert_false(_qs.is_wiring_pending(QID), "and QuestSystem agrees")
	assert_eq(str(q.get("prereq_flag", "")), "world4_orrery_complete", "CONTROL: the chain still waits on the W4 step")
	var v: Node = await _node_prime()
	var orrery: Node = _npc(v, GIVER)
	assert_not_null(orrery, "the quest's giver is placed in Node Prime")
	if orrery != null:
		var c := _cell(orrery)
		assert_true(v._is_cell_walkable(c + Vector2i(0, 1)) or v._is_cell_walkable(c + Vector2i(-1, 0)),
			"a cell beside Orrery can be stood on, so she can be talked to")


func test_decrypting_the_object_moves_the_quest_on() -> void:
	var v: Node = await _node_prime()
	var point: Node = _decrypt_point(v)
	assert_not_null(point, "Node Prime has somewhere to decrypt the object")
	if point == null:
		return
	assert_true(v._is_cell_walkable(_cell(point)), "the object sits where the party can walk up to it")
	GameState.quests[QID] = {"state": "active", "objective_index": 0}
	assert_false(point._is_live(), "CONTROL: before Orrery hands it over, the object is not live")
	GameState.quests[QID] = {"state": "active", "objective_index": 1}
	assert_true(point._is_live(), "CONTROL: the object answers while decrypting is the current step")
	point._examine()
	assert_true(_qs._flag(DECRYPTED), "decrypting is what step 2 asks for")
	assert_eq(_qs.get_objective_index(QID), 2, "the quest moves on to delivering the blueprint")


func test_before_delivery_the_attendant_only_halts_you() -> void:
	var v: Node = await _node_prime()
	var fw: Node = _npc(v, ATTENDANT)
	assert_not_null(fw, "CONTROL: the attendant stands in Node Prime")
	if fw != null:
		assert_eq(fw.dialogue_lines, v.ATTENDANT_DEFAULT_LINES, "no blueprint, no recognition")


func test_delivering_the_blueprint_reaches_the_attendant_the_moment_it_lands() -> void:
	var v: Node = await _node_prime()
	var fw: Node = _npc(v, ATTENDANT)
	assert_not_null(fw, "CONTROL: the attendant stands in Node Prime")
	if fw == null:
		return
	GameState.set_story_flag(DECRYPTED, true)
	GameState.quests[QID] = {"state": "active", "objective_index": 2}
	assert_eq(_qs.notify_talk(ATTENDANT), "", "CONTROL: delivery is not the last step")
	assert_true(_qs._flag(DELIVERED), "talking to the attendant delivers the blueprint")
	assert_eq(_qs.get_objective_index(QID), 3, "the quest moves on to telling Orrery")
	var n: int = v.ATTENDANT_BLUEPRINT_LINES.size()
	assert_eq(fw.dialogue_lines.slice(0, n), v.ATTENDANT_BLUEPRINT_LINES, "the attendant recognises the notation on that same visit")
	assert_eq(fw.dialogue_lines[n], v.ATTENDANT_FILED_LINE, "with the overflow still running, she files it where the builder does not read")


## Delivered and the quest still open, after the party answered the stack: the notes' shelter filing, then the answer.
func test_once_the_overflow_is_resolved_she_files_it_in_the_shelter() -> void:
	GameState.set_story_flag(DELIVERED, true)
	GameState.set_story_flag(SIGNAL_SENT, true)
	GameState.set_story_flag(SENT_ORIGINAL, true)
	GameState.quests[QID] = {"state": "active", "objective_index": 3}
	var v: Node = await _node_prime()
	var fw: Node = _npc(v, ATTENDANT)
	assert_not_null(fw, "CONTROL: the attendant stands in Node Prime")
	if fw == null:
		return
	var n: int = v.ATTENDANT_BLUEPRINT_LINES.size()
	assert_eq(fw.dialogue_lines.slice(0, n), v.ATTENDANT_BLUEPRINT_LINES, "the blueprint comes first")
	assert_eq(fw.dialogue_lines[n], v.ATTENDANT_FILED_IN_SHELTER_LINE, "filed in the shelter the seventeen left")
	var rest: String = " ".join(PackedStringArray(fw.dialogue_lines.slice(n + 1)))
	assert_true(rest.contains("thank you"), "and the answer the party sent the stack still follows: %s" % rest)
	assert_false(rest.contains("HALT"), "not the post's default halt")


## After the turn-in the first sighting is over: one past-tense line, not the recognition again on every visit.
func test_after_the_turn_in_the_recognition_is_past_tense() -> void:
	GameState.set_story_flag(DELIVERED, true)
	GameState.quests[QID] = {"state": "complete", "objective_index": 4}
	var v: Node = await _node_prime()
	var fw: Node = _npc(v, ATTENDANT)
	assert_not_null(fw, "CONTROL: the attendant stands in Node Prime")
	if fw == null:
		return
	assert_eq(_qs.get_state(QID), "complete", "CONTROL: the quest reads as turned in")
	assert_eq(fw.dialogue_lines[0], v.ATTENDANT_BLUEPRINT_AFTER_LINE, "one past-tense line leads")
	assert_false(" ".join(PackedStringArray(fw.dialogue_lines)).contains("administrative notation"), "the first sighting does not replay")
	assert_eq(fw.dialogue_lines.slice(1), v.ATTENDANT_DEFAULT_LINES, "then the post as before")
