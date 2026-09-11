extends GutTest

## Three NPCs tell the player which button to press. One of them named a control that does nothing.
##
## Mall Rat Mike said "squeeze both triggers" to open the Autobattle Editor. Measured 2026-09-11:
## the ONLY simultaneous L+R handler in src/ is GameLoop:901, inside the autogrind console block,
## and it cycles the AUTOGRIND TIER. The editor has four openers -- GameLoop:912 (F5), GameLoop:981
## (ui_menu / Start), BattleCommandMenu's Edit Autobattle row, MenuScene:1256 -- and none is L+R.
##
## 🔑 THE CLAIM CAME FROM THE DOC AND THE DOC CAME FROM NOWHERE. "Open editor | L+R together | F5"
## sat in CLAUDE.md's control table, and had reproduced into TutorialHint.gd:11, three
## BattleCommandMenu comments, and Mike's dialogue. Four citations, zero handlers. A pad player on a
## couch -- the reference context -- squeezed both triggers and nothing happened.
##
## ⛔ AND MY FIRST FIX WAS ALSO WRONG, WHICH IS WHY THE ARM BELOW LOOKS THE WAY IT DOES. I replaced
## "squeeze both triggers" with "Start on a pad" and shipped it. Start opens the editor only in
## BATTLE, and only when no character has autobattle on; in EXPLORATION -- where all three of these
## NPCs stand -- `ui_menu` calls `_open_settings_menu()`. The guard I shipped with it asserted that
## GameLoop still contains the string "ui_menu", which is true of a file that does the opposite.
## I replaced a false claim with another false claim and pinned it with a predicate narrower than
## its own name, in the same hour I published that defect class to the fleet.
##
## ⚠️ THIS TEST DEFENDS THE PROSE, NOT THE DOC. The three lines now name Start and Select, so those
## two bindings are load-bearing for authored content: if either stops existing, an NPC lies again
## and nothing else in the suite would notice. It does NOT try to detect "prose names a fake button"
## in general -- what caught this was reading the handler, and I could not design a check that would
## have caught it rather than one that merely restates the fix.

const GAMELOOP_SRC := "res://src/GameLoop.gd"
const PROJECT_CFG := "res://project.godot"
const MENU_SCENE_SRC := "res://src/ui/MenuScene.gd"
## The lines under guard. Named, so a rewrite that drops the button is visible here.
const SPEAKING_LINES := {
	"res://src/exploration/SuburbanOverworld.gd": "open the menu and hit Autobattle",
	"res://src/maps/villages/FrostholdVillage.gd": "Or the menu, then Autobattle",
	"res://src/maps/villages/HarmoniaVillage.gd": "whatever your pad calls Select",
}


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "cannot open %s" % path)
	return "" if f == null else f.get_as_text()


## ⛔ THIS STRIPPER REMOVES COMMENTS ONLY, NEVER STRING LITERALS, AND THAT IS A LANE-SPECIFIC CHOICE.
## Every target here is a CALL NAME -- _open_settings_menu(), _open_autobattle_editor(, cycle_tier --
## so a quoted occurrence is not a consumer and eating strings would cost nothing. In @cowir-music's
## and @cowir-sfx's guards the string literal IS the consumer (`play_music("boss_mordaine")`), so
## stripping strings there would empty the corpus and report every bed orphaned. Same defect class,
## inverted remedy: check which side your consumers live on before copying this.
##
## ⛔ COMMENTS ARE BLANKED BEFORE EVERY SCAN. @cowir-controller, 2026-09-11: a source-text pin is
## defeated by the realistic removal, not the tidy one — nobody deletes a branch without leaving the
## comment that explained it, so `contains("_open_settings_menu()")` stays true of a file where the
## CALL is gone and only its epitaph remains. Their guard caught "delete the keycode" and missed
## "delete it, leave a comment", which is the version that actually happens.
## Line count is preserved so the offset arithmetic below still lines up.
func _strip_comments(src: String) -> String:
	var out: PackedStringArray = []
	for line in src.split("\n"):
		var text: String = str(line)
		if text.strip_edges().begins_with("#"):
			out.append("")
			continue
		out.append(_code_before_comment(text))
	return "\n".join(out)


