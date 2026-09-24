extends GutTest

## Regression for struktured's report (2026-09-23): "I enter the overworld menu with a confirm button
## or something instead of X sometimes and get stuck in it." 8BitDo Ultimate 2, nintendo_mode on.
##
## ⛔ TWO DEFECTS, ONE CAUSE — the overworld menu was opened by RAW joypad indices, not an action:
##   1. The opener accepted [JOY_BUTTON_X, JOY_BUTTON_Y] = [2, 3]. Index 2 is the WEST face, which is
##      also the `dash` binding. Dash is polled (OverworldPlayer), so it never consumes the press and
##      GameLoop._input saw it too: every dash opened the menu. That is the "sometimes".
##   2. Nothing closed the menu on the pad button that opened it. Keyboard X toggled both ways
##      (OverworldMenu had an explicit KEY_X close); the pad had no counterpart, so the only way out
##      was ui_cancel. Press X to open, press X to leave, nothing happens: "stuck".
##
## The comment on the opener read "JOY_BUTTON_X=2 (Xbox X)" — it took "X" to mean Xbox's X, which is
## the west face. This game's convention (CLAUDE.md, Battle Controls) makes "X" the TOP face, north,
## index 3, and "Y" the west face. North is the only face this fix accepts.


func _joy(index: int, pressed: bool = true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	e.pressed = pressed
	return e


const GdSource := preload("res://test/unit/helpers/gd_source.gd")


## Every .gd under res://src as CODE ONLY — GdSource strips comments and docstrings, so an action is
## "read" only when real code names it, never when prose mentions it.
func _game_code() -> String:
	var out := PackedStringArray()
	var stack := ["res://src"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			if not n.begins_with("."):
				var path := dir + "/" + n
				if d.current_is_dir():
					stack.append(path)
				elif n.ends_with(".gd"):
					out.append(GdSource.code_of(path))
			n = d.get_next()
	return "\n".join(out)


## Every joypad index the predicate treats as the menu toggle — DERIVED from the real predicate, so
## this cannot drift from what GameLoop actually opens on.
func _toggle_pad_buttons() -> Array:
	var out := []
	for i in range(JOY_BUTTON_SDL_MAX):
		if OverworldMenu.is_toggle_event(_joy(i)):
			out.append(i)
	return out


## ⛔ THE DEFECT, stated as the general property rather than as dash alone: no action the GAME READS may
## share a joypad button with the menu toggle. Both sides are derived — the toggle's buttons from the
## predicate, the readers from src/ code — so a new action on the toggle button reds here too.
##
## 📌 SCOPED TO ACTIONS SOME CODE READS, and the scope is derived rather than an exception list. The
## first version of this arm checked every InputMap action and flagged `ui_select -> joy 3`: Godot's
## BUILT-IN default (not in project.godot), read by zero lines of src/, and unable to activate anything
## in OverworldMenu, which has no Button, no grab_focus and no focus mode. A binding nothing responds to
## cannot double-fire, so it is not this defect — and hardcoding `ui_select` as an exemption would be
## the suppression flag CLAUDE.md warns against, silently excusing it if code ever starts reading it.
func test_no_action_the_game_reads_shares_a_button_with_the_menu_toggle() -> void:
	var toggles := _toggle_pad_buttons()
	assert_gt(toggles.size(), 0,
		"CONTROL: the predicate must accept at least one pad button, else this arm checks nothing")
	var code := _game_code()
	assert_true(code.contains('"dash"'),
		"CONTROL: the src/ corpus must contain dash's reader — a broken walk would skip every action "
		+ "and turn this arm into a silent green")
	var clashes := []
	for action in InputMap.get_actions():
		if not code.contains('"%s"' % action):
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton and ev.button_index in toggles:
				clashes.append("%s -> joy %d" % [action, ev.button_index])
	assert_eq(clashes, [],
		"the overworld-menu toggle shares a button with %s — pressing that action opens the menu "
		% [clashes] + "too. This was `dash` on the west face: every dash opened the menu.")


func test_the_dash_button_is_not_the_menu_button() -> void:
	assert_false(OverworldMenu.is_toggle_event(_joy(JOY_BUTTON_X)),
		"the WEST face (index 2) is `dash` — accepting it as the menu toggle opened the menu on "
		+ "every dash. That is the 'confirm button or something' struktured reported.")


## CONTROL, and the one that protects his intended button: north is his "X" (Ⓧ on a Nintendo-family
## pad) and must keep opening the menu, or the fix trades one bug for losing the menu entirely.
func test_the_menu_button_is_the_north_face() -> void:
	assert_true(OverworldMenu.is_toggle_event(_joy(JOY_BUTTON_Y)),
		"CONTROL: the NORTH face (index 3, this game's 'X') must still open the overworld menu")
	assert_false(OverworldMenu.is_toggle_event(_joy(JOY_BUTTON_Y, false)),
		"CONTROL: a RELEASE is not a press — only the press toggles")


func test_confirm_is_not_the_menu_button() -> void:
	assert_false(OverworldMenu.is_toggle_event(_joy(JOY_BUTTON_B)),
		"the EAST face is Confirm under nintendo_mode — it must never open the overworld menu")
	assert_false(OverworldMenu.is_toggle_event(_joy(JOY_BUTTON_A)),
		"the SOUTH face is Cancel — it must never open the overworld menu")


func _open_menu() -> OverworldMenu:
	var c := Combatant.new()
	c.combatant_name = "ToggleProbe"
	add_child_autofree(c)
	var menu := OverworldMenu.new()
	add_child_autofree(menu)
	menu.setup([c])
	await get_tree().process_frame
	await get_tree().process_frame
	menu.modulate.a = 1.0   # skip the 0.15s fade-in guard
	menu.visible = true
	return menu


## ⛔ POSITIVE CONTROL FOR THE HARNESS. The stuck-arm below asserts a close; if this harness could not
## observe a close at all, that arm would fail for a reason unrelated to the defect. ui_cancel has
## always closed the menu, so it must close it here first.
func test_control_cancel_closes_the_menu() -> void:
	var menu := await _open_menu()
	watch_signals(menu)
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	menu._input(cancel)
	assert_signal_emitted(menu, "closed",
		"CONTROL: ui_cancel must close the menu — if not, the harness is broken, not the feature")


## ⛔ THE "STUCK" DEFECT. The pad button that opens the menu must also close it, exactly as keyboard X
## does. Before the fix this press fell through every branch of OverworldMenu._input and did nothing.
func test_the_button_that_opens_the_menu_also_closes_it() -> void:
	assert_false(InputMap.event_is_action(_joy(JOY_BUTTON_Y), "ui_accept"),
		"PRECONDITION: north must not be Confirm here, or this press would confirm instead of close")
	var menu := await _open_menu()
	watch_signals(menu)
	menu._input(_joy(JOY_BUTTON_Y))
	assert_signal_emitted(menu, "closed",
		"pressing the pad button that OPENED the overworld menu must close it — keyboard X toggles "
		+ "both ways and the pad did not, so the only exit was ui_cancel: 'stuck'.")
