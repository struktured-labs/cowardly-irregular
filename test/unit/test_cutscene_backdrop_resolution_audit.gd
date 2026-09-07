extends GutTest

## Regression: cadence #4 scout 2026-07-16 — 8 cutscenes referenced 7
## backdrop ids that didn't exist on disk (castle_harmonia_throne, fire/ice/
## lightning/shadow_cave, suburban_community_center, suburban_strip_mall).
## _try_load_backdrop_image returned false and the scenes fell through to
## _apply_world_gradient — a flat two-color gradient with no atmospheric
## content. The 4 dragon-cave intros + Mordaine throne approach are W1
## boss content in tonight's playtest window.
##
## Ratchet: every `background` id referenced by an overlay cutscene must
## resolve to either an OGV video backdrop (assets/cutscene_videos/) or a
## PNG image backdrop (assets/cutscene_backdrops/). Staged scenes
## (presentation:"staged") don't render a backdrop and are skipped.

const OGV_DIR := "res://assets/cutscene_videos"
const PNG_DIR := "res://assets/cutscene_backdrops"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _cutscene_files() -> Array:
	var out: Array = []
	var dir = DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "cutscenes dir must open")
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append("res://data/cutscenes/%s" % f)
	assert_gt(out.size(), 100, "sanity: many cutscene JSON files expected")
	return out


func _backdrop_resolves(bg: String) -> bool:
	return ResourceLoader.exists("%s/%s.ogv" % [OGV_DIR, bg]) or ResourceLoader.exists("%s/%s.png" % [PNG_DIR, bg])


func test_castle_harmonia_throne_repointed_to_existing_asset() -> void:
	# Direct pin for the highest-priority fix: Mordaine's throne room
	# approach was silently rendering a world-gradient instead of the
	# throne room asset.
	var path := "res://data/cutscenes/world1_throne_room_approach.json"
	assert_true(FileAccess.file_exists(path), "world1_throne_room_approach.json must exist")
	var parsed = JSON.parse_string(_read(path))
	assert_true(parsed is Dictionary, "throne_room_approach must parse")
	assert_eq(str(parsed.get("background", "")), "throne_room",
		"world1_throne_room_approach must use the throne_room backdrop, not a made-up variant that falls back to the world gradient (was 'castle_harmonia_throne', pre-fix)")


func test_every_overlay_cutscene_backdrop_resolves() -> void:
	# Overlay cutscenes without a resolvable backdrop fall through to
	# _apply_world_gradient — a flat two-color gradient. That's a valid
	# design fallback but should NEVER be silently reached because of a
	# typo'd or drifted backdrop id. Staged scenes don't load a backdrop.
	var offenders: Dictionary = {}
	for path in _cutscene_files():
		var parsed = JSON.parse_string(_read(path))
		if not (parsed is Dictionary):
			continue
		if str(parsed.get("presentation", "")) == "staged":
			continue
		var bg := str(parsed.get("background", "")).strip_edges()
		if bg == "":
			continue
		if _backdrop_resolves(bg):
			continue
		if not offenders.has(bg):
			offenders[bg] = []
		if offenders[bg].size() < 3:
			offenders[bg].append(path.get_file())
	if offenders.is_empty():
		assert_true(true)
		return
	var reports: Array = []
	for bg in offenders:
		reports.append("'%s' (e.g. in %s)" % [bg, ", ".join(offenders[bg])])
	assert_true(false,
		"cutscene JSON references backdrops with no OGV or PNG on disk (silent world-gradient fallback):\n  %s" % "\n  ".join(reports))
