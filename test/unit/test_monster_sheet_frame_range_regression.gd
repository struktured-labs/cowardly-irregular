extends GutTest

## Every monster_sheets animation range must fit the frames actually on disk.
##
## Found 2026-08-16 while landing the artist skeleton: setting skeleton's `dead` range to
## {start:12, end:99} on a 14-frame sheet passed test_monster_sprite_integrity,
## test_monster_sheet_coverage_regression AND test_battle_monster_import_loop_matches_manifest.
## Nothing compared a range against the sheet's width, so an off-by-one in an artist drop
## renders a blank or wrong frame with no test failure and no error.

const MANIFEST := "res://data/sprite_manifest.json"


func _manifest() -> Dictionary:
	var txt := FileAccess.get_file_as_string(MANIFEST)
	assert_ne(txt, "", "sprite_manifest.json must be readable")
	var parsed = JSON.parse_string(txt)
	assert_true(parsed is Dictionary, "sprite_manifest.json must parse as a Dictionary")
	return parsed if parsed is Dictionary else {}


func test_every_monster_animation_range_fits_the_sheet() -> void:
	var sheets: Dictionary = _manifest().get("monster_sheets", {})
	assert_gt(sheets.size(), 10, "sanity: manifest should carry plenty of monster sheets")
	var offenders: Array = []
	var checked := 0
	for id in sheets:
		var entry: Dictionary = sheets[id]
		var path: String = str(entry.get("path", ""))
		var fw: int = int(entry.get("frame_width", 0))
		if path == "" or fw <= 0 or not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		if tex == null:
			continue
		var frames: int = int(tex.get_width() / float(fw))
		for anim in entry.get("animations", {}):
			var r: Dictionary = entry["animations"][anim]
			checked += 1
			var s: int = int(r.get("start", 0))
			var e: int = int(r.get("end", 0))
			if s < 0 or e < s or e > frames - 1:
				offenders.append("%s/%s start=%d end=%d but sheet has %d frames" % [id, anim, s, e, frames])
	assert_true(checked > 0, "asserted nothing — no monster animation range was reachable")
	offenders.sort()
	assert_eq(offenders, [],
		"animation range(s) point past the frames on disk — these render blank with no error: %s" % [offenders])


func test_the_artist_skeleton_kept_its_authored_frame_counts() -> void:
	# Pins the VALUE, not just the bound: the artist drew idle=4 and Atk=6, and a re-embed
	# that silently reverts to the old 2+2 AI layout would satisfy the range check above.
	var sheets: Dictionary = _manifest().get("monster_sheets", {})
	var skel: Dictionary = sheets.get("skeleton", {})
	assert_false(skel.is_empty(), "skeleton must be in monster_sheets")
	var anims: Dictionary = skel.get("animations", {})
	var idle: Dictionary = anims.get("idle", {})
	var atk: Dictionary = anims.get("attack", {})
	assert_eq(int(idle.get("end", -1)) - int(idle.get("start", 0)) + 1, 4,
		"artist idle tag is 4 frames — a 2-frame idle means the AI sheet came back")
	assert_eq(int(atk.get("end", -1)) - int(atk.get("start", 0)) + 1, 6,
		"artist Atk tag is 6 frames — a 2-frame attack means the AI sheet came back")
