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
## ⚠️ THIS TEST DEFENDS THE PROSE, NOT THE DOC. The three lines now name Start and Select, so those
## two bindings are load-bearing for authored content: if either stops existing, an NPC lies again
## and nothing else in the suite would notice. It does NOT try to detect "prose names a fake button"
## in general -- what caught this was reading the handler, and I could not design a check that would
## have caught it rather than one that merely restates the fix.

const GAMELOOP_SRC := "res://src/GameLoop.gd"
const PROJECT_CFG := "res://project.godot"
## The lines under guard. Named, so a rewrite that drops the button is visible here.
const SPEAKING_LINES := {
	"res://src/exploration/SuburbanOverworld.gd": "Start on a pad",
	"res://src/maps/villages/FrostholdVillage.gd": "Or Start, if your hands are already full",
	"res://src/maps/villages/HarmoniaVillage.gd": "whatever your pad calls Select",
}


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "cannot open %s" % path)
	return "" if f == null else f.get_as_text()


func test_start_really_opens_the_autobattle_editor() -> void:
	var src := _read(GAMELOOP_SRC)
	assert_gt(src.length(), 1000, "CONTROL: GameLoop source did not load")
	assert_true(src.contains("_toggle_autobattle_editor()"),
		"CONTROL: the editor opener is gone entirely, so the arms below mean nothing")
	## ui_menu is Start. Three NPCs now tell pad players this is how the editor opens.
	assert_true(src.contains("ui_menu"),
		"GameLoop no longer handles ui_menu — Start does not open the editor and two NPCs now lie")


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
