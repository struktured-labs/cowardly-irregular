extends GutTest

## cowir-main 21004 ("crazy boss attacks") then 21676: a signature or glory sequence's sound rides its PHASES ("sfx" keys
## fired in battle time), because one wall-clock sample was in sync only at 4x and early at the 1x every first signature
## plays at. Derived from monsters.json / abilities.json / vfx_sequences.json, so a new signature or glory spell without
## beats reds here. The shared title-card wind-up stays a flourish.

const SCENE := "res://src/battle/BattleScene.tscn"
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const MAX_BEAT_SECONDS := 1.2

var _guard: RefCounted = null


## A live BattleScene starts a battle on the autoload; without this the leak sentinel downstream reads state=3.
func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func _json(path: String) -> Dictionary:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return p if p is Dictionary else {}


func _holders() -> Dictionary:
	var out := {}
	var mon := _json("res://data/monsters.json")
	for id in mon:
		if mon[id] is Dictionary and str(mon[id].get("fx_signature", "")) != "":
			out[str(id)] = str(mon[id].get("fx_signature_sequence", "sig_" + str(id)))
	return out


func _glory() -> Dictionary:
	var out := {}
	var ab := _json("res://data/abilities.json")
	for id in ab:
		var vfx: Variant = (ab[id] as Dictionary).get("vfx", {}) if ab[id] is Dictionary else {}
		if vfx is Dictionary and str(vfx.get("glory", "")) != "":
			out[str(id)] = str(vfx["glory"])
	return out


func _phases(seq_id: String) -> Array:
	var seqs: Dictionary = _json("res://data/vfx_sequences.json").get("sequences", {})
	return (seqs.get(seq_id, {}) as Dictionary).get("phases", [])


## The problems with one sequence's beats, or [] when it voices them.
func _beat_faults(seq_id: String, min_beats: int) -> Array:
	var faults: Array = []
	var beats := 0
	for ph in _phases(seq_id):
		var key := str((ph as Dictionary).get("sfx", ""))
		if key == "":
			continue
		beats += 1
		var e: Dictionary = SoundManager._sfx_manifest.get(key, {})
		var s = load(str(e.get("file", ""))) if not e.is_empty() else null
		if s == null:
			faults.append("%s names %s, which does not load" % [seq_id, key])
		elif s.get_length() > MAX_BEAT_SECONDS:
			faults.append("%s's %s runs %.2fs" % [seq_id, key, s.get_length()])
	if beats < min_beats:
		faults.append("%s voices %d beats, needs %d" % [seq_id, beats, min_beats])
	return faults


func test_every_boss_signature_voices_its_beats() -> void:
	var holders := _holders()
	assert_gt(holders.size(), 5, "PREMISE: batch 1 gives all six W1 bosses a signature, found %d" % holders.size())
	var bad: Array = []
	for id in holders:
		bad.append_array(_beat_faults(holders[id], 2))
	assert_eq(bad, [], "a boss signature plays silent, mistimed or overlong: %s" % [bad])


func test_every_glory_spell_voices_its_first_impact() -> void:
	var glory := _glory()
	assert_gt(glory.size(), 2, "PREMISE: batch 2 gives Firaga, Blizzaga and Thundaga a glory sequence, found %d" % glory.size())
	var bad: Array = []
	for id in glory:
		bad.append_array(_beat_faults(glory[id], 2))
		var tier1_impact := false
		for ph in _phases(glory[id]):
			var d: Dictionary = ph
			if str(d.get("sfx", "")) != "" and int(d.get("min_tier", 1)) <= 1 and str(d.get("kind", "")) == "flash":
				tier1_impact = true
		if not tier1_impact:
			bad.append("%s (%s) has no voiced impact a tier-1 caster hears" % [id, glory[id]])
	assert_eq(bad, [], "a glory spell plays without its beats: %s" % [bad])


func test_no_wall_clock_sample_plays_under_the_beats() -> void:
	# Off-tree: these arms read two pure functions, and a live scene starts a battle that outlives the file (it moved the next file's clock).
	var scene = load(SCENE).instantiate()
	autofree(scene)
	var holders := _holders()
	assert_gt(holders.size(), 5, "PREMISE: the holders are found")
	var doubled: Array = []
	for id in holders:
		var boss := Combatant.new()
		autofree(boss)
		boss.set_meta("monster_type", id)
		if scene.signature_cue(boss) != "":
			doubled.append("%s -> %s" % [id, scene.signature_cue(boss)])
	assert_eq(doubled, [], "a one-sample signature cue would play on top of its phase beats, early at 1x: %s" % [doubled])


func test_the_title_card_has_its_wind_up() -> void:
	var e: Dictionary = SoundManager._sfx_manifest.get("boss_signature_card", {})
	assert_false(e.is_empty(), "the shared wind-up under the title card must exist")
	assert_not_null(load(str(e.get("file", ""))), "and load")


func test_signature_sounds_play_at_4x_and_only_the_grind_is_silent() -> void:
	# Off-tree: these arms read two pure functions, and a live scene starts a battle that outlives the file (it moved the next file's clock).
	var scene = load(SCENE).instantiate()
	autofree(scene)
	var saved := Engine.time_scale
	Engine.time_scale = 1.0
	var at_4x: bool = scene.signature_sound_allowed()
	scene.autogrind_console_mode = true
	var in_grind: bool = scene.signature_sound_allowed()
	scene.autogrind_console_mode = false
	scene.turbo_mode = true
	var in_turbo: bool = scene.signature_sound_allowed()
	scene.turbo_mode = false
	Engine.time_scale = saved
	assert_false(in_turbo, "turbo stays silent")
	assert_true(at_4x, "he plays at 4x; the move he asked for must be heard there (cowir-main 21194)")
	assert_false(in_grind, "the autogrind console stays silent")
