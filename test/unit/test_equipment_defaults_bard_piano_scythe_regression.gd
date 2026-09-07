extends GutTest

## tick 320: EquipmentSystem._create_default_equipment now includes
## piano_scythe so the Bard's auto-equip path in JobSystem.assign_job
## works even when equipment.json fails to load.
##
## Pre-fix JobSystem.assign_job at line ~487 contained:
##   if job_id == "bard" and combatant.equipped_weapon.is_empty():
##       if equipment.weapons.has("piano_scythe"):
##           equipment.equip_weapon(combatant, "piano_scythe")
##
## The `has("piano_scythe")` guard meant a missing entry silently
## skipped the equip — no push_warning, no diagnostic. If equipment.json
## failed to load (push_warning paths at lines 31/40/58/61 of
## EquipmentSystem), every Bard joined unarmed and the player had no
## idea why. Same gap class as tick 319 (Bard's encore passive
## missing from PassiveSystem defaults) and tick 318 (max_mp missing
## from JobSystem stat_modifiers).

const EQUIP_SYSTEM_PATH := "res://src/jobs/EquipmentSystem.gd"
const JOB_SYSTEM_PATH := "res://src/jobs/JobSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: piano_scythe in defaults ────────────────────────────

func test_piano_scythe_in_default_weapons() -> void:
	var src := _read(EQUIP_SYSTEM_PATH)
	var fn_idx: int = src.find("func _create_default_equipment")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The piano_scythe block must be inside the weapons dict (which
	# is the first dict in _create_default_equipment).
	assert_true(body.contains("\"piano_scythe\":"),
		"piano_scythe key must exist in EquipmentSystem defaults")
	# Stats mirror data/equipment.json — pin the numbers so future
	# drift can't reintroduce the gap without a loud test failure.
	var ps_idx: int = body.find("\"piano_scythe\":")
	var ps_body: String = body.substr(ps_idx, 600)
	assert_true(ps_body.contains("\"attack\": 8"),
		"piano_scythe must have attack=8 (matches data/equipment.json)")
	assert_true(ps_body.contains("\"magic\": 6"),
		"piano_scythe must have magic=6")
	assert_true(ps_body.contains("\"speed\": 2"),
		"piano_scythe must have speed=2")


# ── Cross-file invariant: assign_job's auto-equip ref exists ────────

func test_assign_job_auto_equip_target_exists() -> void:
	var job_src := _read(JOB_SYSTEM_PATH)
	# JobSystem.assign_job has the auto-equip guard.
	assert_true(job_src.contains("equipment.equip_weapon(combatant, \"piano_scythe\")"),
		"JobSystem.assign_job must still have the Bard piano_scythe auto-equip path — if this assertion fails, the entire cross-file invariant goes away and this test can be deleted")
	# And our defaults must cover the same id.
	var equip_src := _read(EQUIP_SYSTEM_PATH)
	assert_true(equip_src.contains("\"piano_scythe\":"),
		"EquipmentSystem defaults must include piano_scythe — same cross-file invariant tick 319 enforced for PassiveSystem.encore")


# ── Behavioral: equip_weapon('piano_scythe') succeeds via the real autoload ─

func test_real_autoload_can_equip_piano_scythe() -> void:
	# Real autoload — equipment.json IS available, so this just exercises
	# the canonical path. The defaults path runs only on file failure;
	# that's covered by the source pin above.
	assert_not_null(EquipmentSystem, "EquipmentSystem autoload required")
	if EquipmentSystem == null:
		return
	assert_true(EquipmentSystem.weapons.has("piano_scythe"),
		"EquipmentSystem.weapons must include piano_scythe (whether from json or defaults — both should agree now)")
