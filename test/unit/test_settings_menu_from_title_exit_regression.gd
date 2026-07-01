extends GutTest

## Regression: SettingsMenu opened from TitleScreen (from_title=true) must
## exit cleanly via ui_cancel — even when a submenu flag is stale/stuck.
##
## Live playtest bug (cowir-main msg 1876, 2026-06-30):
##   User navigated title → Settings, got "kind of stuck" — couldn't exit.
##
## Root causes shipped in the failsafe:
##   1. The 4 older submenu openers (_open_controls_menu, _open_jukebox_
##      menu, _open_boss_selector, _open_teleport_menu) set their `*_open`
##      flag BEFORE the load() and didn't reset it on load failure.
##      Load fails silently → flag stays true → _input's 7-flag early-
##      return swallows ui_cancel forever.
##   2. Even for the newer 3 openers (rebalance_history / byok_config /
##      rebalance_review) that DO handle load failure, any missed close
##      signal (e.g. panel freed by parent teardown before firing) leaves
##      the flag stuck.
##
## Fix strategy:
##   - Defensive load in the 4 older openers (match the newer 3 pattern).
##   - Failsafe in _input: if any `*_open` flag is set BUT no live submenu
##     child exists in the tree, reset all flags and continue processing
##     input. Guarantees ui_cancel always works — the modal-lockout only
##     kicks in when a real submenu is actually on screen.

const SETTINGS_MENU_PATH := "res://src/ui/SettingsMenu.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _make_menu(from_title: bool = true):
	var script = load(SETTINGS_MENU_PATH)
	var menu = script.new()
	menu.from_title = from_title
	add_child_autofree(menu)
	return menu


func test_all_four_older_openers_reset_flag_on_load_failure() -> void:
	# Source pin: each of the 4 older openers must reset its flag when the
	# script load fails. Catches anyone reverting to the pre-fix pattern
	# where the flag stayed true forever on a failed load.
	var text = _read(SETTINGS_MENU_PATH)
	for opener in [
			"func _open_controls_menu",
			"func _open_jukebox_menu",
			"func _open_boss_selector",
			"func _open_teleport_menu"]:
		var fn_idx = text.find(opener)
		assert_true(fn_idx > -1, "%s must exist" % opener)
		var fn_end = text.find("\n\n\nfunc ", fn_idx)
		var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx, 1000)
		# Must have an `if not <load result>:` guard that resets the flag
		# and returns early, matching the newer openers' pattern.
		assert_true(body.find("if not ") > -1,
			"%s must guard load failure with `if not ...:` — otherwise flag stays stuck true on failure" % opener)
		assert_true(body.find("_submenu_open = false") > -1 or body.find("submenu_open = false") > -1,
			"%s must reset its *_open flag when the load fails" % opener)


func test_input_failsafe_helpers_exist() -> void:
	# Source pin: both failsafe helpers must exist AND be called from the
	# _input early-return path. Catches anyone deleting the safety net.
	var text = _read(SETTINGS_MENU_PATH)
	assert_true(text.find("func _has_live_submenu_child()") > -1,
		"_has_live_submenu_child helper must exist for the _input failsafe")
	assert_true(text.find("func _reset_submenu_flags()") > -1,
		"_reset_submenu_flags helper must exist for the _input failsafe")
	# Confirm the _input path calls both.
	var input_idx = text.find("func _input(event: InputEvent)")
	assert_true(input_idx > -1, "_input must exist")
	var input_end = text.find("\n\nfunc ", input_idx)
	var body = text.substr(input_idx, input_end - input_idx) if input_end > -1 else text.substr(input_idx, 2000)
	assert_true(body.find("_has_live_submenu_child()") > -1,
		"_input must call _has_live_submenu_child before the modal early-return")
	assert_true(body.find("_reset_submenu_flags()") > -1,
		"_input must call _reset_submenu_flags when flags are stale")


