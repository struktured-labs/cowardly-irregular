extends GutTest

## ⛔ A KO'D PARTY MEMBER STILL COUNTED TOWARD THE GROUP-ATTACK MULTIPLIER. All three pooled-strike
## paths sum attack/magic from LIVING participants only, then raised `participants.size()` — the
## roster fixed at SELECTION time — to the 1.5 power. So a member killed during the execution phase
## contributed no power, paid no AP, and still inflated the scale.
##
## ⚠️ THE `is_alive` GUARDS ARE THE PROOF IT IS REACHABLE. Each of the three functions filters the
## dead when summing power and when spending AP; those guards are dead code unless a participant can
## be dead by the time the action runs. Selection fixes the roster, execution is speed-sorted, and
## nothing re-validates the list in between — `_execute_group_action` reads `action["participants"]`
## and passes it straight through.
##
## ⛔ AND IT FAILED IN THE DIRECTION NOBODY REPORTS: losing a member made the strike STRONGER per
## survivor. pow(4,1.5)/pow(3,1.5) = 1.54x. A player whose Limit Break got better when someone died
## does not file that, which is why this outlived the three `is_alive` guards written beside it.

var _saved_party: Array
var _saved_enemies: Array


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	seed(20260917)


func after_each() -> void:
	randomize()
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.enemy_party.assign(_alive(_saved_enemies))


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _member(name_str: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name_str
	c.max_hp = 500
	c.current_hp = 500
	c.attack = 40
	c.magic = 40
	c.defense = 0
	c.current_ap = 4
	c.is_alive = true
	return c


func _dummy() -> Combatant:
	var e := Combatant.new()
	autofree(e)
	e.combatant_name = "Wall"
	e.max_hp = 100000000
	e.current_hp = 100000000
	e.defense = 0
	e.is_alive = true
	return e


## Runs one pooled strike and returns the damage the single enemy took.
## `dead_count` members are KO'd AFTER the roster is built, which is the live sequence:
## selection fixes `participants`, the execution phase kills somebody, the action then runs.
func _group_damage(roster_size: int, dead_count: int, group_type: String) -> int:
	var roster: Array = []
	for i in range(roster_size):
		roster.append(_member("PC%d" % i))
	for i in range(dead_count):
		roster[i].is_alive = false
	var wall := _dummy()
	BattleManager.player_party.assign(roster as Array[Combatant])
	BattleManager.enemy_party.assign([wall] as Array[Combatant])
	var before: int = wall.current_hp
	var enemies: Array[Combatant] = [wall]
	if group_type == "combo_magic":
		BattleManager._execute_combo_magic(roster, enemies, 2)
	else:
		BattleManager._execute_physical_group(roster, enemies, group_type, 4 if group_type == "limit_break" else 1)
	var dealt: int = before - wall.current_hp
	assert_gt(dealt, 0, "CONTROL: %s with %d/%d alive dealt damage at all" % [group_type, roster_size - dead_count, roster_size])
	return dealt


func test_a_fallen_ally_does_not_add_to_the_multiplier() -> void:
	## The shipped bug: four rostered with one dead must hit exactly as hard as three rostered.
	for group_type in ["limit_break", "all_out_attack", "combo_magic"]:
		var three_alive: int = _group_damage(3, 0, group_type)
		var four_one_dead: int = _group_damage(4, 1, group_type)
		assert_eq(four_one_dead, three_alive,
			"%s: a KO'd member contributes no power and must contribute no scale — three fighting is three fighting" % group_type)


func test_the_multiplier_is_still_superlinear() -> void:
	## ⛔ MY FIRST VERSION OF THIS ARM WAS DECORATIVE AND THE MUTATION SAID SO. It asserted
	## `four > three`, which stays TRUE with the scale flattened to a constant — the power SUM
	## already grows with the roster, so monotonicity is a property of `total_power`, not of the
	## scale it was written to defend. Flattening `_group_scale` to 1.0 left it green.
	##
	## Pooling is sold on superlinear return for the AP, so that is what the arm asserts: doubling
	## the party must MORE than double the strike. Real scale: damage goes as n^2.5, so 4 vs 2 is
	## 5.66x. Flattened: damage goes as n, exactly 2x, and this reds.
	var two: int = _group_damage(2, 0, "limit_break")
	var four: int = _group_damage(4, 0, "limit_break")
	assert_gt(four, 2 * two,
		"doubling the living party must MORE than double the strike (%d vs 2x%d), or the exponential scale is gone" % [four, two])


func test_the_log_counts_the_living() -> void:
	## The announce line read the same unfiltered roster, so it told the player "4 participants"
	## while three swung. Same lie, cheaper surface.
	var seen: Array[String] = []
	var cb := func(msg: String) -> void: seen.append(msg)
	BattleManager.battle_log_message.connect(cb)
	_group_damage(4, 1, "all_out_attack")
	BattleManager.battle_log_message.disconnect(cb)
	var announce: String = ""
	for m in seen:
		if m.contains("All-Out Attack!"):
			announce = m
	assert_ne(announce, "", "CONTROL: the all-out opener was emitted at all")
	assert_true(announce.contains("(3 participants)"),
		"the opener must count who actually swings, not who was rostered: %s" % announce)
