extends GutTest

## struktured 2026-11-01: "blackmage walks backwards on the village if u select him as leader ... from left/right",
## then "we need to stop that from happening". The 48px redraw swapped the Mage's and Necromancer's LEFT and RIGHT
## rows; a mirror check passed it, because a correctly mirrored pair can still be swapped. Facing cannot be measured
## (a silhouette oracle misjudged all six sheets tried), so a person reviews a committed 4-direction strip and
## data/overworld_facing_review.json pins the hash of the sheet they looked at. Any redraw reds here until re-reviewed.

const REVIEW := "res://data/overworld_facing_review.json"
const MANIFEST := "res://data/sprite_manifest.json"


func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _party_sheets() -> Dictionary:
	return _json(MANIFEST).get("overworld_player_sheets", {})


func test_every_party_walk_sheet_was_reviewed_as_it_is_now() -> void:
	var sheets := _party_sheets()
	var reviewed: Dictionary = _json(REVIEW).get("sheets", {})
	assert_gte(sheets.size(), 14, "FLOOR: the 14 party sheets must be found (%d)" % sheets.size())
	var stale: Array = []
	for job in sheets:
		var e = sheets[job]
		if not (e is Dictionary):
			continue
		var row: Dictionary = reviewed.get(job, {})
		var sha := FileAccess.get_sha256(str(e["path"]))
		if row.is_empty():
			stale.append("%s: never reviewed" % job)
		elif str(row.get("sheet_sha256", "")) != sha:
			stale.append("%s: changed since its facing review (render tools/render_facing_strips.py %s, LOOK, then --pin)" % [job, job])
		elif str(row.get("reviewed", "")).strip_edges() == "":
			stale.append("%s: the review does not say who looked" % job)
	assert_eq(stale, [], "these walk sheets need a facing review: %s" % [stale])


func test_every_review_has_its_strip() -> void:
	var reviewed: Dictionary = _json(REVIEW).get("sheets", {})
	assert_gt(reviewed.size(), 0, "CONTROL: the review file must parse and list sheets")
	var missing: Array = []
	for job in reviewed:
		var strip := str(reviewed[job].get("strip", ""))
		if strip == "" or not FileAccess.file_exists(strip):
			missing.append(job)
	assert_eq(missing, [], "a review must leave the strip it looked at: %s" % [missing])


func test_a_review_cannot_outlive_its_sheet() -> void:
	## CONTROL: the pin really is the sheet's hash, so a review of ANOTHER sheet would not pass for this one.
	var reviewed: Dictionary = _json(REVIEW).get("sheets", {})
	var sheets := _party_sheets()
	assert_true(reviewed.has("mage") and reviewed.has("fighter"), "CONTROL: mage and fighter are reviewed")
	assert_ne(str(reviewed["mage"]["sheet_sha256"]), FileAccess.get_sha256(str(sheets["fighter"]["path"])),
		"the mage's review must not match the fighter's sheet")
