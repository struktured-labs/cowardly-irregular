extends GutTest

## NPC archetype sheets are 4x4 grids of 32x32 frames; row 0=down, 1=left, 2=right, 3=up.
## If a row is fully transparent the WanderingNPC silently stays on its prior frame when
## it tries to face that direction — looks like the NPC disappears.
##
## ⚠️ THIS FILE USES TWO READERS ON PURPOSE. Do not unify them.
##   load() -> get_image()      the row test below. Reads the IMPORTED .ctex — which is what the
##                              game actually renders, so it is the right authority for "will this
##                              NPC disappear on screen".
##   Image.load_from_file()     the frame sweeps further down. Reads the PNG on disk — the right
##                              authority for "did the generator write valid art", which is a
##                              question about the artifact a tool produced, not about rendering.
##
## They disagree for exactly one import cycle, and that is the correct behaviour, not a bug.
## Measured 2026-09-11 by wiping row 1 on disk without re-importing: the disk sweeps failed and the
## row test passed; after --import both failed. A reader is not right or wrong in general — it is
## right or wrong for the question being asked, which is why the one place this file DID have a
## wrong reader was an existence claim (see the manifest audit, fixed in c7ab6f06: a test named
## "exists on disk" that asked ResourceLoader, i.e. the cache).

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


## A sheet's own cell size: every one is a 4x4 grid, so the cell is a quarter of the sheet. 32px for the generated
## placeholders, 48px for the artist's Rotha; measuring her at 32 cut her into pieces and read them as empty frames.
func _cell(img: Image) -> int:
	return maxi(1, img.get_width() / COLS)


func _row_has_content(img: Image, row: int) -> bool:
	var fr := _cell(img)
	for col in COLS:
		var opaque: int = 0
		for y in fr:
			for x in fr:
				var pixel_color := img.get_pixel(col * fr + x, row * fr + y)
				if pixel_color.a > 0.0:
					opaque += 1
		var ratio := float(opaque) / float(fr * fr)
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


## The row check above is a DISJUNCTION — a row passes if ANY ONE of its four frames clears 5%.
## So three of four frames can be wiped and it stays green, which is most of the defect it exists
## to catch. Two sweeps below close that at FRAME level, matching what the sibling corpus already
## gets: test_overworld_sheet_frame_contract pins all 85 monster overworld sheets per-frame, and
## these 145 are the same format (128x128, 4x4 of 32) written by the same assembler — the one whose
## second chromakey pass keyed subjects out until 2026-09-09. The guard landed on the corpus where
## the defect was DIAGNOSED, not the corpus where it happened: 40 of these 145 were regenerated for
## exactly that reason on 2026-09-11.
##
## Read from the PNG, not through load() — an imported .ctex is what renders, but these sweeps are
## asking what the GENERATOR wrote, and that is the artifact on disk.
##
## Severity: LATENT. All 145 pass both arms today; this is future cover, not a finding.
const MIN_FRAME_FRACTION_OF_MEDIAN := 0.35
const MIN_OPAQUE_PX_PER_FRAME := 32
const MAX_OPAQUE_FRACTION_PER_FRAME := 0.99


func _frame_occupancy(img: Image) -> Array:
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var w := img.get_width()
	var out: Array = []
	var fr := _cell(img)
	for row in range(img.get_height() / fr):
		for col in range(w / fr):
			var n := 0
			for y in range(row * fr, (row + 1) * fr):
				for x in range(col * fr, (col + 1) * fr):
					if data[(y * w + x) * 4 + 3] > 10:
						n += 1
			out.append({"n": n, "at": Vector2i(col, row)})
	return out


func _median_n(cells: Array) -> float:
	var ns: Array = []
	for c in cells:
		ns.append(int(c["n"]))
	ns.sort()
	if ns.is_empty():
		return 0.0
	var m: int = ns.size() / 2
	return float(ns[m]) if ns.size() % 2 == 1 else (float(ns[m - 1]) + float(ns[m])) / 2.0


