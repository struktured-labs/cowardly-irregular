extends GutTest

## Eight shipped autobattle presets target "highest_atk_enemy" -- "the biggest threat to a tank". It sorted by
## Combatant.base_attack, a placeholder nothing sets on a monster: every enemy read 10, the sort was a tie, and the
## rule hit an arbitrary target. It now sorts by the live attack the enemy actually swings with.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")

var _bm: RefCounted = null


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()


func after_each() -> void:
	if _bm != null:
		_bm.restore()


func _c(n: String, atk: int) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = n
	c.attack = atk
	c.current_hp = 100
	c.max_hp = 100
	c.is_alive = true
	return c


func test_the_highest_attack_enemy_is_the_one_that_hits_hardest() -> void:
	var hero := _c("Hero", 50)
	var weak := _c("Slime", 40)
	var mid := _c("Goblin", 90)
	var brute := _c("Ogre", 300)
	assert_eq(weak.base_attack, brute.base_attack, "CONTROL: base_attack is the same placeholder on every enemy")
	var party: Array[Combatant] = [hero]
	var foes: Array[Combatant] = [weak, mid, brute]
	BattleManager.player_party = party
	BattleManager.enemy_party = foes
	var pick: Combatant = AutobattleSystem._get_highest_atk_enemy(hero)
	assert_eq(pick, brute, "the tank's target is the Ogre (300 ATK), got %s" % (pick.combatant_name if pick else "null"))
