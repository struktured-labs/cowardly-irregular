extends GutTest

## Combo Magic asked a character's JOB what elements it had, not the character.
##
## The gate collected elements from JobSystem.get_job_abilities(job_id), which returns ONLY
## job["abilities"] — the base kit. It skips abilities_at_level, learned, purchased, and the
## secondary job. So a Fighter who bought Fire at Harmonia's magic shop contributed nothing, and a
## character lending a secondary caster's kit contributed nothing, and the party was told it could
## not fuse elements it could actually cast.
##
## struktured's 2026-09-06 ruling is that provenance is irrelevant — kit ∪ secondary ∪ learned ∪
## purchased ∪ level ∪ free_move, one predicate for shops, menus and can_use_ability. Combatant
## .get_known_abilities is that predicate; this gate now uses it.
##
## The error is ONE-DIRECTIONAL and that is why nothing caught it: base-kit spells are always known,
## so the old read never produced a FALSE offer, only a false refusal. A gate that fails closed looks
## like a rule.

const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")

func _pc(display_name: String, job_id: String, kit: Array) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = display_name
	c.job = {"id": job_id, "abilities": kit.duplicate()}
	c.job_level = 1
	c.max_mp = 200; c.current_mp = 200
	c.max_hp = 500; c.current_hp = 500
	return c

func test_the_base_kit_still_counts() -> void:
	## CONTROL: the case that always worked must keep working — a Mage brings three elements.
	var elements := MenuScript.combo_elements_for([_pc("Mira", "mage", ["fire", "blizzard", "thunder"])])
	assert_gte(elements.size(), 3,
		"a Mage's starting kit is three elements, got %s" % str(elements))

func test_a_purchased_spell_counts() -> void:
	## The magic shops sell spells and mark them `purchased_abilities`. Before this, buying Fire for
	## a Fighter changed nothing about what the party could fuse.
	var fighter := _pc("Bram", "fighter", ["power_strike"])
	assert_eq(MenuScript.combo_elements_for([fighter]).size(), 0,
		"CONTROL: a Fighter's own kit carries no element")
	fighter.purchased_abilities.append("fire")
	assert_true("fire" in MenuScript.combo_elements_for([fighter]),
		"a purchased spell must count — the shop said you own it")

func test_a_learned_spell_counts() -> void:
	var fighter := _pc("Bram", "fighter", ["power_strike"])
	fighter.learn_ability("blizzard")
	assert_true("ice" in MenuScript.combo_elements_for([fighter]),
		"a learned spell must count toward the fusion its element enables")

func test_a_secondary_job_lends_its_elements() -> void:
	## Secondary jobs lend their kit (2026-09-06). The old read consulted only the PRIMARY job id.
	var cleric := _pc("Elowen", "cleric", ["cure", "protect"])
	assert_eq(MenuScript.combo_elements_for([cleric]).size(), 0, "CONTROL: a Cleric's kit is element-less")
	cleric.secondary_job = {"id": "mage", "abilities": ["fire", "thunder"]}
	var elements := MenuScript.combo_elements_for([cleric])
	assert_true("fire" in elements and "lightning" in elements,
		"a secondary caster's elements must count, got %s" % str(elements))

func test_a_level_gated_unlock_counts_only_once_reached() -> void:
	## The one direction the old read got right by accident, kept honest: an unlock the character has
	## not reached must NOT count, or the gate starts offering fusions nobody can cast.
	var mage := _pc("Mira", "mage", ["fire"])
	mage.job["abilities_at_level"] = {"4": ["blizzard"]}
	assert_false("ice" in MenuScript.combo_elements_for([mage]),
		"a level-4 unlock must not count at level 1")
	mage.job_level = 4
	assert_true("ice" in MenuScript.combo_elements_for([mage]),
		"and must count once the level is reached")

func test_elements_are_distinct_across_the_party() -> void:
	## Two Mages are not six elements — the gate needs DISTINCT elements, and a duplicate would
	## inflate a two-element party into a three-element Prism Convergence.
	var a := _pc("Mira", "mage", ["fire", "blizzard", "thunder"])
	var b := _pc("Vex", "mage", ["fire", "blizzard", "thunder"])
	assert_eq(MenuScript.combo_elements_for([a, b]).size(), MenuScript.combo_elements_for([a]).size(),
		"a second Mage adds no new element")

func test_a_dead_or_null_member_does_not_crash_the_gate() -> void:
	var mage := _pc("Mira", "mage", ["fire", "blizzard"])
	assert_gt(MenuScript.combo_elements_for([null, mage]).size(), 0,
		"a null entry is skipped, not fatal — the caller builds this list from a live party")
