extends GutTest

## tick 351: BattleManager._execute_ability routes "song" and "status"
## ability types to the support handler.
##
## Pre-fix Bard's signature abilities (lullaby, discord, inspiring_
## melody) had `type: "song"` in abilities.json (and `type: "status"`
## in the JobSystem default fallback). The match in _execute_ability
## (line ~2790) had arms for physical/magic/healing/revival/support/
## meta/escape/mp_restore but NOT for song or status. Every Bard
## cast fell into the `_:` push_warning default and silently fizzled.
##
## Symptom: "lullaby never puts enemies to sleep — and I don't see
## any error in the log."
##
## Companion fix: added sleep/poison/burn/confuse/fear/silence/curse
## to the simple-status arm in _execute_support_ability so lullaby's
## "sleep" effect (and the parallel offensive-status effects from
## other songs) actually applies via add_status.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: song + status arms exist in _execute_ability ────────

func test_song_and_status_arms_exist() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# The match on ability_type is in _execute_ability (called from
	# _execute_ability after retargeting).
	# Find the match block.
	var match_idx: int = src.find("match ability_type:")
	assert_gt(match_idx, -1)
	# Find the end of the match block — the _: arm.
	var default_arm_idx: int = src.find("\"Unknown ability type:", match_idx)
	assert_gt(default_arm_idx, -1)
	var match_body: String = src.substr(match_idx, default_arm_idx - match_idx)
	assert_true(match_body.contains("\"support\", \"song\", \"status\":"),
		"_execute_ability must route support/song/status to the same support handler — Bard's abilities use song; JobSystem fallback uses status")


# ── Source pin: simple-status arm includes sleep/poison/burn/etc. ───

func test_simple_status_arm_includes_lullaby_targets() -> void:
	# lullaby's effect = "sleep" must be in the simple-status arm's
	# comma list so it applies via add_status. discord uses defense_down
	# (already handled). inspiring_melody uses ap_grant (separate path).
	var src := _read(BATTLE_MANAGER_PATH)
	# Find the simple-status arm.
	var arm_idx: int = src.find("\"barrier\", \"invisible\"")
	assert_gt(arm_idx, -1, "the simple-status comma-arm must still exist")
	# Slice to capture the full arm string.
	var colon_idx: int = src.find(":", arm_idx)
	assert_gt(colon_idx, -1)
	var arm_signature: String = src.substr(arm_idx, colon_idx - arm_idx)
	for status in ["sleep", "poison", "burn", "confuse", "fear", "silence", "curse"]:
		assert_true(arm_signature.contains("\"%s\"" % status),
			"simple-status arm must include '%s' so abilities applying it actually fire (was authored-but-unhandled pre-fix)" % status)


# ── Behavioral: type='song' lullaby applies sleep ───────────────────

func test_song_ability_applies_sleep() -> void:
	# End-to-end via _execute_support_ability — same handler that
	# "song" now routes to.
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Object = combatant_script.new()
	add_child_autofree(caster)
	caster.max_hp = 100
	caster.current_hp = 100
	caster.is_alive = true
	var enemy: Object = combatant_script.new()
	add_child_autofree(enemy)
	enemy.max_hp = 100
	enemy.current_hp = 100
	enemy.is_alive = true

	assert_not_null(BattleManager, "BattleManager autoload required")
	if BattleManager == null:
		return

	# Mirror lullaby's shape from abilities.json (line 437).
	var ability: Dictionary = {
		"id": "lullaby_test",
		"type": "song",  # The new routing arm.
		"effect": "sleep",
		"duration": 2,
		"success_rate": 1.0,  # Deterministic
	}
	BattleManager._execute_support_ability(caster, ability, [enemy])
	assert_true(enemy.has_status("sleep"),
		"lullaby-shaped support ability must apply 'sleep' status (pre-fix the arm didn't list sleep, so the call silently fizzled)")


# ── Behavioral: type='status' fallback also applies via support ─────

func test_status_type_jobsystem_fallback_path() -> void:
	# Same shape as above but with type=status (JobSystem default
	# fallback uses this when abilities.json fails to load).
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Object = combatant_script.new()
	add_child_autofree(caster)
	var enemy: Object = combatant_script.new()
	add_child_autofree(enemy)
	enemy.is_alive = true

	if BattleManager == null:
		return

	var ability: Dictionary = {
		"id": "lullaby_fallback_test",
		"type": "status",
		"effect": "sleep",
		"duration": 2,
		"success_rate": 1.0,
	}
	BattleManager._execute_support_ability(caster, ability, [enemy])
	assert_true(enemy.has_status("sleep"),
		"type=status (JobSystem fallback shape) must also apply via support handler")
