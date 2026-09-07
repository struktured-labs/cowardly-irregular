extends GutTest

## battle_tier() is the ONE tier read for a live battle: it takes turbo/autogrind off the
## REGISTERED context so every consumer agrees (cowir-main ruling, msg 6501). Before it,
## BattleScene._tier() passed the real modes while every no-arg presentation_tier() caller
## silently defaulted them to false — two answers for one question, differing only during
## turbo/autogrind, which is exactly when the tier is supposed to be OFF.

const JuiceScript = preload("res://src/battle/BattleJuice.gd")


class ProbeHost:
	extends Node
	var turbo_mode: bool = false
	var autogrind_console_mode: bool = false


var _saved_host = null
var _saved_scale: float = 1.0


func before_each() -> void:
	_saved_host = BattleJuice.burst_host
	_saved_scale = Engine.time_scale


func after_each() -> void:
	## BattleJuice is an autoload and Engine.time_scale is global — both leak across GUT tests.
	BattleJuice.burst_host = _saved_host
	Engine.time_scale = _saved_scale


func _register(turbo: bool, autogrind: bool) -> ProbeHost:
	var h := ProbeHost.new()
	h.turbo_mode = turbo
	h.autogrind_console_mode = autogrind
	autofree(h)
	BattleJuice.burst_host = h
	return h


func test_battle_tier_reads_turbo_off_the_registered_context() -> void:
	Engine.time_scale = 0.25
	var h := _register(false, false)
	assert_eq(BattleJuice.battle_tier(), JuiceScript.Tier.FULL, "CONTROL: 1x with no modes is FULL")
	h.turbo_mode = true
	assert_eq(BattleJuice.battle_tier(), JuiceScript.Tier.OFF,
		"flipping turbo on the REGISTERED host must move the tier with no re-registration")


func test_battle_tier_reads_autogrind_off_the_registered_context() -> void:
	Engine.time_scale = 0.25
	var h := _register(false, false)
	assert_eq(BattleJuice.battle_tier(), JuiceScript.Tier.FULL, "CONTROL: 1x with no modes is FULL")
	h.autogrind_console_mode = true
	assert_eq(BattleJuice.battle_tier(), JuiceScript.Tier.OFF, "autogrind console forces OFF")


func test_battle_tier_still_tracks_the_speed_ladder() -> void:
	_register(false, false)
	Engine.time_scale = 0.25
	assert_eq(BattleJuice.battle_tier(), JuiceScript.Tier.FULL, "1x label is FULL")
	Engine.time_scale = 1.0
	assert_eq(BattleJuice.battle_tier(), JuiceScript.Tier.REDUCED, "4x label is REDUCED")
	Engine.time_scale = 4.0
	assert_eq(BattleJuice.battle_tier(), JuiceScript.Tier.OFF, "16x label is OFF")


func test_outside_battle_it_equals_the_pure_function_with_modes_false() -> void:
	## _exit_tree clears the context; the tier must stay defined and match the static form.
	BattleJuice.burst_host = null
	Engine.time_scale = 1.0
	assert_eq(BattleJuice.battle_tier(), JuiceScript.presentation_tier(1.0, false, false),
		"a null context degrades to the pure function rather than erroring")


func test_a_host_without_the_mode_properties_does_not_break_the_read() -> void:
	## burst_host is typed Node — a registrant lacking the battle vars must not abort the read.
	var bare := Node.new()
	autofree(bare)
	BattleJuice.burst_host = bare
	Engine.time_scale = 0.25
	assert_eq(BattleJuice.battle_tier(), JuiceScript.Tier.FULL,
		"the `in` guards keep a non-BattleScene host from aborting the function")


func test_battle_scene_tier_is_a_delegate_not_a_second_computation() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	assert_true("return BattleJuice.battle_tier()" in src,
		"_tier() must delegate, so the 6 callers and BattleUIManager share one computation")
	assert_false("BattleJuice.presentation_tier(Engine.time_scale, turbo_mode" in src,
		"the duplicated computation must be gone from BattleScene, not merely shadowed")
