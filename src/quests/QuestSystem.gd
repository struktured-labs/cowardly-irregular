extends Node

## QuestSystem — side-quest loader, state machine, and objective engine.
## Data: data/quests/*.json (one file per quest, schema per the 2026-07-01
## huddle: msgs 2107/2109/2111 — settled with cowir-story/main/autogrind/ai).
##
## State lives in GameState.quests: {quest_id: {state, objective_index}}
## with story-flag mirrors (flag_on_complete fields) so cutscenes, NPC
## dialogue, and the LLM prompt context can react without reading the dict.
##
## States: (absent) → "active" → "complete". "offered" is transient UI
## (decline keeps the quest offerable — no persistent offered state).
## Objective types v1: talk, custom (external flag emitters), fetch.
## kill_n arrives with the W3 hunts (gate: AutogrindSystem.is_battle_automated
## when manual_only — seam already merged and waiting).

signal quest_state_changed(quest_id: String, state: String)
signal objective_advanced(quest_id: String, objective_index: int)

const QUEST_DIR := "res://data/quests"

var _quests: Dictionary = {}  # id → parsed quest JSON
var _last_reward_summary: String = ""  # set by _grant_rewards, consumed by _announce_rewards
## Most recently accepted/progressed quest — the HUD tracker follows
## this instead of arbitrary file-load order. Session-only (cosmetic).
var last_progressed_quest_id: String = ""


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_quests.clear()
	var dir := DirAccess.open(QUEST_DIR)
	if dir == null:
		push_warning("[QuestSystem] %s missing — no side quests loaded" % QUEST_DIR)
		return
	for f in dir.get_files():
		# Web exports list .json as .json.import remaps; normalize.
		var fname := f.replace(".import", "")
		if not fname.ends_with(".json"):
			continue
		var path := QUEST_DIR + "/" + fname
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue
		var data = JSON.parse_string(text)
		if not (data is Dictionary) or not data.has("id"):
			push_warning("[QuestSystem] %s failed to parse — skipped" % fname)
			continue
		_quests[data["id"]] = data
	print("[QuestSystem] Loaded %d quests" % _quests.size())


## ── Read API (QuestLog UI + LLM prompt context consume these) ──

func get_quest(quest_id: String) -> Dictionary:
	return _quests.get(quest_id, {})


func get_all_ids() -> Array:
	return _quests.keys()


func get_state(quest_id: String) -> String:
	var entry: Dictionary = GameState.quests.get(quest_id, {})
	return entry.get("state", "")


func get_objective_index(quest_id: String) -> int:
	var entry: Dictionary = GameState.quests.get(quest_id, {})
	return int(entry.get("objective_index", 0))


func get_by_state(state: String) -> Array:
	var out: Array = []
	for qid in _quests:
		if get_state(qid) == state:
			out.append(qid)
	return out


func get_active() -> Array:
	return get_by_state("active")


## A quest is offerable when unstarted and its prereq flag (if any) is set.
## The giver's spawn_flag gates NPC VISIBILITY (plumbing side), not the offer.
func is_offerable(quest_id: String) -> bool:
	var q: Dictionary = get_quest(quest_id)
	if q.is_empty() or get_state(quest_id) != "":
		return false
	var prereq: String = q.get("prereq_flag", "")
	return prereq == "" or _flag(prereq)


## ── State transitions ──

func accept(quest_id: String) -> void:
	if not is_offerable(quest_id):
		return
	GameState.quests[quest_id] = {"state": "active", "objective_index": 0}
	last_progressed_quest_id = quest_id
	quest_state_changed.emit(quest_id, "active")
	# Convention: when step 1 is talk-to-giver, accepting IS that talk.
	var q: Dictionary = get_quest(quest_id)
	var first: Dictionary = _objective(q, 0)
	if first.get("type", "") == "talk" and first.get("target_npc", "") == q.get("giver", {}).get("npc_id", ""):
		_complete_objective(quest_id, 0)


func _complete_objective(quest_id: String, index: int) -> void:
	var q: Dictionary = get_quest(quest_id)
	var obj: Dictionary = _objective(q, index)
	last_progressed_quest_id = quest_id
	var mirror: String = obj.get("flag_on_complete", "")
	if mirror != "":
		GameState.set_story_flag(mirror)
	var objectives: Array = q.get("objectives", [])
	if index + 1 < objectives.size():
		GameState.quests[quest_id]["objective_index"] = index + 1
		objective_advanced.emit(quest_id, index + 1)
	else:
		_complete_quest(quest_id)


func _complete_quest(quest_id: String) -> void:
	var q: Dictionary = get_quest(quest_id)
	GameState.quests[quest_id]["state"] = "complete"
	var mirror: String = q.get("flag_on_complete", "")
	if mirror != "":
		GameState.set_story_flag(mirror)
	_grant_rewards(q)
	quest_state_changed.emit(quest_id, "complete")


