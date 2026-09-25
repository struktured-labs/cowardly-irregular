extends GutTest

const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## A normal victory scaled gold by the drop-rate dial inside the tally, then
## GameState.add_gold scaled that number again. At 2x the loot strip said 2x
## and the wallet received 4x. Autogrind already credits the once-scaled total
## and skips add_gold. The strip reads battle results total_gold, so that
## figure and the wallet delta have to be the same coins.

const BASE_GOLD := 40

var _guard: RefCounted
var _gold: int
var _gold_mult: Variant


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()
	_gold = GameState.party_gold
	_gold_mult = GameState.game_constants.get("gold_multiplier", null)


func after_each() -> void:
	if _guard != null:
		_guard.restore()
	GameState.party_gold = _gold
	if _gold_mult == null:
		GameState.game_constants.erase("gold_multiplier")
	else:
		GameState.game_constants["gold_multiplier"] = _gold_mult


func _finish(dial: float) -> Dictionary:
	GameState.game_constants["gold_multiplier"] = dial
	var hero := Combatant.new()
	hero.combatant_name = "Fighter"
	hero.job_level = 5
	hero.job_exp = 0
	hero.is_alive = true
	hero.current_hp = hero.max_hp
	add_child_autofree(hero)
	var foe := Combatant.new()
	foe.combatant_name = "Purse"
	foe.is_alive = false
	foe.current_hp = 0
	foe.set_meta("gold_reward", BASE_GOLD)
	add_child_autofree(foe)
	BattleManager._first_damage_phase = -1
	BattleManager._one_shot_achieved = false
	BattleManager._full_autobattle = false
	BattleManager._autobattle_player_turns = 0
	BattleManager._ko_this_battle.clear()
	BattleManager.defer_victory_payout = false
	BattleManager.player_party = [hero] as Array[Combatant]
	BattleManager.enemy_party = [foe] as Array[Combatant]
	BattleManager.all_combatants = [hero, foe] as Array[Combatant]
	var gold0: int = GameState.party_gold
	BattleManager.end_battle(true)
	var shown: int = int(BattleManager.get_battle_results().get("total_gold", -1))
	return {"shown": shown, "paid": GameState.party_gold - gold0}


func test_the_loot_strip_prints_total_gold() -> void:
	var code: String = GdSource.code_of("res://src/battle/VictoryOverlay.gd")
	assert_true(code.contains("func _build_loot_strip"), "control: the loot strip must survive the strip")
	var idx: int = code.find("func _build_loot_strip")
	var stop: int = code.find("\nfunc ", idx + 20)
	var body: String = code.substr(idx, (stop - idx) if stop > 0 else -1)
	assert_true(body.contains("results.get(\"total_gold\""),
		"the victory loot strip must display battle results total_gold — that is the number the wallet has to match")
	assert_true(body.contains("\"%d G\""),
		"the strip must print that gold as the chip the player reads")


func test_dial_at_1x_pays_the_authored_gold_once() -> void:
	var got: Dictionary = _finish(1.0)
	assert_eq(int(got["shown"]), BASE_GOLD,
		"at 1x the victory tally must show the authored gold, unchanged")
	assert_eq(int(got["paid"]), int(got["shown"]),
		"at 1x the wallet must receive the number on the victory tally")


func test_dial_at_2x_pays_double_not_quadruple() -> void:
	var got: Dictionary = _finish(2.0)
	assert_eq(int(got["shown"]), BASE_GOLD * 2,
		"at 2x the victory tally must show the authored gold times the dial once")
	assert_eq(int(got["paid"]), BASE_GOLD * 2,
		"at 2x the wallet received %d for %d authored gold — the dial was applied twice" % [int(got["paid"]), BASE_GOLD])
	assert_eq(int(got["paid"]), int(got["shown"]),
		"the victory tally and the wallet must name the same gold")
