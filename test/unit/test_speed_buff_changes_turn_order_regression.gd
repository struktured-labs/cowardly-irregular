extends GutTest

## Speed Tonic, Masterite Haste, Chill, Coil, and Web Shot all write a speed buff or debuff
## and tell the player the target got faster or slower. Turn order read combatant.speed, which
## those effects never touch — get_buffed_stat is what actually moves — so a hasted ally still
## picked and acted in the same slot, and the turn-order strip still printed the old number.
## Lower action-speed values execute first. Jitter is ±1 when no volatility system is attached,
## so the gaps below are wide enough that the random term cannot flip the result.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const UIScript = preload("res://src/battle/BattleUIManager.gd")

var _bm: BattleManager


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _person(who: String, spd: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = who
	c.speed = spd
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	return c


func test_a_hasted_ally_selects_before_a_faster_twin() -> void:
	# Speed Tonic / Masterite Haste are 1.5x. Raw 20 loses to raw 25; buffed 30 wins.
	var hasted := _person("Hasted", 20)
	var rival := _person("Rival", 25)
	hasted.add_buff("Speed_up", "speed", 1.5, 3)
	_bm.player_party.append(hasted)
	_bm.player_party.append(rival)
	_bm._calculate_selection_order()
	assert_eq(_bm.selection_order[0], hasted,
		"the hasted ally must be asked for a command before the higher-base-speed twin")
	assert_eq(_bm.selection_order[1], rival,
		"the unbuffed twin selects second")


func test_a_slowed_enemy_selects_after_a_slower_one() -> void:
	# Web Shot is 0.5x speed. Raw 30 would go first; slowed to 15 it must go last.
	var slowed := _person("Slowed", 30)
	var mid := _person("Mid", 22)
	slowed.add_debuff("Slow", "speed", 0.5, 2)
	_bm.enemy_party.append(slowed)
	_bm.enemy_party.append(mid)
	_bm._calculate_selection_order()
	assert_eq(_bm.selection_order[0], mid,
		"a slowed enemy must give up its place in the selection order")
	assert_eq(_bm.selection_order[1], slowed,
		"the slowed enemy selects after the enemy it used to outspeed")


func test_haste_makes_the_action_resolve_sooner() -> void:
	var hasted := _person("Hasted", 20)
	var rival := _person("Rival", 25)
	hasted.add_buff("Speed_up", "speed", 1.5, 3)
	assert_lt(_bm._compute_action_speed(hasted, "attack"), _bm._compute_action_speed(rival, "attack"),
		"lower sorts first — a 1.5x haste on speed 20 must beat a raw speed 25 attack")


func test_slow_makes_the_action_resolve_later() -> void:
	var slowed := _person("Slowed", 30)
	var mid := _person("Mid", 22)
	slowed.add_debuff("Slow", "speed", 0.5, 2)
	assert_gt(_bm._compute_action_speed(slowed, "attack"), _bm._compute_action_speed(mid, "attack"),
		"a halved speed must land after an enemy with a lower base speed")


func test_an_attack_buff_does_not_move_the_turn() -> void:
	# Discriminator: only the speed stat feeds turn order. Berserk must not act as haste.
	var plain := _person("Plain", 20)
	var berserk := _person("Berserk", 20)
	berserk.add_buff("Berserk", "attack", 1.5, 3)
	var gap := absf(_bm._compute_action_speed(berserk, "attack") - _bm._compute_action_speed(plain, "attack"))
	assert_lte(gap, 2.0,
		"an attack buff must leave action speed inside the ±1 jitter band — it is not haste")


func test_the_grind_uses_the_same_buffed_speed() -> void:
	var resolver = ResolverScript.new()
	var hasted := _person("Hasted", 20)
	var rival := _person("Rival", 25)
	hasted.add_buff("Speed_up", "speed", 1.5, 3)
	assert_lt(resolver._speed_for({"type": "attack"}, hasted), resolver._speed_for({"type": "attack"}, rival),
		"autogrind resolves the same fights — haste has to move its queue too")


func test_the_turn_order_strip_prints_the_buffed_speed() -> void:
	var hasted := _person("Hasted", 20)
	hasted.add_buff("Speed_up", "speed", 1.5, 3)
	var ui = UIScript.new(null)
	var row: HBoxContainer = ui._create_ctb_entry(hasted, false, true, 1)
	var spd := row.get_child(row.get_child_count() - 1) as Label
	assert_eq(spd.text, "30",
		"the TURN ORDER number is what the player reads as speed — haste must change it")
	row.free()