## ⚠️ THE FIRST `#` IS NOT NECESSARILY THE COMMENT. My first version checked the quote parity before
## `find("#")` and bailed when it was odd -- so `var c := "#ff0000"  # the real comment` kept its
## comment and the pin went hollow again. Walk the line and cut at the first `#` OUTSIDE a string.
func _code_before_comment(line: String) -> String:
	var in_string := false
	var quote := ""
	var i := 0
	while i < line.length():
		var ch := line[i]
		if in_string:
			if ch == "\\":
				i += 2
				continue
			if ch == quote:
				in_string = false
		elif ch == "\"" or ch == "'":
			in_string = true
			quote = ch
		elif ch == "#":
			return line.substr(0, i)
		i += 1
	return line


func _read_code(path: String) -> String:
	return _strip_comments(_read(path))


## ⛔ THIS ARM REPLACES ONE THAT WAS HOLLOW. It asserted `src.contains("ui_menu")` and called that
## "Start opens the editor" -- true that the string is present, silent on what the branch DOES.
## In EXPLORATION, where these NPCs stand, ui_menu opens SETTINGS. The pad route to the editor is
## the overworld menu. Both halves are pinned below, and the settings one is pinned deliberately:
## it is the claim I got wrong, so it is the one that must red if it ever changes.
func test_the_pad_route_to_the_editor_is_the_menu_not_start() -> void:
	var src := _read_code(GAMELOOP_SRC)
	assert_gt(src.length(), 1000, "CONTROL: GameLoop source did not load")
	assert_true(src.contains("_toggle_autobattle_editor()"),
		"CONTROL: the editor opener is gone entirely, so the arms below mean nothing")

	var at := src.find("elif current_state == LoopState.EXPLORATION:")
	assert_gt(at, -1, "CONTROL: no EXPLORATION arm found in the ui_menu handler")
	if at < 0:
		return
	var branch := src.substr(at, 900)
	assert_true(branch.contains("_open_settings_menu()"),
		"Start in exploration no longer opens Settings — if it now opens the editor, the NPC lines can say so")
	assert_false(branch.contains("_toggle_autobattle_editor"),
		"CONTROL: the exploration arm must NOT be the editor path, or this test is measuring the battle one")

	var menu := _read_code(MENU_SCENE_SRC)
	assert_gt(menu.length(), 1000, "CONTROL: MenuScene source did not load")
	assert_true(menu.contains("_open_autobattle_editor("),
		"the overworld menu no longer opens the editor — two NPCs now send pad players nowhere")


func test_select_really_toggles_autobattle_for_everyone() -> void:
	var cfg := _read(PROJECT_CFG)
	assert_gt(cfg.length(), 500, "CONTROL: project.godot did not load")
	var idx := cfg.find("battle_toggle_auto={")
	assert_gt(idx, -1, "battle_toggle_auto is gone — Harmonia's elder names a button that is unbound")
	if idx < 0:
		return
	var block := cfg.substr(idx, 700)
	assert_true(block.contains("InputEventJoypadButton"),
		"battle_toggle_auto has no PAD binding left, so 'whatever your pad calls Select' names nothing")
	assert_true(block.contains("InputEventKey"),
		"battle_toggle_auto has no KEY binding left, so the F6 half of that line is wrong too")


## The false claim itself, pinned: if L+R ever DOES open the editor, this reds and whoever wired it
## updates CLAUDE.md and Mike's line together instead of leaving a fifth stale citation.
func test_l_plus_r_together_still_means_the_autogrind_tier() -> void:
	var src := _read_code(GAMELOOP_SRC)
	var idx := src.find("JOY_BUTTON_LEFT_SHOULDER")
	assert_gt(idx, -1, "CONTROL: no L+R handler found at all — this test is measuring nothing")
	if idx < 0:
		return
	var block := src.substr(idx, 400)
	assert_true(block.contains("cycle_tier"),
		"the L+R-together handler no longer cycles the autogrind tier")
	assert_false(block.contains("_toggle_autobattle_editor"),
		"L+R now opens the editor — CLAUDE.md's table and the NPC lines say it does not; update all three")


func test_every_npc_that_names_a_button_still_names_that_button() -> void:
	var missing: Array = []
	for path in SPEAKING_LINES:
		var src := _read(path)
		if not src.contains(SPEAKING_LINES[path]):
			missing.append("%s no longer says '%s'" % [path.get_file(), SPEAKING_LINES[path]])
	assert_eq(missing, [],
		("a guarded line was rewritten and the guard above is now defending nobody: %s\n" +
		"Either restore the button name or retire its entry here — a silent drop leaves the\n" +
		"binding asserts green while the prose they defend is gone.") % str(missing))


