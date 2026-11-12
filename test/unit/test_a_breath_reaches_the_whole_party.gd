extends GutTest

## Measured on v3.33.792 (2026-11-12): 53 live boss casts of an `all_enemies` damage ability, 52 hit exactly ONE hero.
## The enemy ladder queued one target and nothing widened it. An all-enemies move now lands on the whole opposing side,
## with one spread dial (DamageRules.enemy_spread) both engines read, and two crit rules behind dials beside it.

var _guard
var _saved_spread: float
var _saved_mode: String
var _saved_inherit: bool
var _hit: Dictionary = {}


func _unit(n: String, hp: int = 5000) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": hp, "max_mp": 500, "attack": 60, "defense": 20, "magic": 60, "magic_defense": 20, "speed": 10})
	add_child_autofree(c)
	return c


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_spread = DamageRules.enemy_spread
	_saved_mode = DamageRules.crit_mode
	_saved_inherit = DamageRules.abilities_inherit_swing_crit
	_hit = {}
	BattleManager.damage_dealt.connect(_on_damage)


func after_each() -> void:
	if BattleManager.damage_dealt.is_connected(_on_damage):
		BattleManager.damage_dealt.disconnect(_on_damage)
	DamageRules.enemy_spread = _saved_spread
	DamageRules.crit_mode = _saved_mode
	DamageRules.abilities_inherit_swing_crit = _saved_inherit
	_guard.restore()


func _on_damage(target: Combatant, amount: int, _crit: bool, _element: String, _mod: float) -> void:
	_hit[target] = int(_hit.get(target, 0)) + amount


## A dragon and five heroes, in turbo so nothing waits on a presentation hold.
func _field() -> Array:
	var heroes: Array[Combatant] = []
	for i in 5:
		heroes.append(_unit("Hero%d" % i))
	var dragon := _unit("Dragon", 50000)
	dragon.learned_abilities.append("blizzard_breath")
	BattleManager.player_party.assign(heroes)
	BattleManager.enemy_party.assign([dragon] as Array[Combatant])
	BattleManager.turbo_mode = true
	return [dragon, heroes]


func test_the_rule_reaches_the_whole_side_and_leaves_a_single_target_alone() -> void:
	var a := _unit("A")
	var b := _unit("B")
	var fallen := _unit("C")
	fallen.is_alive = false
	var side: Array = [a, b, fallen]
	assert_eq(DamageRules.landing_targets({"target_type": "all_enemies"}, [a], side), [a, b], "all_enemies: every LIVING member of the side the pick is on")
	assert_eq(DamageRules.landing_targets({"target_type": "single_enemy"}, [a], side), [a], "CONTROL: a single-target move keeps its one target")
	assert_eq(DamageRules.landing_targets({"target_type": "all_enemies"}, [a, b], side), [a, b], "a list that is already the side is unchanged, so headless cannot double it")
	assert_eq(DamageRules.landing_targets({"target_type": "all_enemies"}, [], side), [], "nothing picked, nothing lands")


func test_an_enemys_breath_lands_on_all_five_in_live_play() -> void:
	var breath: Dictionary = JobSystem.get_ability("blizzard_breath")
	assert_eq(str(breath.get("target_type", "")), "all_enemies", "FLOOR: blizzard_breath is still an all-party move")
	var field := _field()
	var dragon: Combatant = field[0]
	var heroes: Array = field[1]
	await BattleManager._execute_ability(dragon, "blizzard_breath", [heroes[2]])
	assert_eq(_hit.size(), 5, "the ladder named ONE hero; the breath damaged %d of five" % _hit.size())
	for h in heroes:
		assert_gt(int(_hit.get(h, 0)), 0, "%s was hit" % h.combatant_name)


func test_a_single_target_spell_from_an_enemy_still_hits_one() -> void:
	var prison: Dictionary = JobSystem.get_ability("ice_prison")
	assert_eq(str(prison.get("target_type", "")), "single_enemy", "FLOOR: ice_prison is still single-target")
	var field := _field()
	var dragon: Combatant = field[0]
	dragon.learned_abilities.append("ice_prison")
	await BattleManager._execute_ability(dragon, "ice_prison", [field[1][2]])
	assert_eq(_hit.size(), 1, "CONTROL: a single-target spell is not widened")
	assert_true(_hit.has(field[1][2]), "and it hits the hero it was aimed at")


