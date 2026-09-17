extends GutTest

## The +3%/hit ramp exists to make a multi-hit chain ESCALATE. It counted play_attack_hit CALLS.
## BattleScene:4025 spawns one PHYSICAL effect per target inside a single tween callback, so a
## participant striking N enemies fires N same-key hits in ONE frame. The per-key cooldown
## (SFX_MIN_INTERVAL_MS = 80) sounds the first and suppresses the rest — correct, because identical
## same-frame samples comb-filter — but the counter advanced on the silent ones too.
## Measured before the fix: 5 calls -> 1 audible play, _combo_step 5, bias 1.1200 = the CAP.
## So a group attack jumped to maximum pitch with nothing audible causing it, which is the ramp
## defeating its own purpose exactly where it was meant to shine.

const HITS := 5


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func before_each() -> void:
	var sm: Node = _sm()
	if sm:
		sm._sfx_cooldowns.clear()
		sm.reset_hit_chain()


func test_suppressed_hits_do_not_advance_the_ramp() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has("attack_hit_sword"),
		"CONTROL: attack_hit_sword must be in the manifest, or the cooldown path is never taken")
	for i in range(HITS):
		sm.play_attack_hit("sword", false)
	assert_eq(sm._combo_step, 1,
		"%d same-frame hits advanced the ramp %d steps — the player heard ONE, so the next audible hit pitches up as if %d had landed" % [HITS, sm._combo_step, sm._combo_step])


func test_the_ramp_still_ramps_when_the_hits_are_audible() -> void:
	## ANTI-OVERCORRECTION: the repair must not be "stop counting". Clearing the cooldown between
	## calls is what a real chain spaced beyond SFX_MIN_INTERVAL_MS looks like.
	var sm: Node = _sm()
	if sm == null:
		return
	for i in range(HITS):
		sm._sfx_cooldowns.clear()
		sm.play_attack_hit("sword", false)
	assert_eq(sm._combo_step, HITS,
		"%d AUDIBLE hits advanced the ramp only %d steps — the repair silenced the ramp instead of correcting its count" % [HITS, sm._combo_step])
	assert_gt(sm.get_combo_pitch_bias(), 1.0,
		"CONTROL: an audible chain must still pitch up, or this arm is asserting about a dead feature")


func test_one_hit_is_still_bit_identical_to_the_pre_ramp_path() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_attack_hit("sword", false)
	assert_eq(sm._combo_step, 1, "CONTROL: a single audible hit must advance exactly one step")
	sm.reset_hit_chain()
	assert_almost_eq(sm.get_combo_pitch_bias(), 1.0, 0.0001,
		"step 0 must yield exactly 1.0 — an unchained hit has to stay identical to the pre-ramp path")


func test_the_suppression_flag_means_heard_not_handled() -> void:
	## The distinction the fix rests on: _try_play_sfx_from_manifest returns true for BOTH a real
	## play and a cooldown suppression, so `true` alone cannot drive the counter.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_true(sm.has_method("_advance_hit_chain"),
		"SoundManager has no _advance_hit_chain — the ramp is back to counting calls")
	assert_ne(sm.get("_sfx_suppressed_by_cooldown"), null,
		"SoundManager has no _sfx_suppressed_by_cooldown — nothing distinguishes handled from heard")
	sm._sfx_cooldowns.clear()
	assert_true(sm._try_play_sfx_from_manifest(sm._battle_player, "attack_hit_sword"),
		"CONTROL: a cold key must actually play")
	assert_false(sm._sfx_suppressed_by_cooldown, "a real play must not be flagged as suppressed")
	assert_true(sm._try_play_sfx_from_manifest(sm._battle_player, "attack_hit_sword"),
		"CONTROL: the second call must still report HANDLED, or the procedural fallback would double it")
	assert_true(sm._sfx_suppressed_by_cooldown,
		"a cooldown-suppressed call reported itself as heard — the ramp would count it")
