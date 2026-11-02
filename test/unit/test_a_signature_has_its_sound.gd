extends GutTest

## cowir-main 21004 ("crazy boss attacks"): each boss's signature sequence has a cue timed to its beats, plus a shared
## wind-up under the title card. Derived from monsters.json, so a new fx_signature without a sound reds here.

const SCENE := "res://src/battle/BattleScene.tscn"


func _holders() -> Array:
	var out: Array = []
	var mon: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	for id in mon:
		if mon[id] is Dictionary and str(mon[id].get("fx_signature", "")) != "":
			out.append(str(id))
	return out


func test_every_signature_has_a_recorded_cue() -> void:
	var holders := _holders()
	assert_gt(holders.size(), 5, "PREMISE: batch 1 gives all six W1 bosses a signature, found %d" % holders.size())
	var bad: Array = []
	for id in holders:
		var e: Dictionary = SoundManager._sfx_manifest.get("boss_signature_" + id, {})
		var s = load(str(e.get("file", ""))) if not e.is_empty() else null
		if s == null:
			bad.append(id)
		elif s.get_length() > 2.5:
			bad.append("%s runs %.2fs" % [id, s.get_length()])
	assert_eq(bad, [], "a boss's signature plays silent or overlong: %s" % [bad])


func test_the_title_card_has_its_wind_up() -> void:
	var e: Dictionary = SoundManager._sfx_manifest.get("boss_signature_card", {})
	assert_false(e.is_empty(), "the shared wind-up under the title card must exist")
	assert_not_null(load(str(e.get("file", ""))), "and load")


func test_the_scene_names_the_cue_by_the_casters_own_id() -> void:
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	var boss := Combatant.new()
	autofree(boss)
	boss.set_meta("monster_type", "ice_dragon")
	assert_eq(scene.signature_cue(boss), "boss_signature_ice_dragon", "Glacius's signature plays Glacius's cue")
	var nobody := Combatant.new()
	autofree(nobody)
	nobody.set_meta("monster_type", "goblin")
	assert_eq(scene.signature_cue(nobody), "", "a monster with no recorded signature asks for nothing")
