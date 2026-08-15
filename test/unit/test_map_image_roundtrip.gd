extends GutTest

## The PNG map must decode to EXACTLY the ASCII literal it replaces.
##
## This is the gate on the format migration. The ASCII stays in OverworldScene.gd until this
## passes; only then does the runtime switch to the image, and only then is the literal
## deleted. Three steps, each independently green -- so at no point is "the map still loads"
## an assumption.
##
## THE FAILURE THIS EXISTS TO CATCH is not "the image is wrong" in general. It is that 12 of
## the 25 map characters appear EXACTLY ONCE -- every landmark is a single pixel. A stray
## paint stroke, a palette edit, or an image-importer processing pass loses one, and the
## symptom is a spawn point that silently stops existing. `_register_spawn_point` keys on the
## character, so a lost pixel deletes a dragon cave's arrival coordinate with no error
## anywhere. A whole-grid comparison catches it; nothing else would.

const Loader := preload("res://src/exploration/MapImageLoader.gd")

const MAP_PNG := "res://data/maps/overworld_w1.png"
const SCENE_GD := "res://src/exploration/OverworldScene.gd"

## Landmark characters are DERIVED from the palette's own `landmarks` section, never listed
## here. The first version of this file hand-listed them and was wrong on its first run:
## "C" and "H" each appear TWICE in W1, not once, so an eyeballed singleton list asserted a
## falsehood about the map it was guarding. Deriving from the palette cannot drift.


## Structural extraction: the array's opening bracket to its MATCHING close, never a line
## count. A truncated read returns real rows, correctly parsed, from an incomplete region,
## and nothing in the output says it was cut.
func _ascii_rows() -> Array:
	var src := FileAccess.get_file_as_string(SCENE_GD)
	# The anchor ENDS with the array's own '[', so its index is derived from the anchor.
	# Re-searching for "[" from the declaration finds Array[String]'s bracket instead --
	# depth then opens and closes on that pair and the block is the word "String".
	const DECL := "var map_data: Array[String] = ["
	var open_at := src.find(DECL)
	if open_at < 0:
		return []
	var i := open_at + DECL.length() - 1
	var depth := 0
	var start := i
	while i < src.length():
		var c := src[i]
		if c == "[":
			depth += 1
		elif c == "]":
			depth -= 1
			if depth == 0:
				break
		i += 1
	if depth != 0:
		return []  # never closed -- refuse rather than return a truncated grid
	var block := src.substr(start + 1, i - start - 1)
	var rows: Array = []
	var q := block.find("\"")
	while q >= 0:
		var e := block.find("\"", q + 1)
		if e < 0:
			break
		rows.append(block.substr(q + 1, e - q - 1))
		q = block.find("\"", e + 1)
	return rows


func _census(rows: Array) -> Dictionary:
	var out := {}
	for row in rows:
		for ch in str(row):
			out[ch] = int(out.get(ch, 0)) + 1
	return out


func test_the_palette_loads_and_is_collision_free() -> void:
	var err: String = Loader.ensure_palette()
	assert_eq(err, "", "palette must load cleanly -- a collision or a missing section is fatal")
	var chars: Array = Loader.palette_chars()
	assert_gt(chars.size(), 20, "palette has %d entries -- too few; the read broke" % chars.size())
	# named members, not a count: a count control passes on an empty parse
	assert_true("~" in chars, "palette knows water")
	assert_true("4" in chars, "palette knows the fire dragon cave -- a single-pixel landmark")
	assert_false("Z" in chars, "a fabricated character is absent, so membership means something")


func test_the_ascii_literal_is_still_readable() -> void:
	var rows := _ascii_rows()
	assert_gt(rows.size(), 10, "extracted %d ASCII rows -- the structural read broke" % rows.size())
	var widths := {}
	for r in rows:
		widths[str(r).length()] = true
	assert_eq(widths.size(), 1,
		"the ASCII map has ragged rows (%s). An image cannot represent that, so the export would silently pick one width." % str(widths.keys()))


func test_the_png_decodes_to_exactly_the_ascii_map() -> void:
	var ascii := _ascii_rows()
	var png: Array = Loader.load_rows(MAP_PNG)

	# Both non-empty FIRST: load_rows returns [] on any failure, and [] == [] would pass
	# a naive equality check while proving nothing.
	assert_gt(ascii.size(), 10, "ASCII side is non-empty")
	assert_gt(png.size(), 10, "PNG side is non-empty -- an empty result means the load FAILED, not that the map is empty")
	assert_eq(png.size(), ascii.size(), "row count must match")

	var mismatches: Array = []
	for y in range(min(png.size(), ascii.size())):
		if str(png[y]) != str(ascii[y]):
			if mismatches.size() < 5:
				mismatches.append("row %d:\n    ascii: %s\n    png:   %s" % [y, ascii[y], png[y]])
	assert_true(mismatches.is_empty(),
		"PNG and ASCII disagree on %d row(s):\n  %s" % [mismatches.size(), "\n  ".join(mismatches)])


func _coords_of(rows: Array, ch: String) -> Array:
	var out: Array = []
	for y in range(rows.size()):
		var row := str(rows[y])
		for x in range(row.length()):
			if row[x] == ch:
				out.append("%d,%d" % [x, y])
	return out


## Every landmark must survive at the SAME COORDINATES, not merely in the same quantity.
## A count is blind to a landmark that moved, and `_register_spawn_point` derives arrival
## coordinates from the character's position -- so a moved pixel relocates a dragon cave's
## spawn while every count still balances.
func test_every_landmark_survives_at_its_exact_coordinates() -> void:
	var ascii_rows := _ascii_rows()
	var png_rows: Array = Loader.load_rows(MAP_PNG)
	var landmarks: Array = Loader.landmark_chars()

	assert_gt(landmarks.size(), 5, "derived %d landmark chars from the palette -- too few; the derivation broke" % landmarks.size())
	assert_true("4" in landmarks, "the palette's landmark set includes the fire dragon cave")
	assert_false("~" in landmarks, "water is terrain, not a landmark -- so the sections are really separate")
	assert_gt(png_rows.size(), 10, "PNG side non-empty -- otherwise the comparisons below are vacuous")

	var problems: Array = []
	var total_placed := 0
	for ch in landmarks:
		var a := _coords_of(ascii_rows, ch)
		var p := _coords_of(png_rows, ch)
		total_placed += a.size()
		if a != p:
			problems.append("'%s': ascii at [%s] but png at [%s]" % [ch, ", ".join(a), ", ".join(p)])
	# without this, a run where NO landmark was found would report zero problems
	assert_gt(total_placed, 10, "only %d landmark placements found in the ASCII map -- the scan broke" % total_placed)
	assert_true(problems.is_empty(), "landmark placement changed:\n  %s" % "\n  ".join(problems))


func test_no_character_is_gained_or_dropped_anywhere() -> void:
	var ascii := _census(_ascii_rows())
	var png := _census(Loader.load_rows(MAP_PNG))
	assert_gt(ascii.size(), 5, "ASCII census non-empty")

	var diffs: Array = []
	var keys := {}
	for k in ascii: keys[k] = true
	for k in png: keys[k] = true
	for ch in keys:
		var a: int = int(ascii.get(ch, 0))
		var p: int = int(png.get(ch, 0))
		if a != p:
			diffs.append("'%s': ascii %d vs png %d" % [ch, a, p])
	assert_true(diffs.is_empty(), "per-character counts differ:\n  %s" % "\n  ".join(diffs))
