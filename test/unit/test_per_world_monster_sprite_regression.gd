extends GutTest

## Regression test for the per-world monster sprite picker (2026-05-07).
##
## Wire-up landed for cowir-sprites' slime palette variants
## (suburban/steampunk/industrial/digital/abstract — feature/slime-world-variants
## merged as 7b37acc). BattleScene._get_monster_sprite_frames now tries
## "<monster_id>_<world_suffix>" first before falling back to the bare
## monster id, so future per-world variants of any monster auto-pick up.
##
## These tests guard against regressions:
## 1. The world-suffix lookup must remain in BattleScene, BEFORE the
##    bare-id fallback (otherwise variants are dormant)
## 2. The "medieval" suffix must skip the variant branch (no slime_medieval
##    is registered — that path would be a wasted manifest lookup)
## 3. The 5 slime variants must remain in sprite_manifest.json under
##    monster_sheets (so the picker has something to pick)
## 4. SoundManager._get_current_world_suffix must remain accessible
##    (BattleScene depends on it)


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_battle_scene_picks_per_world_variant_first() -> void:
	"""BattleScene._get_monster_sprite_frames must try the world-variant
	id (<monster>_<suffix>) BEFORE the bare id. Putting the bare-id lookup
	first would mean variants only show up when the bare id is missing —
	exact opposite of intent (variants should override on themed worlds)."""
	var text = _read("res://src/battle/BattleScene.gd")
	var idx = text.find("func _get_monster_sprite_frames")
	assert_gt(idx, -1, "_get_monster_sprite_frames must exist")
	var next_func = text.find("\nfunc ", idx + 1)
	if next_func == -1:
		next_func = text.length()
	var body = text.substr(idx, next_func - idx)
	var variant_idx = body.find("variant_id")
	var external_idx = body.find("external_frames")
	assert_gt(variant_idx, -1,
		"_get_monster_sprite_frames must reference variant_id (per-world picker)")
	assert_gt(external_idx, -1,
		"_get_monster_sprite_frames must keep the external_frames fallback")
	assert_lt(variant_idx, external_idx,
		"variant lookup must come BEFORE bare-id lookup (regression: order swapped, variants dormant)")


func test_medieval_skips_variant_lookup() -> void:
	"""On the base "medieval" world there's no <id>_medieval variant
	registered — skipping the lookup avoids a wasted manifest miss every
	time a monster sprite is built. If the skip-medieval branch is removed,
	every battle in W1 pays for an unnecessary lookup per enemy."""
	var text = _read("res://src/battle/BattleScene.gd")
	var idx = text.find("func _get_monster_sprite_frames")
	var next_func = text.find("\nfunc ", idx + 1)
	if next_func == -1:
		next_func = text.length()
	var body = text.substr(idx, next_func - idx)
	assert_true(body.find("medieval") != -1,
		"_get_monster_sprite_frames must skip medieval (regression: lookup runs every W1 battle)")


func test_slime_variants_present_in_manifest() -> void:
	"""All 5 slime variants must be registered in sprite_manifest.json
	under monster_sheets. If they get removed or renamed, the picker
	silently falls back to the base slime everywhere."""
	var text = _read("res://data/sprite_manifest.json")
	var json = JSON.new()
	var parse_result = json.parse(text)
	assert_eq(parse_result, OK, "sprite_manifest.json must parse as valid JSON")
	var data: Dictionary = json.data
	var sheets = data.get("monster_sheets", {})
	for variant in ["slime_suburban", "slime_steampunk", "slime_industrial", "slime_digital", "slime_abstract"]:
		assert_true(sheets.has(variant),
			"sprite_manifest.json monster_sheets must include '%s' (regression: variant removed, picker dormant)" % variant)


func test_sound_manager_world_suffix_helper_remains() -> void:
	"""BattleScene._get_monster_sprite_frames calls
	SoundManager._get_current_world_suffix() to decide which variant id to
	try. If that helper is renamed or made private differently, the
	picker breaks silently (no compile error if the call is in a string-
	concat expression). Verify the symbol still exists in source."""
	var text = _read("res://src/audio/SoundManager.gd")
	assert_true(text.find("func _get_current_world_suffix") != -1,
		"SoundManager._get_current_world_suffix must remain (regression: per-world sprite picker breaks)")
