extends GutTest

## The Lost Cartographer's 6 authored lines shipped in v3.33.223 going to stdout only — DragonCave's `_get_boss_intro_dialogue` fallback is `print()`.

const DUNGEON_DIR := "res://src/maps/dungeons"
const CUTSCENE_DIR := "res://data/cutscenes"


func _dungeon_scripts() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DUNGEON_DIR)
	assert_not_null(dir, "dungeons dir must open")
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd") and f != "DragonCave.gd":
			out.append(f)
	return out


func _src(f: String) -> String:
	return FileAccess.get_file_as_string("%s/%s" % [DUNGEON_DIR, f])


## Authored lines with no cutscene id reach `print()` and nothing else — the player never sees them.
func test_every_dungeon_with_authored_boss_lines_declares_a_cutscene() -> void:
	var scripts := _dungeon_scripts()
	assert_gt(scripts.size(), 0, "the sweep must find dungeon scripts, else it passes vacuously")
	var console_only: Array = []
	for f in scripts:
		var s := _src(f)
		if not s.contains("func _get_boss_intro_dialogue"):
			continue
		if not s.contains('boss_cutscene_id = "'):
			console_only.append(f)
	assert_eq(console_only.size(), 0,
		"these dungeons author boss dialogue but declare no boss_cutscene_id, so DragonCave's " +
		"fallback prints the lines to stdout and the player sees nothing: " + str(console_only))


## A cutscene id pointing at no file falls through the same fallback, silently.
func test_every_declared_boss_cutscene_id_resolves_to_a_file() -> void:
	var checked := 0
	for f in _dungeon_scripts():
		var s := _src(f)
		var re := RegEx.new()
		re.compile('boss_cutscene_id\\s*=\\s*"(?<id>[a-z0-9_]+)"')
		for m in re.search_all(s):
			var id := m.get_string("id")
			checked += 1
			assert_true(FileAccess.file_exists("%s/%s.json" % [CUTSCENE_DIR, id]),
				"%s declares boss_cutscene_id '%s' but no such cutscene exists — DragonCave " % [f, id] +
				"falls back to the console print, which reads on screen as a boss with no intro")
	assert_gt(checked, 0, "at least one dungeon must declare a cutscene id, else this proves nothing")


## CONTROL: the sweep must SEE a dungeon known to carry both, or the two tests above are free.
func test_sweep_reaches_a_dungeon_known_to_have_both() -> void:
	var s := _src("ContrarianDepths.gd")
	assert_gt(s.length(), 0, "ContrarianDepths must be readable — if not, the sweep is looking at nothing")
	assert_true(s.contains("func _get_boss_intro_dialogue"),
		"ContrarianDepths must still author boss lines — it is this guard's known-present member")
	assert_true(s.contains('boss_cutscene_id = "'),
		"and must still declare the cutscene that carries them to the screen")


## The fallback is print-only by design; if that ever changes this guard's premise is void.
func test_the_fallback_is_still_console_only() -> void:
	var s := FileAccess.get_file_as_string("%s/DragonCave.gd" % DUNGEON_DIR)
	var i := s.find("var lines = _get_boss_intro_dialogue()")
	assert_gt(i, -1, "the fallback call site must still exist")
	var body := s.substr(i, 400)
	assert_true(body.contains("print("),
		"the fallback still prints. If it ever renders on screen instead, this whole guard " +
		"becomes unnecessary rather than wrong — delete it then, do not weaken it")
