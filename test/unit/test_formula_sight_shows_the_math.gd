extends GutTest

## ⛔ `meta_effects` HAD NO CONSUMER. The Scriptweaver's two meta passives were equippable and inert:
## `formula_sight` (show_formulas) and `autobattle_verbs` (autobattle_advanced) each occur exactly once
## in src/ — their own declaration inside PassiveSystem's fallback copy of passives.json — while
## CLAUDE.md listed the first as SHIPPED. Four independent sweeps found the same nothing.
##
## Formula Sight now does what its description says: with it equipped, a damage row's tooltip shows the
## arithmetic that produced that row's "~N dmg". The number and the working are ONE computation
## (estimate_*_breakdown), so the explanation cannot drift from the estimate it explains.
##
## Still inert and NOT claimed here: autobattle_verbs.

const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")
const SceneScript = preload("res://src/battle/BattleScene.gd")

var _saved_party: Array
var _saved_order: Array
var _saved_index: int
var _saved_current


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_order = BattleManager.selection_order.duplicate()
	_saved_index = BattleManager.selection_index
	_saved_current = BattleManager.current_combatant


func after_each() -> void:
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.selection_order.assign(_alive(_saved_order))
	BattleManager.selection_index = _saved_index
	BattleManager.current_combatant = _saved_current if is_instance_valid(_saved_current) else null


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _pc(passives: Array[String]) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Vex"
	c.job = {"id": "scriptweaver"}
	c.max_hp = 400
	c.current_hp = 400
	c.attack = 120
	c.magic = 90
	c.current_ap = 2
	c.is_alive = true
	for p in passives:
		c.equipped_passives.append(p)
	return c


func _enemy(defense: int, magic_defense: int = 30) -> Combatant:
	var e := Combatant.new()
	autofree(e)
	e.combatant_name = "Goblin"
	e.max_hp = 900
	e.current_hp = 900
	e.defense = defense
	e.magic_defense = magic_defense
	e.is_alive = true
	return e


# ─── the passive is finally readable ───

func test_a_meta_effect_is_readable_from_the_passive_a_pc_has_equipped() -> void:
	var bare := _pc([])
	var seer := _pc(["formula_sight"])
	assert_false(PassiveSystem.has_meta_effect(bare, "show_formulas"), "nothing equipped, nothing seen")
	assert_true(PassiveSystem.has_meta_effect(seer, "show_formulas"), "formula_sight declares show_formulas")
	assert_false(PassiveSystem.has_meta_effect(seer, "autobattle_advanced"),
		"CONTROL: a different meta_effect is not granted by this passive — the reader keys on the KEY, not on having any meta passive")
	assert_true(PassiveSystem.has_meta_effect(_pc(["autobattle_verbs"]), "autobattle_advanced"),
		"and autobattle_verbs declares its own (still unconsumed — this only proves the reader)")
	assert_false(PassiveSystem.has_meta_effect(null, "show_formulas"), "a null combatant sees nothing")
	assert_false(PassiveSystem.has_meta_effect(_pc(["no_such_passive"]), "show_formulas"), "an unknown passive id grants nothing")


# ─── the working matches the number it explains ───

func test_the_attack_formula_is_the_estimate_it_explains() -> void:
	var pc := _pc([])
	var goblin := _enemy(60)
	var breakdown: Dictionary = BattleManager.estimate_attack_breakdown(pc, goblin)
	assert_eq(int(breakdown["damage"]), BattleManager.estimate_attack_damage(pc, goblin),
		"the preview number comes from this same computation")
	var formula: String = str(breakdown["formula"])
	assert_true(formula.contains("ATK 120"), "it names the attacker's stat as used (%s)" % formula)
	assert_true(formula.contains("DEF 60"), "and the target's")
	assert_true(formula.contains(str(int(breakdown["damage"]))), "and ends at the number on the row")


