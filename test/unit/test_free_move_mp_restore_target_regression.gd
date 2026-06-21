extends GutTest

## Regression: Free Move MP-restore abilities Pray (Cleric) and Riff (Bard) had
## target_type=self in abilities.json AND _execute_mp_restore_ability hardcoded
## caster restoration — CLAUDE.md documents Pray=single ally and Riff=whole
## party. Both fronts are fixed:
##   - abilities.json: pray=single_ally, riff=all_allies
##   - BattleManager._execute_mp_restore_ability now honors ability.target_type

const ABILITIES_PATH := "res://data/abilities.json"


func _read_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	var data = JSON.parse_string(text)
	assert_true(data is Dictionary, "abilities.json must parse as a Dictionary")
	return data


func _make_combatant(cname: String, mp: int = 10, max_mp: int = 30) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = cname
	c.max_hp = 100
	c.current_hp = 100
	c.max_mp = max_mp
	c.current_mp = mp
	c.attack = 10
	c.defense = 10
	c.magic = 10
	c.speed = 10
	c.is_alive = true
	return c


func test_pray_target_type_is_single_ally() -> void:
	var data = _read_json(ABILITIES_PATH)
	assert_eq(data["pray"]["target_type"], "single_ally",
		"Pray must target a single ally (CLAUDE.md: 'Restores MP to a party member').")


func test_riff_target_type_is_all_allies() -> void:
	var data = _read_json(ABILITIES_PATH)
	assert_eq(data["riff"]["target_type"], "all_allies",
		"Riff must target all allies (CLAUDE.md: 'Restores MP to whole party').")


func test_channel_target_type_remains_self() -> void:
	var data = _read_json(ABILITIES_PATH)
	assert_eq(data["channel"]["target_type"], "self",
		"Channel is a self-only MP restore (Mage's Free Move).")


func test_mp_restore_all_allies_restores_every_alive_party_member() -> void:
	var bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(bm)
	var bard := _make_combatant("Bard", 5)
	var fighter := _make_combatant("Fighter", 0)
	var cleric := _make_combatant("Cleric", 8)
	add_child_autofree(bard)
	add_child_autofree(fighter)
	add_child_autofree(cleric)
	# _ready() clobbers current_mp = max_mp; re-pin the test values now.
	bard.current_mp = 5
	fighter.current_mp = 0
	cleric.current_mp = 8
	var riff_party: Array[Combatant] = [bard, fighter, cleric]
	bm.player_party = riff_party
	var ability := {
		"id": "riff",
		"name": "Riff",
		"type": "mp_restore",
		"target_type": "all_allies",
		"mp_amount": 6
	}
	bm._execute_mp_restore_ability(bard, ability, [])
	assert_eq(bard.current_mp, 11, "Bard MP must rise from 5 to 11")
	assert_eq(fighter.current_mp, 6, "Fighter MP must rise from 0 to 6")
	assert_eq(cleric.current_mp, 14, "Cleric MP must rise from 8 to 14")


func test_mp_restore_single_ally_uses_provided_target() -> void:
	var bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(bm)
	var cleric := _make_combatant("Cleric", 5)
	var fighter := _make_combatant("Fighter", 0)
	add_child_autofree(cleric)
	add_child_autofree(fighter)
	cleric.current_mp = 5
	fighter.current_mp = 0
	var pray_party: Array[Combatant] = [cleric, fighter]
	bm.player_party = pray_party
	var ability := {
		"id": "pray",
		"name": "Pray",
		"type": "mp_restore",
		"target_type": "single_ally",
		"mp_amount": 6
	}
	bm._execute_mp_restore_ability(cleric, ability, [fighter])
	assert_eq(fighter.current_mp, 6, "Pray on fighter must restore fighter's MP")
	assert_eq(cleric.current_mp, 5, "Pray on fighter must NOT restore caster")


func test_mp_restore_self_legacy_behavior_unchanged() -> void:
	# Default target_type=self (Channel) keeps the caster-only restore — proves
	# the new branching didn't break the existing free-move path.
	var bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(bm)
	var mage := _make_combatant("Mage", 3)
	add_child_autofree(mage)
	mage.current_mp = 3
	var channel_party: Array[Combatant] = [mage]
	bm.player_party = channel_party
	var ability := {
		"id": "channel",
		"name": "Channel",
		"type": "mp_restore",
		"target_type": "self",
		"mp_amount": 6
	}
	bm._execute_mp_restore_ability(mage, ability, [])
	assert_eq(mage.current_mp, 9, "Channel must restore caster only")
