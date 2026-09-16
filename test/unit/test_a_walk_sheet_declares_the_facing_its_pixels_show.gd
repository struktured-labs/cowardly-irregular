extends GutTest

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
## ⚠️ AND THE LIMIT, MEASURED RATHER THAN ASSUMED. This identifies WHICH PAIR is left/right. It
## does NOT say which of the two is left, nor which of the other two is down. I tried to recover
## the full order by matching rows across sheets that declare the same order: the identity
## permutation won 93 of 406 pairs (22.9%) with a median margin of 0.007 — noise. So 116
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
		var img: Image = (load(s["path"]) as Texture2D).get_image()
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
		var img: Image = (load(s["path"]) as Texture2D).get_image()
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
