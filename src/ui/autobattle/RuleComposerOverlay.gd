extends Control

## RuleComposerOverlay — modal for the Rule Composer flow.
##
## Life cycle: open(domain, character_id, current_rules) -> prompt field ->
## Compose -> thinking indicator -> preview -> Confirm (installed) OR Cancel
## (cancelled) OR Regenerate (loops back to Compose).
##
## Headless-safe: every UI node reference is resolved via get_node_or_null()
## and guarded before use, so RuleComposerOverlay.new() (no .tscn children)
## never crashes -- only the .tscn-instantiated overlay has a live UI.

signal installed(profile_index: int)
signal cancelled

const RC_DOMAIN_AUTOBATTLE := "autobattle"
const RC_DOMAIN_AUTOGRIND  := "autogrind"

var _domain: String = ""
var _character_id: String = ""
var _current_rules: Array = []
var _last_composition: Dictionary = {}
var _busy: bool = false

var _prompt_field: LineEdit = null
var _status_label: Label = null
var _preview_panel: Panel = null
var _compose_button: Button = null
var _regen_button: Button = null
var _confirm_button: Button = null
var _cancel_button: Button = null
var _replace_toggle: CheckBox = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_prompt_field = get_node_or_null("Panel/VBox/PromptField") as LineEdit
	_status_label = get_node_or_null("Panel/VBox/StatusLabel") as Label
	_preview_panel = get_node_or_null("Panel/VBox/PreviewPanel") as Panel
	_compose_button = get_node_or_null("Panel/VBox/ButtonsHBox/ComposeButton") as Button
	_regen_button = get_node_or_null("Panel/VBox/ButtonsHBox/RegenButton") as Button
	_confirm_button = get_node_or_null("Panel/VBox/ButtonsHBox/ConfirmButton") as Button
	_cancel_button = get_node_or_null("Panel/VBox/ButtonsHBox/CancelButton") as Button
	_replace_toggle = get_node_or_null("Panel/VBox/ReplaceToggle") as CheckBox
	if _compose_button != null:
		_compose_button.pressed.connect(_on_compose_pressed)
	if _regen_button != null:
		_regen_button.pressed.connect(_on_regen_pressed)
	if _confirm_button != null:
		_confirm_button.pressed.connect(_on_confirm_pressed)
	if _cancel_button != null:
		_cancel_button.pressed.connect(_on_cancel_pressed)
	hide()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Typing "r"/"x" into the prompt must not trigger Regenerate/Cancel.
	if _prompt_field != null and _prompt_field.has_focus():
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("battle_advance") and not event.is_echo():
		_on_regen_pressed()
		get_viewport().set_input_as_handled()


func open(domain: String, character_id: String, current_rules: Array) -> void:
	_domain = domain
	_character_id = character_id
	_current_rules = current_rules
	_last_composition = {}
	if _prompt_field != null:
		_prompt_field.text = ""
	if _status_label != null:
		_status_label.text = ""
		_status_label.remove_theme_color_override("font_color")
	if _preview_panel != null:
		_preview_panel.visible = false
	if _confirm_button != null:
		_confirm_button.disabled = true
	if _regen_button != null:
		_regen_button.disabled = true
	show()
	# Upfront honesty for the no-backend case (every web player): say WHY
	# Compose will fail BEFORE they type an essay — the grid stays fully manual.
	var rc = get_node_or_null("/root/RuleComposer")
	if rc == null or not rc.has_method("has_llm") or not rc.has_llm():
		if _status_label != null:
			_status_label.text = "No LLM backend reachable — Compose needs one (Settings → Configure BYOK, or local Ollama). The rule grid and presets work fine without it."
			_status_label.add_theme_color_override("font_color", Color(0.95, 0.80, 0.40))
	if _prompt_field != null:
		_prompt_field.grab_focus()
	elif _compose_button != null:
		_compose_button.grab_focus()


func get_domain() -> String:
	return _domain


func get_character_id() -> String:
	return _character_id


func cancel() -> void:
	hide()
	cancelled.emit()


func compose(prompt_text: String) -> void:
	if _busy:
		return
	var rc = get_node_or_null("/root/RuleComposer")
	if rc == null:
		_show_error(["RuleComposer autoload missing"])
		return
	_busy = true
	_set_thinking(true)
	var result: Dictionary = await rc.compose_async(_domain, prompt_text, _character_id, _current_rules)
	_busy = false
	_set_thinking(false)
	_last_composition = result
	var errors = result.get("errors", [])
	if not errors is Array:
		errors = []
	if errors.size() > 0:
		_show_error(errors)
		return
	var composed_rules = result.get("rules", [])
	if not composed_rules is Array:
		composed_rules = []
	if composed_rules.size() == 0:
		_show_error(["No rules were composed."])
		return
	_show_preview(result)