func _grant_rewards(q: Dictionary) -> void:
	var rewards: Dictionary = q.get("rewards", {})
	var items: Array = rewards.get("items", [])
	# Per-lead-job reward swap (e.g. Bard gets the Unwritten Chord from Orrery).
	var variants: Dictionary = rewards.get("job_variants", {})
	var lead_job := _leader_job_id()
	if variants.has(lead_job):
		items = variants[lead_job].get("items", items)
	var summary_parts: Array = []
	var gold: int = int(rewards.get("gold", 0))
	if gold > 0:
		GameState.add_gold(gold)
		summary_parts.append("%d gold" % gold)
	var exp_total: int = int(rewards.get("exp", 0))
	var game_loop = get_tree().root.get_node_or_null("GameLoop")
	if exp_total > 0 and game_loop and "party" in game_loop:
		for member in game_loop.party:
			if member.has_method("gain_exp"):
				member.gain_exp(exp_total)
		summary_parts.append("%d EXP" % exp_total)
	if game_loop and game_loop.party.size() > 0:
		for entry in items:
			var iid: String = entry.get("item_id", "")
			var count: int = int(entry.get("count", 1))
			if iid != "" and game_loop.party[0].has_method("add_item"):
				game_loop.party[0].add_item(iid, count)
				summary_parts.append(_item_display_name(iid) + ("" if count <= 1 else " ×%d" % count))
	# Stashed for the completion dialogue to announce — grants happen
	# BEFORE the dialogue plays, so the summary rides until then.
	_last_reward_summary = "" if summary_parts.is_empty() else "Received: " + ", ".join(summary_parts) + "."


func _item_display_name(item_id: String) -> String:
	if ItemSystem:
		var data: Dictionary = ItemSystem.get_item(item_id)
		var display: String = str(data.get("name", ""))
		if display != "":
			return display
	return item_id.replace("_", " ").capitalize()


## Plays the stashed reward summary as a final dialogue line + the
## item_obtain chime. Rewards previously arrived in total silence —
## gold/EXP/items landed with no announcement of any kind.
func _announce_rewards(npc: Node) -> void:
	if _last_reward_summary == "":
		return
	var line: String = _last_reward_summary
	_last_reward_summary = ""
	if SoundManager:
		SoundManager.play_ui("item_obtain")
	await _play_lines(npc, [{"speaker": "✦", "text": line}])


## ── Objective progression hooks (called by the plumbing) ──

## Called at the START of any NPC interaction. Progresses active talk
## objectives silently (the NPC's own lines still play — e.g. Phil in
## fools_spread step 2). Returns the quest_id it COMPLETED (final step)
## so the caller can run the completion dialogue with this NPC as
## presenter (thirty_seven turns in at the scholar, not the giver).
func notify_talk(npc_id: String) -> String:
	for qid in get_active():
		var q: Dictionary = get_quest(qid)
		var idx := get_objective_index(qid)
		var obj: Dictionary = _objective(q, idx)
		if obj.get("type", "") != "talk":
			# Opportunistic fetch check: a fetch objective completes the
			# moment its items are in inventory and we're mid-conversation.
			if obj.get("type", "") == "fetch" and _fetch_satisfied(obj):
				_complete_objective(qid, idx)
				idx = get_objective_index(qid)
				obj = _objective(q, idx)
				if obj.get("type", "") != "talk":
					continue
			else:
				continue
		if obj.get("target_npc", "") != npc_id:
			continue
		var req: String = obj.get("required_flag", "")
		if req != "" and not _flag(req):
			continue
		var objectives: Array = q.get("objectives", [])
		var is_final: bool = idx + 1 >= objectives.size()
		_complete_objective(qid, idx)
		if is_final:
			return qid
	return ""


## Called by external emitters (chicken puzzle, tally wall, light-spell
## interact, battle telemetry) AFTER they set the custom flag.
func notify_flag(flag: String) -> void:
	for qid in get_active():
		var q: Dictionary = get_quest(qid)
		var idx := get_objective_index(qid)
		var obj: Dictionary = _objective(q, idx)
		if obj.get("type", "") != "custom":
			continue
		if obj.get("required_flag", "") == flag and _flag(flag):
			_complete_objective(qid, idx)


## ── Giver dialogue (the interact-routing quest path) ──

## True when this NPC currently OWNS quest dialogue: gives an offerable
## quest, or is mid-conversation-relevant for one it gave.
func has_giver_business(npc_id: String) -> bool:
	return _giver_quest_for(npc_id) != ""


## Marker affordance for this NPC:
##   "offer" — has a new quest to give ("!")
##   "talk"  — an active quest's CURRENT objective is a talk targeting
##             this NPC — progress or turn-in, go speak to them ("?").
##             Covers non-giver targets too (Phil, the scholar).
##   ""      — nothing actionable (a giver whose active quest's current
##             step is elsewhere would only repeat flavor — no marker)
## The required_flag gate matches notify_talk's, so a "?" never points
## at a conversation that can't actually progress yet.
func giver_business_kind(npc_id: String) -> String:
	for qid in _quests:
		if get_quest(qid).get("giver", {}).get("npc_id", "") == npc_id and is_offerable(qid):
			return "offer"
	for qid in get_active():
		var obj: Dictionary = _objective(get_quest(qid), get_objective_index(qid))
		if obj.get("type", "") != "talk" or obj.get("target_npc", "") != npc_id:
			continue
		var req: String = obj.get("required_flag", "")
		if req == "" or _flag(req):
			return "talk"
	return ""


