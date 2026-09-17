extends GutTest
const ImageProbe := preload("res://test/unit/helpers/image_probe.gd")

## The geometry ratchet proves a sheet is cut correctly. NOTHING proved the DECLARATION names the
## right rows — a sheet sliced perfectly at 32px with walk_left pointing at the up row renders a
## character walking backwards, and every cardinal stays clean. That is the defect I fixed in
## RoamingMonster by reading rows from the manifest; this is the half that checks the manifest.
##
## 🔑 THE SIGNAL IS THAT LEFT AND RIGHT ARE MIRRORS OF EACH OTHER, which is a property of walk
## sheets rather than of any character, so it needs no per-sheet ground truth. Measured over the
## 53 declaring sheets 2026-09-16: the mirror-pair metric picks the declared walk_left/walk_right
## pair on 43, and every one of the 10 it misses is a sheet whose SILHOUETTE CANNOT ANSWER —
## bat, ghost, imp, spider, slime are horizontally symmetric, so all six row-pairs score 1.000
## and the margin is exactly 0.000. The instrument is not wrong there; the question is not asked.
##
## ⛔ SO THE EXCLUSION IS DERIVED FROM EACH SHEET'S OWN MARGIN, never hand-listed (cowir-ai's
## rule). Calibration, all three overworld sections:
##
##   margin >= 0.00   53 sheets   43 correct   10 wrong
##   margin >= 0.02   46 sheets   43 correct    3 wrong
##   margin >= 0.05   42 sheets   42 correct    CLEAN   <- the floor this file uses
##   margin >= 0.15   28 sheets   28 correct    CLEAN
##
## ⛔ AND HERE IS WHAT THE MIRROR ARM CANNOT SEE, PROVEN RATHER THAN SUSPECTED. Swap a sheet's
## walk_left and walk_right with EACH OTHER and this file stays green — EC=0, Passing 2 — while
## the character moonwalks, showing the right-facing row when travelling left. The arm compares an
## unordered pair against an unordered pair, so a swap inside it is invisible.
##
## 🔑 THAT IS NOT A HOLE I CAN CLOSE WITH PIXELS, AND THE MEASUREMENT SAYS WHY: walk_right is a
## LITERAL MIRROR of walk_left — 47 of the 53 declaring sheets are BYTE-FOR-BYTE mirrors, exact
## RGBA equality, not merely similar. Mirror-generated art has no intrinsic handedness, so for
## those 47 "which row faces left" is not a property of the image at all.
##
## ⛔ AND THE SCOPE OF THAT NEGATIVE IS 47, NOT 53 — corrected after cowir-adhoc read it. I ran two
## cross-sheet tests (declared left rows, direct vs mirrored: 204/406 = 50.2% on alpha, 198/406 =
## 48.8% on masked colour, median margin 0.0000) and called the result decisive. It was chance BY
## CONSTRUCTION: 47 of the 53 can only contribute noise, and they outvote the 6 that could carry
## signal nine to one. A pooled test over a corpus that is 89% zero-signal cannot answer in either
## direction — my own "a green sweep is evidence only about a corpus that could have contained the
## defect", committed by me, in the commit that quoted it.
##
## 📌 THE 6 NON-EXACT SHEETS, and why no restricted test is run here. Five are meta-job sheets
## (bossbinder, necromancer, scriptweaver, skiptrotter, time_mage) with genuine hand-drawn
## asymmetry — ~25 differing alpha px per frame in one column band, no shift helps. The sixth is
## slime, which is NOT asymmetric: its rows differ only by a 1px internal registration offset, and
## its alpha centroid and bounding box are IDENTICAL across all four rows to three decimals, so
## nothing moves when it turns. That leaves five signal-bearing sheets of one art family. Too few
## to decide handedness, and stating that is the honest end of it rather than a thinner test.
##
## ✅ SO THE SWAP IS CAUGHT BY AGREEMENT INSTEAD — CLAUDE.md case (a). All 53 declaring sheets
## across the three sections use ONE order (walk_down 0, walk_left 1, walk_right 2, walk_up 3), so
## a single swapped sheet stops agreeing with the other 52 and the arm below reds. A GLOBAL swap of
## all 53 would pass, and that is stated rather than hidden: it is not an accident anyone makes,
## and no instrument here could tell it from a deliberate convention change.
##
## ⚠️ AND THE OTHER LIMIT. This identifies WHICH PAIR is left/right; it does NOT say which of the
## other two is down. Recovering the full order by matching rows across sheets gave the identity
## permutation 93 of 406 pairs (22.9%), median margin 0.007 — noise. So the 116
## overworld_npc_sheets entries that declare no animations STAY undeclared; provenance names an
## anchor for 110 of them and an anchor string is not a pixel.
const MANIFEST := "res://data/sprite_manifest.json"
const SECTIONS: Array[String] = [
	"overworld_npc_sheets", "overworld_monster_sheets", "overworld_player_sheets",
]
const MARGIN_FLOOR := 0.05


