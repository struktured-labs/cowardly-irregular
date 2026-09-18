extends GutTest

## ControlsMenu is opened as a CHILD of SettingsMenu (:1808) and of OverworldMenu (:818) — both
## parents stay alive underneath it. Both build a footer naming `ui_accept` and `ui_cancel` ONCE,
## inline in `_build_ui`, and `_on_controls_closed()` only clears a flag.
##
## ⛔ SO CHANGING YOUR CONTROLS LEAVES THE SCREEN BEHIND YOU NAMING THE OLD ONES — and because the
## Nintendo toggle SWAPS these two actions, the stale caption is INVERTED rather than merely wrong:
##     nintendo_mode on      ui_accept=Ⓑ   ui_cancel=Ⓐ
##     nintendo_mode off     ui_accept=Ⓐ   ui_cancel=Ⓑ
##     stale footer says     "Ⓑ: Select   Ⓐ: Back"   while Ⓐ selects and Ⓑ goes back
## A caption that names the button doing the OPPOSITE thing is worse than no caption — it is the
## same harm this lane spent .308-.338 removing, arriving through a correctly-derived string that
## went stale instead of a frozen literal.
##
## 📌 InputProfileManager's own signal docstring describes this bug and does not cover it:
## "Surfaces whose captions are DERIVED rebuild on this — deriving them is only half the job if the
## answer is frozen at the moment the screen was built." `input_device_changed` fires ONLY from
## `_on_joy_connection_changed`. A profile cycle, a rebind and the Nintendo toggle all emit nothing.
##
## ⚠️ HEADLESS SHOWS KEYBOARD LETTERS (Z/X), which do NOT move with the convention — so the arms
## below overwrite the footer with a SENTINEL and assert it is re-derived. That measures "the
## caption was rebuilt" on a machine where the derived value itself cannot change, and it is why
## these arms pin the effect rather than the signal wiring.

const SENTINEL := "ZZZ_STALE_SENTINEL"
const PAD := "Xbox Series Controller"

var _saved_nintendo: bool = false
var _saved_profile: String = ""


func before_all() -> void:
	_saved_nintendo = InputProfileManager.nintendo_mode
	_saved_profile = InputProfileManager.active_profile


## set_nintendo_mode calls apply_profile AND save_config, so this restores through the same door it
## mutated through rather than assigning the field — the sibling lanes' rule, and here the door is
## what re-binds the InputMap for everything that runs after this file.
func after_all() -> void:
	InputProfileManager.set_nintendo_mode(_saved_nintendo)
	InputProfileManager.apply_profile(_saved_profile)


