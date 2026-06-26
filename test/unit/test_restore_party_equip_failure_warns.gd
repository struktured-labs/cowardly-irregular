extends GutTest

## tick 189 regression: GameLoop._restore_party_from_save_data
## now checks bool returns from EquipmentSystem.equip_weapon /
## equip_armor / equip_accessory and PassiveSystem.equip_passive
## (the per-passive loop). Pre-fix returns ignored — unknown
## equipment / passive IDs (Scriptweaver custom items,
## save-format drift, items removed from equipment.json after
## save was made) silently failed, leaving slots empty while
## the save thought the character was equipped.
##
## Continuation of tick 188's primary-job fallback pattern.
## Empty equipment is a valid state (unlike empty primary job),
## so no fallback — just surface the failure to push_warning.

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _restore_body() -> String:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _restore_party_from_save_data")
	assert_gt(idx, -1, "_restore_party_from_save_data must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


# ── Equipment equip checks ─────────────────────────────────────────────

func test_equip_weapon_failure_pushes_warning() -> void:
	var body := _restore_body()
	# Pin: condition combines non-empty + return check.
	assert_true(body.contains("if w != \"\" and not EquipmentSystem.equip_weapon(c, w):"),
		"_restore_party_from_save_data must check equip_weapon return value")
	assert_true(body.contains("push_warning(\"[GameLoop] _restore_party_from_save_data: equip_weapon"),
		"weapon equip failure must push_warning")


func test_equip_armor_failure_pushes_warning() -> void:
	var body := _restore_body()
	assert_true(body.contains("if a != \"\" and not EquipmentSystem.equip_armor(c, a):"),
		"_restore_party_from_save_data must check equip_armor return value")
	assert_true(body.contains("push_warning(\"[GameLoop] _restore_party_from_save_data: equip_armor"),
		"armor equip failure must push_warning")


func test_equip_accessory_failure_pushes_warning() -> void:
	var body := _restore_body()
	assert_true(body.contains("if acc != \"\" and not EquipmentSystem.equip_accessory(c, acc):"),
		"_restore_party_from_save_data must check equip_accessory return value")
	assert_true(body.contains("push_warning(\"[GameLoop] _restore_party_from_save_data: equip_accessory"),
		"accessory equip failure must push_warning")


# ── Passive equip check ────────────────────────────────────────────────

func test_equip_passive_failure_pushes_warning() -> void:
	var body := _restore_body()
	# Pin: per-passive loop checks the return.
	assert_true(body.contains("if not PassiveSystem.equip_passive(c, pid):"),
		"_restore_party_from_save_data passive loop must check equip_passive return")
	assert_true(body.contains("push_warning(\"[GameLoop] _restore_party_from_save_data: equip_passive"),
		"passive equip failure must push_warning")


# ── Warning content quality ────────────────────────────────────────────

func test_warnings_include_failing_id_and_character_name() -> void:
	# Pin: warning messages include both the ID that failed AND
	# the combatant_name so devs can pinpoint which save/character
	# is affected.
	var body := _restore_body()
	for fragment in [
		"equip_weapon('%s') failed for %s",
		"equip_armor('%s') failed for %s",
		"equip_accessory('%s') failed for %s",
		"equip_passive('%s') failed for %s",
	]:
		assert_true(body.contains(fragment),
			"warning must include failing id + combatant_name: %s" % fragment)


func test_warnings_state_consequence() -> void:
	# Pin: warnings explain what state the system is in after
	# the failure ("slot left empty" / "passive skipped").
	var body := _restore_body()
	# Three equipment slots all say "slot left empty"
	var count: int = 0
	var cursor: int = 0
	while true:
		var idx: int = body.find("slot left empty", cursor)
		if idx < 0:
			break
		count += 1
		cursor = idx + 1
	assert_gte(count, 3,
		"all 3 equipment slot warnings must say 'slot left empty' (consequence statement)")
	# Passive uses "passive skipped" (distinct — slot is reusable
	# for the next passive in the loop).
	assert_true(body.contains("passive skipped"),
		"passive warning must say 'passive skipped'")


# ── No fallback (empty equipment is valid state) ───────────────────────

func test_equipment_failure_no_fallback_to_default() -> void:
	# Negative pin: failure path must NOT try a fallback like
	# `equip_weapon(c, "bronze_sword")`. Unlike primary job
	# (tick 188), empty equipment is a valid state.
	var body := _restore_body()
	# The equipment-check block should NOT contain another equip
	# call after the failure (would imply a fallback).
	var weapon_idx: int = body.find("if w != \"\" and not EquipmentSystem.equip_weapon(c, w):")
	assert_gt(weapon_idx, -1)
	var window: String = body.substr(weapon_idx, 250)
	# Within ~250 chars of the failure check, the only equip_weapon
	# call should be the original (one match in the if-statement).
	var equip_weapon_count: int = 0
	var w_cursor: int = 0
	while true:
		var idx: int = window.find("EquipmentSystem.equip_weapon", w_cursor)
		if idx < 0:
			break
		equip_weapon_count += 1
		w_cursor = idx + 1
	assert_eq(equip_weapon_count, 1,
		"failure path must NOT have a fallback equip_weapon call — empty is valid state")


# ── Cross-pin: tick 188 job fallback preserved ─────────────────────────

func test_tick_188_job_fallback_preserved() -> void:
	# Non-regression: don't lose tick 188's job-fallback work.
	var body := _restore_body()
	assert_true(body.contains("if not JobSystem.assign_job(c, job_id):"),
		"tick 188 job assignment check preserved")
	assert_true(body.contains("JobSystem.assign_job(c, \"fighter\")"),
		"tick 188 fighter fallback preserved")


# ── Cross-pin: tick 180 EquipmentSystem warnings preserved ─────────────

func test_tick_180_equipment_system_warnings_preserved() -> void:
	# Tick 180's lower-level warnings still in place — they tell
	# WHY the equip failed (id not found, etc.) while the
	# GameLoop-side warning tells WHICH character + save context.
	var es: String = FileAccess.get_file_as_string("res://src/jobs/EquipmentSystem.gd")
	assert_true(es.contains("push_warning(\"[EquipmentSystem] equip_weapon"),
		"tick 180 EquipmentSystem warning preserved")
	var ps: String = FileAccess.get_file_as_string("res://src/jobs/PassiveSystem.gd")
	assert_true(ps.contains("push_warning(\"[PassiveSystem] equip_passive"),
		"tick 180 PassiveSystem warning preserved")
