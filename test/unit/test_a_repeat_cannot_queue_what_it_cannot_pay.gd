extends GutTest

## Y (Repeat last turn) re-queued a saved Advance exactly as it was. The menu's queue (.546) and
## autobattle (.548) now refuse casts and items the turn cannot pay for, but a repeated
## "Fire, Fire, Fire" after the MP had dropped queued all three again, and every one past what the
## MP covered failed at execution ("can't use that right now") and still cost its Advance AP.
## A repeated Advance now goes through the same _affordable_advance as autobattle.

var _saved: Dictionary = {}


func before_each() -> void:
	var bm = BattleManager
	_saved = {"player_party": bm.player_party.duplicate(), "enemy_party": bm.enemy_party.duplicate(),
		"pending": bm.pending_actions.duplicate(), "prev": bm.previous_round_actions.duplicate(true)}


func after_each() -> void:
	var bm = BattleManager
	bm.player_party.assign(_saved["player_party"].filter(func(x): return is_instance_valid(x)))
	bm.enemy_party.assign(_saved["enemy_party"].filter(func(x): return is_instance_valid(x)))
	bm.pending_actions.assign(_saved["pending"])
	bm.previous_round_actions = _saved["prev"]


func _c(n: String, mp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": 100, "max_mp": 99, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_mp = mp
	c.inventory = {}
	return c


func _repeat(mage: Combatant, saved: Array) -> Dictionary:
	var bm = BattleManager
	var foe := _c("Foe", 0)
	bm.player_party.assign([mage] as Array[Combatant])
	bm.enemy_party.assign([foe] as Array[Combatant])
	bm.pending_actions.clear()
	bm.previous_round_actions = {"mage": saved}
	bm._queue_repeated_action(mage)
	return bm.pending_actions.back() if bm.pending_actions.size() > 0 else {}


func _fire_advance(n: int) -> Dictionary:
	var subs: Array = []
	for i in n:
		subs.append({"type": "ability", "ability_id": "fire"})
	return {"type": "advance", "actions": subs}


func test_fire_costs_what_this_file_assumes() -> void:
	assert_eq(JobSystem.get_ability_mp_cost(_c("Mage", 99), "fire"), 8, "CONTROL: MP below is sized for an 8-MP Fire")


func test_a_repeated_advance_keeps_only_what_the_mp_covers() -> void:
	var queued := _repeat(_c("Mage", 17), [_fire_advance(3)])
	var n: int = (queued.get("actions", []) as Array).size() if queued.get("type", "") == "advance" else (1 if queued.get("ability_id", "") == "fire" else 0)
	assert_eq(n, 2, "17 MP pays for two 8-MP Fires; the third would fail at execution and cost its AP")


func test_a_repeat_the_mp_covers_in_full_is_unchanged() -> void:
	var queued := _repeat(_c("Mage", 99), [_fire_advance(3)])
	assert_eq(str(queued.get("type", "")), "advance", "CONTROL: an affordable repeat stays an Advance")
	assert_eq((queued.get("actions", []) as Array).size(), 3, "and keeps all three")


func test_a_repeat_nothing_covers_becomes_the_attack_repeat_already_falls_back_to() -> void:
	var queued := _repeat(_c("Mage", 0), [_fire_advance(2)])
	assert_eq(str(queued.get("type", "")), "attack",
		"with no MP for any Fire, repeat queues the basic attack it uses when nothing was saved")
