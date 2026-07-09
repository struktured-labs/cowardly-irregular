extends Area2D
class_name CivicFrontDesk

## CivicFrontDesk — the Community Center counter's quest multiplexer. One
## interact, resolved by active-quest priority (one grant per interact so
## repeated visits drain the queue):
##  1. forms_in_triplicate step 2 — the complaint backlog (visitor credential
##     issued standalone via a brief front-desk sub-beat).
##  2. acceptable_variance step 4 — Form 44-Omega (granted twice in history).
##  3. fine_print step 2, Cleric lead — receptionist assumes any healthcare
##     worker is pre-approved. Credential free; the assumption has never
##     been challenged.
##  4. fine_print step 3 — the form itself, with credential in hand.

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


func _setup_collision() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 64.0
	cs.shape = shape
	cs.scale = Vector2(1.0, 1.67)
	add_child(cs)


func _setup_indicator() -> void:
	_indicator = Label.new()
	_indicator.text = "[A] Front desk"
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator.position = Vector2(-48, -36)
	_indicator.size = Vector2(96, 14)
	_indicator.add_theme_font_size_override("font_size", 10)
	_indicator.add_theme_color_override("font_color", Color(0.75, 0.85, 0.9))
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
	if _player_in_zone and not _busy and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_busy = true
		_serve()
		_busy = false


func _serve() -> void:
	var qs = get_node_or_null("/root/QuestSystem")
	if qs == null:
		_toast("Take a number. The numbers are decorative, but take one.")
		return

	# 1. Complaint backlog (forms step 2).
	if _at_custom_step(qs, "world2_forms_in_triplicate", "quest_world2_forms_in_triplicate_backlog_obtained"):
		GameState.set_story_flag("quest_world2_forms_in_triplicate_backlog_obtained")
		qs.notify_flag("quest_world2_forms_in_triplicate_backlog_obtained")
		if SoundManager:
			SoundManager.play_ui("item_obtain")
		_toast("Visitor credential issued. The backlog is... all of this. Seven boxes.")
		return

	# 1b. Processing the backlog (forms step 3, paths a/b — path c is the
	# mail carrier filing third-party via her dialogue emitter).
	if _at_custom_step(qs, "world2_forms_in_triplicate", "quest_world2_forms_in_triplicate_complaints_processed"):
		var lead := _lead_job()
		if lead == "bard":
			GameState.set_story_flag("quest_world2_forms_in_triplicate_complaints_processed")
			qs.notify_flag("quest_world2_forms_in_triplicate_complaints_processed")
			if SoundManager:
				SoundManager.play_ui("secret_found")
			_toast("The Bard reads all seven complaints aloud as one narrative. The room goes quiet. The clerk stamps it 'PROCESSED' without looking up.")
		elif lead == "rogue":
			GameState.set_story_flag("quest_world2_forms_in_triplicate_complaints_processed")
			qs.notify_flag("quest_world2_forms_in_triplicate_complaints_processed")
			if SoundManager:
				SoundManager.play_ui("secret_found")
			_toast("The Rogue finds the processing code taped under the counter. Seven complaints, batch-entered. Processed.")
		else:
			_toast("Seven complaints, no processing authority. A storyteller could narrate them. A sneak could find the code. A federal employee could just... file them.")
		return

	# 2. Form 44-Omega (variance step 4).
	if _at_custom_step(qs, "world2_acceptable_variance", "quest_world2_acceptable_variance_variance_granted"):
		GameState.set_story_flag("quest_world2_acceptable_variance_variance_granted")
		qs.notify_flag("quest_world2_acceptable_variance_variance_granted")
		if SoundManager:
			SoundManager.play_ui("chalk_tap")
		_toast("Form 44-Omega: VARIANCE GRANTED. The clerk says that's happened twice. Ever.")
		return

	# 3. Cleric-lead credential (fine_print step 2, path B).
	if _at_custom_step(qs, "world2_fine_print", "quest_world2_fine_print_credential_obtained"):
		if _lead_job() == "cleric":
			GameState.set_story_flag("quest_world2_fine_print_credential_obtained")
			qs.notify_flag("quest_world2_fine_print_credential_obtained")
			if SoundManager:
				SoundManager.play_ui("item_obtain")
			_toast("The receptionist waves the Cleric through. Nobody questions this. The assumption has never been challenged.")
		else:
			_toast("'Credentials?' You have none. The mail carrier might owe a favor. Or bring a healthcare professional.")
		return

	# 4. The form itself (fine_print step 3, credential in hand).
	if _at_custom_step(qs, "world2_fine_print", "quest_world2_fine_print_form_obtained"):
		GameState.set_story_flag("quest_world2_fine_print_form_obtained")
		qs.notify_flag("quest_world2_fine_print_form_obtained")
		if SoundManager:
			SoundManager.play_ui("item_obtain")
		_toast("One (1) form, stamped in triplicate. Madame Orrery is waiting.")
		return

	_toast("'Welcome to the Community Center. How can we defer you today?'")


func _at_custom_step(qs: Node, quest_id: String, flag: String) -> bool:
	if qs.get_state(quest_id) != "active" or GameState.get_story_flag(flag):
		return false
	var obj: Dictionary = qs.get_quest(quest_id).get("objectives", [])[qs.get_objective_index(quest_id)]
	return obj.get("type", "") == "custom" and obj.get("required_flag", "") == flag


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


func _toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.position = Vector2(-150, -64)
	lbl.size = Vector2(300, 34)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 18.0, 2.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 2.0).set_delay(0.9)
	tw.chain().tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free())
