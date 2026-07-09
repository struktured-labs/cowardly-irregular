extends GutTest

## Feature 2026-07-05: autobattle 'enemy_has_status' condition. Mirrors
## ally_has_status but over the enemy party — true when ANY LIVING enemy carries
## the named status. Lets rules react to enemy state (all-out attack a stunned
## foe, dispel an enemy's regen, hold fire while a debuff still ticks). Auto-
## surfaces in the grid editor + validator (CONDITION_TYPES) and is documented
## to the LLM Rule Composer.

var _sp: Array[Combatant] = []
var _se: Array[Combatant] = []


func before_each() -> void:
	_sp = BattleManager.player_party.duplicate()
	_se = BattleManager.enemy_party.duplicate()


func after_each() -> void:
	BattleManager.player_party = _sp
	BattleManager.enemy_party = _se


func _mk(cname: String, statuses: Array = []) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = cname
	c.is_alive = true
	var st: Array[String] = []
	for s in statuses:
		st.append(str(s))
	c.status_effects = st
	return c


func _arm(hero: Combatant, enemies: Array[Combatant]) -> void:
	var p: Array[Combatant] = [hero]
	BattleManager.player_party = p
	BattleManager.enemy_party = enemies


func _eval(hero: Combatant, status: String) -> bool:
	return AutobattleSystem._evaluate_grid_condition(hero, {"type": "enemy_has_status", "status": status})


func test_true_when_an_enemy_has_the_status() -> void:
	var hero := _mk("Hero")
	var foes: Array[Combatant] = [_mk("A"), _mk("B", ["stun"])]
	_arm(hero, foes)
	assert_true(_eval(hero, "stun"), "an enemy carrying the status makes the condition true")


func test_false_when_no_enemy_has_the_status() -> void:
	var hero := _mk("Hero")
	var foes: Array[Combatant] = [_mk("A", ["poison"]), _mk("B")]
	_arm(hero, foes)
	assert_false(_eval(hero, "stun"), "no enemy has 'stun' → false")


func test_ignores_dead_enemies() -> void:
	var hero := _mk("Hero")
	var dead := _mk("Dead", ["stun"])
	dead.is_alive = false
	var foes: Array[Combatant] = [dead]
	_arm(hero, foes)
	assert_false(_eval(hero, "stun"), "a KO'd enemy's status doesn't count — only living enemies")


func test_registered_in_condition_types() -> void:
	assert_true(AutobattleSystem.CONDITION_TYPES.has("enemy_has_status"),
		"the condition must be registered so the editor + validator accept it")