func confirm(replace_current: bool) -> void:
	if _busy or _last_composition.is_empty():
		return
	var raw_rules = _last_composition.get("rules", [])
	var comp_rules: Array = raw_rules if raw_rules is Array else []
	if comp_rules.is_empty():
		return
	var idx: int = -1
	if _domain == RC_DOMAIN_AUTOBATTLE:
		var autobattle = get_node_or_null("/root/AutobattleSystem")
		if autobattle == null:
			_show_error(["AutobattleSystem missing"])
			return
		if replace_current:
			autobattle.set_character_script(_character_id, {
				"character_id": _character_id,
				"name": str(_last_composition.get("name", "Composed")),
				"description": str(_last_composition.get("description", "")),
				"rules": comp_rules
			})
		else:
			idx = autobattle.install_composition_as_new_profile(_character_id, _last_composition)
			if idx < 0:
				_show_error(["Profile limit reached (8 max). Delete a profile or check 'Replace current profile'."])
				return
	else:
		var autogrind = get_node_or_null("/root/AutogrindSystem")
		if autogrind == null:
			_show_error(["AutogrindSystem missing"])
			return
		if replace_current:
			autogrind.set_autogrind_rules(comp_rules)
		else:
			idx = _install_autogrind_new_profile(autogrind, comp_rules)
			if idx < 0:
				_show_error(["Profile limit reached (8 max). Delete a profile or check 'Replace current profile'."])
				return
	hide()
	installed.emit(idx)


# install_as_new_profile(template_id: String, ...) is a static catalog lookup, not autoload-hosted -- replicate its create/switch/write/restore recipe instead.
func _install_autogrind_new_profile(autogrind, comp_rules: Array) -> int:
	if not autogrind.has_method("create_new_autogrind_profile"):
		return -1
	var comp_name: String = str(_last_composition.get("name", ""))
	if comp_name.is_empty():
		comp_name = "Composed"
	var new_idx: int = autogrind.create_new_autogrind_profile(comp_name)
	if new_idx < 0:
		return -1
	var previous_active: int = 0
	if autogrind.has_method("get_active_autogrind_profile_index"):
		previous_active = autogrind.get_active_autogrind_profile_index()
	if autogrind.has_method("set_active_autogrind_profile"):
		autogrind.set_active_autogrind_profile(new_idx)
	autogrind.set_autogrind_rules(comp_rules)
	if autogrind.has_method("set_active_autogrind_profile"):
		autogrind.set_active_autogrind_profile(previous_active)
	return new_idx


func _on_compose_pressed() -> void:
	var prompt_text: String = _prompt_field.text if _prompt_field != null else ""
	compose(prompt_text)


func _on_regen_pressed() -> void:
	_on_compose_pressed()


func _on_confirm_pressed() -> void:
	var replace: bool = _replace_toggle.button_pressed if _replace_toggle != null else false
	confirm(replace)


func _on_cancel_pressed() -> void:
	cancel()


func _set_thinking(active: bool) -> void:
	if _status_label != null:
		_status_label.text = "Thinking..." if active else ""
	if _compose_button != null:
		_compose_button.disabled = active
	if _regen_button != null:
		_regen_button.disabled = active
	if _confirm_button != null and active:
		_confirm_button.disabled = true


func _show_preview(result: Dictionary) -> void:
	var preview_rules = result.get("rules", [])
	var rule_count: int = preview_rules.size() if preview_rules is Array else 0
	if _status_label != null:
		_status_label.remove_theme_color_override("font_color")
		_status_label.text = "Composed %d rule(s). Confirm to install, or Regenerate." % rule_count
	if _preview_panel != null:
		_preview_panel.visible = true
		_populate_preview(result)
	if _confirm_button != null:
		_confirm_button.disabled = false
		_confirm_button.grab_focus()
	if _regen_button != null:
		_regen_button.disabled = false


func _populate_preview(result: Dictionary) -> void:
	if _preview_panel == null:
		return
	var label: Label = _preview_panel.get_node_or_null("PreviewLabel") as Label
	if label == null:
		label = Label.new()
		label.name = "PreviewLabel"
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_preview_panel.add_child(label)
	var preview_rules = result.get("rules", [])
	var rule_count: int = preview_rules.size() if preview_rules is Array else 0
	var desc: String = str(result.get("description", ""))
	if desc.is_empty():
		label.text = "%d rule(s) composed." % rule_count
	else:
		label.text = "%s\n%d rule(s) composed." % [desc, rule_count]


func _show_error(errors: Array) -> void:
	if _status_label != null:
		var msg_parts: Array = []
		for e in errors:
			msg_parts.append(str(e))
		_status_label.text = "Error: %s" % ", ".join(msg_parts)
		_status_label.add_theme_color_override("font_color", Color.ORANGE_RED)
	if _confirm_button != null:
		_confirm_button.disabled = true
