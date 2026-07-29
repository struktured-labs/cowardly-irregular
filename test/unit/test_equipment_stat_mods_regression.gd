extends GutTest

## Equipment stat_mods accept ANY real stat — struktured 2026-07-29: "equipmods should be able to
## affect any stat really."
##
## get_equipment_mods built a hardcoded six-key dict and filtered every slot through
## `if total_mods.has(stat)`. A stat_mods key it did not name was dropped in silence — no warning,
## no log, no crash. Latent rather than live (all six authored keys were in the list), but the
## magic_defense split landed the same day and is exactly the stat someone would reach for next.
## A piece of gear granting +40 M.DEF would simply have done nothing.
##
## Fixed by inverting the filter: unknown keys are SUMMED, not discarded, and the default key set
## is driven off Combatant.MODDABLE_STATS so adding a stat there is the only edit required.
##
## That trades a silent drop for a silent no-op — a typo like "atack" now reaches Combatant and
## finds no such property. So generalising the mechanism ALONE would have moved the failure rather
## than removed it. test_every_authored_stat_mods_key_is_a_real_stat is the other half: it turns
## the typo red at the data layer, which is the only place it can be caught loudly.


func test_moddable_stats_is_the_single_authority() -> void:
	# Every stat the damage/turn systems read must be gear-reachable. If a stat exists on
	# Combatant but not in this list, gear can never touch it and nothing says so.
	for stat in ["max_hp", "max_mp", "attack", "defense", "magic", "magic_defense", "speed"]:
		assert_has(Combatant.MODDABLE_STATS, stat,
			"'%s' is a real combatant stat and must be gear-moddable" % stat)


func test_every_moddable_stat_actually_exists_on_combatant() -> void:
	# The reverse direction. A name in the list that is not a property is a set() into nothing.
	var c := Combatant.new()
	for stat in Combatant.MODDABLE_STATS:
		assert_true(stat in c, "MODDABLE_STATS names '%s' but Combatant has no such property" % stat)
	c.free()


func test_get_equipment_mods_defaults_include_magic_defense() -> void:
	var c := Combatant.new()
	c.combatant_name = "test"
	var mods: Dictionary = EquipmentSystem.get_equipment_mods(c)
	assert_true(mods.has("magic_defense"),
		"the default key set must cover magic_defense — the old hand-listed six omitted it, so "
		+ "M.DEF gear would have been dropped before any combatant saw it")
	c.free()


func test_an_unrecognised_stat_key_is_summed_not_dropped() -> void:
	# SWEPT across keys AND slots. The property is "ANY stat key on ANY slot is summed" — a single
	# probe cannot express that, and the original version (one magic_defense weapon) passed 9/9
	# against a fix that special-cased exactly that key. cowir-ai's fixture-coincidence class:
	# the mutation applied, the guard ran, the code was broken, and it printed green.
	var es := EquipmentSystem
	var tables := {"weapons": es.weapons, "armors": es.armors, "accessories": es.accessories}
	var slot_field := {"weapons": "equipped_weapon", "armors": "equipped_armor",
		"accessories": "equipped_accessory"}
	var checked: int = 0
	for slot in tables:
		for stat in Combatant.MODDABLE_STATS:
			var probe_id: String = "__probe_%s_%s__" % [slot, stat]
			(tables[slot] as Dictionary)[probe_id] = {
				"id": probe_id, "name": "Probe", "weapon_type": "sword",
				"stat_mods": {stat: 40}
			}
			var c := Combatant.new()
			c.combatant_name = "test"
			c.set(slot_field[slot], probe_id)
			var mods: Dictionary = es.get_equipment_mods(c)
			checked += 1
			assert_eq(int(mods.get(stat, 0)), 40,
				"%s on the %s slot must be summed — filtering ANY key is what made gear bonuses "
					% [stat, slot] + "vanish without a word")
			c.free()
			(tables[slot] as Dictionary).erase(probe_id)
	assert_eq(checked, 21, "positive control — 3 slots × 7 moddable stats must be exercised")


