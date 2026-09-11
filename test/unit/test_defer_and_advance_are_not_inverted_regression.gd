extends GutTest

## struktured 2026-09-10, while reporting the queue-commit ask: "which is R… or should be R…
## one should be L one should be R." He could not remember which, and he was right not to trust
## his memory — THE KEYBOARD WAS INVERTED against everything that documents it.
##
## MEASURED before the fix:
##   project.godot     battle_defer = L key      battle_advance = R key
##   hint bar          "[L] Defer · [R] Advance"                        agrees
##   BattleScene:4867  keycode == KEY_R  -> BattleManager.player_defer()     🔴 R DEFERRED
##   BattleScene:4877  keycode == KEY_L  -> log "Use R to queue actions"     🔴 and lectured
##
## REACHABLE, not dead code: Win98Menu._input consumes both actions, but only while a menu exists,
## and BattleScene's own next branch reopens the menu because "closed while selecting" is a real
## state it anticipates. With no menu open, the raw handlers ran.
##
## ⚠️ My own shadowed-handler ratchet cannot see this: it detects a keycode branch under an
## is_action_pressed branch IN THE SAME FUNCTION, and this pair was shadowed ACROSS NODES.

const BS := "res://src/battle/BattleScene.gd"


## The premise, read from the InputMap the engine actually loaded — not from project.godot text.
func test_the_bindings_say_l_defers_and_r_advances() -> void:
	var defer_keys := []
	var adv_keys := []
	for ev in InputMap.action_get_events("battle_defer"):
		if ev is InputEventKey:
			defer_keys.append(OS.get_keycode_string(ev.keycode))
	for ev in InputMap.action_get_events("battle_advance"):
		if ev is InputEventKey:
			adv_keys.append(OS.get_keycode_string(ev.keycode))
	assert_has(defer_keys, "L", "battle_defer must bind L — the hint bar says '[L] Defer'")
	assert_has(adv_keys, "R", "battle_advance must bind R — the hint bar says '[R] Advance'")
	assert_does_not_have(defer_keys, "R", "CONTROL: defer must NOT also claim R, or the arms below prove nothing")


## THE DEFECT: no raw keycode branch may contradict those bindings.
func test_no_raw_key_branch_inverts_defer_and_advance() -> void:
	# UNCONDITIONAL. The first version guarded each check on the branch existing, so with the raw
	# branches gone it asserted NOTHING and GUT scored it [Risky] — a guard that passes by not
	# running, which is the shape this lane keeps finding in other people's code.
	var src := FileAccess.get_file_as_string(BS)
	var inverted := 0
	for pair in [["keycode\\s*==\\s*KEY_R\\b", "player_defer"],
			["keycode\\s*==\\s*KEY_L\\b", "Use R to queue"]]:
		var re := RegEx.new()
		re.compile(pair[0])
		for m in re.search_all(src):
			if src.substr(m.get_start(), 260).contains(pair[1]):
				inverted += 1
	assert_eq(inverted, 0,
		"%d raw key branch(es) contradict the bindings — R is battle_advance, L is battle_defer" % inverted)
	# CONTROL: the scanner must be able to COUNT, or zero means nothing
	var ctl := RegEx.new()
	ctl.compile("keycode\\s*==\\s*KEY_[A-Z0-9_]+\\b")
	assert_gt(ctl.search_all(src).size(), 0,
		"CONTROL: BattleScene must still contain raw keycode branches, else the sweep above is vacuous")


## And the handling must be on the ACTIONS, so a pad's shoulders and triggers reach it too and a
## Controls rebind follows. Raw keycodes are keyboard-only by construction.
func test_defer_and_advance_are_handled_as_actions() -> void:
	var src := FileAccess.get_file_as_string(BS)
	assert_true(src.contains('event.is_action_pressed("battle_defer")'),
		"defer must be action-driven here, not keycode-driven")
	assert_true(src.contains('event.is_action_pressed("battle_advance")'),
		"and advance likewise — a pad with no menu open had no route at all")


## Advance with no menu must OPEN the menu, not print an instruction to press the key you pressed.
func test_advance_reopens_the_menu_rather_than_lecturing() -> void:
	var src := FileAccess.get_file_as_string(BS)
	var at := src.find('event.is_action_pressed("battle_advance")')
	assert_gt(at, -1, "the advance branch must exist")
	var body := src.substr(at, 320)
	assert_true(body.contains("_show_win98_command_menu"),
		"advance with no menu must reopen it — queueing happens in the menu")
	assert_false(body.contains("log_message"),
		"and must not answer a control press with an instruction to press that control")