func test_the_ability_formula_names_the_stats_that_branch() -> void:
	var pc := _pc([])
	var goblin := _enemy(60, 20)
	var physical := BattleManager.estimate_ability_breakdown(pc, goblin, {"type": "physical", "damage_multiplier": 2.0})
	assert_true(str(physical["formula"]).contains("ATK 120") and str(physical["formula"]).contains("DEF 60"),
		"a physical ability reads ATK against DEF (%s)" % str(physical["formula"]))
	var magical := BattleManager.estimate_ability_breakdown(pc, goblin, {"type": "magic", "damage_multiplier": 2.0})
	assert_true(str(magical["formula"]).contains("MAG 90") and str(magical["formula"]).contains("MDEF 20"),
		"a magic ability reads MAG against MDEF — the branch a player cannot see from the number alone (%s)" % str(magical["formula"]))
	assert_eq(int(magical["damage"]), BattleManager.estimate_ability_damage(pc, goblin, {"type": "magic", "damage_multiplier": 2.0}),
		"and the magic number is still the preview's number")
	assert_true(str(physical["formula"]).contains("×2.0"), "the multiplier is shown, not folded away")


func test_an_immune_target_says_so_instead_of_showing_a_phantom_number() -> void:
	var pc := _pc([])
	var goblin := _enemy(60)
	goblin.elemental_immunities.append("ice")
	var frozen := BattleManager.estimate_ability_breakdown(pc, goblin, {"type": "magic", "damage_multiplier": 2.0, "element": "ice"})
	assert_eq(int(frozen["damage"]), 0, "CONTROL: immunity previews a truthful 0")
	assert_true(str(frozen["formula"]).contains("immune"), "and the working says why (%s)" % str(frozen["formula"]))


# ─── the menu shows it only to a PC who has the passive ───

func _scene_with(pc: Combatant, enemy: Combatant) -> Node:
	BattleManager.player_party.assign([pc] as Array[Combatant])
	BattleManager.selection_order.assign([pc] as Array[Combatant])
	BattleManager.selection_index = 0
	BattleManager.current_combatant = pc
	var scene = autofree(SceneScript.new())
	scene.party_members.assign([pc] as Array[Combatant])
	scene.test_enemies.assign([enemy] as Array[Combatant])
	var sprite := AnimatedSprite2D.new()
	add_child_autofree(sprite)
	scene.party_sprite_nodes.append(sprite)
	var enemy_sprite := AnimatedSprite2D.new()
	add_child_autofree(enemy_sprite)
	scene.enemy_sprite_nodes.append(enemy_sprite)
	add_child_autofree(scene)
	return scene


func _attack_rows(pc: Combatant, enemy: Combatant) -> Array:
	var menu = MenuScript.new(_scene_with(pc, enemy))
	for item in menu.build_command_menu_items_with_targets(pc):
		if str(item.get("id", "")) == "attack_menu":
			return item.get("submenu", []) as Array
	return []


func test_the_attack_row_carries_the_formula_only_for_a_pc_who_can_see_it() -> void:
	var goblin := _enemy(60)
	var bare_rows: Array = _attack_rows(_pc([]), goblin)
	assert_eq(bare_rows.size(), 1, "CONTROL: the Attack row lists the one enemy")
	assert_true(str(bare_rows[0].get("label", "")).contains("dmg"), "CONTROL: and still previews a number")
	assert_eq(str(bare_rows[0].get("tooltip", "")), "", "without the passive there is no formula under it")

	var seer := _pc(["formula_sight"])
	var seer_rows: Array = _attack_rows(seer, goblin)
	var tooltip: String = str(seer_rows[0].get("tooltip", ""))
	assert_ne(tooltip, "", "Formula Sight puts the working under the row")
	assert_eq(tooltip, str(BattleManager.estimate_attack_breakdown(seer, goblin)["formula"]),
		"and it is the engine's own working, not a second copy of the maths")
	assert_true(str(seer_rows[0].get("label", "")).contains("dmg"),
		"the row itself is unchanged — the passive adds a tooltip, it does not rewrite the label")
