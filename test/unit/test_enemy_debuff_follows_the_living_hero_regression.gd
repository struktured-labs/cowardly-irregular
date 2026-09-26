extends GutTest

## A hippie queues Bad Vibes on the fighter. The fighter drops before that
## turn resolves. The debuff used to land on the hippie's own packmate,
## because support is not type physical/magic, so _execute_ability sent
## the KO through _retarget_ally. Rattle (all_enemies) did the same for
## the empty slot. A heal aimed at a fallen packmate must still stay
## on the monster's side.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _body(who: String, hp: int, max_hp: int) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = who
	c.max_hp = max_hp
	c.current_hp = hp
	c.max_mp = 80
	c.current_mp = 80
	c.attack = 20
	c.defense = 20
	c.magic = 20
	c.speed = 10
	c.is_alive = hp > 0
	return c


func _knows(c: Combatant, ability_id: String) -> void:
	c.learned_abilities.append(ability_id)


func _parties(foes: Array, heroes: Array) -> void:
	_bm.enemy_party.clear()
	_bm.player_party.clear()
	for foe in foes:
		_bm.enemy_party.append(foe)
	for hero in heroes:
		_bm.player_party.append(hero)


func _has_effect(c: Combatant, effect: String) -> bool:
	for debuff in c.active_debuffs:
		if str(debuff.get("effect", "")) == effect:
			return true
	return false


func test_bad_vibes_moves_to_the_standing_hero_when_its_target_is_down() -> void:
	var hippie := _body("New Age Retro Hippie", 1200, 1200)
	var pack := _body("Imp", 40, 200)
	var fallen := _body("Fighter", 0, 400)
	var standing := _body("Cleric", 300, 400)
	_knows(hippie, "bad_vibes")
	_parties([hippie, pack], [fallen, standing])
	_bm._execute_ability(hippie, "bad_vibes", [fallen])
	assert_true(_has_effect(standing, "Despair (ATK)"),
		"Bad Vibes was aimed at the party — the standing cleric should wear it")
	assert_false(_has_effect(pack, "Despair (ATK)"),
		"the imp took the debuff meant for the party")
	assert_false(_has_effect(hippie, "Despair (ATK)"),
		"the hippie debuffed itself")


func test_rattle_does_not_weaken_a_packmate_for_a_fallen_hero() -> void:
	var skeleton := _body("Skeleton", 800, 800)
	var pack := _body("Skeleton", 50, 200)
	var fallen := _body("Fighter", 0, 400)
	var standing := _body("Bard", 200, 400)
	_knows(skeleton, "rattle")
	_parties([skeleton, pack], [fallen, standing])
	_bm._execute_ability(skeleton, "rattle", [fallen, standing])
	assert_true(_has_effect(standing, "Weaken"),
		"Rattle lowers the attack of every hero still standing")
	assert_false(_has_effect(pack, "Weaken"),
		"the empty party slot weakened a skeleton")
	assert_eq(standing.active_debuffs.size(), 1,
		"the fallen hero's slot must not stack a second Weaken on the survivor")


func test_a_heal_for_a_fallen_packmate_stays_on_the_monster_side() -> void:
	var healer := _body("Slime", 500, 500)
	var fallen_pack := _body("Slime", 0, 200)
	var hurt_pack := _body("Bat", 80, 200)
	var hero := _body("Fighter", 10, 400)
	_knows(healer, "cure")
	_parties([healer, fallen_pack, hurt_pack], [hero])
	var before := hurt_pack.current_hp
	_bm._execute_ability(healer, "cure", [fallen_pack])
	assert_gt(hurt_pack.current_hp, before,
		"a single_ally heal follows the living packmate")
	assert_eq(hero.current_hp, 10,
		"the heal crossed to the party")
