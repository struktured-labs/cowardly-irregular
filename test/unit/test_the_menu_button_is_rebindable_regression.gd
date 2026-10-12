extends GutTest

## The field menu opened on a RAW keycode and a RAW pad index, so it was the one control a player
## could not rebind and the Controls screen could not list — and naming it anywhere took a bespoke
## helper each time (the quest-log hint, the How to Play row, a face-cell-by-index). It is a real
## binding now: `ui_field_menu`, S + the north face, in REMAPPABLE_ACTIONS and in every profile.
##
## ⛔ AND THE REBIND IS REFUSED ON TWO BUTTONS, which is the half that needed struktured's call
## (2026-10-12, asked and answered): his FIRST controls report was "I enter the overworld menu with
## a confirm button or something" — dash shared the opener's face, so every dash opened the menu.
## Handing a player a rebind screen is handing them that same defect to build by hand, on the two
## buttons they press most. So Confirm and Cancel are refused like the Controls-screen lock-in,
## rather than left as "the player's business". Both directions: the collision is symmetric, and
## which of the pair you happened to move last is not a thing the player should have to reason about.

const CONFIG := "user://input/controls.json"

var _mode: bool = true
var _profile: String = ""
var _custom: Dictionary = {}
var _chosen: bool = false
var _saved_config: String = ""
var _had_config: bool = false


func _ipm() -> Node:
	return get_node_or_null("/root/InputProfileManager")


## Snapshot the file ONCE per file, the per-test state per test — the neighbouring rebind guard
## records why: a per-test config snapshot faithfully restores the first arm's pollution.
func before_all() -> void:
	_had_config = FileAccess.file_exists(CONFIG)
	_saved_config = FileAccess.get_file_as_string(CONFIG) if _had_config else ""


func after_all() -> void:
	if _had_config and _saved_config != "":
		if FileAccess.get_file_as_string(CONFIG) != _saved_config:
			DirAccess.make_dir_recursive_absolute("user://input")
			var f := FileAccess.open(CONFIG, FileAccess.WRITE)
			if f:
				f.store_string(_saved_config)
				f.close()
	elif FileAccess.file_exists(CONFIG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))


func before_each() -> void:
	var m: Node = _ipm()
	if m == null:
		return
	_mode = m.nintendo_mode
	_profile = m.active_profile
	_custom = m.custom_bindings.duplicate(true)
	_chosen = m.profile_chosen_by_user


func after_each() -> void:
	var m: Node = _ipm()
	if m == null:
		return
	m.nintendo_mode = _mode
	m.custom_bindings = _custom.duplicate(true)
	m.active_profile = _profile
	m.profile_chosen_by_user = _chosen
	m.apply_profile(_profile)


