extends GutTest

## Building a tileset must not write into the player's user:// directory.
##
## `BaseTileGenerator.create_tileset()` dumped the assembled atlas to
## `user://<name>.png` behind `OS.is_debug_build()` alone — which is TRUE in every
## headless GUT run. Six subclasses override the name, so a suite that constructs
## the overworlds left six PNGs (~110 KB) in the player's directory. Measured
## 2026-08-06: all six present, all stamped that day.
##
## They are debug artifacts rather than player data, and they overwrite in place.
## The reason it still mattered is the shape: an ungated `src/` writer reaching
## `user://` on a path tests take. The same audit that afternoon found an ungated
## writer whose blast radius was two bytes and another whose was a whole profile;
## nothing about the code decides which you get.
##
## WHY THE FLAG SELF-DEFAULTS. AutogrindSystem's `_test_disable_persistence` is set
## BY each test — and 19 of its 48 tests never set it, which is how that directory
## got written all day. Here that failure would be certain rather than likely:
## generators are constructed TRANSITIVELY by overworld scenes, so a test builds
## `IndustrialOverworld` and never mentions this class. Measured: 8 overworld
## scenes construct one, 2 test files name one. An opt-in flag would sit false
## forever. It defaults from the headless probe SoundManager already uses for the
## same reason, and remains settable so the editor is untouched.

const GEN_DIR := "res://src/exploration"


func _generator_paths() -> Array:
	var out: Array = []
	var dir := DirAccess.open(GEN_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not (f.ends_with(".gd") and f.contains("TileGenerator")):
			continue
		var script = load(GEN_DIR + "/" + f)
		if script != null and script.get_script_constant_map().has("PALETTES"):
			out.append(GEN_DIR + "/" + f)
	out.sort()
	return out


## Every `user://*.png` currently present — the surface the dump would land on.
func _user_pngs() -> Array:
	var out: Array = []
	var dir := DirAccess.open("user://")
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".png"):
			out.append(f)
	out.sort()
	return out


## The default must come from the environment, not from a test remembering to set
## it. This drives the real class rather than re-deriving the expression.
func test_the_dump_is_suppressed_by_default_under_headless() -> void:
	assert_true(DisplayServer.get_name() == "headless" or OS.has_feature("headless"),
		"this suite runs headless — if that stops being true the default below is not the one under test")
	assert_true(BaseTileGenerator._test_disable_persistence,
		"the suppression must be ON without any test setting it — generators are built transitively, so an opt-in flag would never be set by the tests that reach them")


## The real check: build every generator's tileset and assert nothing appeared.
## The tile count is the control — without it, "no new files" is equally true of a
## generator that never ran, which is the vacuous-zero shape this audit kept hitting.
func test_building_every_tileset_writes_nothing_to_user() -> void:
	var paths := _generator_paths()
	assert_gt(paths.size(), 0, "found tile generators — zero would pass this file for free")

	var before := _user_pngs()
	var built := 0
	var total_tiles := 0
	var offenders: Array = []

	for path in paths:
		var gen = load(path).new()
		if gen == null:
			continue
		if gen is Node:
			add_child_autofree(gen)
		var ts: TileSet = gen.create_tileset()
		built += 1
		if ts == null:
			offenders.append("%s: create_tileset() returned null" % path.get_file())
			continue
		var src_count := ts.get_source_count()
		for i in range(src_count):
			var src = ts.get_source(ts.get_source_id(i))
			if src is TileSetAtlasSource:
				total_tiles += (src as TileSetAtlasSource).get_tiles_count()

	var after := _user_pngs()

	assert_gt(built, 0, "constructed at least one generator")
	assert_true(offenders.is_empty(), "%d generator(s) failed to build:\n  %s" % [offenders.size(), "\n  ".join(offenders)])
	# THE CONTROL: the work must actually have happened, or the assertion below is vacuous.
	assert_gt(total_tiles, 0,
		"built %d generator(s) but produced ZERO tiles — the atlas path did not run, so 'nothing was written' proves nothing" % built)

	var added: Array = []
	for f in after:
		if not (f in before):
			added.append(f)
	assert_true(added.is_empty(),
		"building %d tilesets (%d tiles) created %d file(s) in the player's user:// directory: %s" % [
			built, total_tiles, added.size(), ", ".join(added)])
