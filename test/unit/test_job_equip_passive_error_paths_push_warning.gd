extends GutTest

## tick 180 regression: JobSystem.assign_job / EquipmentSystem.
## equip_* / PassiveSystem.equip_passive / unequip_passive error
## paths now push_warning instead of print(). Pre-fix the 10
## error sites used print() — debug-console-only output, invisible
## to CI / editor warnings panel / test runs.
##
## Real impact: failed equips returned false (the API correctly
## signaled failure) but the WHY was opaque to upstream callers.
## E.g., AbilitiesMenu shows a "Slots full" toast on can_equip_
## passive=false, but if the actual reason was "passive not in
## the table" (save-format drift / Scriptweaver custom), the
## menu's generic "slots full" message misled the player.

const JOB_SYSTEM := "res://src/jobs/JobSystem.gd"
const EQUIPMENT_SYSTEM := "res://src/jobs/EquipmentSystem.gd"
const PASSIVE_SYSTEM := "res://src/jobs/PassiveSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── JobSystem.assign_job ────────────────────────────────────────────────

func test_assign_job_warns_on_unknown_id() -> void:
	var src := _read(JOB_SYSTEM)
	assert_true(src.contains("push_warning(\"[JobSystem] assign_job: job_id '%s' not found"),
		"assign_job must push_warning on unknown job_id")
	# Negative pin: the print() error must be gone.
	assert_false(src.contains("print(\"Error: Job '%s' not found\""),
		"old print() error must be replaced — silent failure to CI")


# ── EquipmentSystem.equip_* ─────────────────────────────────────────────

func test_equip_weapon_warns_on_unknown_id() -> void:
	var src := _read(EQUIPMENT_SYSTEM)
	assert_true(src.contains("push_warning(\"[EquipmentSystem] equip_weapon: weapon_id '%s' not found"),
		"equip_weapon must push_warning on unknown weapon_id")
	assert_false(src.contains("print(\"Error: Weapon '%s' not found\""),
		"old print() Error must be replaced")


func test_equip_armor_warns_on_unknown_id() -> void:
	var src := _read(EQUIPMENT_SYSTEM)
	assert_true(src.contains("push_warning(\"[EquipmentSystem] equip_armor: armor_id '%s' not found"),
		"equip_armor must push_warning on unknown armor_id")
	assert_false(src.contains("print(\"Error: Armor '%s' not found\""),
		"old print() Error must be replaced")


func test_equip_accessory_warns_on_unknown_id() -> void:
	var src := _read(EQUIPMENT_SYSTEM)
	assert_true(src.contains("push_warning(\"[EquipmentSystem] equip_accessory: accessory_id '%s' not found"),
		"equip_accessory must push_warning on unknown accessory_id")
	assert_false(src.contains("print(\"Error: Accessory '%s' not found\""),
		"old print() Error must be replaced")


# ── PassiveSystem.equip_passive — 5 failure modes ──────────────────────

func test_equip_passive_warns_on_invalid_combatant() -> void:
	var src := _read(PASSIVE_SYSTEM)
	assert_true(src.contains("push_warning(\"[PassiveSystem] equip_passive: invalid combatant"),
		"equip_passive must push_warning on invalid combatant")


func test_equip_passive_warns_on_unknown_passive_id() -> void:
	var src := _read(PASSIVE_SYSTEM)
	assert_true(src.contains("push_warning(\"[PassiveSystem] equip_passive: passive_id '%s' not found"),
		"equip_passive must push_warning on unknown passive_id")


func test_equip_passive_warns_on_slot_full_with_counts() -> void:
	# Include /N format: "slot full (3/5)" gives the caller the
	# exact numbers without re-querying state.
	var src := _read(PASSIVE_SYSTEM)
	assert_true(src.contains("slot full (%d/%d) — equip of '%s' failed"),
		"slot-full warning must include current/max counts for debugging clarity")


func test_equip_passive_warns_on_already_equipped() -> void:
	var src := _read(PASSIVE_SYSTEM)
	assert_true(src.contains("push_warning(\"[PassiveSystem] equip_passive: '%s' already equipped on %s"),
		"equip_passive must push_warning when passive already equipped")
	# Bonus pin: explains it's an idempotency check.
	assert_true(src.contains("idempotency check"),
		"warning must explain WHY (idempotency check)")


func test_equip_passive_warns_on_unknown_cause() -> void:
	# Catch-all branch: can_equip_passive returned false but none
	# of the specific causes matched. This shouldn't happen normally
	# but push_warning surfaces it if it does.
	var src := _read(PASSIVE_SYSTEM)
	assert_true(src.contains("unknown reason"),
		"catch-all branch must push_warning with 'unknown reason' for diagnosis")


# ── PassiveSystem.unequip_passive ───────────────────────────────────────

func test_unequip_passive_warns_when_not_equipped() -> void:
	var src := _read(PASSIVE_SYSTEM)
	assert_true(src.contains("push_warning(\"[PassiveSystem] unequip_passive: '%s' not currently equipped on %s"),
		"unequip_passive must push_warning when passive isn't equipped")
	assert_false(src.contains("print(\"Error: Passive not equipped\""),
		"old print() Error must be replaced")


# ── Cross-pin: success path prints still preserved ─────────────────────

func test_success_path_prints_still_preserved() -> void:
	# Non-regression: the success-path prints ("X equipped Y")
	# stay as low-noise debug logging. Only the FAILURE paths
	# get upgraded to push_warning.
	var ps := _read(PASSIVE_SYSTEM)
	assert_true(ps.contains("print(\"%s equipped %s\""),
		"PassiveSystem success-path print preserved for debug")
	var es := _read(EQUIPMENT_SYSTEM)
	assert_true(es.contains("print(\"%s equipped %s\""),
		"EquipmentSystem success-path print preserved for debug")


# ── Orphan-signal audit (documentation pin) ────────────────────────────

func test_orphan_signals_documented_status() -> void:
	# Pin: the 5 orphan signals from the tick 180 audit are
	# declared in their respective systems. They have zero
	# connect callers — pure architectural waste right now,
	# but kept for future use. Test pins the current declarations
	# so a future refactor that REMOVES them would surface the
	# decision in PR review.
	var ps := _read(PASSIVE_SYSTEM)
	assert_true(ps.contains("signal passive_equipped(combatant: Combatant, passive_id: String)"),
		"passive_equipped signal still declared (orphan but kept for future UI listeners)")
	assert_true(ps.contains("signal passive_unequipped(combatant: Combatant, passive_id: String)"),
		"passive_unequipped signal still declared (orphan)")
	var es := _read(EQUIPMENT_SYSTEM)
	assert_true(es.contains("signal equipment_equipped(combatant: Combatant, slot: String, item_id: String)"),
		"equipment_equipped signal still declared (orphan)")
	assert_true(es.contains("signal equipment_unequipped(combatant: Combatant, slot: String)"),
		"equipment_unequipped signal still declared (orphan)")
