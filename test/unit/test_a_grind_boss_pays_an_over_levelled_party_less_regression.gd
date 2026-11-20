extends GutTest

## A headless (ludicrous) grind boss paid its whole EXP to every member, however far over the fight they stood.
## Live BattleManager halves EXP per ExpRules.HALVING_LEVELS over the fight for bosses too, so the grind farmed bosses at full rate.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const AREA := 12
const POT := 400

var _ag_state: Dictionary


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutogrindSystem.per_character_exp.clear()
	AutogrindSystem.last_area_level = AREA


func after_each() -> void:
	AutogrindState.restore(_ag_state)


func _member(name: String, level: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 500, "max_mp": 50,
		"attack": 20, "defense": 20, "magic": 20, "speed": 20})
	add_child_autofree(c)
	c.job_level = level
	c.job_exp = 0
	c.is_alive = true
	return c


func test_a_member_at_the_fights_level_keeps_the_whole_pot() -> void:
	var hero := _member("AtLevel", AREA)
	AutogrindSystem.grind_party = [hero]
	AutogrindSystem.account_boss_fight_rewards(POT, {}, true)
	assert_eq(hero.job_exp, POT, "CONTROL: a member at the boss's level is paid the whole pot")


func test_an_over_levelled_member_is_paid_what_live_would_pay() -> void:
	var hero := _member("Over", AREA + 6)
	var want := int(POT * ExpRules.over_level_factor(hero.job_level, AREA))
	assert_lt(want, POT, "CONTROL: six levels over the fight must cost EXP, or this arm proves nothing")
	AutogrindSystem.grind_party = [hero]
	AutogrindSystem.account_boss_fight_rewards(POT, {}, true)
	assert_eq(hero.job_exp, want, "the headless boss must halve EXP per %d levels over, as live does" % int(ExpRules.HALVING_LEVELS))
	assert_eq(int(AutogrindSystem.per_character_exp.get("Over", -1)), want, "the session bar must show what was paid")


func test_a_watched_boss_pays_nothing_here_and_the_bar_keeps_the_pot() -> void:
	var hero := _member("Watched", AREA + 6)
	AutogrindSystem.grind_party = [hero]
	AutogrindSystem.account_boss_fight_rewards(POT, {}, false)
	assert_eq(hero.job_exp, 0, "a watched fight was already paid by BattleManager")
	assert_eq(int(AutogrindSystem.per_character_exp.get("Watched", -1)), POT, "the watched bar is unchanged by this fix")
