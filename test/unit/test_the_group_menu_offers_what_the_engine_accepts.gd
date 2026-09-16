extends GutTest

## ⛔ The Group submenu answered its own AP questions, and answered them differently from the engine
## that grants the attack. Measured in a live battle (5 PCs, real menu, real BattleManager):
##
##   actor AP  others AP   menu row    player_group_attack
##      +3        +4       ENABLED     REFUSED — "Limit Break requires ALL participants at full AP (4)!"
##
## Two causes, both in the menu: it added a phantom +1 AP for the ACTOR, whose natural gain is already
## in current_ap by the time the menu opens (selection_phase grants it, then selection_turn_started
## fires and the menu is built); and it gated on every ALIVE member, while the engine pools only the
## actor and the PCs after them in the selection order — the same distinction
## test_group_attack_participants_regression already fixed on the engine side, never carried here.
##
## The gate now has ONE owner: BattleManager.group_participants / group_ap_shortfall. These arms pin
## that the menu asks it rather than re-deriving the answer.

const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")
const SceneScript = preload("res://src/battle/BattleScene.gd")

var _saved_party: Array
var _saved_order: Array
var _saved_index: int
var _saved_current
var _saved_state: int
var _saved_enemies: Array


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_order = BattleManager.selection_order.duplicate()
	_saved_index = BattleManager.selection_index
	_saved_current = BattleManager.current_combatant
	_saved_state = BattleManager.current_state
	_saved_enemies = BattleManager.enemy_party.duplicate()


## Restore only what is still alive: this file's Combatants are autofreed, and assigning a freed one
## is a script error that aborts the rest of after_each, leaving the autoload dirty for the next file.
func after_each() -> void:
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.selection_order.assign(_alive(_saved_order))
	BattleManager.selection_index = _saved_index
	BattleManager.current_combatant = _saved_current if is_instance_valid(_saved_current) else null
	BattleManager.current_state = _saved_state
	BattleManager.enemy_party.assign(_alive(_saved_enemies))


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _pc(name: String, job: String, ap: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name
	c.job = {"id": job}
	c.max_hp = 500
	c.current_hp = 500
	c.is_alive = true
	c.current_ap = ap
	return c


## A party in selection order, with `acting_index` taking its turn right now.
func _party(aps: Array, acting_index: int) -> Array[Combatant]:
	var jobs := ["fighter", "cleric", "mage", "rogue", "bard"]
	var party: Array[Combatant] = []
	for i in aps.size():
		party.append(_pc("PC%d" % i, jobs[i % jobs.size()], int(aps[i])))
	BattleManager.player_party.assign(party)
	BattleManager.selection_order.assign(party)
	BattleManager.selection_index = acting_index
	BattleManager.current_combatant = party[acting_index]
	var goblin := _pc("Goblin", "", 0)
	BattleManager.enemy_party.assign([goblin])
	return party


func test_the_pool_is_the_actor_and_everyone_after_them() -> void:
	var party := _party([4, 4, 4, 4], 1)
	var pool: Array = BattleManager.group_participants()
	assert_eq(pool.size(), 3, "the actor plus the two PCs still to choose")
	assert_eq(pool[0], party[1], "the actor leads the pool")
	assert_false(pool.has(party[0]), "a PC who already chose neither pays nor gates")
	BattleManager.current_combatant = null
	assert_eq(BattleManager.group_participants().size(), 0, "no actor, no pool")


func test_a_spent_pc_who_already_acted_cannot_block_the_pool() -> void:
	## The engine's own regression: PC0 acted and is in AP debt; it is not a participant.
	var party := _party([-2, 4, 4], 1)
	assert_null(BattleManager.group_ap_shortfall("limit_break"), "PC0's debt is not the pool's problem")
	party[2].current_ap = 3
	assert_eq(BattleManager.group_ap_shortfall("limit_break"), party[2], "a participant one short is named")
	assert_null(BattleManager.group_ap_shortfall("all_out_attack"), "and still affords the 1 AP strike")


func test_the_actors_natural_gain_is_not_counted_twice() -> void:
	## selection_phase grants the +1 BEFORE selection_turn_started, so current_ap already holds it.
	var party := _party([3, 4, 4], 0)
	assert_eq(BattleManager.group_ap_shortfall("limit_break"), party[0],
		"an actor at 3 AP is one short — the menu used to read it as 4 and offer the row")


func _limit_row(scene, combatant: Combatant) -> Dictionary:
	var menu = MenuScript.new(scene)
	for item in menu.build_command_menu_items_with_targets(combatant):
		if str(item.get("id", "")) == "group_menu":
			for sub in (item.get("submenu", []) as Array):
				if str(sub.get("id", "")) == "group_limit":
					return sub
	return {}


func _scene_for(party: Array[Combatant]) -> Node:
	var scene = autofree(SceneScript.new())
	scene.party_members.assign(party)
	scene.test_enemies.assign(BattleManager.enemy_party)
	for m in party:
		var sprite := AnimatedSprite2D.new()
		add_child_autofree(sprite)
		scene.party_sprite_nodes.append(sprite)
	var enemy_sprite := AnimatedSprite2D.new()
	add_child_autofree(enemy_sprite)
	scene.enemy_sprite_nodes.append(enemy_sprite)
	add_child_autofree(scene)
	return scene


func test_the_menu_row_agrees_with_the_engine_at_every_ap_split() -> void:
	## The matrix that caught it. Each case: what the row says, and what group_ap_shortfall says.
	var cases := [[3, 4], [4, 3], [3, 3], [4, 4]]
	var disagreed: Array = []
	var enabled_seen: int = 0
	for case in cases:
		var party := _party([int(case[0]), int(case[1]), int(case[1])], 0)
		var row: Dictionary = _limit_row(_scene_for(party), party[0])
		assert_false(row.is_empty(), "CONTROL: the Limit Break row is built for %s" % str(case))
		var row_says_yes: bool = not bool(row.get("disabled", false))
		var engine_says_yes: bool = BattleManager.group_ap_shortfall("limit_break") == null
		if row_says_yes:
			enabled_seen += 1
		if row_says_yes != engine_says_yes:
			disagreed.append("actor %+d others %+d: menu %s, engine %s" % [case[0], case[1],
				"enabled" if row_says_yes else "disabled", "accepts" if engine_says_yes else "refuses"])
	assert_eq(disagreed.size(), 0, "the menu offered what the engine refuses, or hid what it accepts: " + str(disagreed))
	assert_eq(enabled_seen, 1, "CONTROL: exactly the +4/+4 case is offered, so this is not passing by disabling everything")


func test_the_group_row_is_gone_when_the_engine_would_pool_one_pc() -> void:
	## The last PC in the order pools only itself; "all party members strike together" is not on offer.
	var party := _party([4, 4, 4], 2)
	assert_eq(BattleManager.group_participants().size(), 1, "CONTROL: the pool is the actor alone")
	var rows: Array = MenuScript.new(_scene_for(party)).build_command_menu_items_with_targets(party[2])
	var ids: Array = []
	for item in rows:
		ids.append(str(item.get("id", "")))
	assert_gt(ids.size(), 3, "CONTROL: the menu built its ordinary rows (%s)" % str(ids))
	assert_false(ids.has("group_menu"), "no Group row when only the actor would pool")
