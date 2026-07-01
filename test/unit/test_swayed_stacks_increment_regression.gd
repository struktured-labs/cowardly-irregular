extends GutTest

## Regression for the swayed-stacks increment on the Bard's spotlight
## courtier duel. cowir-main tick 472 wired the win_condition dispatch
## to prefer a _<status>_stacks meta counter; this pins that counter
## goes up when a Bard song ability lands on an enemy while the current
## battle has a status_threshold win_condition.

const BM_PATH: String = "res://src/battle/BattleManager.gd"


func _make_bm() -> Node:
	var bm_script = load(BM_PATH)
	var bm: Node = bm_script.new()
	return bm


func _make_combatant(name_str: String) -> Combatant:
	var cb: Combatant = Combatant.new()
	cb.combatant_name = name_str
	cb.max_hp = 999
	cb.current_hp = 999
	cb.is_alive = true
	return cb


func _setup_status_threshold_battle(bm: Node, target: Combatant) -> void:
	bm._win_condition = {"type": "status_threshold", "status": "swayed", "value": 3}
	var party: Array[Combatant] = [target]
	bm.enemy_party = party


func test_song_defense_down_bumps_swayed_stacks() -> void:
	var bm = _make_bm()
	var caster = _make_combatant("Bard")
	var target = _make_combatant("Courtier")
	_setup_status_threshold_battle(bm, target)
	var discord_ability: Dictionary = {"id": "discord", "type": "song", "effect": "defense_down"}
	assert_eq(int(target.get_meta("_swayed_stacks", 0)), 0, "starts at 0")
	bm._maybe_bump_win_condition_status_stacks(caster, discord_ability, target)
	assert_eq(int(target.get_meta("_swayed_stacks", 0)), 1, "discord land bumps 0→1")
	bm._maybe_bump_win_condition_status_stacks(caster, discord_ability, target)
	assert_eq(int(target.get_meta("_swayed_stacks", 0)), 2, "second land bumps 1→2")
	caster.free()
	target.free()
	bm.free()


func test_song_sleep_effect_bumps_swayed_stacks() -> void:
	var bm = _make_bm()
	var caster = _make_combatant("Bard")
	var target = _make_combatant("Courtier")
	_setup_status_threshold_battle(bm, target)
	var lullaby_ability: Dictionary = {"id": "lullaby", "type": "song", "effect": "sleep"}
	bm._maybe_bump_win_condition_status_stacks(caster, lullaby_ability, target)
	assert_eq(int(target.get_meta("_swayed_stacks", 0)), 1, "lullaby (song, sleep) also bumps")
	caster.free()
	target.free()
	bm.free()


func test_non_song_ability_does_not_bump() -> void:
	var bm = _make_bm()
	var caster = _make_combatant("MonsterA")
	var target = _make_combatant("Courtier")
	_setup_status_threshold_battle(bm, target)
	## An enemy's sleep_gas or an Arbiter's Armor Break applies the
	## same effect but not via voice — must not count.
	var non_song: Dictionary = {"id": "sleep_gas", "type": "status", "effect": "sleep"}
	bm._maybe_bump_win_condition_status_stacks(caster, non_song, target)
	assert_eq(int(target.get_meta("_swayed_stacks", 0)), 0,
		"non-song abilities that apply sleep/defense_down must NOT bump swayed")
	caster.free()
	target.free()
	bm.free()


func test_no_bump_when_win_condition_absent() -> void:
	var bm = _make_bm()
	var caster = _make_combatant("Bard")
	var target = _make_combatant("SomeMob")
	bm._win_condition = {}
	var party: Array[Combatant] = [target]
	bm.enemy_party = party
	var song: Dictionary = {"id": "discord", "type": "song", "effect": "defense_down"}
	bm._maybe_bump_win_condition_status_stacks(caster, song, target)
	assert_eq(int(target.get_meta("_swayed_stacks", 0)), 0,
		"no bump when the battle has no custom win_condition (normal fights)")
	caster.free()
	target.free()
	bm.free()


func test_no_bump_when_win_condition_is_survive_turns() -> void:
	var bm = _make_bm()
	var caster = _make_combatant("Bard")
	var target = _make_combatant("Fester")
	bm._win_condition = {"type": "survive_turns", "value": 8}
	var party: Array[Combatant] = [target]
	bm.enemy_party = party
	var song: Dictionary = {"id": "discord", "type": "song", "effect": "defense_down"}
	bm._maybe_bump_win_condition_status_stacks(caster, song, target)
	assert_eq(int(target.get_meta("_swayed_stacks", 0)), 0,
		"no bump on Cleric's survive_turns duel — different win condition")
	caster.free()
	target.free()
	bm.free()


func test_no_bump_when_target_not_in_enemy_party() -> void:
	var bm = _make_bm()
	var caster = _make_combatant("Bard")
	var ally = _make_combatant("Bard Self")
	var other_enemy = _make_combatant("Courtier")
	_setup_status_threshold_battle(bm, other_enemy)
	## battle_hymn on an ally shouldn't count even though it's a song.
	var battle_hymn: Dictionary = {"id": "battle_hymn", "type": "song", "effect": "attack_up"}
	bm._maybe_bump_win_condition_status_stacks(caster, battle_hymn, ally)
	assert_eq(int(ally.get_meta("_swayed_stacks", 0)), 0,
		"ally-targeted song must not bump swayed (defensive guard)")
	caster.free()
	ally.free()
	other_enemy.free()
	bm.free()
