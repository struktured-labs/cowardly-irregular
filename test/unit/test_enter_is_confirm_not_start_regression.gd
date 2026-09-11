extends GutTest

## ENTER is a CONFIRM key that also fires the START action, and in battle that opened the
## autobattle editor mid-fight — struktured's 2026-08-30 complaint about Escape, still live for the
## key most likely to be pressed.
##
## MEASURED against the InputMap, not read off project.godot:
##   ui_accept -> Z, Enter, Space, JOY1
##   ui_menu   -> Enter, Escape, JOY6, JOY7
## Enter is the ONLY key on both. Escape was special-cased in GameLoop's BATTLE branch after the
## artist read it as an inescapable pause menu; Enter was not, so one Confirm press toggled
## autobattle off or opened the editor, and BattleScene's own "reopen the menu on Space/Enter/Z"
## branch below it never ran because GameLoop consumed the press first.
##
## CROSS-NODE, which is why neither of this lane's input ratchets could see it: the shadow ratchet
## is same-function, the contradiction ratchet compares a raw key against the action that binds it,
## and this is one action shadowing another from a different node. Verified headless that
## set_input_as_handled() really does stop _input for later nodes, so the collision only bites in
## the window where nothing upstream consumes — the same window that hid the R/L inversion.

const GL_PATH := "res://src/GameLoop.gd"
const BS_PATH := "res://src/battle/BattleScene.gd"


## Bounded at the branch's own end, never a fixed character window. A fixed window is a claim about
## LAYOUT; the guard's reach is a claim about CONTROL FLOW. I shipped that bug in this lane's
## deadzone test earlier today — 2000 chars where the answer sat at 2108.
func _battle_ui_menu_branch() -> String:
	var src := FileAccess.get_file_as_string(GL_PATH)
	var handler := src.find("if event.is_action_pressed(\"ui_menu\"):")
	assert_gt(handler, -1, "the ui_menu handler must exist")
	var start := src.find("elif current_state == LoopState.BATTLE:", handler)
	assert_gt(start, handler, "the BATTLE arm must sit inside the ui_menu handler")
	var stop := src.find("elif current_state == LoopState.EXPLORATION:", start)
	assert_gt(stop, start, "the EXPLORATION arm must follow it — that is this branch's end")
	return _code_only(src.substr(start, stop - start))


## COMMENTS ARE NOT CODE, and this guard was HOLLOW without the distinction. Measured 2026-09-11:
## delete the real `keycode in [KEY_ESCAPE, KEY_ENTER]` arm but leave a comment saying KEY_ENTER,
## and find() returns the COMMENT — the ordering assert still holds and the file scores GREEN with
## Enter opening the editor again. Arm 1 (drop KEY_ENTER outright) was caught; only the commented
## form survived, which is the realistic shape, because that is what a person leaves behind when
## they remove a branch. Same discriminator as _frozen_code_lines in the interact-prompt ratchet;
## I fixed it there and left it here — @cowir-autogrind hit the identical bare-find() class today.
## ⛔ A THIRD COSTUME. My first fix blanked FULL-LINE comments only, so
## `keycode in [KEY_ESCAPE]:  # KEY_ENTER dropped for now` was still hollow — measured, EC=0.
## @cowir-overworld named it before I tested it. Trailing comments must go too, and the cut has to
## be quote-aware or a `#` inside a string literal would truncate real code.
func _code_only(text: String) -> String:
	var out := ""
	for raw in text.split("\n"):
		out += _strip_comment(raw) + "\n"   # line count preserved so substr offsets stay comparable
	return out


func _strip_comment(line: String) -> String:
	var quote := ""
	for i in range(line.length()):
		var c := line[i]
		if quote != "":
			if c == quote and (i == 0 or line[i - 1] != "\\"):
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
	return line


func _keys_for(action: String) -> Array[String]:
	var out: Array[String] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(OS.get_keycode_string(ev.keycode))
	return out


## THE DEFECT. Enter must not reach the editor-opening code, and the guard must come BEFORE it —
## a guard placed after the branch it defends is decoration.
func test_enter_cannot_open_the_autobattle_editor_mid_fight() -> void:
	var branch := _battle_ui_menu_branch()
	var guard := branch.find("KEY_ENTER")
	var opens := branch.find("_toggle_autobattle_editor()")
	assert_gt(guard, -1,
		"the BATTLE arm must special-case KEY_ENTER — ui_menu binds it, so Confirm opened the editor")
	assert_gt(opens, guard,
		"the KEY_ENTER guard must precede _toggle_autobattle_editor, or Enter still opens it")


