extends GutTest

## A party spell confirmed from the battle menu was queued for the caster alone.
## Battle Hymn, Guardian Wall, Inspiring Melody and Mandatory Overtime all author
## target_type all_allies, and the command row even labels them [All]. Both menus
## hand BattleScene._execute_ability one focus and set the all-target flag only
## for all_enemies, the same collapse Mega Potion used to have. Autobattle already
## expands all_allies, so a scripted Bard buffed the party and a manual one did not.

const SceneScript = preload("res://src/battle/BattleScene.gd")
const BattleStateHelper = preload("res://test/unit/helpers/battle_state.gd")

var _snap
var _scene: Control
var _bard: Combatant
var _fighter: Combatant
var _down: Combatant


func before_each() -> void:
	_snap = BattleStateHelper.new()
	_snap.snapshot()
	_bard = _make("Lyra")
	_fighter = _make("Bram")
	_down = _make("Marta")
	_down.is_alive = false
	_down.current_hp = 0
	_bard.learn_ability("battle_hymn")
	_scene = SceneScript.new()
	## assign() — a plain Array into Array[Combatant] aborts before_each and the queue looks empty.
	_scene.party_members.assign([_bard, _fighter, _down])
	var bm: Node = _bm()
	bm.player_party.assign([_bard, _fighter, _down])
	bm.pending_actions.clear()
	bm.selection_order.clear()
	bm.selection_order.append(_bard)
	bm.selection_order.append(_fighter)
	bm.selection_index = 0
	bm.current_combatant = _bard
	bm.current_state = bm.BattleState.PLAYER_SELECTING
	bm.is_autobattle_enabled = false


func after_each() -> void:
	if _snap != null:
		_snap.restore()
	if is_instance_valid(_scene):
		_scene.free()


func _bm() -> Node:
	return get_node("/root/BattleManager")


func _make(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname,
		"max_hp": 200,
		"max_mp": 40,
		"attack": 20,
		"defense": 10,
		"magic": 12,
		"speed": 10,
	})
	add_child_autofree(c)
	return c


func _queued_targets(ability_id: String) -> Array:
	var found: Array = []
	for action in _bm().pending_actions:
		if str(action.get("ability_id", "")) == ability_id:
			found = action.get("targets", [])
	return found


func _names(targets: Array) -> Array:
	var out: Array = []
	for t in targets:
		if t is Combatant:
			out.append(t.combatant_name)
	out.sort()
	return out


func test_a_manual_battle_hymn_is_queued_for_every_living_ally() -> void:
	var hymn: Dictionary = JobSystem.get_ability("battle_hymn")
	assert_eq(str(hymn.get("target_type", "")), "all_allies",
		"battle_hymn must still be the party song this test is about")
	_scene._execute_ability("battle_hymn", _bard, false)
	var targets := _queued_targets("battle_hymn")
	assert_eq(_names(targets), ["Bram", "Lyra"],
		"a manual Battle Hymn must be aimed at every living ally, not only the singer")
	assert_false(_down in targets, "a downed ally is not a Battle Hymn target")
	_bm()._execute_ability(_bard, "battle_hymn", targets)
	assert_true(_has_attack_buff(_bard), "the singer is buffed")
	assert_true(_has_attack_buff(_fighter), "the other living ally is buffed by the same cast")
	assert_false(_has_attack_buff(_down), "a downed ally does not receive the song")


func test_a_single_ally_cure_stays_on_the_chosen_target() -> void:
	var cure: Dictionary = JobSystem.get_ability("cure")
	assert_eq(str(cure.get("target_type", "")), "single_ally",
		"cure must stay single-target — the party expansion is only for all_allies")
	_scene._execute_ability("cure", _fighter, false)
	assert_eq(_names(_queued_targets("cure")), ["Bram"],
		"aiming Cure at one ally must not splash the rest of the party")


func _has_attack_buff(c: Combatant) -> bool:
	for b in c.active_buffs:
		if b is Dictionary and str(b.get("stat", "")) == "attack":
			return true
	return false