func test_stale_flag_gets_reset_when_no_submenu_child_alive() -> void:
	# Behavioral: set _controls_submenu_open = true WITHOUT actually
	# adding a submenu child. Call _has_live_submenu_child — must return
	# false. Then _reset_submenu_flags must clear all 7 flags.
	var menu = _make_menu(true)
	menu._controls_submenu_open = true
	menu._jukebox_submenu_open = true  # extra stuck flag for safety
	assert_false(menu._has_live_submenu_child(),
		"No submenu child in tree → _has_live_submenu_child must return false")
	menu._reset_submenu_flags()
	assert_false(menu._controls_submenu_open, "_controls_submenu_open must reset")
	assert_false(menu._jukebox_submenu_open, "_jukebox_submenu_open must reset")
	assert_false(menu._boss_submenu_open, "_boss_submenu_open must reset")
	assert_false(menu._teleport_submenu_open, "_teleport_submenu_open must reset")
	assert_false(menu._rebalance_review_open, "_rebalance_review_open must reset")
	assert_false(menu._byok_config_open, "_byok_config_open must reset")
	assert_false(menu._rebalance_history_open, "_rebalance_history_open must reset")


func test_live_submenu_child_keeps_flags_and_modal_intact() -> void:
	# If a REAL submenu child is in the tree, the modal early-return
	# should still fire — we're not removing that behavior, only adding
	# the "stale flag" recovery.
	var menu = _make_menu(true)
	# Fake a live submenu: attach a Control child with a script path
	# matching one of the recognized submenu scripts. We use a real load
	# so the path signature is authoritative.
	var script = load("res://src/ui/ControlsMenu.gd")
	if script == null:
		pending("ControlsMenu.gd not loadable in this test context")
		return
	var fake_submenu: Node = script.new()
	menu.add_child(fake_submenu)
	menu._controls_submenu_open = true
	assert_true(menu._has_live_submenu_child(),
		"With a real ControlsMenu child in the tree, _has_live_submenu_child must return true")
	# Cleanup — script.new()'d Nodes need explicit tear down since GUT
	# only auto-frees the top-level menu.
	fake_submenu.queue_free()


func test_from_title_flag_hides_quit_to_title_row() -> void:
	# Regression sanity check on the from_title flow that shipped in the
	# v2 settings batch. When from_title=true, the "Quit to Title" action
	# row must NOT appear (it's a no-op — we're already on the title
	# screen). Guards against anyone reverting the check that hides it.
	var text = _read(SETTINGS_MENU_PATH)
	# The gate looks like `if not from_title:` immediately before the
	# add_action.call("Quit to Title", ...) invocation.
	# Look for the actual add_action.call — matches only the _build_ui
	# registration, not the docstring / confirm dialog title.
	var quit_idx = text.find("add_action.call(\"Quit to Title\"")
	assert_true(quit_idx > -1, "add_action.call for 'Quit to Title' must be present in _build_ui")
	if quit_idx > -1:
		# Walk backwards ~200 chars — must find `if not from_title:` guard
		# immediately preceding the add_action.call registration.
		var preceding = text.substr(max(0, quit_idx - 200), 200)
		assert_true(preceding.find("if not from_title:") > -1,
			"add_action.call('Quit to Title', ...) must be gated by `if not from_title:` — otherwise it's a no-op on title screen")


func test_close_settings_still_emits_signal_and_frees() -> void:
	# Behavioral belt-and-suspenders: _close_settings must fire the
	# closed signal and queue_free. The parent (GameLoop._on_title_
	# settings) listens on `closed` to tear down the CanvasLayer wrapper
	# — if either half breaks, the overlay leaks.
	var menu = _make_menu(true)
	var received: Array = []
	menu.closed.connect(func(): received.append(1))
	menu._close_settings()
	assert_eq(received.size(), 1,
		"_close_settings must emit `closed` exactly once (parent listens for it)")
	# queue_free actually happens; verify by is_queued_for_deletion
	assert_true(menu.is_queued_for_deletion(),
		"_close_settings must call queue_free — otherwise the overlay leaks")
