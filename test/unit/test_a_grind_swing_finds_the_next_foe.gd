extends GutTest

## A grind blow aimed at a foe that fell earlier in the round goes to the lowest-HP foe still standing, as live's _retarget_enemy sends it.
## Before this the headless executor dropped the action, so a party aiming at the weakest foe killed one foe a round.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()
	_res.use_live_enemy_ladder = false


func after_each() -> void:
	DamageRules.enemy_spread = 1.0
	DamageRules.crit_mode = "shipped"
	DamageRules.abilities_inherit_swing_crit = false


func _body(who: String, hp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": who, "max_hp": 9999, "max_mp": 999, "attack": 60, "defense": 10, "magic": 60, "magic_defense": 5, "speed": 10})
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = c.max_mp
	c.is_alive = hp > 0
	return c


## One hero, a second hero, and three foes: one fallen, one hurt, one fresh.
func _field() -> Dictionary:
	var f := {"hero": _body("Hero", 9999), "ally": _body("Ally", 9999),
		"fallen": _body("Fallen", 0), "hurt": _body("Hurt", 4000), "fresh": _body("Fresh", 9000)}
	_res._player_party = [f["hero"], f["ally"]]
	_res._enemy_party = [f["fallen"], f["fresh"], f["hurt"]]
	return f


func test_the_subject_exposes_what_these_arms_drive() -> void:
	for m in ["_execute_action", "_retarget_foe", "_retarget_ability_targets", "_resolve_ability", "_foe_ability_targets", "_swing_crit_chance"]:
		assert_true(_res.has_method(m), "%s is driven below; a rename would abort an arm" % m)
	assert_true("_player_party" in _res and "_enemy_party" in _res, "the two party arrays are set by hand below")
	assert_eq(str(JobSystem.get_ability("fire").get("target_type", "")), "single_enemy", "CONTROL: fire is the one-foe spell these arms cast")
	assert_eq(str(JobSystem.get_ability("cure").get("type", "")), "healing", "CONTROL: cure is the heal that must not follow a foe")
	assert_true(BattleManager.has_method("_retarget_enemy"), "live's rule, which the parity arm asks")


func test_a_swing_at_a_fallen_foe_lands_on_the_weakest_one_standing() -> void:
	var f := _field()
	_res._execute_action({"type": "attack", "combatant": f["hero"], "target": f["fallen"]})
	assert_lt(f["hurt"].current_hp, 4000, "the swing went to the lowest-HP foe still standing")
	assert_eq(f["fresh"].current_hp, 9000, "and to nobody else")


func test_a_swing_at_a_standing_foe_stays_on_it() -> void:
	var f := _field()
	_res._execute_action({"type": "attack", "combatant": f["hero"], "target": f["fresh"]})
	assert_lt(f["fresh"].current_hp, 9000, "CONTROL: a living target keeps the blow")
	assert_eq(f["hurt"].current_hp, 4000, "CONTROL: the weaker foe is not preferred over a living target")


func test_a_one_foe_spell_follows_too() -> void:
	var f := _field()
	_res._execute_action({"type": "ability", "combatant": f["hero"], "ability_id": "fire", "targets": [f["fallen"]]})
	assert_lt(f["hurt"].current_hp, 4000, "the spell went to the lowest-HP foe still standing")
	assert_eq(f["fresh"].current_hp, 9000, "and to nobody else")
	assert_lt(f["hero"].current_mp, f["hero"].max_mp, "it was a real cast: the MP was paid")


func test_a_heal_at_a_fallen_ally_is_not_sent_to_a_foe() -> void:
	var f := _field()
	f["ally"].current_hp = 0
	f["ally"].is_alive = false
	var kept: Array = _res._retarget_ability_targets(f["hero"], "cure", [f["ally"]])
	assert_eq(kept.size(), 1, "a heal keeps its one target")
	assert_true(kept.size() == 1 and kept[0] == f["ally"], "and it is still the ally, not a foe")
	var widened: Array = _res._retarget_ability_targets(f["hero"], "fire", [f["hurt"], f["fallen"]])
	assert_eq(widened.size(), 2, "a list that was already expanded is left as it was handed in")


func test_with_no_foe_standing_the_blow_does_nothing() -> void:
	var f := _field()
	for k in ["hurt", "fresh"]:
		f[k].current_hp = 0
		f[k].is_alive = false
	assert_null(_res._retarget_foe(f["hero"], f["fallen"]), "nobody to send it to")
	_res._execute_action({"type": "attack", "combatant": f["hero"], "target": f["fallen"]})
	assert_eq(f["ally"].current_hp, 9999, "and it does not fall on the hero's own side")


func test_a_foe_whose_mark_fell_turns_on_the_weakest_hero() -> void:
	var f := _field()
	f["ally"].current_hp = 3000
	var dead_hero := _body("Gone", 0)
	_res._player_party = [dead_hero, f["hero"], f["ally"]]
	_res._execute_action({"type": "attack", "combatant": f["fresh"], "target": dead_hero})
	assert_lt(f["ally"].current_hp, 3000, "a foe's blow follows the same rule onto the party")
	assert_eq(f["hero"].current_hp, 9999, "and lands on one hero only")


func test_the_grind_picks_who_live_picks() -> void:
	var f := _field()
	var was_party: Array = BattleManager.player_party
	var was_foes: Array = BattleManager.enemy_party
	BattleManager.player_party = [f["hero"], f["ally"]]
	BattleManager.enemy_party = [f["fallen"], f["fresh"], f["hurt"]]
	var live = BattleManager._retarget_enemy(f["hero"], f["fallen"])
	BattleManager.player_party = was_party
	BattleManager.enemy_party = was_foes
	assert_not_null(live, "CONTROL: live finds a foe to send it to")
	assert_true(live == _res._retarget_foe(f["hero"], f["fallen"]), "both engines send the blow to the same foe")


## Five heroes at full HP and one foe that casts; returns the HP each hero lost to one cast of `ability_id` on `targets_of`.
func _foe_cast_losses(ability_id: String, whole_party: bool) -> Array:
	var party: Array = []
	for i in range(5):
		party.append(_body("PC%d" % i, 9999))
	var foe := _body("Caster", 9999)
	_res._player_party = party
	_res._enemy_party = [foe]
	_res._resolve_ability(foe, ability_id, party if whole_party else [party[0]])
	var lost: Array = []
	for c in party:
		lost.append(9999 - c.current_hp)
	return lost


func test_a_foes_party_wide_move_reads_the_shared_spread_dial() -> void:
	assert_eq(str(JobSystem.get_ability("firaga").get("target_type", "")), "all_enemies", "CONTROL: firaga is the party-wide move cast below")
	var full: Array = _foe_cast_losses("firaga", true)
	DamageRules.enemy_spread = 0.4
	var spread: Array = _foe_cast_losses("firaga", true)
	assert_gt(int(full[0]), 0, "CONTROL: at 1.0 the cast lands")
	assert_gt(int(spread[4]), 0, "at 0.4 it still lands on the last hero")
	assert_lt(int(spread[0]), int(full[0]), "and each hero takes less than at 1.0")
	var one_full: Array = []
	DamageRules.enemy_spread = 1.0
	one_full = _foe_cast_losses("fire", false)
	DamageRules.enemy_spread = 0.4
	var one_spread: Array = _foe_cast_losses("fire", false)
	assert_gt(int(one_full[0]), 0, "CONTROL: the one-target spell lands")
	assert_eq(int(one_spread[0]), int(one_full[0]), "CONTROL: a one-target move ignores the dial")


func test_the_partys_own_party_wide_move_ignores_the_dial() -> void:
	var f := _field()
	_res._resolve_ability(f["hero"], "firaga", [f["hurt"], f["fresh"]])
	var lost_full: int = 9000 - f["fresh"].current_hp
	f = _field()
	DamageRules.enemy_spread = 0.4
	_res._resolve_ability(f["hero"], "firaga", [f["hurt"], f["fresh"]])
	assert_gt(lost_full, 0, "CONTROL: the party's cast lands")
	assert_eq(9000 - f["fresh"].current_hp, lost_full, "the dial is for a foe's move; the party's lands whole")


func test_a_list_the_grind_already_widened_is_not_widened_again() -> void:
	var party: Array = []
	for i in range(5):
		party.append(_body("PC%d" % i, 9999))
	var mine: Array = _res._foe_ability_targets("firaga", party[0], party)
	var both: Array = DamageRules.landing_targets(JobSystem.get_ability("firaga"), mine, party)
	assert_eq(mine.size(), 5, "CONTROL: the grind hands a foe's party-wide move the whole party")
	assert_eq(both.size(), 5, "and the shared rule returns the same five, not ten")


func test_a_swing_crits_by_the_rule_live_reads() -> void:
	var hero := _body("Swift", 9999)
	hero.speed = 20
	for mode in ["shipped", "comment", "level"]:
		DamageRules.crit_mode = mode
		var want: float = minf(DamageRules.crit_cap(), DamageRules.CRIT_BASE + DamageRules.speed_crit_bonus(20.0, int(BattleManager._archetype_level(hero))))
		assert_almost_eq(_res._swing_crit_chance(hero), want, 0.0001, "%s: the grind's swing crit is the shared rule's" % mode)
		assert_almost_eq(float(BattleManager._calculate_crit_chance(hero)), want, 0.0001, "%s: and live's, for a hero with no gear or passives" % mode)
	DamageRules.crit_mode = "shipped"
	assert_almost_eq(_res._swing_crit_chance(hero), 0.25, 0.0001, "CONTROL: shipped is 5% + speed x 1%")
	DamageRules.crit_mode = "comment"
	assert_lt(_res._swing_crit_chance(hero), 0.25, "and the modes differ, so the arm above can tell them apart")
