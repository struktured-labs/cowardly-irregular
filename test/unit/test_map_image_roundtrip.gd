extends GutTest

## The W1 overworld map is a PNG. These pins are what stands between it and silent damage.
##
## PROVENANCE OF THE GOLDEN VALUES. They were derived from the ASCII literal that
## OverworldScene.gd carried until fbcb65f8, at a moment when a round-trip test proving
## PNG == ASCII was green in a full suite. So they describe the PRE-migration map, not the
## image they now guard -- that ordering is the whole reason they are worth anything. Had
## they been read out of the PNG, they would assert only that the PNG equals itself.
##
## WHAT THIS EXISTS TO CATCH. 12 of the 25 map characters appear EXACTLY ONCE: every
## landmark is a single pixel. `_register_spawn_point` keys on the CHARACTER, so one stray
## paint stroke deletes a dragon cave's arrival coordinate with no error anywhere -- the
## symptom is a player walking to where a cave used to be. A census cannot catch a landmark
## that MOVED (every count still balances), so the coordinates are pinned, not the counts.

const Loader := preload("res://src/exploration/MapImageLoader.gd")
const SceneScript := preload("res://src/exploration/OverworldScene.gd")

const MAP_PNG := "res://data/maps/overworld_w1.png"
const SCENE_GD := "res://src/exploration/OverworldScene.gd"

const GOLDEN_W := 100
const GOLDEN_H := 70

const GOLDEN_LANDMARKS := {
	"1": ["10,4"],
	"2": ["75,6"],
	"3": ["10,57"],
	"4": ["82,56"],
	"C": ["3,20", "2,21"],
	"D": ["10,55"],
	"E": ["29,6"],
	"G": ["73,8"],
	"H": ["6,2", "81,50"],
	"I": ["81,58"],
	"P": ["39,57"],
	"V": ["4,25"],
	"W": ["9,6"],
}

const GOLDEN_CENSUS := {
	".": 3386, "1": 1, "2": 1, "3": 1, "4": 1, "B": 21, "C": 2, "D": 1,
	"E": 1, "F": 225, "G": 1, "H": 2, "I": 1, "M": 213, "P": 1, "S": 61,
	"V": 1, "W": 1, "c": 126, "d": 175, "g": 518, "i": 97, "l": 108,
	"s": 380, "~": 1675,
}


func _coords_of(rows: Array, ch: String) -> Array:
	var out: Array = []
	for y in range(rows.size()):
		var row := str(rows[y])
		for x in range(row.length()):
			if row[x] == ch:
				out.append("%d,%d" % [x, y])
	return out


func test_the_palette_loads_and_is_collision_free() -> void:
	# MAP_PNG here and MAP_IMAGE in the scene are two names for one file. Redundant sources
	# get an AGREEMENT assert, never a precedence rule -- if both agree the question is moot.
	assert_eq(MAP_PNG, SceneScript.MAP_IMAGE, "the test and the scene must load the same image")

	var err: String = Loader.ensure_palette()
	assert_eq(err, "", "palette must load cleanly -- a collision or a missing section is fatal")
	var chars: Array = Loader.palette_chars()
	assert_gt(chars.size(), 20, "palette has %d entries -- too few; the read broke" % chars.size())
	# named members, not a count: a count control passes on an empty parse
	assert_true("~" in chars, "palette knows water")
	assert_true("4" in chars, "palette knows the fire dragon cave -- a single-pixel landmark")
	assert_false("Z" in chars, "a fabricated character is absent, so membership means something")


## The image and the declared constants are two sources for one number. `_generate_map`
## loops `for y in range(MAP_HEIGHT)`, so an image shorter than the constant reads past its
## own data and a taller one is silently cropped -- neither raises anything.
func test_the_image_agrees_with_the_declared_dimensions() -> void:
	var rows: Array = Loader.load_rows(MAP_PNG)
	assert_gt(rows.size(), 10, "PNG side is non-empty -- an empty result means the load FAILED")
	assert_eq(rows.size(), GOLDEN_H, "row count")
	assert_eq(str(rows[0]).length(), GOLDEN_W, "row width")
	assert_eq(SceneScript.MAP_HEIGHT, GOLDEN_H, "OverworldScene.MAP_HEIGHT must track the image")
	assert_eq(SceneScript.MAP_WIDTH, GOLDEN_W, "OverworldScene.MAP_WIDTH must track the image")