func _labels(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Label:
			out.append(c)
		_labels(c, out)


func _footer_of(menu: Node, marker: String) -> Label:
	var found: Array = []
	_labels(menu, found)
	for l in found:
		if marker in (l as Label).text:
			return l
	return null


func _menu_in_tree(path: String) -> Node:
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	add_child_autofree(sv)
	var m = load(path).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	sv.add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


## ⛔ THE CONTROL, and it is what makes the staleness matter rather than being cosmetic: these two
## captions do not drift, they TRADE PLACES. Without this arm the rest could be true of a caption
## whose value never changes, and stale would cost nothing.
func test_the_two_captions_invert_when_the_convention_flips() -> void:
	var a0: String = InputProfileManager.hint_for_action("ui_accept", PAD)
	var b0: String = InputProfileManager.hint_for_action("ui_cancel", PAD)
	InputProfileManager.set_nintendo_mode(not InputProfileManager.nintendo_mode)
	var a1: String = InputProfileManager.hint_for_action("ui_accept", PAD)
	var b1: String = InputProfileManager.hint_for_action("ui_cancel", PAD)

	assert_ne(a0, a1, "CONTROL: ui_accept's pad caption must change with the convention (%s)" % a0)
	assert_eq(a1, b0, "the toggle SWAPS them: accept takes what cancel had (%s vs %s)" % [a1, b0])
	assert_eq(b1, a0, "…and cancel takes what accept had (%s vs %s)" % [b1, a0])


## ⛔ THE DEFECT, on the screen the player backs out to.
func test_the_settings_footer_is_rebuilt_after_a_controls_change() -> void:
	var m = await _menu_in_tree("res://src/ui/SettingsMenu.gd")
	var footer: Label = _footer_of(m, "RClick: Back")
	assert_not_null(footer, "CONTROL: SettingsMenu must build a footer naming Select/Back")
	assert_true(footer.text.contains(InputProfileManager.hint_for_action("ui_accept")),
		"CONTROL: the footer must be DERIVED to begin with, got '%s'" % footer.text)

	footer.text = SENTINEL
	InputProfileManager.set_nintendo_mode(not InputProfileManager.nintendo_mode)
	await get_tree().process_frame

	assert_ne(footer.text, SENTINEL,
		"the Settings footer names ui_accept/ui_cancel and was built once; changing the controls "
		+ "underneath it left it frozen. The Nintendo toggle SWAPS those two, so the stale caption "
		+ "names the button that now does the opposite thing.")


## The other parent. ControlsMenu is reachable from BOTH, and a fix applied to one is half a fix —
## OverworldMenu opens it directly (:818), not by way of Settings.
func test_the_overworld_footer_is_rebuilt_after_a_controls_change() -> void:
	var m = await _menu_in_tree("res://src/ui/OverworldMenu.gd")
	var footer: Label = _footer_of(m, "RClick: Close")
	assert_not_null(footer, "CONTROL: OverworldMenu must build a footer naming Confirm/Close")
	assert_true(footer.text.contains(InputProfileManager.hint_for_action("ui_accept")),
		"CONTROL: the footer must be DERIVED to begin with, got '%s'" % footer.text)

	footer.text = SENTINEL
	InputProfileManager.set_nintendo_mode(not InputProfileManager.nintendo_mode)
	await get_tree().process_frame

	assert_ne(footer.text, SENTINEL,
		"the overworld footer derives FOUR captions — accept, cancel and both leader-cycle "
		+ "shoulders — and was built once. A profile cycle moves the shoulders too, so this is not "
		+ "only the face-convention case.")


## Every key the InputMap binds to an action — an INDEPENDENT path to the answer the caption
## should carry. Headless has no pad, so the caption is a key name, and InputMap can supply it
## without going through the resolver the footer itself uses.
func _bound_key_names(action: String) -> Array:
	var out: Array = []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			out.append(OS.get_keycode_string((e as InputEventKey).keycode))
	return out


## The token the footer prints immediately before a given separator, e.g. "Z" in "…  Z/Click: Select".
func _token_before(text: String, sep: String) -> String:
	var at := text.find(sep)
	if at < 0:
		return ""
	var head: String = text.substr(0, at).strip_edges()
	var parts: PackedStringArray = head.split(" ")
	return str(parts[parts.size() - 1]) if parts.size() > 0 else ""


## …and a rebuild must re-derive, not merely overwrite with something. A refresh that wrote a
## constant would satisfy the sentinel arms above while telling the player nothing true.
##
## ⛔ THE EXPECTATION DOES NOT COME FROM THE SUBJECT'S OWN RESOLVER, AND IT DID. This arm asserted
## `footer.text.contains(hint_for_action("ui_accept"))` — but the footer is BUILT with
## hint_for_action, so both sides moved together. Measured: stub the resolver to a constant "ZZ"
## and this arm PASSED with it completely broken; only the convention control noticed.
##
## ⚠️ AND `contains` IS THE WRONG OPERATOR EVEN WITH AN INDEPENDENT EXPECTATION: "ZZ" CONTAINS "Z",
## so a substring test would still have passed that same stub. The token is compared for EQUALITY
## against the set of keys the InputMap actually binds.
func test_the_rebuilt_footer_names_the_current_binding() -> void:
	var m = await _menu_in_tree("res://src/ui/SettingsMenu.gd")
	var footer: Label = _footer_of(m, "RClick: Back")
	assert_not_null(footer, "CONTROL: the footer must exist")

	var accept_keys: Array = _bound_key_names("ui_accept")
	var cancel_keys: Array = _bound_key_names("ui_cancel")
	assert_gt(accept_keys.size(), 0, "CONTROL: ui_accept must bind a key, or there is nothing to name")
	assert_gt(cancel_keys.size(), 0, "CONTROL: ui_cancel must bind a key")

	footer.text = SENTINEL
	InputProfileManager.set_nintendo_mode(not InputProfileManager.nintendo_mode)
	await get_tree().process_frame

	var shown_accept: String = _token_before(footer.text, "/Click: Select")
	var shown_cancel: String = _token_before(footer.text, "/RClick: Back")
	assert_true(shown_accept in accept_keys,
		"the footer prints '%s' for Select; the keys actually bound to ui_accept are %s — full text: '%s'"
			% [shown_accept, accept_keys, footer.text])
	assert_true(shown_cancel in cancel_keys,
		"the footer prints '%s' for Back; ui_cancel binds %s" % [shown_cancel, cancel_keys])