func _joy(index: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	e.pressed = true
	return e


func _key(kc: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = kc
	e.pressed = true
	return e


func test_the_menu_is_a_binding_the_controls_screen_can_list() -> void:
	var m: Node = _ipm()
	assert_not_null(m, "PRECONDITION: InputProfileManager autoload")
	assert_true(InputMap.has_action(OverworldMenu.FIELD_MENU_ACTION),
		"the field menu must be a real action, not a raw keycode")
	assert_true(OverworldMenu.FIELD_MENU_ACTION in m.REMAPPABLE_ACTIONS,
		"and it must be remappable, or the Controls screen still cannot show it")
	assert_ne(str(m.ACTION_LABELS.get(OverworldMenu.FIELD_MENU_ACTION, "")), "",
		"and it needs a human label for the row")
	for prof in [m.PROFILE_STANDARD, m.PROFILE_SN30, m.PROFILE_ULTIMATE_PRO_2]:
		assert_true(prof.has(OverworldMenu.FIELD_MENU_ACTION),
			"every profile must bind it, or the row vanishes on that profile")


func test_it_ships_on_the_defaults_it_always_had() -> void:
	assert_true(OverworldMenu.is_toggle_event(_key(OverworldMenu.TOGGLE_KEY)),
		"S must still open the menu")
	assert_true(OverworldMenu.is_toggle_event(_joy(OverworldMenu.TOGGLE_PAD_BUTTON)),
		"and so must the north face")
	assert_true(OverworldMenu.is_toggle_event(_key(KEY_ESCAPE)),
		"Escape stays outside the binding — the universal back-out a rebind must not take away")


## ⛔ THE FEATURE: the opener follows the binding. Before this, a rebind moved nothing.
func test_the_opener_follows_a_rebind() -> void:
	var m: Node = _ipm()
	var free_button := 8
	assert_false(OverworldMenu.is_toggle_event(_joy(free_button)),
		"PRECONDITION: the target button must not already open the menu")
	m.set_custom_binding(OverworldMenu.FIELD_MENU_ACTION, [free_button])
	assert_true(OverworldMenu.is_toggle_event(_joy(free_button)),
		"after a rebind the NEW button must open the field menu")
	assert_false(OverworldMenu.is_toggle_event(_joy(OverworldMenu.TOGGLE_PAD_BUTTON)),
		"…and the old one must stop — a rebind that leaves both live is two buttons doing one job")


## CONTROL FOR THE TWO REFUSALS BELOW: a legal rebind must be ACCEPTED, or "refused" proves nothing.
func test_control_a_rebind_to_a_free_button_is_allowed() -> void:
	var m: Node = _ipm()
	var trap: Dictionary = m.binding_would_trap_the_player(OverworldMenu.FIELD_MENU_ACTION, [8])
	assert_false(bool(trap.get("trapped", false)),
		"a free button must be a legal home for the menu: %s" % str(trap.get("reason", "")))


func test_the_menu_cannot_be_bound_onto_confirm_or_cancel() -> void:
	var m: Node = _ipm()
	for other in ["ui_accept", "ui_cancel"]:
		var taken: Array = m.get_current_button_indices(other)
		assert_false(taken.is_empty(), "PRECONDITION: %s is bound to a button" % other)
		var trap: Dictionary = m.binding_would_trap_the_player(
			OverworldMenu.FIELD_MENU_ACTION, [int(taken[0])])
		assert_true(bool(trap.get("trapped", false)),
			"binding the menu onto %s rebuilds struktured's first controls report by hand" % other)
		assert_string_contains(str(trap.get("reason", "")), "field menu",
			"and the refusal must say what would happen, not just decline")


## ⛔ THE LIMIT, STATED RATHER THAN LEFT TO BE DISCOVERED: the rule is DIRECTIONAL. Moving CONFIRM
## onto the menu's button is still allowed — it is the same collision, but it is not a lock-in, and
## symmetry would forbid a binding players have always had (and that three existing guards use as
## their free parking button). This arm pins the asymmetry so it reads as a decision, not an
## oversight; if it ever becomes symmetric, change this arm deliberately.
func test_the_reverse_direction_is_deliberately_still_allowed() -> void:
	var m: Node = _ipm()
	var menu_buttons: Array = m.get_current_button_indices(OverworldMenu.FIELD_MENU_ACTION)
	assert_false(menu_buttons.is_empty(), "PRECONDITION: the menu is bound to a button")
	var trap: Dictionary = m.binding_would_trap_the_player("ui_accept", [int(menu_buttons[0])])
	assert_false(bool(trap.get("trapped", false)),
		"moving Confirm onto the menu's button stays the player's business: %s" % str(trap.get("reason", "")))


## ⛔ A HELD ESCAPE WAS MANY PRESSES. The binding branch above guards `not event.is_echo()`; the
## Escape fallback did not, so OS key-repeat re-fired the toggle and the field menu opened and closed
## at repeat rate — an EVEN number of toggles leaves it shut after printing that it opened. Found by
## @cowir-deploy while hardening the web smoke to outlast a cutscene: their hold had to put taps
## first to work around it. One function, two paths, one of them guarded — the asymmetry is the bug.
func test_a_held_escape_is_one_press_not_many() -> void:
	var first := _key(KEY_ESCAPE)
	assert_true(OverworldMenu.is_toggle_event(first),
		"CONTROL: the FIRST Escape must still toggle the menu — this arm must not pass by breaking Escape")
	var repeat := _key(KEY_ESCAPE)
	repeat.echo = true
	assert_false(OverworldMenu.is_toggle_event(repeat),
		"an OS key-repeat must NOT re-toggle the field menu: holding Escape flickers it open/closed, "
		+ "and an even count leaves it shut after something already logged that it opened")


## The same question asked of the KEY fallback, which is reachable only when the action is absent.
## Checked because a fix that guards one path and not its sibling is the shape this file keeps finding.
func test_the_key_fallback_also_ignores_a_repeat() -> void:
	var repeat := _key(OverworldMenu.TOGGLE_KEY)
	repeat.echo = true
	assert_false(OverworldMenu.is_toggle_event(repeat),
		"a held %s must not re-toggle the menu either" % OS.get_keycode_string(OverworldMenu.TOGGLE_KEY))


## ⛔ ESCAPE IS OUTSIDE THE BINDING ON PURPOSE AND NOTHING PINNED THAT PAST THE DEFAULTS. Three
## files drive Escape at the field menu and ALL THREE do it on the default binding, so routing every
## toggle through `ui_field_menu` — the obvious tidy-up now that the binding exists — would leave the
## whole suite green. The only loud signal is cowir-deploy's web smoke, which opens the menu with
## Escape at stage 3 (`tools/web_smoke.mjs:127`, 12 retries) and would red on every web publish
## looking like a menu bug rather than an input one. Raised by cowir-main off the .657 publish.
##
## The keyboard key is here for a second reason: `set_custom_binding` calls `_replace_joypad_buttons`,
## so a PAD rebind must not take the KEY with it. That is a claim about the replacement's scope, and
## the method name is not the measurement.
func test_escape_and_the_key_outlive_a_rebind_of_the_menu_button() -> void:
	var m: Node = _ipm()
	var free_button := 8
	assert_false(OverworldMenu.is_toggle_event(_joy(free_button)),
		"PRECONDITION: the target button must not already open the menu")
	m.set_custom_binding(OverworldMenu.FIELD_MENU_ACTION, [free_button])
	assert_true(OverworldMenu.is_toggle_event(_joy(free_button)),
		"PRECONDITION: the rebind must have TAKEN — if it silently failed, everything below is a fact about the defaults")
	assert_true(OverworldMenu.is_toggle_event(_key(KEY_ESCAPE)),
		"Escape must still open the field menu after the button moves — it is the universal back-out, and the web smoke presses it")
	assert_true(OverworldMenu.is_toggle_event(_key(OverworldMenu.TOGGLE_KEY)),
		"and a PAD rebind must not unbind the KEY — _replace_joypad_buttons touches joypad events only")


## The lock-in this check was written for must survive the table it now lives in.
func test_control_the_original_lockout_is_still_refused() -> void:
	var m: Node = _ipm()
	var cancel: Array = m.get_current_button_indices("ui_cancel")
	assert_false(cancel.is_empty(), "PRECONDITION: Cancel is bound")
	var trap: Dictionary = m.binding_would_trap_the_player("ui_accept", [int(cancel[0])])
	assert_true(bool(trap.get("trapped", false)),
		"Confirm onto Cancel must still be refused — that one removes the way to undo itself")

## ⛔ THE UPGRADE PATH, and it is struktured's own config shape: every saved controls.json on disk
## predates ui_field_menu. His (Custom profile, written 2026-09-23) names six actions and not this
## one. If apply_profile treated "absent" as "bind nothing", loading it would ERASE the menu button
## and the control would simply stop working for every existing player — silently, on upgrade.
## apply_profile skips an action its bindings do not mention, so the project default survives; this
## pins that, because the failure mode is invisible until someone presses the button.
func test_an_existing_config_that_never_heard_of_this_action_still_opens_the_menu() -> void:
	var m: Node = _ipm()
	var before: Array = m.get_current_button_indices(OverworldMenu.FIELD_MENU_ACTION)
	assert_false(before.is_empty(), "PRECONDITION: the menu is bound before the old config loads")
	## His six, verbatim in shape — no ui_field_menu key, which is the whole point.
	m.custom_bindings = {
		"battle_advance": [10], "battle_defer": [9], "battle_toggle_auto": [4],
		"ui_accept": [1], "ui_cancel": [0], "ui_menu": [6, 7],
	}
	m.active_profile = "Custom"
	m.apply_profile("Custom")
	assert_eq(m.get_current_button_indices(OverworldMenu.FIELD_MENU_ACTION), before,
		"an old config must leave the menu button alone, not unbind it")
	assert_true(OverworldMenu.is_toggle_event(_joy(int(before[0]))),
		"and the button must still open the menu after that config is applied")
	assert_true(OverworldMenu.is_toggle_event(_key(OverworldMenu.TOGGLE_KEY)),
		"…and so must the key, which no saved config has ever carried")