## Escape's guard is what this one is modelled on; losing it re-opens the 2026-08-30 report.
func test_escape_keeps_its_own_guard() -> void:
	var branch := _battle_ui_menu_branch()
	assert_gt(branch.find("KEY_ESCAPE"), -1,
		"Escape must stay excluded — struktured 2026-08-30, 'a pause menu he could not escape'")


## WHY THE GUARD EXISTS, pinned so it cannot quietly become an INERT suppression. If someone
## unbinds Enter from ui_menu at the root, this guard stops defending anything and should be
## removed rather than left as a line nobody dares touch.
func test_the_collision_the_guard_defends_still_exists() -> void:
	var accept := _keys_for("ui_accept")
	var menu := _keys_for("ui_menu")
	assert_true(accept.has("Enter"), "precondition: ui_accept must bind Enter, or this file is moot")
	assert_true(menu.has("Enter"),
		"ui_menu no longer binds Enter — the root collision is GONE, so the KEY_ENTER guard in " +
		"GameLoop's BATTLE arm is now inert and should be deleted, not kept")


## THE CONTROL. Without it, "Enter is on both lists" is unfalsifiable — a probe that returned every
## key for every action would pass the test above and prove nothing.
func test_the_probe_can_tell_the_two_actions_apart() -> void:
	var accept := _keys_for("ui_accept")
	var menu := _keys_for("ui_menu")
	assert_true(accept.has("Z"), "Z must bind ui_accept")
	assert_false(menu.has("Z"),
		"Z must NOT bind ui_menu — if it did, the probe cannot distinguish the actions at all")
	assert_true(menu.has("Escape"), "Escape must bind ui_menu — the known-present member")
	assert_false(accept.has("Escape"), "Escape must not bind ui_accept")


## The path the fix RESTORES: BattleScene already treats Space/Enter/Z as equivalent for reopening
## the command menu. Two of the three worked. If that branch stops naming Enter, the guard above is
## defending a door nobody walks through and this file needs re-reading.
func test_battlescene_still_claims_enter_reopens_the_menu() -> void:
	var src := FileAccess.get_file_as_string(BS_PATH)
	var idx := src.find("KEY_SPACE, KEY_ENTER, KEY_Z")
	assert_gt(idx, -1,
		"BattleScene must still list Enter among the keys that reopen the command menu — " +
		"that claim is what makes GameLoop eating Enter a defect rather than a preference")


## THE STRIPPER'S OWN UNIT TEST. @cowir-sfx cut at the first `#` on a line and lost real calls to
## `[color=#44ff44]` / `"BATTLE #%d"` — 84 lines in src/ carry a `#` inside a string. Mine is
## quote-aware BY CONSTRUCTION, which is exactly the kind of claim this session kept disproving, so
## it is pinned rather than reasoned. Both directions: it must cut comments AND keep code.
func test_the_comment_stripper_cuts_comments_and_keeps_code() -> void:
	# KEEP: a '#' inside a string literal is data, not a comment.
	assert_eq(_strip_comment("\tvar s = \"[color=#44ff44]hi\""), "\tvar s = \"[color=#44ff44]hi\"",
		"a # inside double quotes must NOT truncate — @cowir-sfx lost real calls this way")
	assert_eq(_strip_comment("\tvar s = 'BATTLE #%d'"), "\tvar s = 'BATTLE #%d'",
		"single quotes too")
	assert_eq(_strip_comment("\tvar s = \"it's fine\"  # trailing"), "\tvar s = \"it's fine\"  ",
		"an apostrophe INSIDE double quotes must not open a quote state and swallow the comment")
	# CUT: real comments, leading and trailing.
	assert_eq(_strip_comment("# whole line"), "", "a full-line comment must go")
	assert_eq(_strip_comment("\tcode()  # tail"), "\tcode()  ", "a trailing comment must go")
	# The line the guard actually reads must survive untouched.
	var real := "\t\t\tif event is InputEventKey and event.keycode in [KEY_ESCAPE, KEY_ENTER]:"
	assert_eq(_strip_comment(real), real, "the real guard line has no comment and must be preserved")
