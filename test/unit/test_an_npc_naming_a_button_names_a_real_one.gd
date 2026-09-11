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


## ⛔ THIS ARM REPLACES ONE THAT WAS HOLLOW. It asserted `src.contains("ui_menu")` and called that
## "Start opens the editor" -- true that the string is present, silent on what the branch DOES.
## In EXPLORATION, where these NPCs stand, ui_menu opens SETTINGS. The pad route to the editor is
## the overworld menu. Both halves are pinned below, and the settings one is pinned deliberately:
## it is the claim I got wrong, so it is the one that must red if it ever changes.
func test_the_pad_route_to_the_editor_is_the_menu_not_start() -> void:
	var src := _read(GAMELOOP_SRC)
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

	var menu := _read(MENU_SCENE_SRC)
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
	var src := _read(GAMELOOP_SRC)
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