## Two arms, and their division of labour differs from the sibling guard's because the row check
## above already seconds one of them.
##
##  RELATIVE — a frame far thinner than its own sheet's typical frame. This is the partial-wipe
##  shape, and it is the arm doing real work here: the row check cannot see it at all.
##  Headroom measured across all 145: the thinnest legitimate frame is monk_digital's up-row at
##  0.448 of its sheet median (209 px), and the two broken dark_knight builds scored 0.156 and
##  0.089. 0.35 sits between them — 1.3x above, 2.2x below. Tighter above than the monster corpus
##  (0.743) because a chibi back view is genuinely thin, so a new sheet CAN red here legitimately;
##  the message names the sheet, the frame and the ratio so triage is one look at the PNG.
##
##  ABSOLUTE — a floor of 32 px. It does NOT earn its place on the uniformly-empty sheet the way it
##  does in the monster corpus: there, no other instrument sees that case; here the row check reds
##  on it too. What it catches alone is a SINGLE frame at or near zero inside an otherwise healthy
##  row, where the relative arm's median is fine and the row's disjunction is satisfied.
## NAMED MEMBERSHIP, because a size floor is blind to PARTIAL loss — and both sweeps below used to
## carry only a floor. Measured 2026-09-11: hiding 43 of the 145 sheets left this file Passing 8 /
## EC 0, because 102 still cleared `> 100` and the 43 absent sheets were simply not in the corpus,
## so nothing reported them. The head-lock gate, which names every sheet it expects, said "43 of 145
## npc sheets were NOT measured" on the identical tree.
##
## The manifest is the independent register of what must be on disk — a sheet that vanishes leaves
## its entry behind, so the register cannot shrink with the corpus it is used to check.
const MANIFEST := "res://data/sprite_manifest.json"


func _registered_archetypes() -> Array:
	var raw := FileAccess.get_file_as_string(MANIFEST)
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY or not data.has("overworld_npc_sheets"):
		return []
	var prefix := "res://assets/sprites/npcs/"
	var out: Array = []
	for key in data["overworld_npc_sheets"]:
		var path: String = str(data["overworld_npc_sheets"][key].get("path", ""))
		if path.begins_with(prefix) and path.ends_with("/overworld.png"):
			out.append(path.substr(prefix.length(), path.length() - prefix.length() - 14))
	out.sort()
	return out


## The premise both sweeps below stand on: every sheet the manifest registers must be one this
## file actually measures. Asserted once, naming the extent and the members, so partial loss is
## as loud as total loss.
func _assert_corpus_covers_the_register(measured: Array, sweep: String) -> void:
	var registered := _registered_archetypes()
	assert_gt(registered.size(), 100,
		"CONTROL: the manifest registered only %d npc sheets — the register is the thing being trusted here, so a short read makes every coverage claim below free" % registered.size())
	var seen := {}
	for m in measured:
		seen[m] = true
	var unmeasured: Array = []
	for r in registered:
		if not seen.has(r):
			unmeasured.append(r)
	assert_eq(unmeasured, [],
		"%d of %d registered npc sheets were NOT measured by %s — a sheet absent from the corpus is indistinguishable from one that passed: %s" % [
			unmeasured.size(), registered.size(), sweep, str(unmeasured)])


func test_no_npc_frame_is_empty() -> void:
	var names := _list_archetypes()
	assert_gt(names.size(), 100,
		"CONTROL: only %d archetype sheets found — the scan is broken and any clean result below is free" % names.size())

	var blank: Array = []
	var measured: Array = []
	var thinnest := 1 << 30
	for n in names:
		var img := Image.load_from_file("%s/%s/overworld.png" % [NPCS_DIR, n])
		if img == null:
			continue
		measured.append(n)
		var cells := _frame_occupancy(img)
		var med := _median_n(cells)
		for c in cells:
			var px: int = int(c["n"])
			thinnest = min(thinnest, px)
			if px < MIN_OPAQUE_PX_PER_FRAME:
				blank.append("%s frame (col %d,row %d) holds %d opaque px" % [n, c["at"].x, c["at"].y, px])
			elif med > 0.0 and float(px) / med < MIN_FRAME_FRACTION_OF_MEDIAN:
				blank.append("%s frame (col %d,row %d) holds %d px, %.0f%% of this sheet's median %d" % [
					n, c["at"].x, c["at"].y, px, 100.0 * float(px) / med, int(med)])

	assert_eq(measured.size(), names.size(), "read %d of %d sheets" % [measured.size(), names.size()])
	_assert_corpus_covers_the_register(measured, "the occupancy sweep")
	assert_gt(thinnest, 0,
		"CONTROL: the emptiest frame measured 0 px across every sheet — the alpha probe is reading nothing")
	assert_eq(blank, [],
		"an NPC frame with almost no pixels renders as an invisible character on one walk step — the sheet is valid, the art is gone: %s" % str(blank))


