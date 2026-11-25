extends GutTest

## world6_the_last_thing was withheld (wiring_pending): its giver stood nowhere and nothing could set step 2's
## recall flag. The Shopkeeper now stands in Vertex and the step is a choice the player makes at the counter.

const QID := "world6_the_last_thing"
const NPC_ID := "last_shopkeeper_w6"
const FLAG := "quest_world6_the_last_thing_items_recalled"
const SWORD_LABEL := "The sword that came back"
const NOTHING_LABEL := "Nothing"

var _qs: Node
var _real_quest: Dictionary = {}
var _held_state: Variant = null
var _flag_was: Variant = null
var _loop: Node = null


class FakeMember:
	var inventory: Dictionary = {}


class FakeLoop extends Node:
	var party: Array = []


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	_real_quest = (_qs.get_quest(QID) as Dictionary).duplicate(true)
	_held_state = GameState.quests.get(QID, null)
	_flag_was = GameState.story_flags.get(FLAG, null)
	GameState.story_flags.erase(FLAG)


func after_each() -> void:
	_qs._quests[QID] = _real_quest
	if _held_state == null:
		GameState.quests.erase(QID)
	else:
		GameState.quests[QID] = _held_state
	if _flag_was == null:
		GameState.story_flags.erase(FLAG)
	else:
		GameState.story_flags[FLAG] = _flag_was
	if is_instance_valid(_loop):
		_loop.free()
	_loop = null


## The real quest's choices and gates, silenced: no lines to click through, and step 3 answered by someone else so the
## run stops at the step under test instead of completing the quest and granting its rewards.
func _arm(holds_sword: bool) -> Node2D:
	assert_null(get_tree().root.get_node_or_null("GameLoop"), "CONTROL: no real GameLoop here, so the fake party is the one read")
	_loop = FakeLoop.new()
	_loop.name = "GameLoop"
	var member := FakeMember.new()
	if holds_sword:
		member.inventory["returned_sword"] = 1
	_loop.party = [member]
	get_tree().root.add_child(_loop)
	var q: Dictionary = _real_quest.duplicate(true)
	q["dialogue"] = {}
	for c in q["objectives"][1].get("choices", []):
		c["lines"] = []
	q["objectives"][2]["target_npc"] = "zz_someone_else"
	_qs._quests[QID] = q
	GameState.quests[QID] = {"state": "active", "objective_index": 1}
	assert_eq(_qs.get_objective_index(QID), 1, "CONTROL: the recall step is current")
	assert_false(_qs._flag(FLAG), "CONTROL: nothing has been recalled yet")
	var npc := Node2D.new()
	npc.set("npc_name", "The Shopkeeper")
	add_child_autofree(npc)
	return npc


func _open_menu(npc: Node2D) -> Node:
	_qs.run_giver_dialogue(NPC_ID, npc)
	for _i in range(30):
		await get_tree().process_frame
		var menu: Node = get_tree().root.find_child("QuestChoice", true, false)
		if menu != null:
			return menu
	return null


func _settle() -> void:
	for _i in range(10):
		await get_tree().process_frame


func test_nothing_is_always_on_offer_and_moves_the_quest_on() -> void:
	var menu: Node = await _open_menu(_arm(false))
	assert_not_null(menu, "talking to the Shopkeeper mid-quest offers the recall")
	if menu == null:
		return
	assert_eq(Array(menu._choices), [NOTHING_LABEL], "without the sword, only Nothing is offered")
	menu._selection = 0
	menu._confirm()
	await _settle()
	assert_true(_qs._flag(FLAG), "choosing Nothing is a real recall, by design: same reward regardless")
	assert_eq(_qs.get_objective_index(QID), 2, "the quest moves on to giving the Shopkeeper the word")


func test_the_sword_is_offered_to_the_party_that_holds_it() -> void:
	var menu: Node = await _open_menu(_arm(true))
	assert_not_null(menu, "the recall is offered")
	if menu == null:
		return
	assert_eq(Array(menu._choices), [SWORD_LABEL, NOTHING_LABEL], "holding the returned sword adds its memory")
	menu._selection = 0
	menu._confirm()
	await _settle()
	assert_eq(_qs.get_objective_index(QID), 2, "remembering the sword moves the quest on")


func test_backing_out_leaves_the_recall_open() -> void:
	var menu: Node = await _open_menu(_arm(true))
	assert_not_null(menu, "the recall is offered")
	if menu == null:
		return
	menu._cancel()
	await _settle()
	assert_false(_qs._flag(FLAG), "cancel recalls nothing")
	assert_eq(_qs.get_objective_index(QID), 1, "the step waits for the next visit")


func test_the_real_quest_can_be_finished_at_the_counter() -> void:
	assert_false(bool(_real_quest.get("wiring_pending", false)), "the quest is offered to players")
	var steps: Array = _real_quest.get("objectives", [])
	assert_eq(str(steps[1].get("required_flag", "")), FLAG, "step 2 waits on the flag the choice sets")
	var open_choices := 0
	for c in steps[1].get("choices", []):
		var need: String = str(c.get("requires_item", ""))
		if need == "":
			open_choices += 1
		else:
			assert_false(ItemSystem.get_item(need).is_empty(), "%s names a real item" % need)
		var lines: Array = c.get("lines", [])
		assert_false(lines.is_empty() or str(lines[0].get("text", "")) == "", "%s says something" % c.get("label", "?"))
	assert_gt(open_choices, 0, "some choice needs nothing, so every party can finish the quest")
	assert_eq(str(steps[2].get("target_npc", "")), NPC_ID, "step 3 is answered at the same counter")
	assert_eq(str(steps[2].get("required_flag", "")), FLAG, "step 3 opens once the recall is made")


func test_the_shopkeeper_stands_in_vertex() -> void:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var v: Node = load("res://src/maps/villages/VertexVillage.gd").new()
	vp.add_child(v)
	await get_tree().process_frame
	var found: Node = null
	for n in v.npcs.get_children():
		if n.has_method("get_npc_id") and n.get_npc_id() == NPC_ID:
			found = n
	assert_not_null(found, "the quest's giver is placed in the village its quest names")
	if found != null:
		assert_true(v._is_cell_walkable(Vector2i(floori(found.position.x / 32.0), floori(found.position.y / 32.0)) + Vector2i(0, 1)),
			"the cell in front of the Shopkeeper can be stood on, so they can be talked to")