func test_the_spread_dial_scales_a_party_wide_hit_and_nothing_else() -> void:
	assert_eq(DamageRules.spread_factor(5, true), DamageRules.enemy_spread, "an enemy's hit on five takes the dial")
	DamageRules.enemy_spread = 0.4
	assert_almost_eq(DamageRules.spread_factor(5, true), 0.4, 0.0001, "the dial is read at call time")
	assert_almost_eq(DamageRules.spread_factor(1, true), 1.0, 0.0001, "CONTROL: one target takes the full hit")
	assert_almost_eq(DamageRules.spread_factor(5, false), 1.0, 0.0001, "CONTROL: the party's own Firaga is not softened by the enemy dial")
	## Through the engine: the same breath at 0.4 deals well under the same breath at 1.0 (variance is +-10%).
	var field := _field()
	await BattleManager._execute_ability(field[0], "blizzard_breath", [field[1][0]])
	var soft: int = int(_hit.get(field[1][0], 0))
	_hit = {}
	DamageRules.enemy_spread = 1.0
	(field[0] as Combatant).current_mp = (field[0] as Combatant).max_mp
	await BattleManager._execute_ability(field[0], "blizzard_breath", [field[1][0]])
	var full: int = int(_hit.get(field[1][0], 0))
	assert_gt(full, 0, "CONTROL: the breath lands at 1.0")
	assert_lt(float(soft), float(full) * 0.7, "at 0.4 a hero takes far less than at 1.0 (%d vs %d)" % [soft, full])


func test_the_crit_dials_ship_as_the_game_plays_today() -> void:
	assert_eq(DamageRules.crit_mode, "shipped", "the shipped formula until the live table picks one")
	assert_false(DamageRules.abilities_inherit_swing_crit, "an ability crits only if its row says so, until the table picks")
	assert_almost_eq(DamageRules.speed_crit_bonus(40.0, 10), 0.40, 0.0001, "shipped: speed x 0.01")
	assert_almost_eq(DamageRules.ability_crit_chance({}, 0.5), 0.0, 0.0001, "shipped: Power Strike never crits")
	assert_almost_eq(DamageRules.ability_crit_chance({"crit_chance": 0.3}, 0.5), 0.3, 0.0001, "a row's own chance always wins")
	DamageRules.crit_mode = "comment"
	assert_almost_eq(DamageRules.speed_crit_bonus(40.0, 10), 0.04, 0.0001, "comment: each 10 speed = +1%")
	DamageRules.crit_mode = "level"
	assert_almost_eq(DamageRules.speed_crit_bonus(100.0, 10), 0.0, 0.0001, "level: average speed for the level earns nothing")
	assert_gt(DamageRules.speed_crit_bonus(160.0, 10), 0.0, "level: speed above par earns crit")
	assert_lte(DamageRules.CRIT_BASE + DamageRules.speed_crit_bonus(9999.0, 10), DamageRules.crit_cap(), "and it cannot pass the mode's cap")
	DamageRules.abilities_inherit_swing_crit = true
	assert_almost_eq(DamageRules.ability_crit_chance({}, 0.5), 0.5, 0.0001, "inherit: a signature move crits as its user's swing does")
	assert_almost_eq(DamageRules.ability_crit_chance({"crit_chance": 0}, 0.5), 0.0, 0.0001, "and a row opts OUT with crit_chance 0")


func test_both_engines_read_the_one_rule() -> void:
	var live := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true("DamageRules.landing_targets(" in live, "live widens through the shared rule")
	assert_eq(live.count("DamageRules.spread_factor("), 2, "live applies the dial in its two damage executors, magic and physical")
	assert_true("DamageRules.speed_crit_bonus(" in live and "DamageRules.ability_crit_chance(" in live, "and its two crit reads")
	assert_false("attacker.speed * 0.01" in live, "the bare formula is gone from live")
