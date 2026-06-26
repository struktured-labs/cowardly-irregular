extends GutTest

## tick 175 regression: physical group attacks (All-Out Attack /
## Limit Break) and formation specials now emit an opening
## announcement in the battle log. Pre-fix:
##
##   - _execute_physical_group went straight to per-enemy hit
##     lines ("Group all_out_attack hits X for N!") with no
##     opener. The combo magic path DOES announce ("★ Steam
##     Burst! ★") so this closes the parity gap.
##
##   - _execute_formation_special had no opener — six formation
##     specials all started straight into their effect with no
##     signal that a FORMATION SPECIAL (vs ordinary group attack)
##     had just triggered. Player saw mechanical effects but no
##     dramatic moment.
##
## Limit Break gets the most dramatic treatment (★★★ + gold);
## ordinary all-out attacks use the orange-color group palette;
## formation specials use ✦ + gold to mirror the meta abilities'
## ✦ marker convention (tick 172).

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _fn_body(name: String) -> String:
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func " + name)
	assert_gt(idx, -1, "%s must exist" % name)
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


# ── All-Out Attack announcement ─────────────────────────────────────────

func test_all_out_attack_announces_with_participant_count() -> void:
	var body := _fn_body("_execute_physical_group")
	assert_true(body.contains("[color=orange]All-Out Attack![/color] (%d participants)"),
		"_execute_physical_group must announce 'All-Out Attack!' with participant count")


func test_all_out_attack_emit_NOT_in_limit_break_branch() -> void:
	# Pin: the All-Out Attack emit is in the `else` branch, not
	# the `if is_limit_break:` branch. Otherwise we'd double-emit
	# on Limit Break too. Verify by source-text ordering:
	#   if is_limit_break:
	#       battle_log_message.emit("LIMIT BREAK!")  ← lb_idx
	#   else:                                         ← else_idx
	#       battle_log_message.emit("All-Out...")    ← aoa_idx
	var body := _fn_body("_execute_physical_group")
	var lb_idx: int = body.find("if is_limit_break:")
	var aoa_idx: int = body.find("All-Out Attack!")
	assert_gt(lb_idx, -1)
	assert_gt(aoa_idx, -1)
	# An `else:` must exist between lb_idx and aoa_idx — proves
	# the AoA emit is in the else branch.
	var between: String = body.substr(lb_idx, aoa_idx - lb_idx)
	assert_true(between.contains("\telse:") or between.contains("\n\telse:") or between.contains("else:"),
		"AoA emit must be in the else branch — find 'else:' between LB and AoA emits")


# ── Limit Break announcement ────────────────────────────────────────────

func test_limit_break_announces_with_dramatic_marker() -> void:
	var body := _fn_body("_execute_physical_group")
	assert_true(body.contains("[color=gold]★★★ LIMIT BREAK! ★★★[/color]"),
		"Limit Break must get the most dramatic announcement — gold + ★★★ markers signal the 4-AP commitment")


# ── Formation Special announcement ──────────────────────────────────────

func test_formation_special_announces_without_redundant_name() -> void:
	# Tick 176 update: each formation branch already emits a
	# descriptor at the END that names + describes the effect.
	# The opener must NOT also name the formation (was duplicate
	# pre-tick-176).
	var body := _fn_body("_execute_formation_special")
	# Positive pin: name-less marker.
	assert_true(body.contains("[color=gold]✦ FORMATION SPECIAL ✦[/color]"),
		"_execute_formation_special must emit the name-less '✦ FORMATION SPECIAL ✦' opener")
	# Negative pin: the tick-175 named version must be gone.
	assert_false(body.contains("[color=gold]✦ FORMATION SPECIAL: %s ✦[/color]"),
		"the original tick-175 named version must be removed — descriptor at branch end already names the formation")


func test_formation_announcement_runs_BEFORE_ap_spend() -> void:
	# Critical ordering: the opener must be announced BEFORE the
	# AP-spend loop. Otherwise on a partial-AP case the AP loop
	# runs first, then the announcement which feels backwards.
	var body := _fn_body("_execute_formation_special")
	var announce_idx: int = body.find("FORMATION SPECIAL")
	var ap_spend_idx: int = body.find("p.spend_ap(ap_cost)")
	assert_gt(announce_idx, -1)
	assert_gt(ap_spend_idx, -1)
	assert_lt(announce_idx, ap_spend_idx,
		"formation announcement must come BEFORE AP-spend loop — narrative ordering")


# ── Pre-existing emits preserved ────────────────────────────────────────

func test_physical_group_per_enemy_emit_preserved() -> void:
	# Don't regress the existing per-enemy hit log.
	var body := _fn_body("_execute_physical_group")
	assert_true(body.contains("[color=orange]Group %s hits %s for %d![/color]"),
		"per-enemy hit log preserved")


func test_combo_magic_announcement_preserved() -> void:
	# Cross-pin: combo magic already announces — was the parity
	# reference. Make sure I didn't accidentally remove it.
	var body := _fn_body("_execute_combo_magic")
	assert_true(body.contains("[color=magenta]★ %s! ★[/color]"),
		"combo magic announcement (the parity reference) preserved")


func test_limit_break_cleanse_emit_preserved() -> void:
	# Cross-pin: the Limit Break post-effect emit.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=lime]%s is cleansed by the Limit Break![/color]"),
		"limit break cleanse emit preserved")
