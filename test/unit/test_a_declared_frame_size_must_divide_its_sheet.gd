extends GutTest

## Every `frame_width`/`frame_height` in the manifest is a claim about a PNG that nothing checked.
##
## ⛔ A SHEET WHOSE DECLARED FRAME DOES NOT DIVIDE ITS DIMENSIONS SLICES GARBAGE, SILENTLY. The
## consumers take frame size and column count straight from the manifest; a 96x96 sheet declared
## at 32x32 yields three columns where the animation wants four, and every frame after the first
## row is offset by a third of a frame. Nothing raises — AnimatedSprite2D is happy to cut a
## region that does not line up, so the failure is visual and arrives in a build, not in a log.
##
## 🔑 THE CORPUS IS *EVERY SECTION*, DERIVED — NOT A LIST I MAINTAIN. test_overworld_sheet_manifest
## _audit.gd keys on SHEET_ROOTS and audits `<name>/overworld.png`; a section added tomorrow is
## invisible to it until someone edits a constant. This walks the manifest itself, so a new
## section is covered on the day it lands.
##
## ⚠️ EACH ENTRY IS JUDGED BY *ITS OWN* DECLARING SECTION, WHICH IS THE WHOLE TRICK AND MY FIRST
## SWEEP GOT IT WRONG. `sheets/bard` declares 256x256 (battle animations) and the same directory
## holds `overworld.png` at 128x128, which `overworld_player_sheets` declares at 32x32. Judging a
## file by the geometry of a neighbouring entry produced 61 false violations. A path belongs to
## the entry that DECLARES it, never to the directory it sits in.
##
## 📌 LATENT, AND SAID SO: 290 declared sheets pass today. This defends the pipeline — the
## generators in tools/ write frame sizes into the manifest, and a wrong one is invisible until
## someone looks at the sprite.

const VALID_SUFFIX := ".png"


## A PNG's dimensions from its IHDR, without decoding a single pixel.
##
## ⚠️ `Image.load_from_file` was the obvious call and it DECODES THE WHOLE SHEET to read two
## integers — 290 of them, some 1536x256, every suite run. The width and height are bytes 16..23
## of every PNG by spec, so this reads 24 bytes and stops. Returns (-1, -1) for anything that is
## not a PNG, which the caller must treat as a failure rather than skip.
static func _png_size(path: String) -> Vector2i:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return Vector2i(-1, -1)
	var head := f.get_buffer(24)
	f.close()
	if head.size() < 24:
		return Vector2i(-1, -1)
	# \x89 P N G \r \n \x1a \n -- a JPEG renamed .png would otherwise yield garbage dimensions.
	var sig: Array = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
	for i in sig.size():
		if head[i] != sig[i]:
			return Vector2i(-1, -1)
	var w: int = (head[16] << 24) | (head[17] << 16) | (head[18] << 8) | head[19]
	var h: int = (head[20] << 24) | (head[21] << 16) | (head[22] << 8) | head[23]
	return Vector2i(w, h)


func _manifest() -> Dictionary:
	var f := FileAccess.open("res://data/sprite_manifest.json", FileAccess.READ)
	assert_not_null(f, "sprite_manifest.json must be readable")
	var parsed = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary, "sprite_manifest.json must parse to a Dictionary")
	return parsed if parsed is Dictionary else {}


## Every {path, frame_width, frame_height} triple the manifest declares, from any section.
func _declared_sheets() -> Array:
	var out: Array = []
	var manifest := _manifest()
	for section in manifest:
		if not (section is String) or str(section).begins_with("_"):
			continue
		var entries = manifest[section]
		if not (entries is Dictionary):
			continue
		for name in entries:
			var e = entries[name]
			if not (e is Dictionary):
				continue
			var p = e.get("path", "")
			if not (p is String) or not str(p).ends_with(VALID_SUFFIX):
				continue
			if not (e.get("frame_width") is float or e.get("frame_width") is int):
				continue
			if not (e.get("frame_height") is float or e.get("frame_height") is int):
				continue
			out.append({
				"id": "%s/%s" % [section, name],
				"path": str(p),
				"fw": int(e["frame_width"]),
				"fh": int(e["frame_height"]),
			})
	return out


