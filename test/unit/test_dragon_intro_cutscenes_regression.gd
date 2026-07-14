extends GutTest

## Regression: each elemental dragon cave wires a boss_cutscene_id whose
## JSON file exists, parses, and has the minimum structural beats. Prior to
## this slice, the four W1 dragons skipped straight to combat — only the
## scripted-print fallback fired, and players never saw the dialogue arrays
## sitting in _get_boss_intro_dialogue.

const CUTSCENE_DIR: String = "res://data/cutscenes/"

const DRAGON_TO_CUTSCENE: Dictionary = {
	"FireDragonCaveScene": "world1_pyrroth_intro",
	"IceDragonCaveScene": "world1_glacius_intro",
	"LightningDragonCaveScene": "world1_voltharion_intro",
	"ShadowDragonCaveScene": "world1_umbraxis_intro",
}


func _instantiate(class_name_str: String) -> Node:
	var script_path: String = "res://src/maps/dungeons/%s.gd" % class_name_str.replace("Scene", "")
	# Subclasses extend DragonCave; instantiate via the script so _init wires
	# all the cave_id / boss_id / boss_cutscene_id values.
	var script: Script = load(script_path)
	assert_not_null(script, "missing script for %s" % class_name_str)
	if script == null:
		return null
	var inst: Node = script.new()
	return inst


func test_each_dragon_cave_sets_boss_cutscene_id() -> void:
	for cls in DRAGON_TO_CUTSCENE.keys():
		var inst: Node = _instantiate(cls)
		assert_not_null(inst, "could not instantiate %s" % cls)
		if inst == null:
			continue
		var cid: String = str(inst.get("boss_cutscene_id"))
		assert_eq(cid, DRAGON_TO_CUTSCENE[cls],
			"%s.boss_cutscene_id should be %s (got %s)" % [cls, DRAGON_TO_CUTSCENE[cls], cid])
		inst.free()


func test_each_dragon_intro_cutscene_file_exists_and_parses() -> void:
	for cls in DRAGON_TO_CUTSCENE.keys():
		var cid: String = DRAGON_TO_CUTSCENE[cls]
		var path: String = CUTSCENE_DIR + cid + ".json"
		assert_true(FileAccess.file_exists(path), "missing cutscene file %s" % path)
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		assert_not_null(f, "could not open %s" % path)
		if f == null:
			continue
		var raw: String = f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(raw)
		assert_true(parsed is Dictionary, "%s did not parse as Dictionary" % path)
		if not (parsed is Dictionary):
			continue
		var d: Dictionary = parsed
		assert_eq(str(d.get("id", "")), cid, "%s id field should match filename" % path)
		var steps: Variant = d.get("steps", null)
		assert_true(steps is Array and (steps as Array).size() > 0,
			"%s must have a non-empty steps array" % path)
		# Must contain at least one dialogue step so the player actually hears the boss.
		var has_dialogue: bool = false
		for s in (steps as Array):
			if s is Dictionary and str((s as Dictionary).get("type", "")) == "dialogue":
				has_dialogue = true
				break
		assert_true(has_dialogue, "%s must contain a 'dialogue' step" % path)


## Boss-intro-stinger sweep (msg 2175/2284, 2026-07-09). The 4 dragon intros
## used to stop_music then reveal the dragon (boss_intro step) in total
## silence — dead air at the dramatic beat. rat_king + mordaine intros
## already had play_sfx; these 4 were the gap. Each now fires the 2.5s
## boss_intro_stinger doom-hit immediately BEFORE the boss_intro reveal so
## it lands on the name-drop.
func test_each_dragon_intro_fires_stinger_before_reveal() -> void:
	for cls in DRAGON_TO_CUTSCENE.keys():
		var cid: String = DRAGON_TO_CUTSCENE[cls]
		var path: String = CUTSCENE_DIR + cid + ".json"
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		assert_not_null(f, "could not open %s" % path)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if not (parsed is Dictionary):
			continue
		var steps: Array = (parsed as Dictionary).get("steps", [])
		# Find the boss_intro reveal step; the stinger must be the step
		# immediately before it (playing on the reveal, not before the
		# letterbox has framed it).
		var reveal_idx: int = -1
		for i in steps.size():
			if steps[i] is Dictionary and str(steps[i].get("type", "")) == "boss_intro":
				reveal_idx = i
				break
		assert_gt(reveal_idx, 0, "%s must have a boss_intro reveal step (not at index 0)" % cid)
		if reveal_idx <= 0:
			continue
		var prev: Dictionary = steps[reveal_idx - 1]
		assert_eq(str(prev.get("type", "")), "play_sfx",
			"%s: step before boss_intro reveal must be play_sfx (the stinger)" % cid)
		assert_eq(str(prev.get("sfx", "")), "boss_intro_stinger",
			"%s: reveal stinger must be boss_intro_stinger" % cid)


## The stinger key must resolve in the SFX manifest — otherwise it plays
## into silence (ghost sfx), which is the exact dead-air bug this sweep
## fixes. The global test_sfx_key_orphan_audit also catches this, but a
## local pin documents the dependency for this feature.
func test_boss_intro_stinger_resolves_in_manifest() -> void:
	var f: FileAccess = FileAccess.open("res://data/sfx_manifest.json", FileAccess.READ)
	assert_not_null(f, "sfx_manifest.json must be readable")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(parsed is Dictionary and (parsed as Dictionary).has("sfx"),
		"sfx_manifest.json must have an 'sfx' section")
	if not (parsed is Dictionary):
		return
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	assert_true(sfx.has("boss_intro_stinger"),
		"boss_intro_stinger must exist in sfx_manifest — dragon intros reference it")
