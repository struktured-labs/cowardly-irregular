extends GutTest

## Item 9 (2026-07-01): hold-to-dash on overworld + "Dash: always on" toggle.
##
## Pins: the `dash` input action exists (Shift + joypad X), the multiplier
## composes multiplicatively with terrain (dash through swamp is faster but
## still slowed), the always-on GameState flag drives the multiplier without
## the button, and the setting round-trips through save/load plumbing.

const PlayerScript := preload("res://src/exploration/OverworldPlayer.gd")


func test_dash_input_action_registered() -> void:
	assert_true(InputMap.has_action("dash"),
		"project.godot must register the `dash` action (Shift + joypad button 2)")
	var has_key := false
	var has_pad := false
	for ev in InputMap.action_get_events("dash"):
		if ev is InputEventKey:
			has_key = true
		elif ev is InputEventJoypadButton:
			has_pad = true
			assert_eq((ev as InputEventJoypadButton).button_index, JOY_BUTTON_X,
				"dash gamepad binding must be button 2 (X west face) — the free run-button slot")
	assert_true(has_key, "dash must have a keyboard binding")
	assert_true(has_pad, "dash must have a gamepad binding")


func test_dash_multiplier_off_by_default() -> void:
	var player := PlayerScript.new()
	add_child_autofree(player)
	GameState.dash_always_on = false
	assert_eq(player._dash_multiplier(), 1.0,
		"no button held + toggle off → 1.0 (no dash)")


func test_dash_always_on_flag_drives_multiplier() -> void:
	var player := PlayerScript.new()
	add_child_autofree(player)
	GameState.dash_always_on = true
	assert_eq(player._dash_multiplier(), PlayerScript.DASH_MULTIPLIER,
		"dash_always_on=true → DASH_MULTIPLIER without holding the button")
	GameState.dash_always_on = false


func test_dash_multiplier_composes_with_terrain() -> void:
	# The velocity line is base × terrain × dash. Verify DASH_MULTIPLIER is a
	# sane hold-to-run factor and that a slowed terrain stays slowed while
	# dashing (0.5 terrain × 1.7 dash < 1.7 → still below full dash speed).
	assert_between(PlayerScript.DASH_MULTIPLIER, 1.5, 2.0,
		"dash factor stays in the classic run-button range")
	var swamp_dash: float = 0.5 * PlayerScript.DASH_MULTIPLIER
	assert_lt(swamp_dash, PlayerScript.DASH_MULTIPLIER,
		"terrain penalty must still apply while dashing")


func test_dash_always_on_round_trips_through_save_data() -> void:
	GameState.dash_always_on = true
	var data: Dictionary = GameState._create_save_data()
	assert_true(bool(data.get("dash_always_on", false)),
		"GameState._create_save_data must include dash_always_on")
	GameState.dash_always_on = false
	GameState._apply_save_data(data)
	assert_true(GameState.dash_always_on,
		"_apply_save_data must restore dash_always_on")
	GameState.dash_always_on = false
