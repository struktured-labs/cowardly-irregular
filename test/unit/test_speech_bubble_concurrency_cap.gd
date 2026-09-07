extends GutTest

## Smoke-shot find 2026-07-03 (victory frame): four speech bubbles from
## different triggers (battle-start, crit, victory quips) stacked at
## once, burying the party panel under text. spawn() now caps live
## bubbles at MAX_CONCURRENT (oldest evicted) and replaces a speaker's
## own still-showing bubble instead of double-bubbling them.


func before_each() -> void:
	BattleSpeechBubble._live.clear()
	Engine.time_scale = 1.0


func _host() -> Control:
	var h := Control.new()
	add_child_autofree(h)
	return h


func _alive_count() -> int:
	var n := 0
	for e in BattleSpeechBubble._live:
		if is_instance_valid(e["bubble"]) and not e["bubble"].is_queued_for_deletion():
			n += 1
	return n


func test_cap_evicts_oldest() -> void:
	var host := _host()
	var first = BattleSpeechBubble.spawn(host, Vector2(100, 100), "Fighter", "one")
	BattleSpeechBubble.spawn(host, Vector2(200, 100), "Mage", "two")
	BattleSpeechBubble.spawn(host, Vector2(300, 100), "Bard", "three")
	assert_eq(_alive_count(), BattleSpeechBubble.MAX_CONCURRENT,
		"third bubble must evict the oldest, not stack to three")
	assert_true(first == null or first.is_queued_for_deletion(),
		"the evicted bubble is the OLDEST (Fighter's)")


func test_same_speaker_replaces_own_bubble() -> void:
	var host := _host()
	var a = BattleSpeechBubble.spawn(host, Vector2(100, 100), "Bard", "verse one")
	var b = BattleSpeechBubble.spawn(host, Vector2(100, 100), "Bard", "verse two")
	assert_true(a.is_queued_for_deletion(), "Bard's first bubble must clear when he speaks again")
	assert_false(b.is_queued_for_deletion())
	assert_eq(_alive_count(), 1)


func test_suppressed_at_4x_still() -> void:
	var host := _host()
	Engine.time_scale = 4.0
	var b = BattleSpeechBubble.spawn(host, Vector2(100, 100), "Mage", "quiet")
	Engine.time_scale = 1.0
	assert_null(b, "4x+ suppression must survive the cap change")
