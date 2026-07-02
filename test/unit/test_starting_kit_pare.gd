extends GutTest

## Item 18 (user: "at beginning the players should have fairly limited
## abilities... they kind of come stacked rn"). Mage shipped with all
## NINE elemental spells including the -ga tier at level 1; Cleric
## with the full heal suite including raise. Pared: small base kits,
## the rest moved to abilities_at_level (existing level-up mechanism).
## Old saves back-fill on load via from_dict reconciliation.

func _job(jid: String) -> Dictionary:
	return JobSystem.get_job(jid) if JobSystem.has_method("get_job") else JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))["jobs"][jid]


func _full_kit(jid: String) -> Array:
	var j: Dictionary = _job(jid)
	var kit: Array = (j.get("abilities", []) as Array).duplicate()
	for lvl in j.get("abilities_at_level", {}):
		kit.append_array(j["abilities_at_level"][lvl])
	return kit


func test_mage_starts_with_three_elements_only() -> void:
	var base: Array = _job("mage").get("abilities", [])
	assert_eq(base.size(), 3, "mage base kit must be exactly the tier-1 trio")
	for aid in ["fire", "blizzard", "thunder"]:
		assert_has(base, aid)
	for aid in ["fira", "firaga", "blizzaga", "thundaga"]:
		assert_does_not_have(base, aid, "%s must be level-gated, not innate" % aid)


func test_cleric_starts_lean() -> void:
	var base: Array = _job("cleric").get("abilities", [])
	assert_eq(base.size(), 2, "cleric base kit: cure + protect")
	assert_has(base, "cure")
	assert_does_not_have(base, "raise", "revival is a level-10 milestone, not innate")


func test_no_spell_was_lost_in_the_pare() -> void:
	# Everything the old stacked kits had must still be reachable
	# through base + abilities_at_level.
	for aid in ["fire", "blizzard", "thunder", "fira", "blizzara", "thundara",
			"firaga", "blizzaga", "thundaga"]:
		assert_has(_full_kit("mage"), aid, "mage must still reach %s" % aid)
	for aid in ["cure", "cura", "raise", "protect", "esuna", "regen"]:
		assert_has(_full_kit("cleric"), aid, "cleric must still reach %s" % aid)


func test_every_gated_ability_resolves() -> void:
	# The pare must not introduce ghost ability ids.
	for jid in ["mage", "cleric"]:
		for aid in _full_kit(jid):
			assert_false(JobSystem.get_ability(str(aid)).is_empty(),
				"%s kit entry %s must resolve in abilities.json" % [jid, aid])


func test_old_save_backfills_on_restore() -> void:
	# A pre-pare save: level-12 mage with EMPTY learned_abilities (they
	# never "learned" firaga — it was innate). Production restore order
	# is from_dict THEN assign_job (GameLoop._restore_party...), and
	# assign_job now grants everything at or below the current level.
	var c := Combatant.new()
	add_child_autofree(c)
	c.from_dict({
		"combatant_name": "Old Save Mage",
		"job_level": 12,
		"max_hp": 100, "current_hp": 100,
	})
	assert_true(JobSystem.assign_job(c, "mage"))
	var kit: Array = (c.job.get("abilities", []) as Array).duplicate()
	kit.append_array(c.learned_abilities)
	for aid in ["fira", "blizzara", "thundara", "firaga", "blizzaga"]:
		assert_has(kit, aid, "level-12 restored mage must have %s back-granted" % aid)
	assert_does_not_have(c.learned_abilities, "thundaga",
		"level-13 unlock must NOT back-grant at level 12")


func test_fresh_level_one_gets_no_unlocks() -> void:
	var c := Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": "Fresh Mage", "max_hp": 80, "max_mp": 60,
		"attack": 5, "defense": 5, "magic": 12, "speed": 8})
	assert_true(JobSystem.assign_job(c, "mage"))
	assert_does_not_have(c.learned_abilities, "fira",
		"a level-1 mage must start with the lean kit only")


func test_duel_kit_relations_survive_the_pare() -> void:
	# The duel audit runs in the same suite, but pin the two direct
	# dependencies here for a fast local signal: mage duel (level 5)
	# still covers all prismatic weaknesses from BASE; cleric duel
	# (level 2) still has its heal innate.
	var mage_base: Array = _job("mage").get("abilities", [])
	for aid in ["fire", "blizzard", "thunder"]:
		assert_has(mage_base, aid)
	assert_has(_job("cleric").get("abilities", []), "cure")
