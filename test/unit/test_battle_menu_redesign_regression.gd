extends GutTest

## Regression tests for the 2026-04 battle menu redesign.
##
## New menu shape: Auto / [MRU/Pin slot 1] / [MRU/Pin slot 2] / Free Move /
## Ability ▸ / Item ▸ / Group ▸ / Scan ▸ / Defer
##
## Per-job 'Free Move' replaces the legacy top-level 'Attack' for everyone.
## Fighter/Rogue: basic attack with custom label (Attack / Strike).
## Mage/Cleric/Bard: 0-MP self-target ability (Channel / Pray / Riff)
## that restores a small amount of MP — keeps casters from being bricked
## when MP runs dry.

const CombatantClass = preload("res://src/battle/Combatant.gd")


func test_combatant_mru_records_recent_uses() -> void:
	# Push 3 abilities. Only the last 2 should remain (MRU_SIZE = 2).
	var c = CombatantClass.new()
	c.record_ability_use("fire")
	c.record_ability_use("blizzard")
	c.record_ability_use("thunder")
	assert_eq(c.recent_abilities.size(), 2,
		"MRU should cap at MRU_SIZE (regression: cap enforcement)")
	assert_eq(c.recent_abilities[0], "thunder",
		"Most-recent should be at index 0 (front)")
	assert_eq(c.recent_abilities[1], "blizzard",
		"Second-most-recent at index 1")


func test_combatant_mru_dedupes() -> void:
	# Re-using an ability should bump it to front, not duplicate
	var c = CombatantClass.new()
	c.record_ability_use("fire")
	c.record_ability_use("blizzard")
	c.record_ability_use("fire")  # should bump fire to front, not add duplicate
	assert_eq(c.recent_abilities.size(), 2,
		"Re-used ability must not duplicate (dedupe)")
	assert_eq(c.recent_abilities[0], "fire",
		"Re-used ability bumps to front")
	assert_eq(c.recent_abilities[1], "blizzard",
		"Other entry shifts down")


func test_combatant_mru_skips_pinned_abilities() -> void:
	# Pinned abilities have their own slot — recording them should not pollute MRU.
	var c = CombatantClass.new()
	c.pinned_abilities.append("fire")
	c.record_ability_use("fire")
	assert_eq(c.recent_abilities.size(), 0,
		"Pinned ability should not enter MRU (regression: pin/MRU separation)")


func test_combatant_quick_slots_pin_priority() -> void:
	# Pins fill slots first, MRU fills the remainder.
	var c = CombatantClass.new()
	c.pinned_abilities.append("fire")
	c.recent_abilities.append("blizzard")
	c.recent_abilities.append("thunder")
	var slots = c.get_quick_slot_abilities(2)
	assert_eq(slots.size(), 2, "Should return 2 slots when MRU_SIZE=2")
	assert_eq(slots[0], "fire", "Pin takes the first slot")
	assert_eq(slots[1], "blizzard", "MRU fills the next available slot")


func test_combatant_quick_slots_dedupe_pin_in_mru() -> void:
	# If an ability is both pinned AND in MRU (shouldn't happen but defensively),
	# it should appear once.
	var c = CombatantClass.new()
	c.pinned_abilities.append("fire")
	c.recent_abilities.append("fire")  # technically pinned
	c.recent_abilities.append("blizzard")
	var slots = c.get_quick_slot_abilities(2)
	assert_eq(slots.size(), 2)
	assert_eq(slots[0], "fire")
	assert_eq(slots[1], "blizzard", "Duplicate skipped, blizzard fills second slot")


func test_jobs_json_has_free_move_per_starter() -> void:
	# Regression: every starter job MUST declare a free_move so the menu
	# always has the 4th slot. If this disappears the menu silently regresses
	# to having no free move and the player can't do anything when MP=0.
	var path = "res://data/jobs.json"
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "jobs.json must exist")
	var text = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "jobs.json must parse as Dictionary")

	var starter_jobs = ["fighter", "cleric", "mage", "rogue", "bard"]
	for job_id in starter_jobs:
		assert_true(parsed.has(job_id), "jobs.json missing starter job: %s" % job_id)
		var job: Dictionary = parsed[job_id]
		assert_true(job.has("free_move"),
			"Starter job '%s' must declare free_move (regression: redesign coverage)" % job_id)
		var fm: Dictionary = job["free_move"]
		assert_true(fm.has("type"),
			"%s.free_move missing 'type' field" % job_id)
		assert_true(fm.has("label"),
			"%s.free_move missing 'label' field" % job_id)
		var fm_type: String = fm.get("type", "")
		assert_true(fm_type in ["basic_attack", "ability"],
			"%s.free_move.type must be 'basic_attack' or 'ability', got '%s'" % [job_id, fm_type])
		if fm_type == "ability":
			assert_true(fm.has("ability_id"),
				"%s.free_move type='ability' must declare ability_id" % job_id)


func test_abilities_json_has_zero_mp_caster_moves() -> void:
	# Mage/Cleric/Bard need 0-MP fallback abilities so they're never bricked.
	var path = "res://data/abilities.json"
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "abilities.json must exist")
	var text = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	assert_true(parsed is Dictionary)

	for ability_id in ["channel", "pray", "riff"]:
		assert_true(parsed.has(ability_id),
			"Free-Move ability '%s' must exist (regression: caster fallback)" % ability_id)
		var a: Dictionary = parsed[ability_id]
		assert_eq(a.get("mp_cost", -1), 0,
			"%s must be 0 MP (it's the no-resource fallback)" % ability_id)
		assert_eq(a.get("type", ""), "mp_restore",
			"%s must use mp_restore type so BattleManager dispatches correctly" % ability_id)
		assert_true(a.get("mp_amount", 0) > 0,
			"%s must restore some MP (mp_amount > 0)" % ability_id)
