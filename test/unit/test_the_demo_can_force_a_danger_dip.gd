extends GutTest

## tools/demo_prep.gd's `--force-danger=S` (cowir-main 23026/23029, sfx 23027, music 23031): ONE real hit takes the
## Fighter to 20% max HP, alive, at the first Selection Phase after S s of boss theme, so a capture can show the danger
## bed hand the theme back (6fabbfc7f). Without the flag NOTHING is armed: the camera's ordinary takes are untouched.

const DemoPrep = preload("res://tools/demo_prep.gd")

var _saved_party: Array = []
var _saved_music: String = ""


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_music = str(SoundManager.get("_current_music"))


func after_each() -> void:
	BattleManager.player_party = _saved_party
	SoundManager.set("_current_music", _saved_music)
	var n := get_tree().root.get_node_or_null("DemoForceDanger")
	if n:
		n.free()


func _member(job_id: String, hp: int = 500) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "Test" + job_id.capitalize()
	c.max_hp = hp
	c.current_hp = hp
	c.max_mp = 50
	c.current_mp = 50
	c.attack = 10
	c.defense = 10
	c.magic = 10
	c.job = {"id": job_id}
	autofree(c)
	add_child(c)
	return c


func test_the_flag_is_parsed_and_only_a_positive_value_arms() -> void:
	assert_eq(DemoPrep.force_danger_seconds([]), -1.0, "no flag: off")
	assert_eq(DemoPrep.force_danger_seconds(["--party-level=35"]), -1.0, "another flag: off")
	assert_eq(DemoPrep.force_danger_seconds(["--force-danger=30"]), 30.0)
	assert_eq(DemoPrep.force_danger_seconds(["--force-danger=0"]), -1.0, "zero: off")
	assert_eq(DemoPrep.force_danger_seconds(["--force-danger=x"]), -1.0, "junk: off")


func test_without_the_flag_nothing_is_armed() -> void:
	var n = DemoPrep.arm_force_danger(get_tree().root, ["--party-level=35"])
	assert_null(n, "no node returned")
	assert_null(get_tree().root.get_node_or_null("DemoForceDanger"), "and none added to the tree")


func test_under_the_theme_floor_it_defers_and_touches_nothing() -> void:
	var f := _member("fighter")
	BattleManager.player_party = [f]
	var n = DemoPrep.arm_force_danger(get_tree().root, ["--force-danger=30"])
	assert_not_null(n)
	n.position_source = func(): return 10.0
	BattleManager.selection_phase_started.emit()
	assert_eq(f.current_hp, 500, "deferred: HP untouched")
	assert_false(n.done, "still armed for a later Selection Phase")


func test_past_the_floor_one_real_hit_leaves_the_fighter_in_danger_and_alive() -> void:
	var cleric := _member("cleric")
	var f := _member("fighter")
	# real armour: with defense 10 a raw hit of `need` already lands at 22%, so a missing damage_preview search went
	# unseen (this slot's M2). At 200 the raw hit leaves him at ~47%, and only the search reaches the 20-25% band.
	f.defense = 200
	BattleManager.player_party = [cleric, f]
	watch_signals(f)
	var n = DemoPrep.arm_force_danger(get_tree().root, ["--force-danger=30"])
	n.position_source = func(): return 31.0
	BattleManager.selection_phase_started.emit()
	assert_true(f.is_alive, "no KO")
	assert_true(f.current_hp >= int(floor(500 * 0.20)), "never below 20%% (got %d)" % f.current_hp)
	assert_true(f.get_hp_percentage() < 25.0, "below the danger threshold (got %.1f%%)" % f.get_hp_percentage())
	assert_signal_emit_count(f, "hp_changed", 1, "ONE hit through the real damage path")
	assert_eq(cleric.current_hp, 500, "only the Fighter is touched")
	var after := f.current_hp
	BattleManager.selection_phase_started.emit()
	assert_eq(f.current_hp, after, "once: a later Selection Phase changes nothing")


func test_the_trigger_reads_the_themes_own_clock_not_the_battle_speed() -> void:
	# cowir-music 23055 / main 23059: a demo battle runs at Engine.time_scale 0.375; the theme plays unscaled. Play the REAL
	# bed, slow the engine, and the trigger must fire off the bed's position. The reference is the position itself; the
	# wall clock only bounds the wait (sprites 23056: never a SceneTreeTimer as the yardstick).
	var f := _member("fighter")
	BattleManager.player_party = [f]
	SoundManager.play_music("boss_mordaine")
	var n = DemoPrep.arm_force_danger(get_tree().root, ["--force-danger=1"])
	var saved_scale := Engine.time_scale
	Engine.time_scale = 0.375
	var t0 := Time.get_ticks_usec()
	# the REFERENCE is the player's raw position, read here, independent of the node under test
	var raw := func() -> float:
		var p = SoundManager.get("_music_player")
		return p.get_playback_position() if p and p is AudioStreamPlayer and p.playing else -1.0
	while raw.call() < 1.5 and Time.get_ticks_usec() - t0 < 8_000_000:
		await get_tree().process_frame
	var wall_s := (Time.get_ticks_usec() - t0) / 1_000_000.0
	var ref: float = raw.call()
	var pos: float = n.theme_position()
	Engine.time_scale = saved_scale
	assert_true(ref >= 1.5, "CONTROL: the boss bed's position advanced (raw %.2f s after %.2f s wall)" % [ref, wall_s])
	assert_almost_eq(pos, ref, 0.25, "the node reads the bed's own clock at 0.375x (node %.2f vs bed %.2f)" % [pos, ref])
	BattleManager.selection_phase_started.emit()
	assert_true(f.get_hp_percentage() < 25.0, "fired off the position (%.2f s of theme at 0.375x), Fighter at %.1f%%" % [pos, f.get_hp_percentage()])
	if SoundManager.has_method("stop_music"):
		SoundManager.stop_music()


func test_with_no_living_fighter_nothing_is_touched() -> void:
	var cleric := _member("cleric")
	BattleManager.player_party = [cleric]
	var n = DemoPrep.arm_force_danger(get_tree().root, ["--force-danger=30"])
	n.position_source = func(): return 31.0
	BattleManager.selection_phase_started.emit()
	assert_eq(cleric.current_hp, 500)
	assert_true(n.done, "it gives up once, rather than hitting someone else")
