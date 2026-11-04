extends GutTest

## cowir-sfx 21675 / cowir-main 21676: a boss signature's cue was ONE sample started with the sequence, cut to battle
## seconds, so it lined up only at engine 1.0 and ran early at 1x (0.25), where every beat lands 4x later in wall time.
## A sequence phase may now name its own "sfx": FractalFX fires it when THAT phase runs, in battle time, so the sound
## lands on the beat at any speed. EffectSystem.play_phase_sfx plays it, muted by the battle's own signature gate.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const AT := 0.4

## What a leaked battle does to the scale: writes its own, every frame.
class ScaleLeak extends Node:
	var scale := 1.0

	func _process(_delta: float) -> void:
		Engine.time_scale = scale


var _guard
var _saved_scale := 1.0
var _saved_gate: Callable


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_scale = Engine.time_scale
	_saved_gate = EffectSystem.phase_sfx_gate


func after_each() -> void:
	Engine.time_scale = _saved_scale
	EffectSystem.phase_sfx_gate = _saved_gate
	_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _known_key() -> String:
	var keys: Array = SoundManager.SOUNDS.keys()
	return str(keys[0]) if keys.size() > 0 else ""


## Plays one cue phase at engine `scale` beside a reference SceneTreeTimer for the same `at`: the engine's own battle
## clock, whatever an earlier file left behind (sfx 21734: wall AND summed-delta clocks both drifted after
## test_a_secondary_job_shows_on_the_artist_sprite). Returns frames from the reference to the cue (0 = same frame,
## negative = early), or NO_CUE if it never fired.
const NO_CUE := -9999


func _cue_vs_clock(scale: float, phase: Dictionary, tier: int = 1) -> int:
	var host := Node2D.new()
	add_child_autofree(host)
	var cue: Array = []
	var ref: Array = []
	var fx := FractalFX.new(host, 7)
	fx.tier = tier
	fx.on_sfx = func(key: String) -> void: cue.append([key, Engine.get_process_frames()])
	Engine.time_scale = scale
	var at := float(phase.get("at", 0.0))
	get_tree().create_timer(at).timeout.connect(func() -> void: ref.append(Engine.get_process_frames()))
	fx.play({"phases": [phase]}, Vector2.ZERO, Vector2(100, 0))
	var wall_deadline := Time.get_ticks_msec() + int(at / minf(scale, 1.0) * 1000.0) + 3000
	while (cue.is_empty() or ref.is_empty()) and Time.get_ticks_msec() < wall_deadline:
		await get_tree().process_frame
	Engine.time_scale = _saved_scale
	# FractalFX holds itself in a static list until its release timer; drop our lambda and let it go before the test ends.
	fx.on_sfx = Callable()
	FractalFX._live.erase(fx)
	assert_false(ref.is_empty(), "CONTROL: the reference clock reached %.2f s" % at)
	if cue.is_empty() or ref.is_empty():
		return NO_CUE
	assert_eq(str(cue[0][0]), str(phase.get("sfx", "")), "it fires the phase's own key")
	assert_eq(cue.size(), 1, "exactly once")
	return int(cue[0][1]) - int(ref[0])


func test_every_sfx_a_phase_names_is_a_cue_the_game_can_play() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/vfx_sequences.json"))
	var seqs: Dictionary = raw.get("sequences", {}) if raw is Dictionary else {}
	assert_gt(seqs.size(), 10, "CONTROL: the sequences were read")
	var named := 0
	for id in seqs:
		for p in seqs[id].get("phases", []):
			if p is Dictionary and p.has("sfx"):
				named += 1
				var key := str(p["sfx"])
				assert_true(SoundManager._sfx_manifest.has(key) or SoundManager.SOUNDS.has(key), "%s names sfx '%s', which no cue answers" % [id, key])
	gut.p("phases naming an sfx: %d" % named)