## The mirror failure of the same cleanup step: not keying the background out at all. The ceiling is
## taken from the FORMAT CONTRACT, not the population — these frames composite over terrain, so a
## frame with no transparent pixels cannot be a keyed sprite whatever the corpus happens to do.
## Nothing on the MAX side existed for this corpus at any level; the row check has a MIN arm only.
func test_no_npc_frame_is_fully_opaque() -> void:
	var names := _list_archetypes()
	assert_gt(names.size(), 100, "CONTROL: only %d archetype sheets found — the scan is broken" % names.size())

	var solid: Array = []
	var fullest := 0.0
	var measured: Array = []
	for n in names:
		var img := Image.load_from_file("%s/%s/overworld.png" % [NPCS_DIR, n])
		if img == null:
			continue
		measured.append(n)
		var area := _cell(img) * _cell(img)
		var cap := int(float(area) * MAX_OPAQUE_FRACTION_PER_FRAME)
		for c in _frame_occupancy(img):
			var px: int = int(c["n"])
			fullest = max(fullest, float(px) / float(area))
			if px > cap:
				solid.append("%s frame (col %d,row %d) is %d/%d opaque — background not keyed out" % [
					n, c["at"].x, c["at"].y, px, area])

	_assert_corpus_covers_the_register(measured, "the opacity-ceiling sweep")
	assert_lt(fullest, 1.0,
		"CONTROL: the fullest frame in the corpus measured 100% opaque — either a real defect or the alpha probe is stuck")
	assert_eq(solid, [],
		"an NPC frame with no transparent pixels renders as a solid square walking over the terrain: %s" % str(solid))


