extends GutTest

## Bugfix 2026-07-04: estimate_ability_damage (the "~N dmg" preview in the
## ability→enemy submenu) applied weakness (1.5x) and resistance (0.5x) but
## IGNORED immunity — so an enemy the intel panel flagged "Immune: Ice" still
## previewed positive damage the swing would never deal. The preview now reuses
## Combatant.calculate_elemental_modifier (the real hit's source of truth) and
## returns a truthful 0 for immunity, bypassing the min-1 damage floor.

const FIRE := {"type": "magic", "power": 12, "element": "fire"}


func _attacker() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Caster"
	c.magic = 30
	c.attack = 30
	return c


func _target(weak: Array = [], resist: Array = [], immune: Array = []) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Foe"
	c.defense = 10
	c.max_hp = 999
	c.current_hp = 999
	var tw: Array[String] = []
	for e in weak:
		tw.append(str(e))
	c.elemental_weaknesses = tw
	var tr: Array[String] = []
	for e in resist:
		tr.append(str(e))
	c.elemental_resistances = tr
	var ti: Array[String] = []
	for e in immune:
		ti.append(str(e))
	c.elemental_immunities = ti
	return c


func test_immune_enemy_previews_zero() -> void:
	var dmg := BattleManager.estimate_ability_damage(_attacker(), _target([], [], ["fire"]), FIRE)
	assert_eq(dmg, 0, "an enemy immune to the ability's element must preview 0 — not phantom damage")


func test_weak_beats_neutral_beats_resist() -> void:
	var neutral := BattleManager.estimate_ability_damage(_attacker(), _target(), FIRE)
	var weak := BattleManager.estimate_ability_damage(_attacker(), _target(["fire"]), FIRE)
	var resist := BattleManager.estimate_ability_damage(_attacker(), _target([], ["fire"]), FIRE)
	assert_gt(weak, neutral, "weakness must raise the estimate (1.5x)")
	assert_lt(resist, neutral, "resistance must lower the estimate (0.5x)")
	assert_gt(resist, 0, "a resisted (not immune) hit still previews at least 1")


func test_nonelemental_preview_ignores_target_immunity() -> void:
	# A physical (element null) ability isn't elemental, so a fire-immune target
	# must not zero its preview.
	var phys := {"type": "physical", "power": 12, "element": null}
	var vs_immune := BattleManager.estimate_ability_damage(_attacker(), _target([], [], ["fire"]), phys)
	assert_gt(vs_immune, 0, "a non-elemental ability ignores the target's elemental immunities")


func test_estimate_matches_the_canonical_modifier() -> void:
	# The whole point of the fix: parity with the real hit. Pin that the estimate
	# routes through calculate_elemental_modifier rather than a hand-rolled subset.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("func estimate_ability_damage")
	var body: String = src.substr(idx, src.find("\nfunc ", idx + 1) - idx)
	assert_true(body.contains("calculate_elemental_modifier"),
		"estimate must reuse the real hit's elemental source of truth")
