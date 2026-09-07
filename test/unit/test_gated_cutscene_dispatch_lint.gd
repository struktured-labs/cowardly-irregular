extends GutTest

## W1-endgame readiness ratchet (2026-07-16): every cutscene wired into
## _CUTSCENE_COMPLETION_FLAGS is on the critical story path — a missing
## file, a parse error, or a step type the CutsceneDirector can't
## dispatch wedges the game AT THE GATE, live, mid-playthrough. This
## lint walks the whole map every suite run. Generalizes the per-scene
## check from test_harmonia_after_cave_gate_regression to all 51+ gated
## scenes, and self-updates as scenes/step-types are added.

const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"
const GAME_LOOP := "res://src/GameLoop.gd"


func _dispatcher_types() -> Dictionary:
	var src := FileAccess.get_file_as_string(DIRECTOR)
	var types := {}
	var re := RegEx.new()
	re.compile("(?m)^\\t\\t\"([a-z_]+)\":")
	for m in re.search_all(src):
		types[m.get_string(1)] = true
	return types


func _gated_ids() -> Array:
	var gl = load(GAME_LOOP).new()
	autofree(gl)
	return gl._CUTSCENE_COMPLETION_FLAGS.keys()


func test_every_gated_cutscene_exists_parses_and_dispatches() -> void:
	var known := _dispatcher_types()
	assert_gt(known.size(), 20, "dispatcher type extraction must find the match block (regex drift guard)")
	var ids := _gated_ids()
	assert_gt(ids.size(), 30, "completion-flag map must be populated")
	for cid in ids:
		var path := "res://data/cutscenes/%s.json" % cid
		assert_true(FileAccess.file_exists(path),
			"gated cutscene '%s' has no JSON — the gate would fire and wedge on a missing file" % cid)
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_true(parsed is Dictionary,
			"gated cutscene '%s' failed to parse — wedges at the gate" % cid)
		if not (parsed is Dictionary):
			continue
		for s in (parsed as Dictionary).get("steps", []):
			var t := str((s as Dictionary).get("type", ""))
			assert_true(known.has(t),
				"cutscene '%s' uses step type '%s' the CutsceneDirector cannot dispatch — authored-but-unplayable" % [cid, t])
