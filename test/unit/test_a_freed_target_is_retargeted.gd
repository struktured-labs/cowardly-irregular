extends GutTest

## Regression (struktured's .556 play log, 2026-10-04): 13x "Invalid type in function '_retarget_enemy' ... argument 2 (previously
## freed)". A queued attack's target was freed before it fired; the typed Combatant parameter rejected it BEFORE the body could
## retarget, so the call aborted (returning null) and the action fell through. Both helpers now treat a freed target as gone.

var _saved_players: Array = []
var _saved_enemies: Array = []


func before_each() -> void:
	_saved_players = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()


func after_each() -> void:
	BattleManager.player_party.assign(_saved_players)
	BattleManager.enemy_party.assign(_saved_enemies)


func _mk(n: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = n
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	add_child_autofree(c)
	return c


## Helpers, not inline calls: with a typed parameter the error aborts the CALLING frame, so an inline call would abort the test arm
## after its earlier asserts and score it passing. Inside a helper the abort returns null, which the arm's assert then judges.
func _enemy_for(attacker: Combatant, target) -> Variant:
	return BattleManager._retarget_enemy(attacker, target)


func _ally_for(caster: Combatant, target) -> Variant:
	return BattleManager._retarget_ally(caster, target)


func test_an_attack_on_a_freed_enemy_retargets_a_live_one() -> void:
	var hero := _mk("Hero")
	var live := _mk("Live Slime")
	var gone := Combatant.new()
	gone.combatant_name = "Gone Slime"
	BattleManager.player_party.assign([hero])
	BattleManager.enemy_party.assign([live])
	gone.free()
	assert_false(is_instance_valid(gone), "SCOPE: the original target really is freed")
	assert_eq(_enemy_for(hero, gone), live, "a freed target must retarget to the live enemy, not abort")


func test_a_heal_on_a_freed_ally_retargets_a_live_one() -> void:
	var healer := _mk("Cleric")
	var hurt := _mk("Fighter")
	hurt.current_hp = 40
	var gone := Combatant.new()
	BattleManager.player_party.assign([healer, hurt])
	BattleManager.enemy_party.assign([])
	gone.free()
	assert_eq(_ally_for(healer, gone), hurt, "a freed ally target must retarget, not abort")


func test_a_live_target_is_kept() -> void:
	var hero := _mk("Hero")
	var foe := _mk("Foe")
	BattleManager.player_party.assign([hero])
	BattleManager.enemy_party.assign([foe])
	assert_eq(_enemy_for(hero, foe), foe, "CONTROL: a live target is honoured as-is")
