extends GutTest

## Y-repeat keeps last round's targets. A potion aimed at an ally who has since fallen
## failed the "alive in this battle" check, and the fallback swapped in the first living
## enemy. _execute_item then kept that enemy — _retarget_ally returns any living body —
## so the potion healed the monster and left the bag. A party potion did it once per KO'd
## slot. Phoenix Down still wants the corpse. A bomb still wants a living enemy.
## An all-allies list is party order. Replacing an EARLIER KO with a living ally who is
## still ahead in that list appended them again when their own slot arrived, so one
## Mega Potion healed that ally twice. Drop the KO; the living slots already get it.

const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

var _bm: Node = null
var _guard = null


func before_each() -> void:
	_bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	if _bm:
		_bm.pending_actions.clear()
		_bm.previous_round_actions.clear()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func _make(cname: String, hp: int, max_hp: int) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = cname
	c.max_hp = max_hp
	c.max_mp = 20
	c.attack = 10
	c.defense = 10
	c.magic = 10
	c.speed = 10
	c.current_ap = 2
	add_child_autofree(c)
	# Combatant._ready copies max_hp onto current_hp, so a wound set before the node is ready never reaches a heal assert.
	c.current_hp = hp
	c.current_mp = 20
	c.is_alive = hp > 0
	return c


func _stage(party: Array, enemies: Array) -> void:
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	for member in party:
		_bm.player_party.append(member)
	for enemy in enemies:
		_bm.enemy_party.append(enemy)


func _remember(who: Combatant, action: Dictionary) -> void:
	_bm.previous_round_actions[who.combatant_name.to_lower()] = [action]


func _queued_targets() -> Array:
	assert_gt(_bm.pending_actions.size(), 0, "repeat must queue the remembered action")
	return _bm.pending_actions[_bm.pending_actions.size() - 1].get("targets", [])


func test_a_repeated_potion_heals_a_living_ally_not_the_enemy() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var ada := _make("Ada", 100, 500)
	var bo := _make("Bo", 0, 500)
	bo.is_alive = false
	var slime := _make("Slime", 40, 200)
	ada.add_item("potion", 1)
	_stage([ada, bo], [slime])
	_remember(ada, {"type": "item", "item_id": "potion", "targets": [bo], "speed": 1.0})
	_bm._queue_repeated_action(ada)
	var targets: Array = _queued_targets()
	assert_eq(targets.size(), 1, "one potion, one target")
	assert_eq(targets[0], ada, "the fallen ally's potion must land on the living ally")
	var slime_before := slime.current_hp
	_bm._execute_item(ada, "potion", targets)
	assert_eq(slime.current_hp, slime_before, "the enemy must not gain the potion's HP")
	assert_gt(ada.current_hp, 100, "the living ally is who the potion heals")
	assert_eq(ada.get_item_count("potion"), 0, "a real heal still spends the potion")


func test_a_repeated_party_potion_does_not_include_the_enemy() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var ada := _make("Ada", 80, 500)
	var bo := _make("Bo", 0, 500)
	bo.is_alive = false
	var slime := _make("Slime", 40, 200)
	ada.add_item("mega_potion", 1)
	_stage([ada, bo], [slime])
	_remember(ada, {"type": "item", "item_id": "mega_potion", "targets": [ada, bo], "speed": 1.0})
	_bm._queue_repeated_action(ada)
	var targets: Array = _queued_targets()
	assert_true(targets.has(ada), "the living ally stays on a party potion")
	assert_false(targets.has(slime), "a KO'd slot must not be filled with the enemy")
	var slime_before := slime.current_hp
	_bm._execute_item(ada, "mega_potion", targets)
	assert_eq(slime.current_hp, slime_before, "the party potion must not heal the enemy")
	assert_gt(ada.current_hp, 80, "the living ally still receives the party heal")
	assert_eq(ada.get_item_count("mega_potion"), 0, "the party potion is spent once, on the party")


func _flat_heal(item_id: String) -> int:
	var item: Dictionary = ItemSystem.get_item(item_id)
	return int(item.get("effects", {}).get("heal_hp", 0))


