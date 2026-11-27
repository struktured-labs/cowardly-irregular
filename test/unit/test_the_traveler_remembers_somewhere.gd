extends GutTest

## world6_before_she_left was withheld (wiring_pending): its Traveler stood nowhere and nothing read step 2's three beats.
## The Traveler now stands in Vertex, and each talk offers one fragment not yet heard; the step closes after all three.

const QID := "world6_before_she_left"
const NPC_ID := "traveler_w6"
const FLAG := "quest_world6_before_she_left_fragments_gathered"
const BEAT_IDS := ["vowels", "light", "weather"]

var _qs: Node
var _real_quest: Dictionary = {}
var _held_state: Variant = null
var _held_flags: Dictionary = {}


func _flags() -> Array:
	var out: Array = [FLAG]
	for id in BEAT_IDS:
		out.append(_qs.beat_flag(QID, id))
	return out


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	_real_quest = (_qs.get_quest(QID) as Dictionary).duplicate(true)
	_held_state = GameState.quests.get(QID, null)
	_held_flags.clear()
	for f in _flags():
		if GameState.story_flags.has(f):
			_held_flags[f] = GameState.story_flags[f]
		GameState.story_flags.erase(f)


func after_each() -> void:
	_qs._quests[QID] = _real_quest
	if _held_state == null:
		GameState.quests.erase(QID)
	else:
		GameState.quests[QID] = _held_state
	for f in _flags():
		GameState.story_flags.erase(f)
	for f in _held_flags:
		GameState.story_flags[f] = _held_flags[f]


## The real beats, silenced, with step 3 answered elsewhere so a run stops at the step under test.
func _arm() -> Node2D:
	var q: Dictionary = _real_quest.duplicate(true)
	q["dialogue"] = {}
	for b in q["objectives"][1].get("beats", []):
		b["lines"] = []
	q["objectives"][2]["target_npc"] = "zz_someone_else"
	_qs._quests[QID] = q
	GameState.quests[QID] = {"state": "active", "objective_index": 1}
	assert_eq(_qs.get_objective_index(QID), 1, "CONTROL: the recall step is current")
	assert_false(_qs._flag(FLAG), "CONTROL: nothing has been gathered yet")
	var npc := Node2D.new()
	npc.set("npc_name", "The Traveler")
	add_child_autofree(npc)
	return npc


func _labels_by_id() -> Dictionary:
	var out := {}
	for b in _real_quest["objectives"][1].get("beats", []):
		out[str(b["id"])] = str(b["label"])
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


## Picks the beat with this id from the open menu; false when the menu does not offer it.
func _pick(menu: Node, id: String) -> bool:
	var i: int = Array(menu._choices).find(_labels_by_id()[id])
	if i < 0:
		return false
	menu._selection = i
	menu._confirm()
	await _settle()
	return true


func test_each_talk_offers_only_the_fragments_not_yet_heard() -> void:
	var npc := _arm()
	var labels := _labels_by_id()
	var menu: Node = await _open_menu(npc)
	assert_not_null(menu, "talking to the Traveler mid-quest offers the fragments")
	if menu == null:
		return
	assert_eq(Array(menu._choices), [labels["vowels"], labels["light"], labels["weather"]], "all three, in authored order, the first time")
	assert_true(await _pick(menu, "light"), "CONTROL: the light is on offer")
	assert_true(_qs._flag(_qs.beat_flag(QID, "light")), "the fragment heard is remembered")
	assert_false(_qs._flag(FLAG), "one fragment is not all of them")
	assert_eq(_qs.get_objective_index(QID), 1, "the step waits for the rest")

	menu = await _open_menu(npc)
	assert_not_null(menu, "the next talk offers what is left")
	if menu == null:
		return
	assert_eq(Array(menu._choices), [labels["vowels"], labels["weather"]], "a heard fragment is not offered again")
	assert_true(await _pick(menu, "weather"), "CONTROL: the weather-word is on offer")
	assert_false(_qs._flag(FLAG), "two fragments are not all of them")

	menu = await _open_menu(npc)
	assert_not_null(menu, "the last fragment is offered")
	if menu == null:
		return
	assert_eq(Array(menu._choices), [labels["vowels"]], "only the one not yet heard")
	assert_true(await _pick(menu, "vowels"), "CONTROL: the vowels are on offer")
	assert_true(_qs._flag(FLAG), "all three heard gathers the fragments")
	assert_eq(_qs.get_objective_index(QID), 2, "the quest moves on to telling the Traveler where they started")


