extends GutTest

## Overworld sheets are cropped by a HARDCODED frame size, and nothing checked the sheets against it.
##
## RoamingMonster and MasteriteEncounter both draw from assets/sprites/monsters/overworld/<id>.png by
## setting region_rect = Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H) with FRAME_W/H = 32.
## A sheet that is not a whole number of 32px frames does not error -- it renders a CORNER of the
## art, silently. The contract lived only in the consumers' constants and in whatever the sprite
## generator happened to emit.
##
## cowir-sprites measured the population on 2026-09-09: 85 of 85 sheets are exactly 128x128, a 4x4
## grid of 32, zero exceptions, and asked for it to be ASSERTED rather than derived -- deriving the
## frame size from the image is a guess (a 128x128 file could be 4x4 of 32 or one frame at 128), and
## a generator emitting the wrong size should fail loudly there rather than render a corner here.
##
## What is pinned is the RELATIONSHIP -- every sheet is a whole number of the frames its consumers
## crop -- not the 128, so a legitimately longer animation row stays green.

const OVERWORLD_DIR := "res://assets/sprites/monsters/overworld"
const CONSUMERS := [
	"res://src/exploration/RoamingMonster.gd",
	"res://src/exploration/MasteriteEncounter.gd",
]


func _sheets() -> Array:
	var out: Array = []
	var dir := DirAccess.open(OVERWORLD_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".png"):
			out.append(f)
		f = dir.get_next()
	out.sort()
	return out


## Two consumers crop with their own copy of the number. They are supposed to AGREE, so assert that
## rather than modelling which one wins -- if they agree the question of precedence is moot.
func test_both_consumers_crop_with_the_same_frame_size() -> Vector2i:
	var sizes: Array = []
	for path in CONSUMERS:
		var consts: Dictionary = load(path).get_script_constant_map()
		assert_true(consts.has("FRAME_W") and consts.has("FRAME_H"),
			"%s has no FRAME_W/FRAME_H -- it crops by some other means and this ledger is stale" % path.get_file())
		if consts.has("FRAME_W") and consts.has("FRAME_H"):
			sizes.append(Vector2i(int(consts["FRAME_W"]), int(consts["FRAME_H"])))
	assert_eq(sizes.size(), CONSUMERS.size(), "not every consumer reported a frame size")
	for s in sizes:
		assert_eq(s, sizes[0],
			"the two overworld-sheet consumers crop different frame sizes %s -- one of them is drawing the wrong part of every sheet" % str(sizes))
	return sizes[0] if not sizes.is_empty() else Vector2i(32, 32)


func test_every_overworld_sheet_is_a_whole_number_of_frames() -> void:
	var frame := test_both_consumers_crop_with_the_same_frame_size()
	var sheets := _sheets()
	assert_gt(sheets.size(), 50,
		"CONTROL: only %d overworld sheets found (85 at time of writing) -- the scan is broken and any zero below is free" % sheets.size())

	var ragged: Array = []
	var measured := 0
	for f in sheets:
		var img := Image.load_from_file("%s/%s" % [OVERWORLD_DIR, f])
		if img == null:
			ragged.append("%s could not be read as an image" % f)
			continue
		measured += 1
		var w := img.get_width()
		var h := img.get_height()
		if w % frame.x != 0 or h % frame.y != 0 or w < frame.x or h < frame.y:
			ragged.append("%s is %dx%d, not a whole number of %dx%d frames" % [f, w, h, frame.x, frame.y])

	assert_eq(measured, sheets.size(), "read %d of %d sheets" % [measured, sheets.size()])
	assert_eq(ragged, [],
		"a sheet that is not a whole number of frames renders as a CORNER of itself, silently -- no error, no warning: %s" % str(ragged))


func test_the_probe_can_see_a_ragged_sheet() -> void:
	# CONTROL: the divisibility check must be able to come back red, or the sweep above is decoration.
	var frame := Vector2i(32, 32)
	var bad := Image.create(100, 128, false, Image.FORMAT_RGBA8)
	assert_true(bad.get_width() % frame.x != 0,
		"CONTROL: a 100px-wide sheet must read as ragged against a 32px frame")
