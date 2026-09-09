extends GutTest

## Authored + engine-supported + UNREGISTERED = silently inert: the loader only builds animations named in the manifest, so has_animation() is false and play_named_animation falls back to a generic attack.

const MANIFEST := "res://data/sprite_manifest.json"
const ANIMATOR := "res://src/battle/BattleAnimator.gd"
const JOBS_DIR := "res://assets/sprites/jobs"

# an unregistered engine-known anim is only allowed with a REASON, never a bare flag
const OFF_MODEL := {
	"mage/advance": "crude blue-cone wizard, not the artist mage",
	"mage/defer": "crude blue-cone wizard, not the artist mage",
	"mage/cast_fire": "crude blue-cone wizard, not the artist mage",
	"mage/cast_ice": "crude blue-cone wizard, not the artist mage",
	"mage/cast_lightning": "crude blue-cone wizard, not the artist mage",
	"mage/cast_fira": "crude blue-cone wizard, not the artist mage",
}


func _engine_known() -> Dictionary:
	var src := FileAccess.get_file_as_string(ANIMATOR)
	assert_ne(src, "", "BattleAnimator must be readable — the known-set is derived from it, not copied")
	var names := {}
	var re := RegEx.new()
	re.compile("return \"([a-z_]+)\"")
	for mm in re.search_all(src):
		names[mm.get_string(1)] = true
	var re2 := RegEx.new()
	re2.compile("\"([a-z_]+)\"\\s*:\\s*\"([a-z_]+)\"")
	for mm in re2.search_all(src):
		names[mm.get_string(1)] = true
		names[mm.get_string(2)] = true
	return names


func test_every_engine_known_job_animation_on_disk_is_registered() -> void:
	var known := _engine_known()
	assert_true(known.has("battle_hymn"), "CONTROL: the known-set must reach a real ability anim name (%d names)" % known.size())
	assert_true(known.has("idle"), "CONTROL: the known-set must include idle")
	# without this arm a regex that matched EVERY quoted string would look identical to a correct one
	assert_false(known.has("zzq_not_an_animation"), "CONTROL: the known-set must be able to say NO — it is over-broad, so its scope is meaningless")
	var txt := FileAccess.get_file_as_string(MANIFEST)
	var parsed = JSON.parse_string(txt)
	var sheets: Dictionary = (parsed as Dictionary).get("sheets", {}) if parsed is Dictionary else {}
	assert_gt(sheets.size(), 5, "CONTROL: manifest must carry the job roster")
	var unregistered: Array = []
	var scanned := 0
	for job in sheets:
		var e: Dictionary = sheets[job]
		if not (e.get("animations") is Array):
			continue
		var reg := {}
		for a in e["animations"]:
			reg[str(a)] = true
		var d := DirAccess.open("%s/%s" % [JOBS_DIR, job])
		if d == null:
			continue
		for f in d.get_files():
			if not f.ends_with(".png") or f.contains("pre_artist"):
				continue
			var n := f.get_basename()
			if n.begins_with("overworld") or n.begins_with("idle_") or not known.has(n):
				continue
			scanned += 1
			if reg.has(n):
				continue
			var key := "%s/%s" % [job, n]
			if str(OFF_MODEL.get(key, "")).length() > 8:
				continue
			unregistered.append(key)
	assert_gt(scanned, 40, "CONTROL: the scan must reach the job animation corpus (%d)" % scanned)
	assert_eq(unregistered, [], "authored, engine-supported, and never loaded — each falls back to a generic attack: %s" % [unregistered])


func test_the_registered_ability_animations_actually_load() -> void:
	# registration is only half — prove the loader BUILDS them, so has_animation() is true at play time
	var loader = load("res://src/battle/sprites/HybridSpriteLoader.gd")
	var want := {"bard": ["lullaby", "battle_hymn", "discord", "inspiring_melody", "advance", "defer"],
		"cleric": ["heal", "raise", "buff", "advance", "defer"],
		"fighter": ["cleave", "power_strike", "provoke", "advance", "defer"]}
	var missing: Array = []
	var checked := 0
	for job in want:
		var frames = loader.call("load_sprite_frames", null, job)
		assert_not_null(frames, "CONTROL: %s must resolve through the loader" % job)
		if frames == null:
			continue
		assert_true(frames.has_animation("idle"), "CONTROL: %s must have idle" % job)
		for a in want[job]:
			checked += 1
			if not frames.has_animation(a):
				missing.append("%s/%s" % [job, a])
	assert_eq(checked, 16, "CONTROL: must check all 16 newly registered animations, checked %d" % checked)
	assert_eq(missing, [], "registered but the loader did not build them — still inert at play time: %s" % [missing])