func _manifest() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if parsed is Dictionary else {}


## Alpha-IoU between cell (row_a, col) and the horizontal mirror of (row_b, col), averaged.
static func _mirror_score(img: Image, fw: int, fh: int, cols: int, ra: int, rb: int) -> float:
	var total := 0.0
	var counted := 0
	for c in cols:
		var inter := 0.0
		var union := 0.0
		for y in fh:
			for x in fw:
				var a := img.get_pixel(c * fw + x, ra * fh + y).a
				var b := img.get_pixel((c + 1) * fw - 1 - x, rb * fh + y).a
				inter += minf(a, b)
				union += maxf(a, b)
		if union > 0.0:
			total += inter / union
			counted += 1
	return total / float(counted) if counted > 0 else 0.0


## {"pair": Vector2i, "margin": float} — the best-mirroring row pair and its lead over the runner-up.
static func _best_pair(img: Image, fw: int, fh: int, cols: int, rows: int) -> Dictionary:
	var best := -1.0
	var second := -1.0
	var best_pair := Vector2i(-1, -1)
	for i in rows:
		for j in range(i + 1, rows):
			var s := _mirror_score(img, fw, fh, cols, i, j)
			if s > best:
				second = best
				best = s
				best_pair = Vector2i(i, j)
			elif s > second:
				second = s
	return {"pair": best_pair, "margin": best - maxf(second, 0.0)}


func _declaring_sheets() -> Array:
	var out: Array = []
	var m := _manifest()
	for section in SECTIONS:
		var node = m.get(section, {})
		if not (node is Dictionary):
			continue
		for id in node:
			var e = node[id]
			if not (e is Dictionary):
				continue
			var anims = e.get("animations", {})
			if not (anims is Dictionary) or not anims.has("walk_left") or not anims.has("walk_right"):
				continue
			var path := str(e.get("path", ""))
			if path == "" or not ResourceLoader.exists(path):
				continue
			out.append({"section": section, "id": str(id), "entry": e, "path": path})
	return out


## ⛔ THE INSTRUMENT FIRST. A metric that returned a constant would report every declaration
## correct; it must be shown to DISCRIMINATE before it is trusted to agree.
func test_the_mirror_metric_discriminates_before_it_is_believed() -> void:
	var sheets := _declaring_sheets()
	assert_gt(sheets.size(), 40, "ANTI-VACUITY: only %d declaring sheets were readable" % sheets.size())

	var decisive := 0
	var flat := 0
	for s in sheets:
		var probe := ImageProbe.image_of(load(s["path"]) as Texture2D)
		assert_eq(probe.size(), 1,
			"%s: reading the sheet ABORTED rather than measuring it" % str(s["path"]))
		if probe.is_empty():
			continue
		var img: Image = probe[0]
		var e: Dictionary = s["entry"]
		var fw: int = int(e.get("frame_width", 32))
		var fh: int = int(e.get("frame_height", 32))
		var r := _best_pair(img, fw, fh, img.get_width() / fw, img.get_height() / fh)
		if float(r["margin"]) >= MARGIN_FLOOR:
			decisive += 1
		elif float(r["margin"]) <= 0.001:
			flat += 1
	assert_gt(decisive, 35,
		"only %d sheets are decisive — the metric has stopped discriminating and every arm below would pass vacuously" % decisive)
	assert_gt(flat, 0,
		("no sheet is FLAT, yet five symmetric creatures (bat/ghost/imp/spider/slime) measured "
		+ "margin 0.000 — a metric that now separates them is reporting a difference the "
		+ "silhouettes do not contain"))


## The ratchet: where the pixels CAN answer, the declaration must match them.
func test_every_decisive_sheet_declares_the_rows_its_pixels_mirror() -> void:
	var wrong: Array = []
	var checked := 0
	for s in _declaring_sheets():
		var e: Dictionary = s["entry"]
		var probe := ImageProbe.image_of(load(s["path"]) as Texture2D)
		assert_eq(probe.size(), 1,
			"%s: reading the sheet ABORTED rather than measuring it" % str(s["path"]))
		if probe.is_empty():
			continue
		var img: Image = probe[0]
		var fw: int = int(e.get("frame_width", 32))
		var fh: int = int(e.get("frame_height", 32))
		var r := _best_pair(img, fw, fh, img.get_width() / fw, img.get_height() / fh)
		if float(r["margin"]) < MARGIN_FLOOR:
			continue
		checked += 1
		var anims: Dictionary = e.get("animations", {})
		var l: int = int((anims["walk_left"] as Dictionary).get("row", -1))
		var rr: int = int((anims["walk_right"] as Dictionary).get("row", -1))
		var declared := Vector2i(mini(l, rr), maxi(l, rr))
		if declared != r["pair"]:
			wrong.append("%s/%s: declares left=%d right=%d, but rows %s are the mirrored pair (margin %.3f)"
				% [s["section"], s["id"], l, rr, r["pair"], r["margin"]])
	assert_gt(checked, 35, "ANTI-VACUITY: only %d sheets cleared the margin floor" % checked)
	wrong.sort()
	assert_eq(wrong, [],
		("a sheet declares its facing rows somewhere other than where its own pixels put them. The "
		+ "sheet still slices correctly and every geometry check stays green — the character simply "
		+ "walks facing the wrong way: %s") % [wrong])