func test_the_corpus_is_not_empty() -> void:
	# ANTI-VACUITY FLOOR. Every arm below loops this list; an empty one makes them all pass while
	# asserting nothing, scored [Risky] rather than [Failed]. 290 measured 2026-09-19.
	assert_gt(_declared_sheets().size(), 200,
		"the manifest must yield a populated corpus of declared sheets")


func test_the_corpus_spans_more_than_one_section() -> void:
	# CONTROL for the derivation: a walker that silently found only `sheets` would still clear the
	# floor above, and the sections this guard exists for (overworld_*, npc_*) would go unchecked.
	var sections := {}
	for s in _declared_sheets():
		sections[str(s["id"]).split("/")[0]] = true
	assert_gt(sections.size(), 3,
		"declared sheets must come from several manifest sections, got: %s" % str(sections.keys()))


func test_the_header_reader_reports_real_dimensions() -> void:
	# CONTROL FOR THE INSTRUMENT. Every arm below divides by what _png_size returns, so a reader
	# that always answered with some large power of two would make the whole file pass while
	# measuring nothing. Pinned against an independent read of the same bytes (python struct on
	# the IHDR, 2026-09-19).
	#
	# ⚠️ MY FIRST PAIR HERE WAS BOTH 128x128 UNDER A COMMENT CLAIMING THEY DIFFERED, so a
	# constant reader satisfied both -- the exact vacuity this arm exists to prevent, written
	# into the arm itself. The second pin is now NON-SQUARE and a different magnitude, so a
	# constant cannot pass, and a reader that swapped width for height cannot either.
	assert_eq(_png_size("res://assets/sprites/jobs/bard/overworld.png"), Vector2i(128, 128),
		"the overworld sheet is a 4x4 grid of 32x32 frames")
	assert_eq(_png_size("res://assets/sprites/jobs/bard/advance.png"), Vector2i(1024, 256),
		"a battle sheet is a 4-frame strip of 256x256 -- non-square, and W != H catches a swap")


func test_the_header_reader_refuses_what_is_not_a_png() -> void:
	# The signature check is what stops a renamed file yielding plausible-looking garbage.
	assert_eq(_png_size("res://data/sprite_manifest.json"), Vector2i(-1, -1),
		"a non-PNG must report (-1, -1), never a dimension")
	assert_eq(_png_size("res://assets/sprites/nothing_is_here_at_all.png"), Vector2i(-1, -1),
		"a missing file must report (-1, -1)")


func test_every_declared_frame_size_is_positive() -> void:
	var judged := 0
	for s in _declared_sheets():
		judged += 1
		assert_gt(int(s["fw"]), 0, "%s declares frame_width %d" % [s["id"], s["fw"]])
		assert_gt(int(s["fh"]), 0, "%s declares frame_height %d" % [s["id"], s["fh"]])
	assert_gt(judged, 200, "every declared sheet must have been judged, not zero")


func test_every_declared_frame_size_divides_its_own_sheet() -> void:
	var judged := 0
	var missing: Array = []
	for s in _declared_sheets():
		var path := str(s["path"])
		# FileAccess, not ResourceLoader: the import cache serves a sheet whose source is gone.
		if not FileAccess.file_exists(path):
			missing.append(path)
			continue
		var size := _png_size(path)
		assert_gt(size.x, 0, "%s: %s must parse as a PNG (got %s)" % [s["id"], path, str(size)])
		if size.x <= 0:
			continue
		judged += 1
		var w := size.x
		var h := size.y
		assert_eq(w % int(s["fw"]), 0,
			"%s: sheet %s is %dx%d but declares frame_width %d — the slice does not line up" \
				% [s["id"], path, w, h, int(s["fw"])])
		assert_eq(h % int(s["fh"]), 0,
			"%s: sheet %s is %dx%d but declares frame_height %d — the slice does not line up" \
				% [s["id"], path, w, h, int(s["fh"])])
	assert_eq(missing, [],
		"every declared sheet must exist on disk; a stale entry hides a geometry claim: %s" % str(missing))
	assert_gt(judged, 200, "a real PNG must have been measured for every entry, not zero")