func test_a_phase_cue_lands_on_its_beat_at_1x_and_at_4x() -> void:
	var phase := {"at": AT, "kind": "cue", "sfx": "phase_probe"}
	for scale in [0.25, 1.0]:
		var d: int = await _cue_vs_clock(scale, phase)
		assert_ne(d, NO_CUE, "the cue fired at engine %.2f" % scale)
		assert_between(d, -1, 1, "at engine %.2f it fires on the frame its phase's battle clock does (%d frames off)" % [scale, d])


func test_a_tiered_phase_sounds_only_for_a_caster_who_gets_it() -> void:
	var phase := {"at": 0.1, "kind": "cue", "sfx": "tier_probe", "min_tier": 2}
	assert_eq(await _cue_vs_clock(1.0, phase, 1), NO_CUE, "a tier-1 caster neither sees nor hears a tier-2 phase")
	assert_ne(await _cue_vs_clock(1.0, phase, 2), NO_CUE, "CONTROL: a tier-2 caster hears it")


func test_play_phase_sfx_plays_a_known_cue_and_refuses_the_rest() -> void:
	var key := _known_key()
	assert_ne(key, "", "CONTROL: SoundManager has a cue to play")
	EffectSystem.phase_sfx_gate = Callable()
	assert_true(EffectSystem.play_phase_sfx(key), "a known cue plays with no gate installed")
	assert_false(EffectSystem.play_phase_sfx("no_such_cue_xyz"), "an unknown key plays nothing")
	assert_false(EffectSystem.play_phase_sfx(""), "an empty key plays nothing")


## The gate is the battle's own: turbo/autogrind mute phase cues exactly as they mute the signature cue.
func test_a_battle_in_turbo_mutes_phase_cues() -> void:
	var scene = SCENE.instantiate()
	add_child_autofree(scene)
	for i in 3:
		await get_tree().process_frame
	var key := _known_key()
	assert_true(EffectSystem.phase_sfx_gate.is_valid(), "the battle installs its gate")
	scene.turbo_mode = false
	assert_true(EffectSystem.play_phase_sfx(key), "CONTROL: a normal battle plays the cue")
	scene.turbo_mode = true
	assert_false(EffectSystem.play_phase_sfx(key), "turbo mutes it")
	scene.turbo_mode = false


## adhoc 21681: the gate is bound to ONE battle. When that battle leaves, it is cleared rather than left dangling,
## and with no battle running a phase cue plays (turbo and autogrind are battle modes; outside one nothing mutes it).
func test_a_finished_battle_takes_its_gate_with_it() -> void:
	var scene = SCENE.instantiate()
	add_child(scene)
	for i in 3:
		await get_tree().process_frame
	assert_true(EffectSystem.phase_sfx_gate.is_valid(), "CONTROL: the live battle installed its gate")
	scene.turbo_mode = true
	assert_false(EffectSystem.play_phase_sfx(_known_key()), "CONTROL: its turbo mutes")
	remove_child(scene)
	scene.free()
	assert_false(EffectSystem.phase_sfx_gate.is_valid(), "the battle's gate left with it")
	assert_true(EffectSystem.phase_sfx_gate.is_null(), "cleared, not a dangling reference to a freed scene")
	assert_true(EffectSystem.play_phase_sfx(_known_key()), "and with no battle running, a phase cue plays")


## CONTROL for measuring against the engine's own clock (sfx 21734 / main 21735): an earlier file's leaked battle writes its own
## Engine.time_scale every frame. Planted here at 4x through a whole 1x run; the beat still lands on its phase.
func test_a_leaked_battle_writing_the_scale_does_not_move_the_beat() -> void:
	var leak := ScaleLeak.new()
	leak.scale = 1.0
	add_child_autofree(leak)
	var d: int = await _cue_vs_clock(0.25, {"at": AT, "kind": "cue", "sfx": "planted_probe"})
	leak.queue_free()
	assert_ne(d, NO_CUE, "CONTROL: the cue fired")
	assert_between(d, -1, 1, "a leaked 4x moves wall time, not the beat: %d frames off its clock" % d)