func test_backing_out_keeps_what_was_heard() -> void:
	var npc := _arm()
	var menu: Node = await _open_menu(npc)
	assert_not_null(menu, "the fragments are offered")
	if menu == null:
		return
	assert_true(await _pick(menu, "vowels"), "CONTROL: the vowels are on offer")
	menu = await _open_menu(npc)
	assert_not_null(menu, "the rest are offered")
	if menu == null:
		return
	menu._cancel()
	await _settle()
	assert_true(_qs._flag(_qs.beat_flag(QID, "vowels")), "cancel forgets nothing already heard")
	assert_false(_qs._flag(_qs.beat_flag(QID, "light")) or _qs._flag(_qs.beat_flag(QID, "weather")), "and hears nothing new")
	assert_false(_qs._flag(FLAG), "the step stays open")
	menu = await _open_menu(npc)
	assert_not_null(menu, "the next visit offers them again")
	if menu != null:
		assert_eq(Array(menu._choices).size(), 2, "the two not yet heard")
		menu._cancel()
		await _settle()


func test_the_real_quest_can_be_finished_with_the_traveler() -> void:
	assert_false(bool(_real_quest.get("wiring_pending", false)), "the quest is offered to players")
	var steps: Array = _real_quest.get("objectives", [])
	assert_eq(str(steps[1].get("required_flag", "")), FLAG, "step 2 waits on the flag the last beat sets")
	var ids: Array = []
	for b in steps[1].get("beats", []):
		ids.append(str(b.get("id", "")))
		var lines: Array = b.get("lines", [])
		assert_false(lines.is_empty() or str(lines[0].get("text", "")) == "", "%s says something" % b.get("id", "?"))
	assert_eq(ids, BEAT_IDS, "the three fragments, each with its own id")
	var wired := false
	for e in _qs.CHOICE_EMITTERS.get(NPC_ID, []):
		wired = wired or (e["quest"] == QID and e["flag"] == FLAG)
	assert_true(wired, "the Traveler is the one who answers step 2")
	assert_eq(str(steps[2].get("target_npc", "")), NPC_ID, "step 3 is told to the same Traveler")
	assert_eq(str(steps[2].get("required_flag", "")), FLAG, "step 3 opens once the fragments are gathered")


func test_the_traveler_stands_in_vertex() -> void:
	var held_world: int = GameState.current_world
	GameState.current_world = 6
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
		var cell := Vector2i(floori(found.position.x / 32.0), floori(found.position.y / 32.0))
		assert_true(v._is_cell_walkable(cell + Vector2i(0, 1)) or v._is_cell_walkable(cell + Vector2i(-1, 0)),
			"a cell beside the Traveler can be stood on, so they can be talked to")
		assert_eq(str(found.get("_archetype_id")), "traveler_abstract", "in World 6 the Traveler draws her own W6 sheet, not the hooded figure")
	GameState.current_world = held_world


func test_a_heard_fragment_survives_a_save_and_load() -> void:
	var npc := _arm()
	var menu: Node = await _open_menu(npc)
	assert_not_null(menu, "the fragments are offered")
	if menu == null:
		return
	assert_true(await _pick(menu, "weather"), "CONTROL: the weather-word is on offer")
	var saved: Variant = JSON.parse_string(JSON.stringify({"story_flags": GameState.story_flags, "quests": GameState.quests}))
	assert_true(saved is Dictionary, "CONTROL: the save survives a JSON trip")
	GameState.story_flags.erase(_qs.beat_flag(QID, "weather"))
	assert_false(_qs._flag(_qs.beat_flag(QID, "weather")), "CONTROL: the fragment is gone before the load")
	GameState.from_dict(saved)
	assert_true(_qs._flag(_qs.beat_flag(QID, "weather")), "the heard fragment comes back with the save")
	assert_eq(_qs.get_objective_index(QID), 1, "and so does the step")
	menu = await _open_menu(npc)
	assert_not_null(menu, "the loaded quest still offers the rest")
	if menu != null:
		var labels := _labels_by_id()
		assert_eq(Array(menu._choices), [labels["vowels"], labels["light"]], "only the two not yet heard")
		menu._cancel()
		await _settle()
