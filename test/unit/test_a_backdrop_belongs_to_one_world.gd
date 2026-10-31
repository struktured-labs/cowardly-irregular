extends GutTest

## A cutscene backdrop is shown by scenes of ONE world. Seven W2-W6 party chats rendered W1's prologue_forest.
##
## FOUND 2026-10-31 auditing struktured's "the village cutscene art is pretty bad" (docs/art/cutscene-backdrop-shot-list.md).
## world2_pc_association/_maintenance/_zoning, world3_pc_calibration, world4_pc_shift_change, world5_pc_login and
## world6_pc_negative_space all named `prologue_forest`: a mowed suburban lawn, a ticking brass street and a digital
## horizon, each drawn as a medieval wood. Every existing guard was green: the key RESOLVES
## (test_cutscene_backdrop_resolution_audit), and the per-world lenses cover only fragments and masterites.
##
## WORLD IS READ OFF THE SCENE, BACKDROP OWNERSHIP IS DERIVED. No key->world table is written here: a key's world is
## whatever its scenes say, and the assertion is that they agree. A new backdrop is in the corpus the day a scene
## names it, and a new world needs no edit. A scene whose `world` is not 1-6 is an offender rather than exempt,
## because skipping it would silently exempt exactly the scene whose tag is wrong.
##
## WHAT THIS CANNOT SEE: a backdrop of the right world but the wrong PLACE (Brasston's street scenes on the workshop
## interior were fixed in the same change). That is a judgement about prose, not a property of the data.

const CUTSCENE_DIR := "res://data/cutscenes"


## key -> {world -> [scene ids]} for every overlay scene that names a backdrop.
func _backdrop_worlds() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(CUTSCENE_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENE_DIR, f]))
		if not (parsed is Dictionary):
			continue
		var scene := parsed as Dictionary
		if str(scene.get("presentation", "")) == "staged":
			continue  # staged scenes play on the live map; their background is never shown
		var bg := str(scene.get("background", ""))
		if bg == "":
			continue
		var w := int(scene.get("world", 0)) if (scene.get("world", 0) is float or scene.get("world", 0) is int) else 0
		if not out.has(bg):
			out[bg] = {}
		if not (out[bg] as Dictionary).has(w):
			out[bg][w] = []
		(out[bg][w] as Array).append(f.trim_suffix(".json"))
	return out


func test_the_scan_sees_the_whole_corpus() -> void:
	var keys := _backdrop_worlds()
	var scenes := 0
	var worlds := {}
	for bg in keys:
		for w in keys[bg]:
			scenes += (keys[bg][w] as Array).size()
			worlds[w] = true
	assert_gt(scenes, 150, "CONTROL: only %d overlay scenes with a backdrop were read" % scenes)
	assert_gt(keys.size(), 15, "CONTROL: only %d distinct backdrop keys were read" % keys.size())
	assert_eq(worlds.size(), 6, "CONTROL: backdrops should span all six worlds, saw %s" % str(worlds.keys()))


func test_every_backdrop_is_shown_by_one_world() -> void:
	var keys := _backdrop_worlds()
	var offenders: Array = []
	for bg in keys:
		var by_world: Dictionary = keys[bg]
		for w in by_world:
			if int(w) < 1 or int(w) > 6:
				offenders.append("%s: %s carry no world 1-6" % [bg, str(by_world[w])])
		if by_world.size() > 1:
			offenders.append("%s is shown by worlds %s" % [bg, str(by_world)])
	offenders.sort()
	assert_eq(offenders, [],
		("a backdrop is a place, and a place is in one world. Seven W2-W6 party chats named W1's "
		+ "prologue_forest and resolved fine, so only the player could see it. Point each minority scene at its "
		+ "own world's backdrop. Offenders: %s") % str(offenders))


## Story scenes that render the dimmed live capture ON PURPOSE. Each entry is a reason, not a permission.
const SHOWS_THE_LIVE_SCREEN := {
	"world3_transition": "brass becomes steel in the prose; a still of either world would contradict the transformation",
}


## An overlay story scene with no backdrop shows a dimmed capture of whatever map was under it. world6_orrery
## ("The Last Appointment") shipped that way for months, the only orrery of six without its world's backdrop.
func test_every_overlay_story_scene_names_a_backdrop() -> void:
	var missing: Array = []
	var stale: Array = []
	var scanned := 0
	for f in DirAccess.get_files_at(CUTSCENE_DIR):
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENE_DIR, f]))
		if not (parsed is Dictionary):
			continue
		var scene := parsed as Dictionary
		var w: Variant = scene.get("world", 0)
		if str(scene.get("presentation", "")) == "staged" or not (w is float or w is int) or int(w) < 1 or int(w) > 6:
			continue
		scanned += 1
		var id := f.trim_suffix(".json")
		var has_bg := str(scene.get("background", "")) != ""
		if not has_bg and not SHOWS_THE_LIVE_SCREEN.has(id):
			missing.append(id)
		elif has_bg and SHOWS_THE_LIVE_SCREEN.has(id):
			stale.append(id)
	assert_gt(scanned, 150, "CONTROL: only %d overlay story scenes were read" % scanned)
	assert_eq(missing, [], "an overlay story scene with no backdrop shows the dimmed map under it. Name its world's backdrop, or add it to SHOWS_THE_LIVE_SCREEN with the reason: %s" % str(missing))
	assert_eq(stale, [], "SHOWS_THE_LIVE_SCREEN excuses a scene that now has a backdrop; delete the line: %s" % str(stale))
