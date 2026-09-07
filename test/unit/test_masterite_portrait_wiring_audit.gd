extends GutTest

## Regression: struktured directive 2026-07-16 (cowir-main msg 2658/2657) —
## the 4 Masterite families (Warden/Tempo/Arbiter/Curator) needed real
## portraits per world variant. Pre-fix, all 24 speaker names across ~460
## dialogue lines used `portrait: "mysterious"` — every masterite rendered
## the identical procedural purple portrait, no visual distinction between
## families or worlds.
##
## Coordination with cowir-sprites (thread msg 2661→2662→2665): keys match
## monsters.json IDs (`masterite_<role>_<world>`), files at
## `assets/sprites/portraits/masterite_<role>_<world>.png` — 4 medieval
## portraits first for tonight's W1 playtest, W2-W5 phased.
##
## Three ratchets:
##   (A) Every "Warden/Tempo/Arbiter/Curator ..." speaker in cutscene JSON
##       must use a masterite_<role>_<world> portrait key (not the old
##       narrator-fallback "mysterious").
##   (B) All 20 keys must be registered in PORTRAIT_SPRITES with the
##       agreed path pattern — safe to land before PNGs arrive because
##       _create_portrait falls through to mysterious via the
##       masterite_ prefix arm.
##   (C) The masterite_ prefix arm is present in _create_portrait so
##       registered-but-not-yet-delivered keys render intentionally instead
##       of falling through to narrator's grey blur.

const CUTSCENE_DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"
const MASTERITE_ROLES := ["warden", "tempo", "arbiter", "curator"]
const MASTERITE_WORLDS := ["medieval", "suburban", "industrial", "futuristic", "abstract"]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _cutscene_files() -> Array:
	var out: Array = []
	var dir = DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "cutscenes dir must open")
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append("res://data/cutscenes/%s" % f)
	return out


func test_all_20_masterite_keys_registered_in_portrait_sprites() -> void:
	var script: GDScript = load(CUTSCENE_DIALOGUE)
	assert_not_null(script, "CutsceneDialogue must load")
	var sprites: Dictionary = script.PORTRAIT_SPRITES
	var missing: Array = []
	for role in MASTERITE_ROLES:
		for world in MASTERITE_WORLDS:
			var key: String = "masterite_%s_%s" % [role, world]
			if not sprites.has(key):
				missing.append(key)
				continue
			var expected_path: String = "res://assets/sprites/portraits/%s.png" % key
			assert_eq(str(sprites[key]), expected_path,
				"PORTRAIT_SPRITES[%s] must point at %s (cowir-sprites path convention)" % [key, expected_path])
	assert_eq(missing.size(), 0,
		"all 20 masterite keys (4 roles × 5 worlds) must be registered in PORTRAIT_SPRITES: missing %s" % str(missing))


func test_create_portrait_has_masterite_prefix_arm() -> void:
	# Interim contract: keys registered before PNGs arrive must resolve to
	# something intentional (mysterious draw) instead of narrator blur.
	var src := _read(CUTSCENE_DIALOGUE)
	var fn := src.find("func _create_portrait(")
	assert_gt(fn, -1, "_create_portrait must exist")
	var end := src.find("func _create_bust_from_job_sheet", fn)
	var body := src.substr(fn, end - fn) if end > -1 else src.substr(fn)
	assert_true(body.contains('portrait_type.begins_with("masterite_")'),
		"_create_portrait must have a masterite_ prefix arm — keys registered before cowir-sprites' PNGs land would otherwise fall through to narrator's grey blur")
	# And it must route to mysterious draw (interim visual: purple mystery,
	# consistent with the pre-fix appearance so the wiring is invisible until
	# PNGs land).
	var prefix_idx := body.find('portrait_type.begins_with("masterite_")')
	var after := body.substr(prefix_idx, 200)
	assert_true(after.contains("_draw_mysterious_portrait"),
		"masterite_ prefix arm must route to _draw_mysterious_portrait (interim visual, matches pre-fix)")


func test_masterite_speakers_use_per_world_portrait_keys() -> void:
	# Every "Warden of X" / "Tempo of X" / "Arbiter of X" / "Curator of X"
	# speaker MUST use a masterite_<role>_<world> portrait key. Pre-fix all
	# 24 unique speakers shared "mysterious" — same visual for every scene.
	var offenders: Array = []
	for path in _cutscene_files():
		var parsed = JSON.parse_string(_read(path))
		if not (parsed is Dictionary):
			continue
		for step in parsed.get("steps", []):
			if not (step is Dictionary) or step.get("type") != "dialogue":
				continue
			for line in step.get("lines", []):
				if not (line is Dictionary):
					continue
				var spk: String = str(line.get("speaker", "")).strip_edges()
				var role: String = _match_masterite_role(spk)
				if role == "":
					continue
				var portrait: String = str(line.get("portrait", ""))
				if not portrait.begins_with("masterite_%s_" % role):
					offenders.append("%s: '%s' portrait='%s' (must start with masterite_%s_)" % [path.get_file(), spk, portrait, role])
	assert_eq(offenders.size(), 0,
		"Masterite speakers must use per-world portrait keys (not 'mysterious' or ''):\n  %s" % "\n  ".join(offenders))


func test_all_referenced_masterite_keys_are_registered() -> void:
	# Every masterite_<...> portrait used in JSON must be a registered
	# key — no invented "masterite_warden_alien" typos.
	var script: GDScript = load(CUTSCENE_DIALOGUE)
	var sprites: Dictionary = script.PORTRAIT_SPRITES
	var offenders: Dictionary = {}
	for path in _cutscene_files():
		var parsed = JSON.parse_string(_read(path))
		if not (parsed is Dictionary):
			continue
		for step in parsed.get("steps", []):
			if not (step is Dictionary) or step.get("type") != "dialogue":
				continue
			for line in step.get("lines", []):
				if not (line is Dictionary):
					continue
				var portrait: String = str(line.get("portrait", ""))
				if not portrait.begins_with("masterite_"):
					continue
				if sprites.has(portrait):
					continue
				if not offenders.has(portrait):
					offenders[portrait] = []
				if offenders[portrait].size() < 3:
					offenders[portrait].append(path.get_file())
	if offenders.is_empty():
		assert_true(true)
		return
	var reports: Array = []
	for p in offenders:
		reports.append("'%s' (e.g. in %s)" % [p, ", ".join(offenders[p])])
	assert_true(false,
		"cutscene JSON references masterite_ portrait keys not registered in PORTRAIT_SPRITES:\n  %s" % "\n  ".join(reports))


func _match_masterite_role(speaker: String) -> String:
	# Anchor on prefix so "Wardens" (plural) and other coincidences don't
	# match. Speakers are always singular "Warden" / "Warden of X".
	for role_name in ["Warden", "Tempo", "Arbiter", "Curator"]:
		if speaker == role_name or speaker.begins_with(role_name + " "):
			return role_name.to_lower()
	return ""
