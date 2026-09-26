extends GutTest

## A per-job line authored at the turn-in NPC never played when that NPC was
## also the quest giver. run_completion_dialogue speaks job_beat_at, but the
## giver's own completion branch returned after the stock complete lines.
## Word from the Capital turns in at Rowan: a Bard lead is supposed to offer
## the letter in verse. The player heard the stock thanks and nothing else.

const STUB := "res://test/unit/_test_game_loop_stub.gd"
const QID := "world1_word_from_capital"
const VERSE := "The letter says nothing it means"
const RIBBON := "My old ribbon"

var _qs: Node
var _leader: Combatant
var _stub: Node
var _host: Node
var _prev_job = null
var _prev_index: int
var _prev_entry: Dictionary
var _had_entry: bool
var _prev_flag: bool
var _npc: Node


class _Giver:
	extends Node2D
	var npc_id: String = ""
	var npc_name: String = "Rowan"
	func get_npc_id() -> String:
		return npc_id


func before_each() -> void:
	_qs = get_tree().root.get_node("QuestSystem")
	_prev_index = int(GameState.party_leader_index)
	_had_entry = GameState.quests.has(QID)
	_prev_entry = GameState.quests.get(QID, {}).duplicate(true)
	_prev_flag = GameState.get_story_flag("quest_world1_word_from_capital_letter_obtained")
	_mount_leader("fighter")


func after_each() -> void:
	if _npc != null and is_instance_valid(_npc):
		_npc.free()
	_npc = null
	if _prev_job != null and _leader != null and is_instance_valid(_leader):
		_leader.job = _prev_job
	elif _stub != null and is_instance_valid(_stub):
		_stub.free()
	elif _host != null and is_instance_valid(_host) and _leader != null and is_instance_valid(_leader):
		if "party" in _host:
			_host.party.erase(_leader)
		_leader.free()
	_stub = null
	_leader = null
	_host = null
	GameState.party_leader_index = _prev_index
	if _had_entry:
		GameState.quests[QID] = _prev_entry
	else:
		GameState.quests.erase(QID)
	GameState.set_story_flag("quest_world1_word_from_capital_letter_obtained", _prev_flag)


func _mount_leader(job_id: String) -> void:
	var job: Dictionary = JobSystem.get_job(job_id)
	var existing := get_tree().root.get_node_or_null("GameLoop")
	if existing != null and "party" in existing and existing.party.size() > 0:
		_leader = existing.party[0]
		_prev_job = _leader.job
		_leader.job = job
		_host = existing
		_stub = null
	else:
		var host: Node = existing
		if host == null:
			host = load(STUB).new()
			host.name = "GameLoop"
			get_tree().root.add_child(host)
			_stub = host
		else:
			_host = host
		_leader = Combatant.new()
		_leader.combatant_name = "Beat Probe"
		_leader.job = job
		host.add_child(_leader)
		host.party.append(_leader)
	GameState.party_leader_index = 0


func _arm(job_id: String) -> void:
	if _leader != null and is_instance_valid(_leader):
		_leader.job = JobSystem.get_job(job_id)
	GameState.quests[QID] = {"state": "active", "objective_index": 2}
	GameState.set_story_flag("quest_world1_word_from_capital_letter_obtained")
	_npc = _Giver.new()
	_npc.npc_id = "rowan_harmonia"
	_npc.npc_name = "Rowan"
	add_child_autofree(_npc)


func _harvest(seen: Array) -> int:
	var n := 0
	for node in _npc.find_children("*", "", true, false):
		if not node.has_method("skip_all") or not ("_dialogue_queue" in node):
			continue
		for line in node._dialogue_queue:
			if line is Dictionary:
				var text := str((line as Dictionary).get("text", ""))
				if text != "" and not seen.has(text):
					seen.append(text)
					n += 1
		node.skip_all()
	return n


func _turn_in() -> Array:
	var seen: Array = []
	_qs.run_giver_dialogue("rowan_harmonia", _npc)
	var idle := 0
	for _i in range(40):
		await get_tree().process_frame
		if _harvest(seen) == 0:
			idle += 1
			if idle >= 6 and _qs.get_state(QID) == "complete":
				break
		else:
			idle = 0
	return seen


func test_a_bard_hears_the_verse_when_rowan_turns_the_quest_in() -> void:
	_arm("bard")
	assert_eq(_qs.job_beat_at(QID, "rowan_harmonia").substr(0, VERSE.length()), VERSE,
		"control: the Bard beat is authored at Rowan and job_beat_at can see it")
	var seen: Array = await _turn_in()
	assert_eq(_qs.get_state(QID), "complete", "the turn-in still completes the quest")
	assert_true(_joined(seen).contains(RIBBON),
		"the stock thanks must still play, or this arm never opened dialogue: %s" % [seen])
	assert_true(_joined(seen).contains(VERSE),
		"a Bard lead must hear the verse on Rowan's turn-in — the giver branch dropped it: %s" % [seen])


func test_another_lead_does_not_hear_the_bard_verse() -> void:
	_arm("fighter")
	var seen: Array = await _turn_in()
	assert_eq(_qs.get_state(QID), "complete", "the turn-in still completes for a non-Bard")
	assert_true(_joined(seen).contains(RIBBON),
		"the stock thanks must still play: %s" % [seen])
	assert_false(_joined(seen).contains(VERSE),
		"the verse is the Bard's beat and must not play for another lead: %s" % [seen])


func _joined(seen: Array) -> String:
	return "\n".join(seen)
