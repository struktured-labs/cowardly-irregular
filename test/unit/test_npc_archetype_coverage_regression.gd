extends GutTest

## NPC archetype sheets are 4x4 grids of 32x32 frames; row 0=down, 1=left, 2=right, 3=up.
## If a row is fully transparent the WanderingNPC silently stays on its prior frame when
## it tries to face that direction — looks like the NPC disappears.

const NPCS_DIR := "res://assets/sprites/npcs"
const FRAME := 32
const ROWS := 4
const COLS := 4
const OPACITY_THRESHOLD := 0.05

const DIR_NAMES: Array[String] = ["down", "left", "right", "up"]


func _list_archetypes() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(NPCS_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir() and not name.begins_with("."):
			var sheet_path: String = "%s/%s/overworld.png" % [NPCS_DIR, name]
			if FileAccess.file_exists(sheet_path):
				out.append(name)
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


func _row_has_content(img: Image, row: int) -> bool:
	for col in COLS:
		var opaque: int = 0
		for y in FRAME:
			for x in FRAME:
				var pixel_color := img.get_pixel(col * FRAME + x, row * FRAME + y)
				if pixel_color.a > 0.0:
					opaque += 1
		var ratio := float(opaque) / float(FRAME * FRAME)
		if ratio >= OPACITY_THRESHOLD:
			return true
	return false


func test_every_archetype_sheet_has_content_in_all_4_direction_rows() -> void:
	var archetypes := _list_archetypes()
	assert_gt(archetypes.size(), 0, "Expected at least one NPC archetype directory under %s" % NPCS_DIR)
	for archetype in archetypes:
		var path: String = "%s/%s/overworld.png" % [NPCS_DIR, archetype]
		var tex := load(path) as Texture2D
		assert_not_null(tex, "Sheet must load: %s" % path)
		var img := tex.get_image()
		assert_not_null(img, "Sheet image must be readable: %s" % path)
		assert_true(img.get_width() >= FRAME * COLS,
			"%s width < %d" % [path, FRAME * COLS])
		assert_true(img.get_height() >= FRAME * ROWS,
			"%s height < %d" % [path, FRAME * ROWS])
		for row in ROWS:
			assert_true(_row_has_content(img, row),
				"%s direction row '%s' is fully transparent — NPC will disappear when facing that way" % [archetype, DIR_NAMES[row]])


## Every guard on these sheets asks whether a sheet is WELL-FORMED — right size, content in all
## four rows, listed by the head-lock gate. None asks whether it is the RIGHT sheet for its id.
##
## That gap shipped once already, in the sibling corpus: dark_knight and shadow_knight resolved to
## byte-identical art for weeks, so the W1 medieval field elite rendered as an ordinary guard while
## every existing check stayed green — the file existed, was 128x128, had content, and was
## registered. cowir-overworld's ratchet closed it for the 85 monster sheets; nothing closed it
## here, and 40 of these 145 were regenerated on 2026-09-11, which is exactly the operation that
## can silently write one sheet's output under two ids.
##
## Compared on DECODED PIXELS rather than file bytes: re-encoding a PNG changes the bytes and not
## the art, so a byte hash answers a question nobody asked.
##
## Severity: LATENT. Measured 145 of 145 distinct at the time of writing — this is future cover,
## not a finding.
func _pixel_hash(path: String) -> String:
	var img := Image.load_from_file(path)
	if img == null:
		return ""
	img.convert(Image.FORMAT_RGBA8)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(img.get_data())
	return ctx.finish().hex_encode()


## The grouping both the sweep and its control run, so the control cannot pass against a copy.
func _duplicate_groups(hashes: Dictionary) -> Array:
	var by_hash: Dictionary = {}
	for name in hashes:
		var h: String = hashes[name]
		if h == "":
			continue
		if not by_hash.has(h):
			by_hash[h] = []
		by_hash[h].append(name)
	var groups: Array = []
	for h in by_hash:
		if by_hash[h].size() > 1:
			groups.append(by_hash[h])
	return groups


func test_no_two_npc_sheets_are_the_same_art() -> void:
	var names := _list_archetypes()
	assert_gt(names.size(), 100,
		"CONTROL: only %d archetype sheets found — the scan is broken and any clean result below is free" % names.size())
	var hashes: Dictionary = {}
	for n in names:
		hashes[n] = _pixel_hash("%s/%s/overworld.png" % [NPCS_DIR, n])
	var unreadable: Array = []
	for n in hashes:
		if hashes[n] == "":
			unreadable.append(n)
	assert_eq(unreadable, [], "sheets that could not be decoded: %s" % str(unreadable))
	assert_eq(_duplicate_groups(hashes), [],
		"two NPC ids resolve to the SAME ART — one of them is wearing the other's character, and every other guard on these sheets stays green: %s" % str(_duplicate_groups(hashes)))


func test_the_duplicate_check_can_report_a_duplicate() -> void:
	# CONTROL: runs the REAL grouping, not a reimplementation of it. Without this the sweep above
	# is a clean result from a function never shown able to return a dirty one.
	var planted := {"alpha": "HASH_A", "beta": "HASH_B", "gamma": "HASH_A"}
	var groups := _duplicate_groups(planted)
	assert_eq(groups.size(), 1, "CONTROL: the grouping must find the planted pair")
	if groups.size() == 1:
		var g: Array = groups[0]
		g.sort()
		assert_eq(g, ["alpha", "gamma"], "CONTROL: and must NAME both members, not just count them")
	assert_eq(_duplicate_groups({"a": "X", "b": "Y"}), [],
		"CONTROL: and must stay silent on genuinely distinct art")