## The thing that started it: no player-facing string in this lane may name the L+R gesture as a way
## into the editor. One line did, for months, and it read as fine.
func test_no_dialogue_in_this_lane_sends_a_pad_player_to_both_triggers() -> void:
	var offenders: Array = []
	var files_read := 0
	for dir_path in ["res://src/exploration", "res://src/maps/villages"]:
		var dir := DirAccess.open(dir_path)
		assert_not_null(dir, "CONTROL: cannot open %s" % dir_path)
		if dir == null:
			continue
		for f in dir.get_files():
			if not f.ends_with(".gd"):
				continue
			files_read += 1
			var src := _read("%s/%s" % [dir_path, f])
			for line in src.split("\n"):
				var stripped := str(line).strip_edges()
				if stripped.begins_with("#"):
					continue
				var low := stripped.to_lower()
				if not low.contains("\""):
					continue
				if low.contains("both triggers") or low.contains("l+r"):
					offenders.append("%s: %s" % [f, stripped.substr(0, 80)])
	assert_gt(files_read, 15, "CONTROL: only %d scripts scanned — the sweep is broken" % files_read)
	assert_eq(offenders, [],
		"player-facing text sending a pad player to L+R, which cycles the autogrind tier: %s" % str(offenders))


## The instrument itself, both directions. @cowir-music, 2026-09-11: a comment stripper has TWO ways
## to be wrong and mutation arms tend to cover one -- every arm I ran asked whether it lets something
## THROUGH, none asked whether it still lets the right things through. Over-stripping is the quieter
## failure: it would eat the calls these pins look for and report them all absent, which reads as a
## real regression. This pins both sides on the helper directly, so neither needs a GameLoop mutation.
func test_the_comment_stripper_cuts_comments_and_nothing_else() -> void:
	var cases := [
		["x = 1  # gone", "x = 1  ", "a trailing comment must go"],
		["\tcall()  # _open_settings_menu() used to run here", "\tcall()  ", "the epitaph case -- this is the whole point"],
		["var h := \"#ff0000\"", "var h := \"#ff0000\"", "a # inside a string is NOT a comment"],
		["if \"#ff0000\" != \"\": call()  # gone", "if \"#ff0000\" != \"\": call()  ", "a quoted # must not hide a later real comment"],
		["var s := '#hash'  # gone", "var s := '#hash'  ", "single quotes count as string too"],
		["var plain := 42", "var plain := 42", "a line with no # is returned untouched"],
	]
	var wrong: Array = []
	for c in cases:
		var got: String = _code_before_comment(str(c[0]))
		if got != str(c[1]):
			wrong.append("%s\n  in:  '%s'\n  got: '%s'\n  want:'%s'" % [str(c[2]), str(c[0]), got, str(c[1])])
	assert_eq(wrong, [], "the comment stripper is wrong on:\n%s" % "\n".join(PackedStringArray(wrong)))

	## @cowir-deploy / @cowir-ai's sixth costume, 2026-09-11: an ESCAPED BACKSLASH ending a string.
	## A lookbehind check (`c == quote and line[i-1] != "\\"`) sees the backslash and decides the
	## quote is escaped -- but that backslash was itself escaped, so the string really ended, and the
	## comment after it stays scannable. Built with concatenation rather than escape soup so the
	## intent survives reading: the line is   var q := "a\\"  # gone
	var bs := "\\"
	var esc_line: String = "var q := \"a" + bs + bs + "\"  # gone"
	var esc_want: String = "var q := \"a" + bs + bs + "\"  "
	assert_eq(_code_before_comment(esc_line), esc_want,
		"an escaped backslash closed the string but the cutter thought the quote was escaped, " +
		"so the comment after it survived into the scan")

	## Full-line comments are blanked by _strip_comments, not by the cutter, so check that separately
	## -- and check the line COUNT survives, because the substr windows above depend on it.
	var src := "a = 1\n\t# dead\nb = 2  # tail\n"
	var stripped := _strip_comments(src)
	assert_eq(stripped.split("\n").size(), src.split("\n").size(),
		"line count changed, so every substr window in this file is now measuring the wrong bytes")
	assert_false(stripped.contains("dead"), "a full-line comment survived")
	assert_false(stripped.contains("tail"), "a trailing comment survived")
	assert_true(stripped.contains("a = 1") and stripped.contains("b = 2"), "real code was eaten")
