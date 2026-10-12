extends GutTest

## The other exit from the THREE registries keyed by a Combatant. Death is handled (the status icon
## container is freed and erased, and the HP bar is retired on both death paths), but TEARDOWN was
## not: `_create_battle_sprites` frees every party and enemy sprite and `_restart_battle` frees the
## enemy COMBATANTS themselves — the very objects both dicts are keyed under — and neither emptied
## `_status_icon_containers`, `_enemy_hp_bars` or `_buff_visual_nodes`. Measured on main after ONE
## restart (the roster is
## a random encounter and varies run to run, so read the shape, not the names):
##   _enemy_hp_bars           still held the whole previous battle's enemies
##   _status_icon_containers  still held those AND the five party members
##   _buff_visual_nodes       held whichever of them had been buffed, and is the one with NO other
##                            way out: _remove_buff_visual is only reached for a combatant still in
##                            BattleManager's parties, so a replaced enemy is never visited again
## with `_update_enemy_hp_bars` walking the first every frame and `_refresh_all_status_icons` the
## second every round, both defended only by an is_instance_valid skip.
##
## ⚠️ THE FIX IS ONE CLEAR, AT THE REBUILD, AND THE SECOND SITE I WROTE FIRST WAS DEAD CODE.
## `_restart_battle` ENDS by calling `_create_battle_sprites`, so clearing there too changed nothing
## any arm here could see — site A alone passes all five. I had also written that a wholesale clear
## in `_restart_battle` "would silently drop five live party members' status icons": FALSE, the
## rebuild re-registers them three lines later. Both claims died to the same measurement, which is
## why `test_a_restart_keeps_the_partys_status_icons` is kept — not as a trap guard against the
## wrong fix (no such mutant reds), but because the clear below is only safe while the same pass
## re-registers the party, and that arm is what reds when it stops.

const SCENE := "res://src/battle/BattleScene.tscn"
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _guard: RefCounted = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _scene() -> Node:
	var s = load(SCENE).instantiate()
	add_child_autofree(s)
	return s


func _names(keys: Array) -> String:
	var out: Array = []
	for k in keys:
		out.append(str(k.combatant_name) if is_instance_valid(k) and ("combatant_name" in k) else "<freed>")
	return str(out)


## CONTROL: the scene must actually build a battle, or every arm below measures two empty dicts
## and passes for the wrong reason.
func test_control_a_built_battle_registers_both_sides() -> void:
	var scene := _scene()
	assert_gt(scene.test_enemies.size(), 0, "the scene must build enemies")
	assert_gt(scene.party_members.size(), 0, "and a party")
	assert_gt(scene._enemy_hp_bars.size(), 0, "every enemy carries a floating HP bar")
	assert_gt(scene._status_icon_containers.size(), scene.test_enemies.size(),
		"the status registry must hold the PARTY TOO — the clear below empties their entries as well")


## The defect: the enemies of the finished battle must not survive as keys.
func test_a_restart_drops_every_enemy_from_both_registries() -> void:
	var scene := _scene()
	var old_enemies: Array = []
	for e in scene.test_enemies:
		old_enemies.append(e)
	assert_gt(old_enemies.size(), 0, "CONTROL: there must be enemies to drop")
	if old_enemies.is_empty():
		return
	scene._restart_battle()
	for e in old_enemies:
		assert_false(scene._enemy_hp_bars.has(e),
			"a finished battle's enemy must leave the HP bar registry (left %s)" % _names(scene._enemy_hp_bars.keys()))
		assert_false(scene._status_icon_containers.has(e),
			"and the status icon registry (left %s)" % _names(scene._status_icon_containers.keys()))


## The clear empties the PARTY's entries too, and is correct only because the same pass re-registers
## them. Mutating `_setup_status_icons(member, sprite)` away reds this arm (Failing 2), which is what
## it is for — there is no mutant where a restart alone costs the party its icons.
func test_a_restart_keeps_the_partys_status_icons() -> void:
	var scene := _scene()
	var party: Array = []
	for m in scene.party_members:
		if scene._status_icon_containers.has(m):
			party.append(m)
	assert_gt(party.size(), 0, "CONTROL: the party must be registered before a restart can keep it")
	if party.is_empty():
		return
	scene._restart_battle()
	for m in party:
		assert_true(scene._status_icon_containers.has(m),
			"%s must come back out of the rebuild; the clear takes every party entry with it" % str(m.combatant_name))


## The property both repairs defend, measured after the deferred frees land.
func test_no_registry_key_outlives_the_combatant_it_names() -> void:
	var scene := _scene()
	scene._restart_battle()
	await wait_frames(3)
	for k in scene._enemy_hp_bars.keys():
		assert_true(is_instance_valid(k),
			"_update_enemy_hp_bars walks this dict every frame; a freed key has no business in it")
	for k in scene._status_icon_containers.keys():
		assert_true(is_instance_valid(k),
			"_refresh_all_status_icons walks this one every round")
	for k in scene._buff_visual_nodes.keys():
		assert_true(is_instance_valid(k),
			"_update_buff_debuff_visuals walks the parties every frame and can never reach this key again")


## The other teardown site, reached directly. Planted rather than driven because two of the three
## only fill under conditions a fresh battle does not have (a live buff, a landed status).
func test_a_sprite_rebuild_drops_a_stale_entry() -> void:
	var scene := _scene()
	var ghost := Combatant.new()
	ghost.initialize({"name": "Ghost", "max_hp": 1, "max_mp": 0,
		"attack": 1, "defense": 1, "magic": 1, "speed": 1})
	add_child_autofree(ghost)
	scene._enemy_hp_bars[ghost] = {"bar_bg": null, "bar_trail": null, "bar_fill": null}
	scene._status_icon_containers[ghost] = null
	scene._buff_visual_nodes[ghost] = {"glow": null, "particles": null, "sigil": null}
	scene._create_battle_sprites()
	assert_false(scene._enemy_hp_bars.has(ghost),
		"a sprite rebuild frees every sprite that owned a registered node, so the entry must go with it")
	assert_false(scene._status_icon_containers.has(ghost),
		"all three registries are rebuilt by the same pass")
	assert_false(scene._buff_visual_nodes.has(ghost),
		"_buff_visual_nodes has no other exit — _remove_buff_visual never visits a combatant that left the parties")
