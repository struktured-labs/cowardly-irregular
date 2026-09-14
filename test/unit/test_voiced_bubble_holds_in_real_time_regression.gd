extends GutTest

## Regression: a voiced bubble's hold is real seconds (the clip's length) but ran on the scaled tween clock — at default speed 0.25 a 5.3s line stayed up ≈24s (measured 2026-09-14, real battle).

const VOICE_KEY := "voice_mage_low_hp"
const DEFAULT_SPEED := 0.25
## Near-frozen battle clock: a scaled tween advances ~0.004s in 0.4s of wall time, a real-clock one completes its 0.15s fade-in.
const CRAWL_SPEED := 0.01
const WALL_MS := 400

var _prior_scale: float = 1.0
var _parent: Node2D = null


func before_each() -> void:
	BattleSpeechBubble._live.clear()
	_prior_scale = Engine.time_scale
	_parent = Node2D.new()
	add_child_autofree(_parent)


func after_each() -> void:
	Engine.time_scale = _prior_scale
	BattleSpeechBubble._live.clear()


func _sm() -> Node:
	return get_tree().root.get_node_or_null("SoundManager")


## Frame-driven so no GUT or SceneTree timer stalls while the battle clock crawls.
func _wait_wall(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame


## Loads the clip before the measured spawn, so a stream-load hitch can't finish the fade on either clock.
func _warm_voice(sm: Node) -> void:
	sm.play_voice(VOICE_KEY)
	for i in 5:
		await get_tree().process_frame


## The load-bearing property: a voiced bubble's tween runs on the REAL clock, through a mid-hold speed change.
func test_voiced_bubble_tween_ignores_the_battle_clock() -> void:
	var sm := _sm()
	assert_not_null(sm, "CONTROL: SoundManager must be loaded, else no voice resolves and this proves nothing")
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has(VOICE_KEY), "CONTROL: %s must be in the manifest" % VOICE_KEY)
	await _warm_voice(sm)
	Engine.time_scale = DEFAULT_SPEED
	var voiced = BattleSpeechBubble.spawn(_parent, Vector2(150, 500), "Mage", "...", Color.WHITE, 2.0, VOICE_KEY)
	assert_not_null(voiced, "the voiced bubble must spawn")
	if voiced == null:
		return
	assert_true(voiced._voiced, "a resolved clip must mark the bubble voiced")
	Engine.time_scale = CRAWL_SPEED
	await _wait_wall(WALL_MS)
	assert_almost_eq(voiced.modulate.a, 1.0, 0.05,
		"with the battle clock crawling, a real-clock fade-in finishes in %dms; alpha %.2f means the tween is on the scaled clock and the hold stretches with battle speed" % [WALL_MS, voiced.modulate.a])


## CONTROL: a voiceless bubble keeps battle-relative pacing — the fix must not re-time every quip.
func test_voiceless_bubble_still_runs_on_the_battle_clock() -> void:
	Engine.time_scale = DEFAULT_SPEED
	var silent = BattleSpeechBubble.spawn(_parent, Vector2(700, 500), "Fighter", "...", Color.WHITE, 2.0, "")
	assert_not_null(silent, "the silent bubble must spawn")
	if silent == null:
		return
	assert_false(silent._voiced, "no clip means not voiced")
	Engine.time_scale = CRAWL_SPEED
	await _wait_wall(WALL_MS)
	assert_lt(silent.modulate.a, 0.5,
		"a voiceless bubble reached alpha %.2f with the battle clock crawling — its tween left the battle clock, so quip pacing changed" % silent.modulate.a)
