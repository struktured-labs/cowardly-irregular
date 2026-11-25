extends GutTest

## world5_termination_condition was withheld: nothing could read the stack (step 2) or send it an answer (step 3).
## The overflow is now an examine point beside FIREWALL-ALPHA, and the attendant offers the three kinds of answer.

const QID := "world5_termination_condition"
const NPC_ID := "firewall_attendant_w5"
const READ_FLAG := "quest_world5_termination_condition_stack_read"
const SENT_FLAG := "quest_world5_termination_condition_signal_sent"
const VARIANTS := ["quest_world5_termination_condition_sent_task_complete", "quest_world5_termination_condition_sent_terminated",
	"quest_world5_termination_condition_sent_original"]

var _qs: Node
var _real_quest: Dictionary = {}
var _held_state: Variant = null
var _held_flags: Dictionary = {}


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	_real_quest = (_qs.get_quest(QID) as Dictionary).duplicate(true)
	_held_state = GameState.quests.get(QID, null)
	_held_flags.clear()
	for f in [READ_FLAG, SENT_FLAG] + VARIANTS:
		if GameState.story_flags.has(f):
			_held_flags[f] = GameState.story_flags[f]
		GameState.story_flags.erase(f)


func after_each() -> void:
	_qs._quests[QID] = _real_quest
	if _held_state == null:
		GameState.quests.erase(QID)
	else:
		GameState.quests[QID] = _held_state
	for f in [READ_FLAG, SENT_FLAG] + VARIANTS:
		GameState.story_flags.erase(f)
	for f in _held_flags:
		GameState.story_flags[f] = _held_flags[f]


## The real choices, silenced, with step 4 answered elsewhere so the run stops at the step under test.
func _arm_send() -> Node2D:
	var q: Dictionary = _real_quest.duplicate(true)
	q["dialogue"] = {}
	for c in q["objectives"][2].get("choices", []):
		c["lines"] = []
	q["objectives"][3]["target_npc"] = "zz_someone_else"
	_qs._quests[QID] = q
	GameState.quests[QID] = {"state": "active", "objective_index": 2}
	assert_eq(_qs.get_objective_index(QID), 2, "CONTROL: the send step is current")
	assert_false(_qs._flag(SENT_FLAG), "CONTROL: nothing has been sent yet")
	var npc := Node2D.new()
	npc.set("npc_name", "FIREWALL-ALPHA")
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


func _build_node_prime() -> Node:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var v: Node = load("res://src/maps/villages/NodePrimeVillage.gd").new()
	vp.add_child(v)
	return v


func _stack_point(v: Node) -> Node:
	for n in v.npcs.get_children():
		if n.get("quest_id") == QID and n.get("flag") == READ_FLAG:
			return n
	return null


func test_reading_the_stack_moves_the_quest_on() -> void:
	var v := _build_node_prime()
	await get_tree().process_frame
	var point := _stack_point(v)
	assert_not_null(point, "Node Prime has somewhere to read the stack")
	if point == null:
		return
	assert_true(v._is_cell_walkable(Vector2i(floori(point.position.x / 32.0), floori(point.position.y / 32.0))),
		"the overflow stands where the party can walk up to it")
	GameState.quests[QID] = {"state": "active", "objective_index": 1}
	assert_true(point._is_live(), "CONTROL: the point answers while reading is the current step")
	point._examine()
	assert_true(_qs._flag(READ_FLAG), "reading the stack is what step 2 asks for")
	assert_eq(_qs.get_objective_index(QID), 2, "the quest moves on to sending an answer")


func test_the_attendant_offers_every_kind_of_answer() -> void:
	var menu: Node = await _open_menu(_arm_send())
	assert_not_null(menu, "talking to the attendant on the send step offers the answers")
	if menu == null:
		return
	var labels: Array = []
	for c in _real_quest["objectives"][2]["choices"]:
		labels.append(str(c["label"]))
	assert_eq(Array(menu._choices), labels, "every authored answer is offered; none needs an item")
	menu._selection = 1
	menu._confirm()
	await _settle()
	assert_true(_qs._flag(SENT_FLAG), "an answer was sent")
	assert_true(_qs._flag(VARIANTS[1]), "the answer chosen is remembered as its own variant")
	assert_false(_qs._flag(VARIANTS[0]) or _qs._flag(VARIANTS[2]), "and only that one")
	assert_eq(_qs.get_objective_index(QID), 3, "the quest moves on to standing with the attendant")


func test_backing_out_sends_nothing() -> void:
	var menu: Node = await _open_menu(_arm_send())
	assert_not_null(menu, "the answers are offered")
	if menu == null:
		return
	menu._cancel()
	await _settle()
	assert_false(_qs._flag(SENT_FLAG), "cancel sends nothing")
	for f in VARIANTS:
		assert_false(_qs._flag(f), "%s stays unset" % f)
	assert_eq(_qs.get_objective_index(QID), 2, "the step waits for the next visit")


func test_the_real_quest_routes_every_answer_to_one_of_three_endings() -> void:
	assert_false(bool(_real_quest.get("wiring_pending", false)), "the quest is offered to players")
	var steps: Array = _real_quest.get("objectives", [])
	assert_eq(str(steps[1].get("required_flag", "")), READ_FLAG, "step 2 waits on the flag the overflow sets")
	assert_eq(str(steps[2].get("required_flag", "")), SENT_FLAG, "step 3 waits on the flag the choice sets")
	var reached := {}
	for c in steps[2].get("choices", []):
		var v: String = str(c.get("sets", ""))
		assert_has(VARIANTS, v, "%s routes to a named ending" % c.get("label", "?"))
		reached[v] = true
		assert_eq(str(c.get("requires_item", "")), "", "no answer is withheld from a party")
		var lines: Array = c.get("lines", [])
		assert_false(lines.is_empty() or str(lines[0].get("text", "")) == "", "%s says something" % c.get("label", "?"))
	assert_eq(reached.size(), VARIANTS.size(), "all three endings can be reached")
	assert_eq(str(steps[3].get("target_npc", "")), NPC_ID, "step 4 is answered by the same attendant")
