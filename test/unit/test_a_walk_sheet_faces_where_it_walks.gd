extends GutTest

## struktured 2026-11-01: "blackmage walks backwards on the village if u select him as leader ... from left/right",
## then "we need to stop that from happening". The 48px redraw swapped the Mage's and Necromancer's LEFT and RIGHT
## rows; a mirror check passed it, because a correctly mirrored pair can still be swapped. Facing cannot be measured
## (a silhouette oracle misjudged all six sheets tried), so a person reviews a committed 4-direction strip and
## data/overworld_facing_review.json pins the hash of the sheet they looked at. Any redraw reds here until re-reviewed.

const REVIEW := "res://data/overworld_facing_review.json"
const MANIFEST := "res://data/sprite_manifest.json"
## Every overworld section whose sheets walk in four directions.
const SECTIONS := ["overworld_player_sheets", "overworld_npc_sheets", "overworld_monster_sheets"]


func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## {"<section>/<id>": manifest entry} for every walk sheet.
func _walk_sheets() -> Dictionary:
	var man := _json(MANIFEST)
	var out := {}
	for sec in SECTIONS:
		var store = man.get(sec, {})
		for id in store:
			if store[id] is Dictionary:
				out["%s/%s" % [sec, id]] = store[id]
	return out


func _reviewed() -> Dictionary:
	return _json(REVIEW).get("sheets", {})


func test_every_walk_sheet_was_reviewed_as_it_is_now() -> void:
	var sheets := _walk_sheets()
	var reviewed := _reviewed()
	## FLOOR: the 14 party sheets alone; the corpus is every sheet any of the three sections names.
	assert_gte(sheets.size(), 14, "FLOOR: the walk sheets must be found (%d)" % sheets.size())
	var stale: Array = []
	for key in sheets:
		var row: Dictionary = reviewed.get(key, {})
		if row.is_empty():
			stale.append("%s: never reviewed" % key)
		elif str(row.get("sheet_sha256", "")) != FileAccess.get_sha256(str(sheets[key]["path"])):
			stale.append("%s: changed since its facing review (tools/render_facing_strips.py %s, LOOK, then --pin --note)" % [key, key])
		elif str(row.get("reviewed", "")).strip_edges() == "":
			stale.append("%s: the review does not say who looked" % key)
	assert_eq(stale, [], "these walk sheets need a facing review: %s" % [stale])


func test_every_review_has_its_strip() -> void:
	var reviewed := _reviewed()
	assert_gt(reviewed.size(), 0, "CONTROL: the review file must parse and list sheets")
	var missing: Array = []
	for key in reviewed:
		var strip := str(reviewed[key].get("strip", ""))
		if strip == "" or not FileAccess.file_exists(strip):
			missing.append(key)
	assert_eq(missing, [], "a review must leave the strip it looked at: %s" % [missing])


func test_no_review_outlives_its_sheet() -> void:
	## A review of a sheet the manifest no longer names is a promise about nothing.
	var sheets := _walk_sheets()
	var orphans: Array = []
	for key in _reviewed():
		if not sheets.has(key):
			orphans.append(key)
	assert_eq(orphans, [], "reviews of sheets that are gone: %s" % [orphans])


func test_a_pin_is_the_sheets_own_hash() -> void:
	## CONTROL: the pin is THIS sheet's hash, so a review of another sheet cannot pass for it.
	var reviewed := _reviewed()
	var sheets := _walk_sheets()
	var mage := "overworld_player_sheets/mage"
	var fighter := "overworld_player_sheets/fighter"
	assert_true(reviewed.has(mage) and sheets.has(fighter), "CONTROL: the mage is reviewed and the fighter is a walk sheet")
	assert_ne(str(reviewed[mage]["sheet_sha256"]), FileAccess.get_sha256(str(sheets[fighter]["path"])),
		"the mage's review must not match the fighter's sheet")
