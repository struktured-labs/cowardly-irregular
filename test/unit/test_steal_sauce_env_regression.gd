extends GutTest

## struktured 2026-08-14 rulings: steal gets stealth sauce ("travel to the monster and
## back"), env reactivity approved ("try it"), and every bell gets a flag for the coming
## toggle menu. Pins: flag() default-true semantics, the steal dispatch (flag/tier off ==
## byte-for-byte legacy path), the travel reads REAL enemy positions, env pulse triggers
## off heavy trauma only, and phase-2 unrest is set AND reset.

func test_flag_defaults_true_and_honors_false() -> void:
	BattleJuice.flags.clear()
	assert_true(BattleJuice.flag("anything_unknown"), "unknown flags default TRUE — new juice works before the menu knows it")
	BattleJuice.flags["steal_sauce"] = false
	assert_false(BattleJuice.flag("steal_sauce"), "explicit false honored")
	BattleJuice.flags.clear()


func test_steal_dispatch_gates_on_flag_and_tier() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleAnimator.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	for fn in ["play_steal", "play_mug"]:
		var i := src.find("func %s(" % fn)
		assert_gt(i, -1, "%s exists" % fn)
		var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
		assert_true('flag("steal_sauce")' in body, "%s checks the feature flag" % fn)
		assert_true("Tier.OFF" in body, "%s falls back at OFF tier" % fn)
		assert_true("_basic" in body, "%s keeps the legacy path — flag/tier off must be byte-for-byte old behavior" % fn)
	assert_true("func _play_steal_basic" in src and "func _play_mug_basic" in src, "legacy bodies preserved")


func test_stealth_apex_reads_real_enemy_positions() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleAnimator.gd")
	var i := src.find("func _stealth_apex")
	assert_gt(i, -1)
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_true("enemy_sprite_nodes" in body, "travel targets the actual monster column, not a fixed hop")
	assert_true("Vector2(-90, 0)" in body, "fixed-hop fallback kept for no-scene contexts")


func test_env_pulse_triggers_on_heavy_trauma_only() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleJuice.gd")
	var i := src.find("func add_trauma")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_true("amount >= 0.3" in body, "light taps don't thump the arena")
	assert_true('flag("env_pulse")' in body, "pulse is toggleable")
	assert_true("Tier.OFF" in body, "pulse respects the speed tiers")


func test_arena_unrest_set_on_phase2_and_reset_at_battle_start() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _check_masterite_phase2_music_swap")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_true("set_unrest(3.0)" in body, "phase 2 wakes the arena sway")
	assert_true('flag("arena_unrest")' in body, "unrest is toggleable")
	var reset_zone := src.find("_masterite_phase2_swapped = false")
	assert_true("set_unrest(0.0)" in src.substr(reset_zone, 200), "battle start resets unrest beside the phase-2 latch")


func test_background_pulse_recovers() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleBackground.gd")
	var i := src.find("func pulse")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_true("Color.WHITE, 0.22" in body, "pulse always tweens back to neutral — a stuck-dark arena is worse than none")
	assert_true("_pulse_tween.kill()" in body or "kill()" in body, "rapid pulses kill the prior tween")


func test_ghost_promoted_and_scene_delegates() -> void:
	var juice := FileAccess.get_file_as_string("res://src/battle/BattleJuice.gd")
	assert_true("func spawn_ghost" in juice, "ghost helper lives in BattleJuice for steal/lunge reuse")
	var scene := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := scene.find("func _spawn_lunge_ghost")
	assert_gt(i, -1, "melee pin test anchors on this name — it must survive")
	assert_true("BattleJuice.spawn_ghost" in scene.substr(i, 120), "and it delegates")