func test_the_npc_probe_can_see_a_partially_wiped_row() -> void:
	# CONTROL: the case the ROW check is blind to and this file existed without — three of four
	# frames emptied, one healthy. Asserted against the real row predicate, not a description of it.
	var img := Image.create(FRAME * COLS, FRAME * ROWS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	for col in range(1, COLS):
		for y in range(FRAME):
			for x in range(FRAME):
				img.set_pixel(col * FRAME + x, y, Color(0, 0, 0, 0))
	assert_true(_row_has_content(img, 0),
		"CONTROL: the row check must PASS this sheet — one surviving frame satisfies its disjunction")
	var cells := _frame_occupancy(img)
	assert_eq(int(cells[0]["n"]), FRAME * FRAME, "CONTROL: frame 0 must be the survivor")
	assert_lt(int(cells[1]["n"]), MIN_OPAQUE_PX_PER_FRAME,
		"CONTROL: and the frame-level absolute arm must fail the same sheet the row check passed")


func test_the_npc_probe_can_see_an_emptied_frame() -> void:
	# CONTROL: the relative arm at the REAL defect's magnitude — 43 px beside full frames, the
	# second broken dark_knight build. Any absolute floor low enough to clear monk_digital's
	# 209 px passes this, which is why the relative arm is the one carrying the partial-wipe case.
	var img := Image.create(FRAME * COLS, FRAME * ROWS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var kept := 0
	for y in range((ROWS - 1) * FRAME, ROWS * FRAME):
		for x in range((COLS - 1) * FRAME, COLS * FRAME):
			if kept < 43:
				kept += 1
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	var cells := _frame_occupancy(img)
	var med := _median_n(cells)
	var last: Dictionary = cells[cells.size() - 1]
	assert_eq(int(last["n"]), 43, "CONTROL: the planted frame must hold exactly the defect's 43 px")
	assert_gt(int(last["n"]), MIN_OPAQUE_PX_PER_FRAME,
		"CONTROL: 43 px CLEARS the absolute floor — this is precisely why the relative arm exists")
	assert_lt(float(last["n"]) / med, MIN_FRAME_FRACTION_OF_MEDIAN,
		"CONTROL: the relative arm must flag 43 px against a median of %d" % int(med))


func test_the_npc_probe_can_see_an_unkeyed_frame() -> void:
	# CONTROL: the MAX arm. Nothing else in this file can come back red on an unkeyed background.
	var img := Image.create(FRAME * COLS, FRAME * ROWS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range((ROWS - 1) * FRAME, ROWS * FRAME):
		for x in range((COLS - 1) * FRAME, COLS * FRAME):
			img.set_pixel(x, y, Color(0.2, 0.2, 0.2, 1))
	var cells := _frame_occupancy(img)
	var last: Dictionary = cells[cells.size() - 1]
	assert_eq(int(last["n"]), FRAME * FRAME, "CONTROL: the unkeyed frame must measure fully opaque")
	assert_gt(int(last["n"]), int(float(FRAME * FRAME) * MAX_OPAQUE_FRACTION_PER_FRAME),
		"CONTROL: a fully-opaque frame must exceed the ceiling the sweep applies")
	assert_true(_row_has_content(img, ROWS - 1),
		"CONTROL: and the row check calls this sheet HEALTHY — it has no MAX side at all")


## Three consumers cut these sheets: WanderingNPC (village walkers), OverworldNPC (standing NPCs) and CutsceneActor
## (staged puppets). They used to carry three hand copies of the number 32, guarded only for agreeing with each other.
## The artist's first walker (Rotha, 48px cells) made "one agreed number" the wrong invariant: the size belongs to the
## SHEET. The two NPC renderers now ask HybridSpriteLoader.overworld_sheet_frame_size, CutsceneActor measures the
## sheet it loaded, and the manifest is the authority, so it is checked against the files it describes.
const NPC_CROP_CONSUMERS := {
	"res://src/exploration/WanderingNPC.gd": "overworld_sheet_frame_size(",
	"res://src/exploration/OverworldNPC.gd": "overworld_sheet_frame_size(",
	"res://src/cutscene/CutsceneActor.gd": "_frame_px",
}


func test_every_npc_sheet_consumer_takes_the_cell_size_from_the_sheet() -> void:
	var bad: Array = []
	for path in NPC_CROP_CONSUMERS:
		var src := FileAccess.get_file_as_string(path)
		assert_ne(src, "", "CONTROL: %s is readable" % path.get_file())
		if not src.contains(NPC_CROP_CONSUMERS[path]):
			bad.append("%s no longer derives its crop via %s" % [path.get_file(), NPC_CROP_CONSUMERS[path]])
		if src.contains("ARCHETYPE_FRAME_W"):
			bad.append("%s declares a hand copy of the cell size again" % path.get_file())
	assert_eq(bad, [], "a consumer crops NPC sheets by its own number, so a sheet at another size is cut into pieces: %s" % str(bad))


func test_every_registered_sheet_is_the_grid_its_entry_declares() -> void:
	## The renderers trust the manifest's frame size, so an entry that disagrees with its file draws the wrong region.
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var sheets: Dictionary = m.get("overworld_npc_sheets", {})
	assert_gt(sheets.size(), 100, "CONTROL: the register was read (%d)" % sheets.size())
	var bad: Array = []
	var sizes := {}
	for id in sheets:
		var path := str(sheets[id].get("path", ""))
		if not ResourceLoader.exists(path):
			continue
		var want := HybridSpriteLoader.overworld_sheet_frame_size("overworld_npc_sheets", str(id))
		var tex := load(path) as Texture2D
		sizes[want] = true
		if Vector2i(tex.get_size()) != want * 4:
			bad.append("%s: declares %s cells, the sheet is %s" % [id, str(want), str(tex.get_size())])
	assert_gt(sizes.size(), 1, "CONTROL: more than one cell size is in use, so this is not checking a constant against itself")
	assert_eq(bad, [], "manifest entries whose cell size is not a quarter of their sheet: %s" % str(bad.slice(0, 8)))
