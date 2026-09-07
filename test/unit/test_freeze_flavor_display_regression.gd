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
	assert_eq(count, 2,
		"both physical and magic dispatch sites must use the pre-alias name for the log")
	assert_false(src.contains("StatusNames.display(status_to_add)"),
		"post-alias status name in the log leaks the mechanical detail — replaced by log_effect")
