extends Area2D
class_name AnnexLiberation

## AnnexLiberation — the confrontation zone by the Annex's Compliance Officer
## (world2_relocated step 3, MULTI-PATH — any one fires kids_freed):
##  (a) Cleric lead — the scheduled-break walkout. Nobody stops a healthcare
##      professional enforcing break policy.
##  (b) Bard in party — music disruption; enrichment cannot survive a riff.
##  (c) anyone — fight the officer (cranky_lady drop-in per cowir-battle's
##      fit-check; victory tracked via bestiary defeat-count baseline).
## Also: standing IN the annex is finding it — step 2's annex_found emits on
## entry if still pending. Post-rescue the six kids go home (hidden here).

const QUEST_ID := "world2_relocated"
const FOUND_FLAG := "quest_world2_relocated_annex_found"
const FREED_FLAG := "quest_world2_relocated_kids_freed"
const BASELINE_KEY := "relocated_officer_baseline"
const MONSTER := "cranky_lady"
const TILE_SIZE: int = 32

var _indicator: Label
var _player_in_zone: bool = false
var _busy: bool = false


func _ready() -> void:
	add_to_group("interactables")
	_setup_collision()
	_setup_indicator()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	call_deferred("_on_annex_entered")


## Walking in IS finding the place (relocated step 2, exploration path).
## Post-rescue, the kids have gone home — hide their NPCs.
func _on_annex_entered() -> void:
	var qs = get_node_or_null("/root/QuestSystem")
	if qs == null:
		return
	if qs.get_state(QUEST_ID) == "active" and not GameState.get_story_flag(FOUND_FLAG):
		var obj: Dictionary = qs.get_quest(QUEST_ID).get("objectives", [])[qs.get_objective_index(QUEST_ID)]
		if obj.get("required_flag", "") == FOUND_FLAG:
			GameState.set_story_flag(FOUND_FLAG)
			qs.notify_flag(FOUND_FLAG)
	if qs.get_state(QUEST_ID) == "complete":
		_send_kids_home()


func _send_kids_home() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for npc in scene.find_children("*", "Area2D", true, false):
		if "npc_id" in npc and str(npc.npc_id).begins_with("annex_kid_"):
			npc.visible = false
			npc.monitoring = false


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 80.0
	cs.shape = shape
	cs.scale = Vector2(1.0, 1.67)
	add_child(cs)


func _setup_indicator() -> void:
	_indicator = Label.new()
	_indicator.text = "[A] Confront"
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-44, -40)
	_indicator.size = Vector2(88, 14)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(0.95, 0.75, 0.6))
	_indicator.visible = false
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_indicator)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.has_method("set_can_move"):
		_player_in_zone = true
		_indicator.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body.has_method("set_can_move"):
		_player_in_zone = false
		_indicator.visible = false


func _input(event: InputEvent) -> void:
	# Zone-listener class fix (subagent 2026-07-12): a cutscene/dialogue A-press must not also fire the interactable, and a tutorial-hint dismiss press must not either.
	if TutorialHint.is_any_active():
		return
	var ilm = get_tree().root.get_node_or_null("InputLockManager") if is_inside_tree() else null
	if ilm and ilm.is_locked():
		return
	if _player_in_zone and not _busy and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_busy = true
		_confront()
		_busy = false


func _confront() -> void:
	var qs = get_node_or_null("/root/QuestSystem")
	var relevant: bool = qs != null and qs.get_state(QUEST_ID) == "active" \
		and GameState.get_story_flag(FOUND_FLAG) and not GameState.get_story_flag(FREED_FLAG)
	if not relevant:
		_toast("'Enrichment hours are posted. Visitation requires Form 12-C.'")
		return

	# Path (c) resolution: did we already beat the officer?
	var count: int = BestiarySystem.get_defeat_count(MONSTER)
	var baseline: int = int(GameState.game_constants.get(BASELINE_KEY, -1))
	if baseline >= 0 and count > baseline:
		GameState.game_constants.erase(BASELINE_KEY)
		_free_kids(qs, "The officer concedes on procedural grounds. The kids are already at the door.")
		return

	# Path (a): Cleric-lead walkout.
	if _lead_job() == "cleric":
		_free_kids(qs, "The Cleric announces a scheduled break. Nobody stops a healthcare professional. The kids simply walk out.")
		return

	# Path (b): Bard disruption.
	if _party_has("bard"):
		if SoundManager:
			SoundManager.play_ui("magic_surge")
		_free_kids(qs, "The Bard plays. Enrichment cannot survive a riff. The kids leave dancing.")
		return

	# Path (c): fight the officer.
	GameState.game_constants[BASELINE_KEY] = count
	_toast("'That is NOT procedure—' The officer would like to speak to your manager. Violently.")
	_fire_battle()


func _free_kids(qs: Node, line: String) -> void:
	GameState.set_story_flag(FREED_FLAG)
	qs.notify_flag(FREED_FLAG)
	if SoundManager:
		SoundManager.play_ui("secret_found")
	_toast(line)
	_send_kids_home()


func _party_has(job_id: String) -> bool:
	var game_loop = get_node_or_null("/root/GameLoop")
	if game_loop == null or not ("party" in game_loop):
		return false
	for member in game_loop.party:
		var jid := ""
		if member.job is Dictionary:
			jid = member.job.get("id", "")
		elif member.job is String:
			jid = member.job
		if jid == job_id:
			return true
	return false


func _lead_job() -> String:
	var game_loop = get_node_or_null("/root/GameLoop")
	if game_loop == null or not ("party" in game_loop) or game_loop.party.is_empty():
		return ""
	var idx: int = 0
	var gs = get_node_or_null("/root/GameState")
	if gs and "party_leader_index" in gs:
		idx = clampi(gs.party_leader_index, 0, game_loop.party.size() - 1)
	var leader = game_loop.party[idx]
	if leader.job is Dictionary:
		return leader.job.get("id", "")
	elif leader.job is String:
		return leader.job
	return ""


func _fire_battle() -> void:
	var node = get_parent()
	while node:
		if node.has_method("_on_battle_triggered"):
			node._on_battle_triggered([MONSTER])
			return
		node = node.get_parent()


func _toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.position = Vector2(-150, -66)
	lbl.size = Vector2(300, 34)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.75))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 18.0, 2.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 2.0).set_delay(0.9)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
