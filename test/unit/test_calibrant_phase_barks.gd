extends GutTest

## Fable's combat voice had no delivery: the per-face taunts and the react-to-how-you-fight
## lines sat in tmp/ (which gets cleaned) with zero consumers — the authored-with-no-consumer
## class this fleet catalogued five times in one night, about to be instance six.
##
## Now data/boss_dialogue.json carries phase_barks keyed by _boss_face_index, and
## BattleManager._maybe_boss_phase_bark delivers deterministically through battle_log_message:
## reactions fire ONCE per face (advance / autobattle), taunts rotate every 4th player action.
## The thesis line — the boss noticing you let a script fight it — is on_autobattle.

const CALIBRANT := "the_calibrant"

var _lines: Array[String] = []
var _saved_enemy: Array = []
var _saved_player: Array = []


func before_each() -> void:
	_lines = []
	_saved_enemy = BattleManager.enemy_party.duplicate()
	_saved_player = BattleManager.player_party.duplicate()
	BattleManager.battle_log_message.connect(_capture)


func after_each() -> void:
	BattleManager.battle_log_message.disconnect(_capture)
	BattleManager.enemy_party.assign(_saved_enemy)
	BattleManager.player_party.assign(_saved_player)


func _capture(msg: String) -> void:
	if "magenta" in msg:
		_lines.append(msg)


func _rig() -> Array:
	var boss := Combatant.new()
	boss.combatant_name = "The Calibrant"
	boss.is_alive = true
	boss.max_hp = 100
	boss.current_hp = 100
	boss.set_meta("monster_type", CALIBRANT)
	var pc := Combatant.new()
	pc.combatant_name = "Riff"
	pc.is_alive = true
	var te: Array[Combatant] = [boss]
	var tp: Array[Combatant] = [pc]
	BattleManager.enemy_party = te
	BattleManager.player_party = tp
	return [boss, pc]


func test_phase_barks_cover_every_face_index() -> void:
	var boss_dlg = get_node_or_null("/root/BossDialogue")
	assert_not_null(boss_dlg, "BossDialogue autoload required")
	if boss_dlg == null:
		return
	var barks: Dictionary = boss_dlg.get_phase_barks(CALIBRANT)
	assert_false(barks.is_empty(), "the Calibrant ships its combat voice in data, not in tmp/")
	# _boss_face_index runs 0 (opening) .. 5 (no face at all): six wearable states.
	for k in ["0", "1", "2", "3", "4", "5"]:
		assert_true(barks.has(k), "face index %s must have a bark pool" % k)
		for pool in ["taunts", "on_advance", "on_autobattle"]:
			assert_gt((barks[k].get(pool, []) as Array).size(), 0,
				"face %s needs non-empty %s — an empty pool barks nothing, silently" % [k, pool])
	assert_false(boss_dlg.get_phase_barks("slime").size() > 0,
		"CONTROL: a boss without phase_barks returns {} — ordinary monsters stay quiet")


func test_an_advance_is_answered_once_per_face() -> void:
	var rig := _rig()
	var pc: Combatant = rig[1]
	BattleManager._log_player_action(pc, {"type": "advance", "actions": []})
	assert_eq(_lines.size(), 1, "the first Advance gets an answer")
	assert_string_contains(_lines[0], "The Calibrant:", "and it is the boss speaking")
	BattleManager._log_player_action(pc, {"type": "advance", "actions": []})
	assert_eq(_lines.size(), 1, "the SAME face never answers an Advance twice — once per face, not a heckle loop")
	# A new face re-arms the reaction: the boss that changed is allowed to notice again.
	var boss: Combatant = rig[0]
	boss.set_meta("_boss_face_index", 5)
	BattleManager._log_player_action(pc, {"type": "advance", "actions": []})
	assert_eq(_lines.size(), 2, "a face change re-arms the advance reaction")


func test_taunts_rotate_on_a_deterministic_cadence() -> void:
	var rig := _rig()
	var pc: Combatant = rig[1]
	for i in range(8):
		BattleManager._log_player_action(pc, {"type": "attack"})
	assert_eq(_lines.size(), 2, "8 plain actions = 2 taunts (every 4th) — sparse, not spam")
	assert_ne(_lines[0], _lines[1], "consecutive taunts rotate through the pool, not repeat")


func test_a_boss_without_barks_stays_silent() -> void:
	var rig := _rig()
	var boss: Combatant = rig[0]
	boss.set_meta("monster_type", "slime")
	BattleManager._log_player_action(rig[1], {"type": "advance", "actions": []})
	for i in range(8):
		BattleManager._log_player_action(rig[1], {"type": "attack"})
	assert_eq(_lines.size(), 0,
		"CONTROL: the bark path is a no-op for every monster without phase_barks data")
