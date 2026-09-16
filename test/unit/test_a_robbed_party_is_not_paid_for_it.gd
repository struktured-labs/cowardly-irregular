extends GutTest

## ⛔ A MONSTER THAT ROBS THE PARTY PAID THE PARTY. Both steal sites in BattleManager credit gold with
## `GameState.add_gold(...)` and neither checks which side the caster is on, so a goblin's Steal
## INCREASED the player's money while the battle log said it was taking it.
##
## Found by cowir-autogrind (11786) while declining to mirror steal into the grind; confirmed here
## behaviourally before the repair.
##
##   goblin · spiteful_crow · conveyor_gremlin   author `steal`
##   7 encounter pools                          cave_dungeon, cave_floor_3/4/5, overworld_plains,
##                                              overworld_central, suburban_overworld
##
## `goblin` is a cave/plains monster, so this is EARLY GAME, not a corner of W5.
##
## ⚠️ WHAT THIS FILE DOES NOT DECIDE: whether an enemy's steal should COST the party gold. The amount
## is `randi_range(5, 50) * (1 + victim.max_hp / STEAL_GOLD_HP_DIVISOR)` and it scales with the
## VICTIM's HP, so against a party member it is a far bigger number than against a goblin — a drain
## nobody has sized. The unambiguous half is that being robbed must not PAY you; the penalty is
## struktured's call and is declared, not shipped.

const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"

var _saved_gold: int
var _saved_party: Array
var _saved_enemies: Array
var _saved_persist: bool


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_saved_gold = GameState.party_gold
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	seed(20260916)


func after_each() -> void:
	GameState.party_gold = _saved_gold
	AutobattleSystem._test_disable_persistence = _saved_persist
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.enemy_party.assign(_alive(_saved_enemies))


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _combatant(name: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name
	c.max_hp = 400
	c.current_hp = 400
	c.attack = 40
	c.magic = 40
	c.is_alive = true
	return c


## A guaranteed steal, so the arms are about WHO gets paid rather than about a roll.
func _steal() -> Dictionary:
	return {"type": "support", "effect": "steal", "success_rate": 1.0}


func test_an_enemy_stealing_from_the_party_does_not_pay_the_party() -> void:
	var goblin := _combatant("Goblin")
	var rook := _combatant("Rook")
	BattleManager.player_party.assign([rook] as Array[Combatant])
	BattleManager.enemy_party.assign([goblin] as Array[Combatant])
	GameState.party_gold = 1000
	BattleManager._execute_support_ability(goblin, _steal(), [rook])
	assert_true(GameState.party_gold <= 1000,
		"being robbed must not INCREASE the party's gold — it read %d, up from 1000" % GameState.party_gold)


func test_the_party_still_gets_paid_when_the_party_steals() -> void:
	## Anti-vacuity: the fix must gate on the caster's SIDE, not disable stealing.
	var rogue := _combatant("Mira")
	var goblin := _combatant("Goblin")
	BattleManager.player_party.assign([rogue] as Array[Combatant])
	BattleManager.enemy_party.assign([goblin] as Array[Combatant])
	GameState.party_gold = 1000
	BattleManager._execute_support_ability(rogue, _steal(), [goblin])
	assert_gt(GameState.party_gold, 1000, "the Rogue's Steal still pays — it read %d" % GameState.party_gold)


func test_mug_is_gated_the_same_way() -> void:
	## The second site. `mug` is a Rogue ability today and no monster authors it, so this arm defends
	## the SHAPE rather than a live caster — the guard must be in both places or the next monster to
	## carry mug reopens the same hole.
	## ⚠️ FUNCTION-BOUNDED, not a whole-file count: my first version asserted ZERO `add_gold` calls in
	## BattleManager and red on the VICTORY reward at :854, which is the one place that should credit
	## gold directly. A magnitude pin would have had the same problem one layer down.
	var code: String = GdSourceHelper.code_of(BM_PATH)
	assert_true(code.contains("func _award_stolen_gold("), "the owner exists")
	var owner_at: int = code.find("func _award_stolen_gold(")
	var owner_end: int = code.find("\nfunc ", owner_at + 1)
	var owner: String = code.substr(owner_at, owner_end - owner_at)
	assert_true(owner.contains("if not (caster in player_party):"),
		"the owner is where the caster's SIDE is decided — the check both sites were missing")
	assert_true(owner.contains("GameState.add_gold(gold_amount)"), "and the only steal-side credit lives inside it")
	for site in ['"steal":', "ability.get(\"steals\", false)"]:
		var at: int = code.find(site)
		assert_gt(at, -1, "CONTROL: the %s site survives stripping" % site)
		var body: String = code.substr(at, 1400)
		assert_false(body.contains("GameState.add_gold"),
			"the %s site must not credit gold itself — that is how the two drifted apart" % site)
		assert_true(body.contains("_award_stolen_gold("),
			"the %s site routes through the one owner" % site)


func test_the_three_monsters_that_carry_steal_are_still_the_corpus() -> void:
	## CONTROL and blast radius: if a fourth monster gains `steal` the class is wider than this file
	## says, and if these three lose it the arms above defend nothing live.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var monsters: Dictionary = data.get("monsters", data)
	var thieves: Array = []
	for id in monsters:
		var m = monsters[id]
		if m is Dictionary and (m.get("abilities", []) as Array).has("steal"):
			thieves.append(id)
	thieves.sort()
	assert_eq(thieves, ["conveyor_gremlin", "goblin", "spiteful_crow"],
		"the monsters that can rob the party: %s" % str(thieves))
