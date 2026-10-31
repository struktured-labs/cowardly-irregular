extends GutTest

## His play log, 2026-10-31: every Cave Rat King win printed "'cutscene_flag_chapter3_complete' set but not referenced by any
## _get_pending_story_cutscene gate -- post-defeat cutscene will NOT fire (subclass typo?)". False on both counts: the cave
## BACK-FILLS chapter 3's own completion flag for saves that predate its setter, and the gate chain reads that flag. The check
## knew only a hand-kept list of ten defeat flags, so a correct back-fill read as a typo -- a warning that cries wolf in the
## player's own log teaches everyone to ignore the real one.

const GAME_LOOP := "res://src/GameLoop.gd"
const DUNGEONS_DIR := "res://src/maps/dungeons"
const SPEC_OPEN := "pending_boss_defeat = {"

var _loop: Node


func before_each() -> void:
	_loop = load(GAME_LOOP).new()


func after_each() -> void:
	if is_instance_valid(_loop):
		_loop.free()


func test_a_completion_flag_a_boss_backfills_is_not_a_typo() -> void:
	assert_true(_loop._is_known_defeat_flag("cutscene_flag_chapter3_complete"),
		"the Rat King's back-filled chapter-3 completion flag is read by the gate chain, so it must not warn")
	assert_true(_loop._is_known_defeat_flag("cutscene_flag_rat_king_defeated"), "CONTROL: a listed defeat flag is accepted")
	## The point of the warning, kept: a misspelt flag no gate reads must still be caught.
	assert_false(_loop._is_known_defeat_flag("cutscene_flag_wardin_industrial_defeated"),
		"a TYPO must still warn -- accepting every flag would silence the guard instead of fixing it")


## The cutscene_flag_* strings inside each `pending_boss_defeat = {...}` a dungeon writes DIRECTLY. The DragonCave route
## (defeat_cutscene_flags) is judged by test_defeat_cutscene_flag_audit; this form was judged by nothing.
func _directly_written_flags() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DUNGEONS_DIR)
	if dir == null:
		return out
	var rx := RegEx.create_from_string('"(cutscene_flag_[a-z0-9_]+)"')
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string(DUNGEONS_DIR.path_join(f))
		var at := src.find(SPEC_OPEN)
		while at >= 0:
			var end := src.find("\n\t}", at)
			var block := src.substr(at, (end - at) if end > at else 400)
			for m in rx.search_all(block):
				out.append([f, m.get_string(1)])
			at = src.find(SPEC_OPEN, at + SPEC_OPEN.length())
	return out


func test_every_flag_a_dungeon_writes_directly_is_consumed() -> void:
	var written := _directly_written_flags()
	## Floor: the Whispering Cave writes two today. Without it this arm would pass on a walk that found nothing.
	assert_gte(written.size(), 2, "CONTROL: directly written defeat flags were found (%d)" % written.size())
	for pair in written:
		assert_true(_loop._is_known_defeat_flag(pair[1]),
			"%s writes %s, which no gate consumes: its post-defeat cutscene will never fire" % [pair[0], pair[1]])
