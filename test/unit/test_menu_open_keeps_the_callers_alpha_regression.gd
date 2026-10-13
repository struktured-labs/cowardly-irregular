extends GutTest

## Regression: the command menu is deliberately translucent (MENU_ALPHA_OVER_ACTOR = 0.85) because
## at 1280x720 it unavoidably covers the acting PC. _animate_menu_open zeroed the alpha and tweened
## back to a hardcoded 1.0, so 0.12s after every spawn the translucency was gone — and ONLY at the
## default speed, because battle_tier() >= MINIMAL returns early and preserves 0.85 at 4x/turbo.
## The menu was therefore more readable the FASTER you played, inverting the documented intent.
## BattleCommandMenu extends RefCounted — never add_child it; the call needs no scene state.

const SENTINEL_ALPHA: float = 0.42
const MENU_PATH: String = "res://src/battle/BattleCommandMenu.gd"


func test_the_open_animation_returns_to_the_alpha_it_was_given() -> void:
	var ctl := Control.new()
	add_child_autofree(ctl)
	ctl.modulate.a = SENTINEL_ALPHA
	var menu := BattleCommandMenu.new(null)

	## Pin every input battle_tier()/flag() read, so a sibling test's leaked turbo host or FX flag
	## cannot gate the tween off and turn the control below into a spurious red.
	var prev_scale := Engine.time_scale
	var prev_host = BattleJuice.burst_host
	var had_flag: bool = GameState and "battle_fx_flags" in GameState \
		and GameState.battle_fx_flags.has("menu_motion")
	var prev_flag = GameState.battle_fx_flags.get("menu_motion") if had_flag else null
	Engine.time_scale = 0.25
	BattleJuice.burst_host = null
	if GameState and "battle_fx_flags" in GameState:
		GameState.battle_fx_flags["menu_motion"] = true

	menu._animate_menu_open(ctl)
	var zeroed_immediately := ctl.modulate.a

	Engine.time_scale = prev_scale
	BattleJuice.burst_host = prev_host
	if GameState and "battle_fx_flags" in GameState:
		if had_flag:
			GameState.battle_fx_flags["menu_motion"] = prev_flag
		else:
			GameState.battle_fx_flags.erase("menu_motion")

	## CONTROL: without this the main assert passes vacuously whenever juice gates the tween off —
	## an untouched alpha is indistinguishable from a correctly restored one.
	assert_almost_eq(zeroed_immediately, 0.0, 0.001,
		"the animation must actually have run — else the assert below judges an untouched value")

	await wait_seconds(0.4)
	assert_almost_eq(ctl.modulate.a, SENTINEL_ALPHA, 0.02,
		"the open fade must end on the alpha the caller set, not a hardcoded 1.0 — " +
		"MENU_ALPHA_OVER_ACTOR keeps the acting PC readable underneath the menu")


func test_the_fade_target_is_not_a_literal() -> void:
	## The DECLARATION half — that the constant is 0.6..1.0 and is applied at spawn — is already
	## ratcheted by test_command_menu_does_not_cover_actor. This file owns only the ENDPOINT, which
	## that guard cannot see: it passed throughout, because a tween undid the alpha it had verified.
	var src := FileAccess.get_file_as_string(MENU_PATH)
	assert_true('"modulate:a", target_a' in src,
		"the fade target must stay the caller's alpha — a literal here silently drops the intent")
	assert_false('"modulate:a", 1.0, 0.12' in src, "the hardcoded 1.0 fade is the defect itself")
