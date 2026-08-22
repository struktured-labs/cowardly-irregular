extends GutTest

## No monster frame may be near-invisible while its siblings are solid.
##
## Found 2026-08-22 auditing shipped art. meta_knight's WHOLE-SHEET opaque fraction is
## 49.7% — mid-pack, unremarkable on any per-sheet statistic — while its frame 0, the IDLE
## frame a player looks at for most of a battle, is 0.1% solid: a faint grey smear. Frames
## 0, 3 and 4 carry IDENTICAL ink counts, so one degraded image was written into three
## slots. An average over 8 frames cannot move enough for one dead frame to show.
##
## A sheet is its own control here, so there is no cross-sheet threshold to calibrate —
## which is what defeated three threshold-based detectors on the overworld walk grids.

const MANIFEST := "res://data/sprite_manifest.json"
const GHOST_MAX := 0.05
const HEALTHY_MIN := 0.25

## id -> why. Recorded so NEW breakage reds while these do not block; shrink it, never grow it.
const KNOWN := {
	"meta_knight": "DEFECT frames 0(idle) 3 4 — near-erased smear; frame 1 is a crisp knight",
	"masterite_tempo_futuristic": "DEFECT frame 4(hit) — multi-panel design sheet with UI chrome",
	"masterite_arbiter_futuristic": "DEFECT frame 6(dead) — same panel-layout failure",
	"masterite_curator_medieval": "borderline frames 4,5(hit) — visible figure under heavy flame FX",
	"ghost": "INTENTIONAL frame 6(dead) — a ghost dissolving to a wisp is the design",
}


func _manifest() -> Dictionary:
	var txt := FileAccess.get_file_as_string(MANIFEST)
	assert_ne(txt, "", "sprite_manifest.json must be readable")
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}


## Fully-opaque pixels over all ink, per frame. Empty frames report 0.0.
func _frame_solidity(img: Image, fw: int) -> Array:
	var out: Array = []
	var h := img.get_height()
	var n := int(img.get_width() / fw)
	for f in range(n):
		var ink := 0
		var solid := 0
		for y in range(h):
			for x in range(fw):
				var a := img.get_pixel(f * fw + x, y).a
				if a > 0.04:
					ink += 1
					if a >= 0.98:
						solid += 1
		out.append(0.0 if ink == 0 else float(solid) / float(ink))
	return out


func test_no_ghost_frame_beside_healthy_siblings() -> void:
	var sheets: Dictionary = _manifest().get("monster_sheets", {})
	assert_gt(sheets.size(), 10, "sanity: manifest should carry plenty of monster sheets")
	var scanned: Array = []
	var offenders: Array = []
	var short: Array = []
	for id in sheets:
		var entry: Dictionary = sheets[id]
		var path: String = str(entry.get("path", ""))
		if not ResourceLoader.exists(path):
			continue
		var tex = load(path)
		if tex == null or not (tex is Texture2D):
			continue
		var img: Image = tex.get_image()
		if img == null:
			continue
		var fw := int(entry.get("frame_width", img.get_height()))
		if fw <= 0 or int(img.get_width() / fw) < 2:
			continue
		scanned.append(id)
		var frames := int(img.get_width() / fw)
		var sol := _frame_solidity(img, fw)
		# a zero-assert helper that aborts returns a SHORT array, and fewer frames read means fewer ghosts found
		if sol.size() != frames:
			short.append("%s: read %d of %d frames" % [id, sol.size(), frames])
		var ghosts: Array = []
		var healthy := false
		for i in range(sol.size()):
			if float(sol[i]) < GHOST_MAX:
				ghosts.append(i)
			elif float(sol[i]) >= HEALTHY_MIN:
				healthy = true
		if healthy and not ghosts.is_empty() and not KNOWN.has(id):
			offenders.append("%s: frames %s are near-invisible beside solid siblings" % [id, str(ghosts)])
	# a named member the scan MUST reach — a count would pass on one stray match
	assert_true(scanned.has("wolf"), "scan must reach wolf (8 solid frames) — else it read nothing")
	assert_gt(scanned.size(), 50, "scan must cover the bulk of monster_sheets")
	assert_eq(short, [], "a frame-solidity read came back short — the scan skipped frames: %s" % [short])
	assert_eq(offenders, [], "a frame this faint renders as nothing in battle")


func test_known_ghost_list_has_not_gone_stale() -> void:
	var sheets: Dictionary = _manifest().get("monster_sheets", {})
	var missing: Array = []
	for id in KNOWN:
		if not sheets.has(id):
			missing.append(id)
	assert_eq(missing, [], "KNOWN names a sheet that no longer exists — drop the entry")
