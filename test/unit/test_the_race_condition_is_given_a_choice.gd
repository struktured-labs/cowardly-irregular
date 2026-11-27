extends GutTest

## world5_mutual_exclusion was withheld (wiring_pending): its pair stood nowhere and nothing offered step 2's two answers.
## The Race Condition now stands in Node Prime, and talking to them on step 2 offers the schedule or the merge.

const QID := "world5_mutual_exclusion"
const NPC_ID := "race_condition_pair"
const FLAG := "quest_world5_mutual_exclusion_resolved"
const VARIANTS := ["quest_world5_mutual_exclusion_protocol", "quest_world5_mutual_exclusion_merged"]

var _qs: Node
var _real_quest: Dictionary = {}
var _held_state: Variant = null
var _held_flags: Dictionary = {}


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	_real_quest = (_qs.get_quest(QID) as Dictionary).duplicate(true)
	_held_state = GameState.quests.get(QID, null)
	_held_flags.clear()
	for f in [FLAG] + VARIANTS:
		if GameState.story_flags.has(f):
			_held_flags[f] = GameState.story_flags[f]
		GameState.story_flags.erase(f)


func after_each() -> void:
	_qs._quests[QID] = _real_quest
	if _held_state == null:
		GameState.quests.erase(QID)
	else:
		GameState.quests[QID] = _held_state
	for f in [FLAG] + VARIANTS:
		GameState.story_flags.erase(f)
	for f in _held_flags:
		GameState.story_flags[f] = _held_flags[f]


## The real answers, silenced, with step 3 answered elsewhere so the run stops at the step under test.
func _arm() -> Node2D:
	var q: Dictionary = _real_quest.duplicate(true)
	q["dialogue"] = {}
	for c in q["objectives"][1].get("choices", []):
		c["lines"] = []
	q["objectives"][2]["target_npc"] = "zz_someone_else"
	_qs._quests[QID] = q
	GameState.quests[QID] = {"state": "active", "objective_index": 1}
	assert_eq(_qs.get_objective_index(QID), 1, "CONTROL: the choosing step is current")
	assert_false(_qs._flag(FLAG), "CONTROL: nothing has been resolved yet")
	var npc := Node2D.new()
	npc.set("npc_name", "The Race Condition")
	add_child_autofree(npc)
	return npc


func _labels() -> Array:
	var out: Array = []
	for c in _real_quest["objectives"][1].get("choices", []):
		out.append(str(c["label"]))
	return out


func _open_menu(npc: Node2D) -> Node:
	_qs.run_giver_dialogue(NPC_ID, npc)
	for _i in range(30):
		await get_tree().process_frame
		var menu: Node = get_tree().root.find_child("QuestChoice", true, false)
		if menu != null and not menu.is_queued_for_deletion():
			return menu
	return null


func _settle() -> void:
	for _i in range(10):
		await get_tree().process_frame


func _choose(index: int) -> void:
	var menu: Node = await _open_menu(_arm())
	assert_not_null(menu, "talking to the pair on step 2 offers the answers")
	if menu == null:
		return
	assert_eq(Array(menu._choices), _labels(), "both authored answers are offered; neither needs an item")
	menu._selection = index
	menu._confirm()
	await _settle()


func test_writing_them_a_schedule_resolves_the_protocol_path() -> void:
	await _choose(0)
	assert_true(_qs._flag(FLAG), "an answer resolves them")
	assert_true(_qs._flag(VARIANTS[0]), "the schedule is remembered as the protocol path")
	assert_false(_qs._flag(VARIANTS[1]), "and not as the merge")
	assert_eq(_qs.get_objective_index(QID), 2, "the quest moves on to seeing what they became")


func test_showing_them_they_are_one_process_resolves_the_merged_path() -> void:
	await _choose(1)
	assert_true(_qs._flag(FLAG), "an answer resolves them")
	assert_true(_qs._flag(VARIANTS[1]), "the merge is remembered as the merged path")
	assert_false(_qs._flag(VARIANTS[0]), "and not as the protocol")
	assert_eq(_qs.get_objective_index(QID), 2, "the quest moves on to seeing what they became")


func test_backing_out_resolves_nothing() -> void:
	var menu: Node = await _open_menu(_arm())
	assert_not_null(menu, "the answers are offered")
	if menu == null:
		return
	menu._cancel()
	await _settle()
	assert_false(_qs._flag(FLAG), "cancel resolves nothing")
	for f in VARIANTS:
		assert_false(_qs._flag(f), "%s stays unset" % f)
	assert_eq(_qs.get_objective_index(QID), 1, "the step waits for the next visit")


func test_the_real_quest_is_offered_and_answered_by_the_pair() -> void:
	assert_false(bool(_real_quest.get("wiring_pending", false)), "the quest is offered to players")
	var steps: Array = _real_quest.get("objectives", [])
	assert_eq(str(steps[1].get("required_flag", "")), FLAG, "step 2 waits on the flag a choice sets")
	var wired := false
	for e in _qs.CHOICE_EMITTERS.get(NPC_ID, []):
		wired = wired or (e["quest"] == QID and e["flag"] == FLAG)
	assert_true(wired, "the pair is the one who answers step 2")
	assert_eq(str(steps[2].get("target_npc", "")), NPC_ID, "step 3 is seen with the same pair")


func test_the_pair_stands_in_node_prime() -> void:
	var held_ch2: Variant = GameState.game_constants.get("cutscene_flag_world5_chapter2_complete", null)
	GameState.game_constants["cutscene_flag_world5_chapter2_complete"] = true
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var v: Node = load("res://src/maps/villages/NodePrimeVillage.gd").new()
	vp.add_child(v)
	await get_tree().process_frame
	var found: Node = null
	for n in v.npcs.get_children():
		if n.has_method("get_npc_id") and n.get_npc_id() == NPC_ID:
			found = n
	assert_not_null(found, "the quest's giver is placed in Node Prime")
	if found != null:
		var cell := Vector2i(floori(found.position.x / 32.0), floori(found.position.y / 32.0))
		assert_true(v._is_cell_walkable(cell + Vector2i(0, 1)) or v._is_cell_walkable(cell + Vector2i(-1, 0)),
			"a cell beside the pair can be stood on, so they can be talked to")
	if held_ch2 == null:
		GameState.game_constants.erase("cutscene_flag_world5_chapter2_complete")
	else:
		GameState.game_constants["cutscene_flag_world5_chapter2_complete"] = held_ch2
