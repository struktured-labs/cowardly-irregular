extends GutTest

## A page jump (L/R, PageUp/PageDown) clamps at a long list's ends, and eight menus played menu_move even when the clamp held the selection where it was.
## They now share MenuPaging.play_step_cue: a jump that moved plays menu_move, one that moved nothing plays menu_error. Read through cooldown stamps, whose CONTROL is the first arm.

const JUKEBOX := "res://src/ui/JukeboxMenu.gd"
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
## A clamped page jump: the selection is assigned clampi(<it> + page * PAGE_ROWS, …).
const CLAMP_SHAPE := "+ page * MenuPaging.PAGE_ROWS"

var _jb_last: int = 0


func before_each() -> void:
	_jb_last = (load(JUKEBOX) as GDScript).get("_last_selected")
	SoundManager._sfx_cooldowns.clear()


func after_each() -> void:
	(load(JUKEBOX) as GDScript).set("_last_selected", _jb_last)
	SoundManager._sfx_cooldowns.clear()
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()


func _stamped(key: String) -> bool:
	return SoundManager._sfx_cooldowns.has(key)


func _page(m: Node, key: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.pressed = true
	m._input(ev)


func _jukebox(start: int) -> Node:
	(load(JUKEBOX) as GDScript).set("_last_selected", start)
	var m: Node = load(JUKEBOX).new()
	add_child_autofree(m)
	await get_tree().process_frame
	SoundManager._sfx_cooldowns.clear()
	return m


func test_the_cue_oracle_can_see_a_cue() -> void:
	assert_false(_stamped("menu_error"), "FLOOR: the stamp table starts clean")
	SoundManager.play_ui("menu_error")
	assert_true(_stamped("menu_error"), "CONTROL: play_ui leaves a stamp, or every arm here measures nothing")


func test_the_shared_cue_tells_a_move_from_a_stand() -> void:
	MenuPaging.play_step_cue(3, 13)
	assert_true(_stamped("menu_move"), "a jump that moved must play menu_move")
	assert_false(_stamped("menu_error"), "a jump that moved must not play the refusal")
	SoundManager._sfx_cooldowns.clear()
	MenuPaging.play_step_cue(7, 7)
	assert_true(_stamped("menu_error"), "a jump that moved nothing must play the refusal")
	assert_false(_stamped("menu_move"), "a jump that moved nothing still played menu_move")


func test_a_page_from_the_top_still_moves_and_clicks() -> void:
	var m: Node = await _jukebox(0)
	var n: int = (m.get("TRACKS") as Array).size()
	assert_gt(n, MenuPaging.PAGE_ROWS, "CONTROL: the jukebox is longer than one page")
	_page(m, KEY_PAGEDOWN)
	assert_eq(int(m.get("selected_index")), MenuPaging.PAGE_ROWS, "CONTROL: PageDown moved one page")
	assert_true(_stamped("menu_move"), "a real page jump must still play menu_move")
	assert_false(_stamped("menu_error"), "a real page jump must not play the refusal")


func test_a_page_past_either_end_is_refused() -> void:
	var m: Node = await _jukebox(0)
	_page(m, KEY_PAGEUP)
	assert_eq(int(m.get("selected_index")), 0, "PageUp at the top stayed at the top")
	assert_false(_stamped("menu_move"), "PageUp at the top moved nothing and still played menu_move")
	assert_true(_stamped("menu_error"), "PageUp at the top was not refused")
	var last: int = (m.get("TRACKS") as Array).size() - 1
	var m2: Node = await _jukebox(last)
	assert_eq(int(m2.get("selected_index")), last, "CONTROL: the jukebox opened on its last track")
	_page(m2, KEY_PAGEDOWN)
	assert_eq(int(m2.get("selected_index")), last, "PageDown at the end stayed at the end")
	assert_false(_stamped("menu_move"), "PageDown at the end moved nothing and still played menu_move")
	assert_true(_stamped("menu_error"), "PageDown at the end was not refused")


## DERIVED: every src/ui file with a clamped page jump routes its cue through play_step_cue, never a literal menu_move after the clamp.
func test_every_clamped_page_jump_uses_the_shared_cue() -> void:
	var sites := 0
	var offenders: Array = []
	var dir := DirAccess.open("res://src/ui")
	assert_not_null(dir, "FLOOR: res://src/ui opens")
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var code: String = GdSource.code_of("res://src/ui/" + f)
		var at := code.find(CLAMP_SHAPE)
		while at != -1:
			var line_start := code.rfind("\n", at) + 1
			var line := code.substr(line_start, code.find("\n", at) - line_start)
			if "clampi(" in line or code.substr(maxi(0, line_start - 80), 80).contains("clampi("):
				sites += 1
				var tail := code.substr(at, 400)
				var cue := tail.find("play_step_cue(")
				var move := tail.find("play_ui(\"menu_move\")")
				if move != -1 and (cue == -1 or move < cue):
					offenders.append(f)
			at = code.find(CLAMP_SHAPE, at + 1)
	assert_gte(sites, 8, "CONTROL: the scan finds the clamped page jumps, got %d" % sites)
	assert_eq(offenders, [], "these clamp a page jump and then play menu_move whether it moved or not: %s" % [offenders])