func test_the_probe_would_have_failed_before_the_fix() -> void:
	# Positive control: prove the old shape really did drop it, so the test above is not passing
	# for an unrelated reason.
	var old_style := {"attack": 0, "defense": 0, "magic": 0, "speed": 0, "max_hp": 0, "max_mp": 0}
	var authored := {"magic_defense": 40}
	for stat in authored:
		if old_style.has(stat):
			old_style[stat] += authored[stat]
	assert_false(old_style.has("magic_defense"),
		"the pre-fix allowlist must genuinely have had no home for this key")


func test_equipment_mods_reach_the_combatants_stats() -> void:
	# End to end: accumulation is worthless if recalculate_stats does not apply it.
	var src := FileAccess.get_file_as_string("res://src/battle/Combatant.gd")
	assert_string_contains(src, "for stat in MODDABLE_STATS:",
		"recalculate_stats must apply equipment by iterating the authority list — a hand-written "
		+ "run of `stat += equip_mods.get(...)` lines omits whatever it forgets to name")


func test_every_authored_stat_mods_key_is_a_real_stat() -> void:
	# The half that keeps the generalisation honest. Unknown keys are no longer dropped, so a
	# typo reaches Combatant and no-ops. This is the only layer that can catch it loudly.
	var offenders: Array = []
	var eq: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	for category in eq:
		var items: Variant = eq[category]
		if not (items is Dictionary):
			continue
		for item_id in (items as Dictionary):
			var entry: Variant = (items as Dictionary)[item_id]
			if not (entry is Dictionary):
				continue
			var mods: Variant = (entry as Dictionary).get("stat_mods")
			if not (mods is Dictionary):
				continue
			for stat in (mods as Dictionary):
				if not Combatant.MODDABLE_STATS.has(str(stat)):
					offenders.append("%s/%s: '%s'" % [category, item_id, stat])
	assert_eq(offenders, [],
		"stat_mods keys that are not real stats — these silently do nothing:\n  %s"
			% "\n  ".join(offenders))


func test_the_typo_ratchet_can_see_a_bad_key() -> void:
	# Positive control — an empty offender list and a broken scan read identically.
	assert_false(Combatant.MODDABLE_STATS.has("atack"),
		"the ratchet above must reject a plausible misspelling, not accept everything")


func test_magic_defense_has_a_distinct_short_code() -> void:
	# StatNames falls back to substr(0,3).to_upper(), which yields "MAG" for BOTH magic and
	# magic_defense — the exact ambiguity that file's header calls out for max_hp/max_mp.
	assert_ne(StatNames.short_code("magic_defense"), StatNames.short_code("magic"),
		"magic and magic_defense must not share a display code in the equipment/battle readouts")
	assert_eq(StatNames.display_name("magic_defense"), "Magic Defense")


func test_a_key_OUTSIDE_the_seeded_set_is_still_summed() -> void:
	# The 21-combination sweep above CANNOT see the defect class, and finding that out is the point.
	#
	# total_mods is SEEDED from MODDABLE_STATS, so `total_mods.has(stat)` is true for every stat in
	# it. Reinstating the original allowlist filter verbatim passes that sweep 9/9 — every stat it
	# tries is already a key. The drop only shows on a key OUTSIDE the seed.
	#
	# A subtler relative of the fixture-coincidence class: the sweep was wide, and wide along an
	# axis the defect does not vary on. Sweeping harder in the wrong dimension proves nothing, and
	# it looks more rigorous than the single probe it replaced.
	var es := EquipmentSystem
	var future_stat := "luck"   # stands in for any stat the DATA gains before the authority list
	assert_false(Combatant.MODDABLE_STATS.has(future_stat),
		"this test needs a key the seed does NOT contain — if 'luck' became moddable, pick another")
	var probe_id := "__probe_unseeded__"
	es.weapons[probe_id] = {"id": probe_id, "name": "Probe", "weapon_type": "sword",
		"stat_mods": {future_stat: 40}}
	var c := Combatant.new()
	c.combatant_name = "test"
	c.equipped_weapon = probe_id
	var mods: Dictionary = es.get_equipment_mods(c)
	c.free()
	es.weapons.erase(probe_id)
	assert_eq(int(mods.get(future_stat, 0)), 40,
		"a stat_mods key outside the seeded set must be SUMMED. Filtering it is the original "
		+ "defect, and it is invisible to any sweep restricted to stats the seed already contains")