## ⛔ THE HALF THE PIXELS CANNOT ANSWER. A lone swapped sheet is caught here and nowhere else.
##
## 📌 NOT A DUPLICATE of test_a_roaming_monster_reads_its_declared_sheet's roster arm, which asks
## whether the MONSTER sheets match the CONSTANTS RoamingMonster used to hardcode. This asks
## whether all 53 sheets in three sections agree with EACH OTHER. Deliberately move the whole
## fleet to a new order and that arm reds while this one stays green — different questions, and
## the pair is why a convention change is distinguishable from a one-sheet mistake.
func test_every_declaring_sheet_uses_the_same_row_order() -> void:
	var m := _manifest()
	var orders := {}
	var total := 0
	for section in SECTIONS:
		var node = m.get(section, {})
		if not (node is Dictionary):
			continue
		for id in node:
			var e = node[id]
			if not (e is Dictionary):
				continue
			var anims = e.get("animations", {})
			if not (anims is Dictionary) or anims.is_empty():
				continue
			var names: Array = anims.keys()
			names.sort()
			var parts: Array = []
			for n in names:
				parts.append("%s=%d" % [n, int((anims[n] as Dictionary).get("row", -1))])
			var key := ",".join(parts)
			if not orders.has(key):
				orders[key] = []
			(orders[key] as Array).append("%s/%s" % [section, id])
			total += 1
	assert_gt(total, 45, "ANTI-VACUITY: only %d sheets declare an order — nothing is being compared" % total)

	var keys: Array = orders.keys()
	keys.sort()
	if keys.size() > 1:
		var report: Array = []
		for k in keys:
			var who: Array = orders[k]
			who.sort()
			report.append("%s <- %d sheet(s): %s" % [k, who.size(), who if who.size() <= 4 else str(who.slice(0, 4)) + " ..."])
		assert_eq(keys.size(), 1,
			("the overworld sheets no longer agree on one row order. A sheet whose walk_left and "
			+ "walk_right are SWAPPED slices perfectly, mirrors perfectly, and renders a character "
			+ "moonwalking — agreement is the only thing that sees it, because mirror-generated art "
			+ "has no handedness in its pixels: %s") % [report])
	else:
		assert_eq(keys.size(), 1, "exactly one row order must be in use across %d sheets" % total)


## ⛔ THE FACT THE HEADER'S NEGATIVE RESTS ON, RATCHETED so the scope cannot go stale silently.
##
## The claim "pixels cannot tell you which row faces left" is only true because almost every sheet
## is an EXACT mirror. Re-export enough sheets with real asymmetry and the claim narrows — and the
## header would still assert it, because prose does not re-measure itself.
func test_most_declared_mirror_pairs_are_exact_to_the_byte() -> void:
	var exact := 0
	var inexact: Array = []
	for s in _declaring_sheets():
		var e: Dictionary = s["entry"]
		var anims: Dictionary = e.get("animations", {})
		# ⛔ SOURCE BYTES, NOT load(). A Texture2D's get_image() hands back the imported .ctex,
		# which is VRAM-compressed: byte-exactness measured through it is 1 of 53 where the PNG
		# on disk is 47 of 53. CLAUDE.md's "the file on disk is ALSO a pointer" trap, in the one
		# arm here that compares pixels for EQUALITY rather than for overlap.
		var img := Image.load_from_file(s["path"])
		if img == null:
			inexact.append("%s/%s: source PNG unreadable" % [s["section"], s["id"]])
			continue
		var fw: int = int(e.get("frame_width", 32))
		var fh: int = int(e.get("frame_height", 32))
		var l: int = int((anims["walk_left"] as Dictionary).get("row", -1))
		var r: int = int((anims["walk_right"] as Dictionary).get("row", -1))
		var cols: int = img.get_width() / fw
		var same := true
		for c in cols:
			for y in fh:
				for x in fw:
					if img.get_pixel(c * fw + x, l * fh + y) != img.get_pixel((c + 1) * fw - 1 - x, r * fh + y):
						same = false
						break
				if not same:
					break
			if not same:
				break
		if same:
			exact += 1
		else:
			inexact.append("%s/%s" % [s["section"], s["id"]])
	inexact.sort()
	assert_gt(exact + inexact.size(), 45,
		"ANTI-VACUITY: only %d sheets were compared" % (exact + inexact.size()))
	assert_gt(exact, 40,
		("only %d of %d declared mirror pairs are exact. The header's negative — that handedness is "
		+ "not in the pixels — rests on that majority, so a drop means the scope claim needs "
		+ "re-measuring rather than re-asserting. Non-exact: %s")
		% [exact, exact + inexact.size(), inexact])
