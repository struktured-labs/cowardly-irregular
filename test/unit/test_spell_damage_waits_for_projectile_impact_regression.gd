extends GutTest

## #763 (struktured: "the mage's fire attack kills the monster before it lands"). A projectile-style
## ability sequence sets BattleManager.impact_hold during action_executing; the HP drop and the death
## must wait for it, then resolve. No hold (headless, tests, turbo) resolves on the spot as before.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null
var _hold: float = 0.0


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)
	_hold = 0.0
	_bm.action_executing.connect(func(_c, a):
		if str(a.get("type", "")) == "ability" and _hold > 0.0:
			_bm.impact_hold = _hold)


func _unit(cname: String, hp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": cname, "max_hp": hp, "max_mp": 200, "attack": 10, "defense": 1, "magic": 400, "magic_defense": 1, "speed": 10})
	add_child_autofree(c)
	c.current_mp = 200
	c.learned_abilities.append("fire")
	return c


func _setup(foe_hp: int) -> Array:
	var mage := _unit("Vex", 300)
	var foe := _unit("Slime", foe_hp)
	_bm.player_party.clear(); _bm.enemy_party.clear()
	_bm.player_party.append(mage); _bm.enemy_party.append(foe)
	return [mage, foe]


func test_without_a_hold_fire_resolves_immediately() -> void:
	var u := _setup(5000)
	_bm._execute_ability(u[0], "fire", [u[1]])
	assert_lt(u[1].current_hp, 5000, "no projectile hold -> damage lands synchronously (tests/headless/turbo)")


func test_fire_damage_waits_for_the_projectile_impact() -> void:
	_hold = 0.3
	var u := _setup(5000)
	_bm._execute_ability(u[0], "fire", [u[1]])
	assert_eq(u[1].current_hp, 5000, "HP must not drop on the cast frame while the bolt is in flight")
	await wait_seconds(0.45)
	assert_lt(u[1].current_hp, 5000, "HP drops once the bolt lands")


func test_a_killing_fire_does_not_kill_before_impact() -> void:
	_hold = 0.3
	var u := _setup(1)
	_bm._execute_ability(u[0], "fire", [u[1]])
	assert_true(u[1].is_alive, "the target must still be alive mid-flight")
	await wait_seconds(0.45)
	assert_false(u[1].is_alive, "dies at the impact")


func test_turbo_ignores_the_hold() -> void:
	_hold = 0.3
	_bm.turbo_mode = true
	var u := _setup(5000)
	_bm._execute_ability(u[0], "fire", [u[1]])
	assert_lt(u[1].current_hp, 5000, "turbo has no VFX to wait for")
	assert_eq(_bm.impact_hold, 0.0, "hold is consumed, never leaks to the next action")


func test_the_hold_is_capped() -> void:
	_bm.impact_hold = 99.0
	assert_eq(_bm._take_impact_hold(), _bm.IMPACT_HOLD_MAX)
