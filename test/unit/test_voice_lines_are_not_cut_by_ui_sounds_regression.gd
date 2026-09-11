extends GutTest

## 25 of 31 authored party voice lines were being cut mid-word, two ways at once.
##
## MEASURED 2026-09-11 (ffprobe over every voice_* key in sfx_manifest.json):
##   31 voice_* keys · 25 longer than 2.0s · median 4.30s · max 10.90s (voice_mage_low_hp)
##   the 6 short ones are voice_blip_* UI blips, not performances
##
## Defect 1: BattleSpeechBubble played them through SoundManager.play_ui(), whose _ui_player is
##   the SAME player every menu blip and cursor move uses — so the player's next input stopped
##   the line. Identical to the death-cry defect (2026-08-18), different shared player.
## Defect 2: the bubble held 2.0s over a line lasting 4-11s, so the words vanished while the
##   voice was still speaking.
##
## Both are fixed by one thing the guard can check: play_voice() owns a player AND reports the
## clip length, and the bubble holds for what it is told.

const VOICE_KEY := "voice_mage_low_hp"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func test_the_voice_player_is_not_the_ui_player() -> void:
	## THE defect. If these are ever the same node again, a menu blip cuts a spoken line and
	## nothing else in this file would notice — the length asserts below would all still pass.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_not_null(sm._voice_player, "voice lines need their own AudioStreamPlayer")
	assert_not_null(sm._ui_player, "CONTROL: the UI player must exist for this comparison to mean anything")
	assert_ne(sm._voice_player, sm._ui_player,
		"voice lines are back on the shared UI player — every menu blip will cut them mid-word")
	assert_ne(sm._voice_player, sm._battle_player,
		"voice lines are on the battle player — hit sounds will cut them, which is the 2026-08-18 death-cry defect")


func test_play_voice_reports_the_real_clip_length() -> void:
	## The bubble cannot hold for a line it cannot measure. A 0.0 here silently restores the old
	## 2.0s hold, which is a defect that looks exactly like working code.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has(VOICE_KEY), "CONTROL: %s must be in the manifest" % VOICE_KEY)
	var got: float = sm.play_voice(VOICE_KEY)
	assert_gt(got, 2.0,
		"play_voice('%s') reported %.2fs — it was measured at 10.90s, and anything at or under the 2.0s bubble means the length is not reaching the caller" % [VOICE_KEY, got])
	## NEGATIVE control: an unresolvable key must report 0.0, not a stale length from the
	## previous call still sitting on the player's stream.
	var bogus: float = sm.play_voice("voice_no_such_line_xyz")
	assert_eq(bogus, 0.0,
		"an unresolved voice key reported %.2fs — the player's PREVIOUS stream is being measured, so every miss inherits the last hit's length" % bogus)


func test_every_authored_voice_line_outlasts_the_default_bubble() -> void:
	## The reason this fix exists, asserted over the real corpus rather than the one clip above.
	## DERIVED from the manifest: a new voice line is covered the day it lands.
	var sm: Node = _sm()
	if sm == null:
		return
	var performances: Array[String] = []
	for k in sm._sfx_manifest.keys():
		var key: String = str(k)
		if key.begins_with("voice_") and not key.begins_with("voice_blip_"):
			performances.append(key)
	assert_gte(performances.size(), 20,
		"CONTROL: found %d authored voice lines — the derivation is broken, and an empty corpus would pass every assert below" % performances.size())
	var too_short: Array[String] = []
	for key in performances:
		if sm.play_voice(key) <= 0.0:
			too_short.append(key)
	assert_eq(too_short, [],
		"voice lines play_voice() could not resolve or measure (%d): %s — these fall back to the 2.0s bubble" % [too_short.size(), too_short])


func test_the_bubble_holds_for_the_whole_line() -> void:
	## Defect 2, end to end: spawn a real bubble with a real voice key and read the hold it
	## settled on. The number must come from the CLIP, not from the caller's 2.0s.
	var sm: Node = _sm()
	if sm == null:
		return
	var parent := Node2D.new()
	add_child_autofree(parent)
	var prior: float = Engine.time_scale
	Engine.time_scale = 1.0
	var b = BattleSpeechBubble.spawn(parent, Vector2(200, 200), "Mage", "...", Color.WHITE, 2.0, VOICE_KEY)
	Engine.time_scale = prior
	assert_not_null(b, "CONTROL: the bubble must spawn at 1x — a null here makes the assert below vacuous")
	if b == null:
		return
	var clip: float = sm.play_voice(VOICE_KEY)
	assert_gt(b._hold_time, 2.0,
		"the bubble held %.2fs for a %.2fs line — it is still using the caller's hold, so the words leave while the voice is speaking" % [b._hold_time, clip])
	assert_gte(b._hold_time, clip,
		"the bubble held %.2fs, shorter than the %.2fs clip" % [b._hold_time, clip])
	## CONTROL: a bubble with NO voice keeps the caller's hold. Without this the assert above is
	## satisfied by any change that simply made all bubbles longer.
	var silent = BattleSpeechBubble.spawn(parent, Vector2(300, 200), "Fighter", "...", Color.WHITE, 2.0, "")
	assert_not_null(silent, "CONTROL: the silent bubble must spawn too")
	if silent != null:
		assert_almost_eq(silent._hold_time, 2.0 / maxf(1.0, Engine.time_scale), 0.01,
			"a voiceless bubble held %.2fs instead of the caller's 2.0s — the hold is no longer coming from the clip" % silent._hold_time)
