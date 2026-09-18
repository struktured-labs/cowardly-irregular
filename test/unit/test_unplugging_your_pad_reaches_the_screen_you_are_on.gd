extends GutTest

## Every caption surface in this game derives from TWO independent facts — what the bindings are,
## and whether a pad is attached — and each one listened for exactly ONE of them.
##
## ⛔ MEASURED BEFORE THE FIX, on both screens, real menus in a real viewport:
##     footer overwritten with a sentinel, then:
##     input_device_changed(false)   rebuilt: FALSE   ⛔ unplugging left the pad captions up
##     bindings_changed              rebuilt: true    ✅ the half that was already fixed
##
## A pad LEAVING changes what the caption should say without changing a single binding —
## `hint_for_action` answers with keyboard keys once `get_connected_joypads()` is empty. So the
## player unplugs their controller, or a wireless pad sleeps, and the screen in front of them keeps
## naming Ⓐ and Ⓑ at someone who now has only a keyboard. That is the same harm .308-.338 removed,
## arriving through a correctly-derived string that went stale rather than a frozen literal.
##
## 📌 `InputProfileManager` NEVER emits `bindings_changed` for a device change, and that is correct
## rather than an oversight — the InputMap is untouched, so claiming the bindings moved would be a
## lie. `_autodetect_and_apply` DOES emit it, transitively through `apply_profile`, but it is gated
## on `connected` and on `not profile_chosen_by_user`, so neither an unplug nor a re-plug by a
## player who has chosen their own profile ever reaches it. The fix is that a surface depending on
## both facts listens for both, not that one signal starts standing in for the other.
##
## ⚠️ HEADLESS HAS NO PADS, so the derived value cannot itself move here — the arms overwrite the
## footer with a SENTINEL and assert it is re-derived. That measures "this caption was rebuilt",
## which is the contract; the sibling `test_a_controls_change_reaches_the_screen_behind_it` pins
## the same technique for the bindings half.

const SENTINEL := "ZZZ_STALE_SENTINEL"

const SCREENS := [
	["res://src/ui/SettingsMenu.gd", "RClick: Back"],
	["res://src/ui/OverworldMenu.gd", "RClick: Close"],
]


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


## ⛔ THE CONTROL, and it comes first: if the footer is not DERIVED to begin with, every arm below
## is measuring a constant being rewritten with itself.
func test_the_footers_are_derived_to_begin_with() -> void:
	for spec in SCREENS:
		var m = await _menu_in_tree(spec[0])
		var footer: Label = _footer_of(m, spec[1])
		assert_not_null(footer, "CONTROL: %s must build a footer naming its actions" % spec[0])
		assert_true(footer.text.contains(InputProfileManager.hint_for_action("ui_accept")),
			"CONTROL: %s's footer must be derived, got '%s'" % [spec[0], footer.text])


## ⛔ THE DEFECT. A pad leaving is not a binding change, and the screen in front of the player
## derives from both.
func test_a_pad_leaving_rebuilds_the_footer() -> void:
	for spec in SCREENS:
		var m = await _menu_in_tree(spec[0])
		var footer: Label = _footer_of(m, spec[1])
		assert_not_null(footer, "CONTROL: the footer must exist")

		footer.text = SENTINEL
		InputProfileManager.input_device_changed.emit(false)
		await get_tree().process_frame

		assert_ne(footer.text, SENTINEL,
			"%s: the pad went away and this footer kept naming its buttons. `hint_for_action` " % spec[0]
			+ "answers with keyboard keys once no pad is connected, so every caption on screen is "
			+ "now wrong — and nothing emits `bindings_changed` for a disconnect, correctly, because "
			+ "the InputMap did not move.")


## A pad ARRIVING is the same gap in the other direction. `_autodetect_and_apply` emits
## `bindings_changed` transitively, but only when the player has NOT chosen a profile themselves —
## so for anyone who picked their own, a re-plug reaches this footer through no other path.
func test_a_pad_arriving_rebuilds_the_footer() -> void:
	for spec in SCREENS:
		var m = await _menu_in_tree(spec[0])
		var footer: Label = _footer_of(m, spec[1])
		footer.text = SENTINEL
		InputProfileManager.input_device_changed.emit(true)
		await get_tree().process_frame
		assert_ne(footer.text, SENTINEL, "%s: a pad arriving must re-derive the captions too" % spec[0])


## ⛔ THE HALF THAT WAS ALREADY FIXED, kept as a regression: the device wiring must not displace it.
## Connecting one signal and quietly dropping the other would pass every arm above.
func test_a_binding_change_still_rebuilds_the_footer() -> void:
	for spec in SCREENS:
		var m = await _menu_in_tree(spec[0])
		var footer: Label = _footer_of(m, spec[1])
		footer.text = SENTINEL
		InputProfileManager.bindings_changed.emit()
		await get_tree().process_frame
		assert_ne(footer.text, SENTINEL,
			"%s: the bindings half must keep working — ControlsMenu opens as a CHILD of this screen" % spec[0])


## ⛔ THE CONNECTION IS MADE THROUGH `.unbind(1)`, WHICH MINTS A NEW CALLABLE EVERY TIME, so the
## `is_connected` guard beside it is doing non-obvious work. Measured: it DOES recognise an
## equivalent unbound callable, so a rebuild does not stack. Pinned because the failure is silent —
## duplicate connections just refresh N times — and because a future refactor to a lambda, which
## compares by identity, would break it with nothing else on this screen noticing.
func test_rebuilding_the_screen_does_not_stack_connections() -> void:
	var m = await _menu_in_tree("res://src/ui/SettingsMenu.gd")
	var mine: int = 0
	for c in InputProfileManager.input_device_changed.get_connections():
		if c["callable"].get_object() == m:
			mine += 1
	assert_eq(mine, 1, "the screen must be connected exactly once, got %d" % mine)

	m._build_ui()
	await get_tree().process_frame

	var after: int = 0
	for c in InputProfileManager.input_device_changed.get_connections():
		if c["callable"].get_object() == m:
			after += 1
	assert_eq(after, 1,
		"rebuilding the screen must not add a second connection: %d -> %d. `.unbind(1)` returns a "
			% [mine, after]
		+ "fresh Callable each call, so this pins that `is_connected` still matches it.")
