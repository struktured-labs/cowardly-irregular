extends GutTest

## Follow-up 2026-07-03: freeze aliases to stun mechanically, but the
## log message previously used the aliased name — an ice ability would
## announce "inflicted Stun!" losing the ice-family flavor. The battle
## log now uses the ORIGINAL effect name (StatusNames.display maps
## "freeze" → "Frozen" via DISPLAY_OVERRIDES).


func test_status_names_maps_freeze_to_frozen() -> void:
	assert_eq(StatusNames.display("freeze"), "Frozen",
		"freeze must display as 'Frozen' in battle logs — the ice-family flavor")


func test_stun_still_displays_as_stun() -> void:
	assert_eq(StatusNames.display("stun"), "Stun",
		"time_stop and other stun sources must keep the mechanical name")


func test_log_uses_original_effect_name_not_aliased_status() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	# The message must feed StatusNames.display with log_effect (the
	# pre-alias name), not status_to_add (which is now "stun" for ice).
	var count = src.count("StatusNames.display(log_effect)")
	assert_eq(count, 1,
		"one owner since 2026-09-16 — the duplicated block collapsed (found %d)" % count)
	assert_true(_owner_body().contains("StatusNames.display(log_effect)"),
		"the pre-alias name is logged inside _apply_ability_status")
	assert_eq(_owner_callers(), 2,
		"and both physical and magic dispatch still reach it")
	assert_false(src.contains("StatusNames.display(status_to_add)"),
		"post-alias status name in the log leaks the mechanical detail — replaced by log_effect")


## ⚠️ SHAPE CHANGED 2026-09-16, INTENT UNCHANGED. The effect-application block existed VERBATIM in
## _execute_physical_ability AND _execute_magic_ability, so this file counted copies. It is now one
## owner, `_apply_ability_status`, that both call — so the pin is "the rule lives in the owner, and
## both damage executors still reach it", which is what counting two copies was really defending.
func _owner_body() -> String:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var at: int = src.find("func _apply_ability_status(")
	if at < 0:
		return ""
	var nxt: int = src.find("\nfunc ", at + 1)
	return src.substr(at, (nxt - at) if nxt > at else 4000)


## Both damage executors must still CALL that owner, or the rule inside it defends nothing.
func _owner_callers() -> int:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	return src.count("_apply_ability_status(caster, target, ability)")