## Saved party order [KO, A, B]. The KO slot used to retarget onto the lowest living ally, who was then appended again from their own slot.
func test_a_repeated_party_potion_with_an_earlier_ko_heals_each_living_ally_once() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var bo := _make("Bo", 0, 10000)
	var ada := _make("Ada", 400, 10000)
	var cy := _make("Cy", 700, 10000)
	var slime := _make("Slime", 40, 200)
	ada.add_item("mega_potion", 1)
	_stage([bo, ada, cy], [slime])
	_remember(ada, {"type": "item", "item_id": "mega_potion", "targets": [bo, ada, cy], "speed": 1.0})
	_bm._queue_repeated_action(ada)
	var targets: Array = _queued_targets()
	assert_eq(targets.count(bo), 0, "a non-revive party item drops the KO'd ally")
	assert_eq(targets.count(ada), 1, "Ada is already in the saved list and must appear once")
	assert_eq(targets.count(cy), 1, "Cy is already in the saved list and must appear once")
	assert_false(targets.has(slime), "a KO'd slot must not be filled with the enemy")
	var ada_before := ada.current_hp
	var cy_before := cy.current_hp
	var slime_before := slime.current_hp
	var one := ada.heal_preview(_flat_heal("mega_potion"))
	assert_gt(ada.max_hp - ada_before, one * 2, "Ada has room to show a second heal")
	assert_gt(cy.max_hp - cy_before, cy.heal_preview(_flat_heal("mega_potion")) * 2, "Cy has room to show a second heal")
	_bm._execute_item(ada, "mega_potion", targets)
	assert_eq(ada.current_hp - ada_before, one, "Ada receives the party potion once")
	assert_eq(cy.current_hp - cy_before, cy.heal_preview(_flat_heal("mega_potion")), "Cy receives the party potion once")
	assert_eq(slime.current_hp, slime_before, "the party potion must not heal the enemy")
	assert_eq(ada.get_item_count("mega_potion"), 0, "one party potion is spent")


## Saved party order [KO, A], and A is the only one standing. Retargeting the KO onto A and then keeping A's slot healed A twice.
func test_a_repeated_party_potion_heals_the_only_living_user_once() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var bo := _make("Bo", 0, 10000)
	var ada := _make("Ada", 400, 10000)
	var slime := _make("Slime", 40, 200)
	ada.add_item("mega_potion", 1)
	_stage([bo, ada], [slime])
	_remember(ada, {"type": "item", "item_id": "mega_potion", "targets": [bo, ada], "speed": 1.0})
	_bm._queue_repeated_action(ada)
	var targets: Array = _queued_targets()
	assert_eq(targets.count(bo), 0, "a non-revive party item drops the KO'd ally")
	assert_eq(targets.count(ada), 1, "the only living ally appears once")
	assert_false(targets.has(slime), "a KO'd slot must not be filled with the enemy")
	var ada_before := ada.current_hp
	var one := ada.heal_preview(_flat_heal("mega_potion"))
	assert_gt(ada.max_hp - ada_before, one * 2, "Ada has room to show a second heal")
	_bm._execute_item(ada, "mega_potion", targets)
	assert_eq(ada.current_hp - ada_before, one, "the only living ally is healed once")
	assert_eq(ada.get_item_count("mega_potion"), 0, "one party potion is spent")


func test_a_repeated_bomb_still_finds_a_living_enemy() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var ada := _make("Ada", 200, 500)
	var gone := _make("Bone", 0, 80)
	gone.is_alive = false
	var slime := _make("Slime", 40, 200)
	_stage([ada], [gone, slime])
	_remember(ada, {"type": "item", "item_id": "bomb_fragment", "targets": [gone], "speed": 1.0})
	_bm._queue_repeated_action(ada)
	var targets: Array = _queued_targets()
	assert_eq(targets.size(), 1, "one bomb, one target")
	assert_eq(targets[0], slime, "a dead enemy target still repeats onto a living enemy")


func test_a_repeated_phoenix_down_keeps_the_corpse() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var ada := _make("Ada", 200, 500)
	var bo := _make("Bo", 0, 500)
	bo.is_alive = false
	var slime := _make("Slime", 40, 200)
	_stage([ada, bo], [slime])
	_remember(ada, {"type": "item", "item_id": "phoenix_down", "targets": [bo], "speed": 1.0})
	_bm._queue_repeated_action(ada)
	var targets: Array = _queued_targets()
	assert_eq(targets.size(), 1, "one phoenix down, one target")
	assert_eq(targets[0], bo, "a revive item must keep the KO'd ally")
