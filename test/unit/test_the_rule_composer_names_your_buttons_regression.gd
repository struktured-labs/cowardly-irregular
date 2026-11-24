extends GutTest

## Regression 2026-10-03: the Rule Composer's buttons read "Compose (A) · Regenerate (R) · Confirm (A) · Cancel (B)" from the scene,
## Nintendo letters, so Confirm and Cancel were inverted on an Xbox pad and named no key on a keyboard.

const OverlayScene := preload("res://src/ui/autobattle/RuleComposerOverlay.tscn")
const PADS := ["Xbox Wireless Controller", "PS5 Controller", "Nintendo Switch Pro Controller"]


func _overlay():
	var o = OverlayScene.instantiate()
	add_child_autofree(o)
	return o


func _buttons(o) -> Dictionary:
	return {
		"compose": o.get_node("Panel/VBox/ButtonsHBox/ComposeButton").text,
		"regen": o.get_node("Panel/VBox/ButtonsHBox/RegenButton").text,
		"confirm": o.get_node("Panel/VBox/ButtonsHBox/ConfirmButton").text,
		"cancel": o.get_node("Panel/VBox/ButtonsHBox/CancelButton").text,
	}


func test_each_button_names_its_own_action_on_every_pad_family() -> void:
	var o = _overlay()
	for pad in PADS:
		var accept: String = InputProfileManager.hint_for_action("ui_accept", pad)
		var cancel: String = InputProfileManager.hint_for_action("ui_cancel", pad)
		var advance: String = InputProfileManager.hint_for_action("battle_advance", pad)
		assert_true(accept != "" and accept != cancel and advance != accept and advance != cancel,
			"CONTROL: %s must give three different hints (%s / %s / %s), or a crossed action would look correct" % [pad, accept, cancel, advance])
		o._previewing = false
		o._refresh_captions(pad)
		var b := _buttons(o)
		assert_eq(b["compose"], "Compose (%s)" % accept, "%s: before a preview, Compose owns the confirm button" % pad)
		assert_eq(b["confirm"], "Confirm", "%s: and Confirm, with nothing to confirm, names no key" % pad)
		assert_eq(b["cancel"], "Cancel (%s)" % cancel, "%s: Cancel does not name the cancel button" % pad)
		assert_eq(b["regen"], "Regenerate (%s)" % advance, "%s: Regenerate does not name the Advance shoulder it answers to" % pad)
		o._previewing = true
		o._refresh_captions(pad)
		b = _buttons(o)
		assert_eq(b["confirm"], "Confirm (%s)" % accept, "%s: with a preview up, Confirm owns the confirm button" % pad)
		assert_eq(b["compose"], "Compose", "%s: and Compose no longer claims it (Regenerate re-runs the prompt)" % pad)


func test_an_xbox_pad_is_not_told_to_press_the_nintendo_letters() -> void:
	var o = _overlay()
	o._previewing = true
	o._refresh_captions("Xbox Wireless Controller")
	var b := _buttons(o)
	assert_ne(b["confirm"], "Confirm (A)", "Confirm still names Nintendo A, which is Cancel's position on an Xbox pad")
	assert_ne(b["cancel"], "Cancel (B)", "Cancel still names Nintendo B, which is Confirm's position on an Xbox pad")


func test_a_keyboard_player_is_shown_their_keys() -> void:
	var o = _overlay()
	assert_true(Input.get_connected_joypads().is_empty(), "CONTROL: run_tests.sh hides host pads, so this arm measures the keyboard")
	var accept: String = InputProfileManager.hint_for_action("ui_accept")
	var cancel: String = InputProfileManager.hint_for_action("ui_cancel")
	assert_true(accept != "" and cancel != "" and accept != cancel,
		"CONTROL: the keyboard must give confirm and cancel different keys (%s / %s)" % [accept, cancel])
	assert_eq(_buttons(o)["compose"], "Compose (%s)" % accept, "with no pad the composer must name the keyboard confirm key")
	assert_eq(_buttons(o)["cancel"], "Cancel (%s)" % cancel, "with no pad the composer must name the keyboard cancel key")


func test_opening_the_composer_rederives_the_captions() -> void:
	var o = _overlay()
	o.get_node("Panel/VBox/ButtonsHBox/CancelButton").text = "Cancel (B)"
	o.open("autobattle", "fighter", [])
	assert_eq(_buttons(o)["cancel"], "Cancel (%s)" % InputProfileManager.hint_for_action("ui_cancel"),
		"open() left a stale caption — a pad plugged in while the composer was hidden would keep the old letters")


## His "I always press some button by accident": two visible buttons that print the same key read as one press, two meanings.
func test_no_two_buttons_ever_show_the_same_key() -> void:
	var o = _overlay()
	for previewing in [false, true]:
		o._previewing = previewing
		for pad in PADS + [""]:
			o._refresh_captions(pad)
			var keys: Dictionary = {}
			for caption in _buttons(o).values():
				var at: int = str(caption).find("(")
				if at == -1:
					continue
				var key: String = str(caption).substr(at)
				assert_false(keys.has(key), "%s (preview %s): two buttons both say %s" % [pad if pad != "" else "keyboard", previewing, key])
				keys[key] = true
			assert_gt(keys.size(), 2, "CONTROL: at least three buttons name a key (%s)" % str(keys.keys()))


func test_a_preview_disables_compose_and_an_error_restores_it() -> void:
	var o = _overlay()
	o.open("autobattle", "cleric", [])
	var compose: Button = o.get_node("Panel/VBox/ButtonsHBox/ComposeButton")
	assert_false(compose.disabled, "CONTROL: an opened composer can compose")
	o._show_preview({"description": "d", "rules": [{"conditions": [{"type": "always"}], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}]}], "notes": []})
	assert_true(compose.disabled, "one d-pad step from Confirm, a second 'do it again' button is off while a preview waits")
	assert_true(o._previewing, "CONTROL: the preview is up")
	o._show_error(["model unreachable"])
	assert_false(compose.disabled, "a failed regenerate leaves nothing to confirm, so Compose comes back")
	assert_eq(_buttons(o)["compose"], "Compose (%s)" % InputProfileManager.hint_for_action("ui_accept"), "and takes the confirm key back")