## Landmark characters are DERIVED from the palette's own `landmarks` section, never listed
## here. The first version of this file hand-listed them and was wrong on its first run:
## "C" and "H" each appear TWICE in W1, so an eyeballed singleton list asserted a falsehood
## about the map it was guarding.
func test_every_landmark_survives_at_its_exact_coordinates() -> void:
	var rows: Array = Loader.load_rows(MAP_PNG)
	var landmarks: Array = Loader.landmark_chars()

	assert_gt(landmarks.size(), 5, "derived %d landmark chars from the palette -- the derivation broke" % landmarks.size())
	assert_true("4" in landmarks, "the palette's landmark set includes the fire dragon cave")
	assert_false("~" in landmarks, "water is terrain, not a landmark -- so the sections are really separate")
	assert_gt(rows.size(), 10, "PNG side non-empty -- otherwise the comparisons below are vacuous")

	var problems: Array = []
	var total_placed := 0
	for ch in landmarks:
		var got := _coords_of(rows, ch)
		var want: Array = GOLDEN_LANDMARKS.get(ch, [])
		total_placed += want.size()
		if got != want:
			problems.append("'%s': golden [%s] but png [%s]" % [ch, ", ".join(want), ", ".join(got)])
	# without this, a run where the golden table was emptied would report zero problems
	assert_eq(total_placed, 15, "the golden table must describe 15 landmark placements")
	assert_true(problems.is_empty(), "landmark placement changed:\n  %s" % "\n  ".join(problems))


func test_no_character_is_gained_or_dropped_anywhere() -> void:
	var rows: Array = Loader.load_rows(MAP_PNG)
	assert_gt(rows.size(), 10, "PNG side non-empty")

	var census := {}
	for row in rows:
		for ch in str(row):
			census[ch] = int(census.get(ch, 0)) + 1

	var total := 0
	for k in census:
		total += int(census[k])
	assert_eq(total, GOLDEN_W * GOLDEN_H, "every tile must be accounted for")

	var diffs: Array = []
	var keys := {}
	for k in census: keys[k] = true
	for k in GOLDEN_CENSUS: keys[k] = true
	for ch in keys:
		var a: int = int(GOLDEN_CENSUS.get(ch, 0))
		var b: int = int(census.get(ch, 0))
		if a != b:
			diffs.append("'%s': golden %d vs png %d" % [ch, a, b])
	assert_true(diffs.is_empty(), "per-character counts differ:\n  %s" % "\n  ".join(diffs))


## Two sources for one surface is the trap this migration exists to close, so the old ASCII
## literal must be GONE -- not merely unused. An unread literal drifts from the image and
## the next author cannot tell which one the game draws.
func test_the_ascii_literal_is_gone() -> void:
	var src := FileAccess.get_file_as_string(SCENE_GD)
	assert_gt(src.length(), 1000, "read %d bytes of OverworldScene.gd -- the read broke" % src.length())
	assert_true(src.contains("MapImageLoaderScript.load_rows"),
		"OverworldScene must load the image (control: this file IS the one being read)")
	# NOT `contains("= [")` -- that is a PREFIX of the `= []` the new code writes, so it
	# fired on the correct file. The declaration is discriminated by the newline that only
	# a multi-line literal has, and a terrain row is matched directly as a second signal.
	assert_false(src.contains("var map_data: Array[String] = [\n"),
		"OverworldScene still carries an inline map literal -- two sources for one surface")
	assert_false(src.contains("\"~~~~~~~~~~"),
		"a terrain row literal is still present in OverworldScene.gd")


## The pins above guard a FILE. This arm guards that the file reaches the GAME: without it
## every assertion here would still pass if `_generate_map` quietly stopped reading the
## image, and the pins would be defending an artifact nothing loads.
func test_the_image_reaches_the_running_scene() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var scene = SceneScript.new()
	vp.add_child(scene)
	await get_tree().physics_frame

	assert_gt(scene.spawn_points.size(), 8,
		"only %d spawn points registered -- the map did not reach _register_spawn_point" % scene.spawn_points.size())

	# Positions are recomputed from the GOLDEN coordinates through the scene's own
	# constants, so a landmark pixel that moved lands nowhere and is caught here too.
	var landed := 0
	var missing: Array = []
	for ch in GOLDEN_LANDMARKS:
		for coord in GOLDEN_LANDMARKS[ch]:
			var parts: PackedStringArray = str(coord).split(",")
			var off: Vector2i = SceneScript.SPAWN_CLEARANCE.get(ch, Vector2i.ZERO)
			var want := Vector2(
				(int(parts[0]) + off.x) * SceneScript.TILE_SIZE + SceneScript.TILE_SIZE / 2,
				(int(parts[1]) + off.y) * SceneScript.TILE_SIZE + SceneScript.TILE_SIZE / 2)
			var found := false
			for key in scene.spawn_points:
				if scene.spawn_points[key] == want:
					found = true
					break
			if found:
				landed += 1
			else:
				missing.append("'%s' at %s" % [ch, coord])

	# 11, and each of the 4 misses is explained rather than absorbed into a round number:
	# 'H' x2 has no arm in _register_spawn_point at all, and BOTH 'C' tiles are moved after
	# registration -- `cave_entrance` is rewritten one tile east at OverworldScene.gd:337
	# and `castle_entrance` is anchored two tiles east. I predicted 12 and measured 11; the
	# second writer on `cave_entrance` is the difference, and it is the interesting part.
	assert_eq(landed, 11,
		"%d of 15 golden landmark positions reached spawn_points; unmatched: %s" % [landed, ", ".join(missing)])