func _giver_quest_for(npc_id: String) -> String:
	for qid in _quests:
		var q: Dictionary = _quests[qid]
		if q.get("giver", {}).get("npc_id", "") != npc_id:
			continue
		if is_offerable(qid):
			return qid
		if get_state(qid) == "active":
			return qid
	return ""


## Run the full giver-state dialogue with accept/decline on offer.
## `npc` is the OverworldNPC (for name/theme); `player` gets movement-locked
## by the caller. Uses NPCDialogue for rendering, same as scripted lines.
func run_giver_dialogue(npc_id: String, npc: Node) -> void:
	var qid := _giver_quest_for(npc_id)
	if qid == "":
		return
	var q: Dictionary = get_quest(qid)
	var dlg: Dictionary = q.get("dialogue", {})

	if is_offerable(qid):
		await _play_lines(npc, dlg.get("offer", []))
		var accepted := await _prompt_accept(npc, q)
		if accepted:
			accept(qid)
			await _play_lines(npc, dlg.get("accept", []))
		else:
			await _play_lines(npc, dlg.get("decline", []))
		return

	# Active: is the current objective a talk targeting this giver?
	var completed_qid := notify_talk(npc_id)
	if completed_qid == qid:
		await _play_lines(npc, dlg.get("ready_to_turn_in", []))
		await _play_lines(npc, dlg.get("complete", []))
		await _announce_rewards(npc)
		return
	# Otherwise still mid-quest — flavor line.
	await _play_lines(npc, dlg.get("in_progress", []))


## Completion presentation for non-giver final NPCs (notify_talk returned
## a quest the plumbing wants narrated by the current NPC).
func run_completion_dialogue(quest_id: String, npc: Node) -> void:
	var q: Dictionary = get_quest(quest_id)
	var dlg: Dictionary = q.get("dialogue", {})
	await _play_lines(npc, dlg.get("ready_to_turn_in", []))
	await _play_lines(npc, dlg.get("complete", []))
	await _announce_rewards(npc)


func _play_lines(npc: Node, lines: Array) -> void:
	if lines.is_empty():
		return
	var NPCDialogueClass = load("res://src/cutscene/NPCDialogue.gd")
	var dlg = NPCDialogueClass.new()
	npc.add_child(dlg)
	var shaped: Array = []
	for l in lines:
		shaped.append({
			"speaker": l.get("speaker", npc.npc_name if "npc_name" in npc else "???"),
			"text": l.get("text", ""),
			"theme": l.get("theme", "villager"),
			"portrait": l.get("theme", "villager"),
		})
	await dlg.say_lines(shaped)
	dlg.queue_free()


## Accept/Decline via the shared DialogueChoiceMenu (same UI the LLM
## conversations use). Cancel (B) counts as decline.
func _prompt_accept(npc: Node, q: Dictionary) -> bool:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 60
	var root_attach: Node = get_tree().current_scene
	if root_attach == null:
		root_attach = npc
	root_attach.add_child(ui_layer)
	var menu := DialogueChoiceMenu.new()
	menu.name = "QuestOfferChoice"
	ui_layer.add_child(menu)
	var accept_label: String = "Accept \"%s\"" % q.get("title", "the quest")
	var chosen: String = await menu.present([accept_label, "Not now"])
	if is_instance_valid(menu):
		menu.queue_free()
	if is_instance_valid(ui_layer):
		ui_layer.queue_free()
	return chosen == accept_label


## ── Internals ──

func _objective(q: Dictionary, index: int) -> Dictionary:
	var objectives: Array = q.get("objectives", [])
	if index < 0 or index >= objectives.size():
		return {}
	return objectives[index]


func _fetch_satisfied(obj: Dictionary) -> bool:
	var req: String = obj.get("required_flag", "")
	if req != "" and not _flag(req):
		return false
	var iid: String = obj.get("item_id", "")
	var count: int = int(obj.get("count", 1))
	var game_loop = get_tree().root.get_node_or_null("GameLoop")
	if iid == "" or game_loop == null or not ("party" in game_loop) or game_loop.party.is_empty():
		return false
	var member = game_loop.party[0]
	if not ("inventory" in member):
		return false
	return int(member.inventory.get(iid, 0)) >= count


func _flag(flag: String) -> bool:
	if GameState.has_method("is_story_flag_set"):
		return GameState.is_story_flag_set(flag)
	return GameState.get_story_flag(flag)


func _leader_job_id() -> String:
	var game_loop = get_tree().root.get_node_or_null("GameLoop")
	if game_loop == null or not ("party" in game_loop) or game_loop.party.is_empty():
		return ""
	var idx: int = clampi(GameState.party_leader_index, 0, game_loop.party.size() - 1)
	var leader = game_loop.party[idx]
	if leader.job is Dictionary:
		return leader.job.get("id", "")
	elif leader.job is String:
		return leader.job
	return ""
