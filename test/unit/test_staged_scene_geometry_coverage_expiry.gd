extends GutTest

## EXPIRY for a gap I deferred in prose, which is the failure mode the fleet
## named on 2026-07-30: a self-documented gap needs a condition that FAILS, not
## a comment that waits.
##
## test_staged_scene_live_geometry_smoke is the only check that proves a staged
## cutscene still LOOKS right — it builds the real village and asserts puppet
## marks land on walkable ground, walk paths don't cross buildings, and camera
## targets show authored scenery. It carries a hardcoded two-entry list.
##
## Measured on main: 6 staged cutscenes on disk, 2 covered.
##
## The four uncovered cannot be fixed by adding list entries, which is why this
## is an expiry rather than a patch — they play on three DIFFERENT maps while the
## smoke instantiates HarmoniaVillage:
##   world1_mordaine_watch_castle/speaks/procedure  -> Castle Harmonia floors 1-3
##   world1_mordaine_watch_road                     -> the overworld
##
## Their marks were all measured clean by hand (F1 (17,6), F2 (16,7), F3 (15,7)
## are floor tiles in CastleHarmonia's own layouts), so nothing is broken today.
## What was missing is anything that fails when a SEVENTH staged scene is added.
##
## This requires the DELIVERABLE, never permission to skip: a new staged scene
## must either be geometry-checked, or name the map it plays on. Naming the map
## is the input a future extension of the smoke actually needs, so the binding is
## work-in-progress rather than an allowlist. And a binding for a scene the smoke
## already covers FAILS — the carve-out cannot outlive its reason.

const CUTSCENE_DIR := "res://data/cutscenes"
const SMOKE := "res://test/unit/test_staged_scene_live_geometry_smoke.gd"

## staged cutscene id -> the map it plays on. Castle Harmonia is script-instantiated
## (no .tscn); the village and overworld are PackedScenes. Both forms are accepted,
## and both are asserted to resolve.
const MAP_BINDINGS := {
	"world1_mordaine_watch_castle": "res://src/maps/dungeons/CastleHarmonia.gd",
	"world1_mordaine_speaks": "res://src/maps/dungeons/CastleHarmonia.gd",
	"world1_mordaine_procedure": "res://src/maps/dungeons/CastleHarmonia.gd",
	"world1_mordaine_watch_road": "res://src/exploration/OverworldScene.tscn",
	"world1_mordaine_intro": "res://src/maps/dungeons/CastleHarmonia.gd",
}


func _staged_ids() -> Array:
	var out: Array = []
	var dir := DirAccess.open(CUTSCENE_DIR)
	assert_not_null(dir, "cutscenes dir must open")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENE_DIR, f]))
		if parsed is Dictionary and str(parsed.get("presentation", "")) == "staged":
			out.append(f.substr(0, f.length() - 5))
	return out


## Read from the smoke's CONSTANT, not its source text. A regex over source models
## one authoring shape; a scene added as "…%s.json" % id would be invisible and read
## as uncovered, firing a false RED on correct work. Same defect as reading
## _CUTSCENE_COMPLETION_FLAGS by regex — that gave 8 of 55.
func _smoke_covered() -> Array:
	var script := load(SMOKE)
	assert_not_null(script, "the geometry smoke must load at %s" % SMOKE)
	var paths = script.get_script_constant_map().get("STAGED_SCENES", [])
	assert_gt(paths.size(), 0,
		"the smoke's STAGED_SCENES const must be readable — if it was renamed, every scene reads as uncovered and this file fails for the wrong reason")
	var out: Array = []
	for p in paths:
		var id := str(p).get_file().get_basename()
		if id != "" and not out.has(id):
			out.append(id)
	return out


func test_every_staged_scene_is_geometry_checked_or_names_its_map() -> void:
	# THE expiry. A seventh staged scene fails here until someone says which map
	# it plays on, which is the fact a geometry check cannot be written without.
	var staged := _staged_ids()
	assert_gt(staged.size(), 4,
		"POSITIVE CONTROL: the corpus must yield several staged scenes — a small number makes everything below vacuous")
	var covered := _smoke_covered()
	assert_gt(covered.size(), 0,
		"POSITIVE CONTROL: the smoke must name at least one scene, or its source stopped parsing and every scene reads as uncovered")
	var unaccounted: Array = []
	for id in staged:
		if covered.has(id) or MAP_BINDINGS.has(id):
			continue
		unaccounted.append(id)
	assert_eq(unaccounted.size(), 0,
		"staged cutscenes with neither geometry coverage nor a map binding: %s\n  Add it to the smoke's STAGED_SCENES if it plays on HarmoniaVillage, else name its map in MAP_BINDINGS — a geometry check cannot be written without knowing the map." % str(unaccounted))


func test_every_binding_names_a_map_that_exists() -> void:
	# A binding that names nothing is an allowlist wearing a deliverable's clothes.
	var offenders: Array = []
	for id in MAP_BINDINGS:
		var path: String = MAP_BINDINGS[id]
		if not ResourceLoader.exists(path):
			offenders.append("%s -> %s" % [id, path])
	assert_eq(offenders.size(), 0,
		"every map binding must resolve to a real scene or script: %s" % str(offenders))


func test_bindings_only_cover_scenes_that_still_exist() -> void:
	# Self-destructing in the other direction: a binding for a deleted or renamed
	# cutscene is dead weight that reads as coverage.
	var staged := _staged_ids()
	var stale: Array = []
	for id in MAP_BINDINGS:
		if not staged.has(id):
			stale.append(id)
	assert_eq(stale.size(), 0,
		"MAP_BINDINGS names cutscenes that are no longer staged (or no longer exist): %s — remove them" % str(stale))


func test_a_binding_for_a_covered_scene_is_rejected() -> void:
	# The carve-out cannot outlive its reason. When the smoke is extended to cover
	# one of these, its binding must go, or this fails.
	var covered := _smoke_covered()
	var redundant: Array = []
	for id in MAP_BINDINGS:
		if covered.has(id):
			redundant.append(id)
	assert_eq(redundant.size(), 0,
		"these scenes are geometry-checked AND carry a map binding: %s — drop the binding, the check supersedes it" % str(redundant))


func test_the_derivations_discriminate() -> void:
	# NEGATIVE CONTROL. Both sets are derived; an invented id must appear in
	# neither, else the assertions above would pass on anything.
	var staged := _staged_ids()
	var covered := _smoke_covered()
	assert_false(staged.has("zzz_not_a_staged_scene"), "the staged derivation must not match an invented id")
	assert_false(covered.has("zzz_not_a_staged_scene"), "the coverage derivation must not match an invented id")
	assert_false(MAP_BINDINGS.has("zzz_not_a_staged_scene"), "the binding table must not match an invented id")
	# And the covered set must actually be a subset of the staged set — if the
	# regex started matching unrelated paths this would drift silently.
	for id in covered:
		assert_true(staged.has(id),
			"the smoke names '%s' which is not a staged cutscene — the coverage derivation is matching the wrong thing" % id)
