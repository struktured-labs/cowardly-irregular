extends GutTest

## A Mage in the Whispering Cave — W1's tutorial dungeon, with the starting fire/blizzard/thunder
## kit — read "~N dmg" off the command menu and the engine dealt something else. `cave` terrain
## reduces fire and lightning by 25% and boosts ice by 25% (`_get_terrain_modifiers`), and
## `_execute_magic_ability` applies terrain × weather at BattleManager.gd:5277. The estimator
## applied neither, so every elemental spell previewed in a cave was wrong by a quarter.
##
## ⛔ IT IS NOT A COSMETIC NUMBER: BattleCommandMenu renders `[KILL]` when `est >= current_hp` off
## this same value, so a Blizzard that WOULD kill lost its tag and a Fire that would NOT gained one.
##
## ⛔ AND `test_ui_matches_execution` — the file whose entire subject is "does the number on screen
## match what lands" — is green through this and always was. It never sets a terrain, so it runs at
## `plains`/`clear` where both factors are exactly 1.0. The defect lives in the one multiplier its
## corpus pins to the identity.
##
## The arms assert the RELATIONSHIP (a reduced element previews lower in a cave than on plains),
## never a computed number: re-deriving `mitigated * get_terrain_damage_modifier()` here would be
## the fix agreeing with itself.

const BM_SRC := "res://src/battle/BattleManager.gd"

const FIRE := {"type": "magic", "damage_multiplier": 2.0, "element": "fire"}
const ICE := {"type": "magic", "damage_multiplier": 2.0, "element": "ice"}


func _bm() -> Node:
	var bm: Node = load(BM_SRC).new()
	add_child_autofree(bm)
	return bm


func _pc() -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = "Mage"
	c.is_alive = true
	c.max_hp = 999
	c.current_hp = 999
	c.attack = 200
	c.magic = 200
	return c


func _target() -> Combatant:
	var t: Combatant = autofree(Combatant.new())
	t.combatant_name = "Cave Rat"
	t.is_alive = true
	t.max_hp = 99999
	t.current_hp = 99999
	t.defense = 40
	t.magic_defense = 40
	return t


func _preview(bm: Node, terrain: String, ability: Dictionary) -> int:
	bm.set_terrain(terrain)
	return int(bm.estimate_ability_damage(_pc(), _target(), ability))


func test_the_terrain_table_distinguishes_these_elements() -> void:
	## Without this, "cave equals plains" and "the preview reads terrain" are the same green.
	var bm := _bm()
	bm.set_terrain("cave")
	assert_lt(float(bm.get_terrain_damage_modifier("fire")), 1.0,
		"CONTROL: cave must REDUCE fire, or the arm below cannot tell a terrain read from a constant")
	assert_gt(float(bm.get_terrain_damage_modifier("ice")), 1.0,
		"CONTROL: cave must BOOST ice, or the opposite-direction arm proves nothing")
	bm.set_terrain("plains")
	assert_eq(float(bm.get_terrain_damage_modifier("fire")), 1.0,
		"CONTROL: plains must be the identity, or 'differs from plains' is not a terrain claim")


func test_a_reduced_element_previews_lower_in_the_cave_that_reduces_it() -> void:
	var bm := _bm()
	var on_plains: int = _preview(bm, "plains", FIRE)
	var in_cave: int = _preview(bm, "cave", FIRE)
	assert_gt(on_plains, 0, "CONTROL: the plains preview must be non-zero for the comparison to mean anything")
	assert_lt(in_cave, on_plains,
		"cave reduces fire by 25%% and _execute_magic_ability applies that at :5277, so the menu must "
		+ "quote less here than on plains (plains %d, cave %d)" % [on_plains, in_cave])


func test_a_boosted_element_previews_higher_in_the_same_cave() -> void:
	## The opposite direction, so a preview that merely got SMALLER for any reason cannot pass both.
	var bm := _bm()
	var on_plains: int = _preview(bm, "plains", ICE)
	var in_cave: int = _preview(bm, "cave", ICE)
	assert_gt(in_cave, on_plains,
		"cave boosts ice by 25%%, so a Blizzard must quote MORE in the cave — under-quoting is what "
		+ "withheld [KILL] from a lethal blow (plains %d, cave %d)" % [on_plains, in_cave])


func test_a_physical_ability_previews_the_same_whatever_the_terrain() -> void:
	## `_execute_physical_ability` reads no element at all — documented in that function, with a
	## same-day revert of weather scaling recorded in it. The preview must not add what it skips.
	var bm := _bm()
	var phys := {"type": "physical", "damage_multiplier": 2.0, "element": "fire"}
	assert_eq(_preview(bm, "cave", phys), _preview(bm, "plains", phys),
		"the physical path ignores element by construction, so terrain must not move its preview")


func test_a_physical_ability_ignores_a_resistance_the_swing_ignores() -> void:
	## The latent half, monster-only today (dark_slash, lightning_dash, cursed_strike and three
	## more live in monsters.json and no job list) — pinned so it cannot go live wrong.
	var bm := _bm()
	bm.set_terrain("plains")
	var phys := {"type": "physical", "damage_multiplier": 2.0, "element": "dark"}
	var plain_target := _target()
	var immune_target := _target()
	immune_target.elemental_immunities = ["dark"] as Array[String]
	var vs_plain: int = int(bm.estimate_ability_damage(_pc(), plain_target, phys))
	var vs_immune: int = int(bm.estimate_ability_damage(_pc(), immune_target, phys))
	assert_gt(vs_plain, 0, "CONTROL: the unresisted physical preview must be non-zero")
	assert_eq(vs_immune, vs_plain,
		"a physical strike's element is flavour — the swing deals full damage to a dark-immune "
		+ "target, so previewing 0 and labelling it '(immune)' would be a lie the player acts on")
