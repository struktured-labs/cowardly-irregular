extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ControllerScript := preload("res://src/autogrind/AutogrindController.gd")

## A meta-boss (and a collapse boss) returns from on_battle_ended before on_battle_victory,
## so the bonus cannot be paid twice on top of a watched fight. That return also discarded
## the fight's own EXP, gold, and item tally.
##
## Watched fights still received them from BattleManager, then the summary and the history
## row omitted them — Total Gold stayed flat while the wallet moved. Ludicrous speed never
## enters BattleManager, so the same return paid only the bonus: the slime's gold and the
## fight's job EXP were deleted. The console still printed the fight's EXP.

var _ag: Dictionary
var _gold: int
var _c: Node

const FIGHT_EXP := 100
const FIGHT_GOLD := 80
const BONUS_EXP := 40


func before_each() -> void:
	_ag = AutogrindState.snapshot_and_isolate()
	_gold = GameState.party_gold
	AutogrindSystem.current_region_id = ""
	_c = ControllerScript.new()
	add_child_autofree(_c)


func after_each() -> void:
	GameState.party_gold = _gold
	AutogrindState.restore(_ag)


func _hero(name: String, alive: bool) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 500, "max_mp": 50,
		"attack": 20, "defense": 20, "magic": 20, "speed": 20})
	add_child_autofree(c)
	c.job_level = 30
	c.job_exp = 0
	c.current_hp = c.max_hp if alive else 0
	c.is_alive = alive
	return c


func _win_boss(headless: bool, collapse: bool, victory: bool = true) -> void:
	_c.headless_mode = headless
	_c._state = _c.State.BATTLE_RUNNING
	_c._current_battle_is_meta_boss = true
	_c._current_battle_is_collapse_boss = collapse
	_c._current_meta_boss_data = {"name": "Probe Boss", "exp_reward": BONUS_EXP}
	_c.on_battle_ended(victory, FIGHT_EXP if victory else 0, {"gold": FIGHT_GOLD, "potion": 2} if victory else {})


func test_ludicrous_meta_boss_pays_the_fights_exp_and_gold() -> void:
	var hero := _hero("Grinder", true)
	AutogrindSystem.grind_party = [hero] as Array[Combatant]
	var exp0: int = hero.job_exp
	var gold0: int = GameState.party_gold
	var total0: int = AutogrindSystem.total_exp_gained
	var tally0: int = int(AutogrindSystem._grind_stats.get("total_gold", 0))
	var pots0: int = int(AutogrindSystem.total_items_gained.get("potion", 0))
	_win_boss(true, false)
	assert_eq(hero.job_exp - exp0, FIGHT_EXP + BONUS_EXP,
		"ludicrous meta-boss paid only the bonus — the fight's own %d job EXP never landed. Got %d" % [FIGHT_EXP, hero.job_exp - exp0])
	assert_eq(GameState.party_gold - gold0, FIGHT_GOLD,
		"ludicrous meta-boss dropped the fight's gold. Wallet moved %d, the fight was worth %d" % [GameState.party_gold - gold0, FIGHT_GOLD])
	assert_eq(AutogrindSystem.total_exp_gained - total0, FIGHT_EXP + BONUS_EXP,
		"session Total EXP omitted the fight and kept only the bonus")
	assert_eq(int(AutogrindSystem._grind_stats.get("total_gold", 0)) - tally0, FIGHT_GOLD,
		"session Total Gold omitted the meta-boss payout")
	assert_eq(int(AutogrindSystem.total_items_gained.get("potion", 0)) - pots0, 2,
		"the drops were delivered by the resolver path and never entered the item tally")
	assert_eq(int(AutogrindSystem.total_items_gained.get("gold", 0)), 0,
		"gold must stay out of the item tally")
	assert_eq(hero.get_item_count("potion"), 0,
		"this settlement tallies drops; it must not deliver them a second time")


func test_a_watched_meta_boss_tallies_what_the_battle_already_paid() -> void:
	## BattleManager already granted the fight. Paying it again here is the double-pay
	## test_visual_autogrind_pays_once_regression exists to forbid. The summary still
	## has to count it, or Total Gold reads flat while the wallet moved.
	var hero := _hero("Watcher", true)
	AutogrindSystem.grind_party = [hero] as Array[Combatant]
	var exp0: int = hero.job_exp
	var gold0: int = GameState.party_gold
	var total0: int = AutogrindSystem.total_exp_gained
	var tally0: int = int(AutogrindSystem._grind_stats.get("total_gold", 0))
	_win_boss(false, false)
	assert_eq(hero.job_exp - exp0, BONUS_EXP,
		"a watched meta-boss granted the fight's EXP again on top of BattleManager. Got %d extra, the bonus alone is %d" % [hero.job_exp - exp0, BONUS_EXP])
	assert_eq(GameState.party_gold, gold0,
		"a watched meta-boss paid the fight's gold a second time")
	assert_eq(AutogrindSystem.total_exp_gained - total0, FIGHT_EXP + BONUS_EXP,
		"session Total EXP still omitted the fight BattleManager already paid")
	assert_eq(int(AutogrindSystem._grind_stats.get("total_gold", 0)) - tally0, FIGHT_GOLD,
		"session Total Gold stayed flat for gold the wallet already received")


func test_ludicrous_collapse_boss_pays_the_same_way() -> void:
	var hero := _hero("Grinder", true)
	AutogrindSystem.grind_party = [hero] as Array[Combatant]
	var exp0: int = hero.job_exp
	var gold0: int = GameState.party_gold
	var tally0: int = int(AutogrindSystem._grind_stats.get("total_gold", 0))
	_win_boss(true, true)
	assert_eq(hero.job_exp - exp0, FIGHT_EXP + BONUS_EXP,
		"a ludicrous collapse boss dropped the fight's job EXP the same way a meta-boss did")
	assert_eq(GameState.party_gold - gold0, FIGHT_GOLD,
		"a ludicrous collapse boss dropped the fight's gold")
	assert_eq(int(AutogrindSystem._grind_stats.get("total_gold", 0)) - tally0, FIGHT_GOLD,
		"session Total Gold omitted the collapse-boss payout")


func test_a_loss_still_pays_nothing() -> void:
	var hero := _hero("Grinder", true)
	AutogrindSystem.grind_party = [hero] as Array[Combatant]
	var exp0: int = hero.job_exp
	var gold0: int = GameState.party_gold
	var total0: int = AutogrindSystem.total_exp_gained
	_win_boss(true, false, false)
	assert_eq(hero.job_exp, exp0, "a lost meta-boss must not grant the fight's EXP")
	assert_eq(GameState.party_gold, gold0, "a lost meta-boss must not grant the fight's gold")
	assert_eq(AutogrindSystem.total_exp_gained, total0, "a loss must not move the session EXP tally")


func test_a_corpse_without_the_exception_does_not_earn_the_fight() -> void:
	var living := _hero("Living", true)
	var corpse := _hero("Corpse", false)
	AutogrindSystem.grind_party = [living, corpse] as Array[Combatant]
	_win_boss(true, false)
	assert_eq(living.job_exp, FIGHT_EXP + BONUS_EXP, "the living member must receive the fight and the bonus")
	assert_eq(corpse.job_exp, 0, "a KO'd member with no mourner's ledger must not earn the fight's EXP")
