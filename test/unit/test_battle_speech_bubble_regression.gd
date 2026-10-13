extends GutTest

## Playtest brief msg 2101 + amendment 2105: party combat dialogue must
## render as sprite-anchored speech bubbles the player can actually see.
## Root causes fixed: (1) bubbles were suppressed at time_scale >= 2.0
## while the doc promised 4x+ — anyone playing at 2x saw only the
## bottom-middle log; (2) no right-column clamp, so bubbles over
## right-side party sprites could occlude the top-right 200px
## PartyStatusPanel. Voice hook: deterministic trigger_voices lines
## carry voice_trigger → key voice_<job>_<trigger>; LLM lines text-only.

const BUBBLE_PATH := "res://src/battle/BattleSpeechBubble.gd"
const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"
const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const BATTLE_SCENE_SCRIPT = preload("res://src/battle/BattleScene.gd")


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_component_exists_with_spawn_api() -> void:
	var src := _read(BUBBLE_PATH)
	assert_true(src.contains("class_name BattleSpeechBubble"),
		"BattleSpeechBubble class must exist")
	assert_true(src.contains("static func spawn("),
		"BattleSpeechBubble must expose a static spawn factory")
	assert_true(src.contains("audio_key: String = \"\""),
		"spawn must take an optional audio_key (phase-2 voice hook)")


func test_suppression_threshold_is_4x_not_2x() -> void:
	# THE user-facing bug: >= 2.0 hid every bubble for 2x-speed players.
	## This arm pinned the source text "SUPPRESS_TIME_SCALE: float = 4.0" until 2026-10-12, so it
	## passed for three months while the constant meant the 16x LABEL: a label is engine*4 under
	## speed scale v3, and nothing rescaled this constant when that landed. A literal cannot carry
	## which unit it is in, so the threshold is asserted against the ladder it has to agree with.
	var src := _read(BUBBLE_PATH)
	assert_true(src.contains("Engine.time_scale >= SUPPRESS_TIME_SCALE"),
		"spawn must gate on the SUPPRESS_TIME_SCALE const")
	var speeds: Array = BATTLE_SCENE_SCRIPT.BATTLE_SPEEDS
	var labels: Array = BATTLE_SCENE_SCRIPT.BATTLE_SPEED_LABELS
	var i_4x: int = labels.find("4x")
	assert_gt(i_4x, 0, "CONTROL: the speed ladder must carry a 4x label")
	assert_almost_eq(BattleSpeechBubble.SUPPRESS_TIME_SCALE, float(speeds[i_4x]), 0.0001,
		"suppression must begin AT the ladder's 4x entry (engine %s), not engine %s (label %sx)" \
			% [speeds[i_4x], BattleSpeechBubble.SUPPRESS_TIME_SCALE, BattleSpeechBubble.SUPPRESS_TIME_SCALE * 4.0])
	# The old hard-coded 2.0 gate must be gone from the delegate too.
	var scene := _read(BATTLE_SCENE_PATH)
	var fn_idx: int = scene.find("func _spawn_quip_bubble")
	var fn_end: int = scene.find("\n\nfunc ", fn_idx)
	var body: String = scene.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else scene.substr(fn_idx, 1500)
	assert_false(body.contains("time_scale >= 2.0"),
		"_spawn_quip_bubble must not re-add the 2x suppression — that was the invisible-dialogue bug")


func test_the_inert_hold_divisor_does_not_come_back() -> void:
	## This arm asserted the SOURCE TEXT "hold_time / maxf(1.0, Engine.time_scale)" under the
	## message "Bubble hold must shrink at faster battle speeds". Both halves were wrong: a string
	## is not a behaviour, and that divisor could only divide above engine 1.0 — where the
	## suppression gate has already returned null. It was 1.0 at every spawnable speed.
	##
	## ⚠️ The arm two above was converted off a string pin on 2026-10-12 for the identical reason
	## (a literal cannot carry its unit). This is the sibling that fix left behind, in the same
	## file, found by a corpus run the same night. A fix hides its own siblings.
	##
	## Kept as a DO-NOT-RE-ADD ratchet, which is this file's existing convention for a removed
	## mechanism (see the "must not re-add the 2x suppression" arm). The INVARIANT that makes the
	## removal safe — no spawnable engine scale exceeds 1.0 — is derived and mutation-pinned in
	## test_a_bubble_hold_divisor_that_cannot_divide, which reds if that stops being true.
	var src := _read(BUBBLE_PATH)
	assert_false(src.contains("hold_time / maxf(1.0, Engine.time_scale)"),
		"the inert divisor is back: it divides by 1.0 at every speed a bubble can spawn at, because suppression fires first — what bounds a bubble against a fast turn is SUPPRESS_TIME_SCALE, not this")
	assert_true(src.contains("b._hold_time = hold_time"),
		"spawn must pass the requested hold through unscaled — the tween already carries battle speed")


func test_right_column_clamp() -> void:
	# Bubble rect must never enter the reserved top-right party-panel column.
	var src := _read(BUBBLE_PATH)
	assert_true(src.contains("RESERVED_RIGHT_PX: float = 210.0"),
		"Reserved right column must cover the 200px PartyStatusPanel + margin")
	assert_true(src.contains("func _clamped_x("),
		"Bubble must clamp its x position via _clamped_x")
	assert_true(src.contains("vp_w - RESERVED_RIGHT_PX - bubble_width"),
		"_clamped_x must subtract the reserved column from the max x")


func test_clamped_x_behavior() -> void:
	# Behavioral: a bubble pushed toward the right edge clamps left of the column.
	var bubble_script = load(BUBBLE_PATH)
	var b = bubble_script.new()
	add_child_autofree(b)
	var vp_w: float = b.get_viewport().get_visible_rect().size.x
	if vp_w <= 0:
		vp_w = 1280.0
	var w: float = 260.0
	var clamped: float = b._clamped_x(vp_w - 50.0, w)
	assert_lte(clamped + w, vp_w - 210.0 + 0.01,
		"Right-pushed bubble must clamp fully left of the reserved column")
	assert_eq(b._clamped_x(-500.0, w), 8.0,
		"Left-pushed bubble must clamp to the edge margin")


func test_scene_delegate_passes_audio_key() -> void:
	var scene := _read(BATTLE_SCENE_PATH)
	var fn_idx: int = scene.find("func _spawn_quip_bubble")
	var fn_end: int = scene.find("\n\nfunc ", fn_idx)
	var body: String = scene.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else scene.substr(fn_idx, 1500)
	assert_true(body.contains("BattleSpeechBubble.spawn("),
		"_spawn_quip_bubble must delegate to BattleSpeechBubble.spawn")
	assert_true(body.contains("audio_key"),
		"Delegate must forward the audio_key voice hook")


func test_party_line_handler_derives_voice_key() -> void:
	# msg 2105 convention: voice_<job>_<trigger>, derivable, no lookup table.
	var scene := _read(BATTLE_SCENE_PATH)
	var fn_idx: int = scene.find("func _on_party_combat_line")
	var fn_end: int = scene.find("\n\nfunc ", fn_idx)
	var body: String = scene.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else scene.substr(fn_idx, 1500)
	assert_true(body.contains("voice_trigger: String = \"\""),
		"Handler must accept the voice_trigger signal arg")
	assert_true(body.contains("\"voice_%s_%s\" % [job_id, voice_trigger]"),
		"Voice key must derive as voice_<job>_<trigger> per the msg 2105 convention")


func test_llm_lines_stay_text_only() -> void:
	# Deterministic fallback → voice; LLM-generated → text-only (msg 2105).
	var mgr := _read(BATTLE_MANAGER_PATH)
	assert_true(mgr.contains("fallback_key if (not fallback.is_empty() and line == fallback) else \"\""),
		"LLM emit site must pass empty voice_trigger unless the line fell back to the deterministic one")
	# All five deterministic fallback sites carry the picked variant's key (event_kind, or event_kind_<n>).
	var count: int = mgr.count("_emit_party_line(combatant, fallback, fallback_key)")
	assert_eq(count, 5,
		"All 5 deterministic fallback emit sites must pass the variant's voice key (got %d)" % count)


## The rule as a player meets it: at 2x a bubble appears, at 4x it does not.
func test_a_player_at_2x_sees_a_bubble_and_at_4x_does_not() -> void:
	var speeds: Array = BATTLE_SCENE_SCRIPT.BATTLE_SPEEDS
	var labels: Array = BATTLE_SCENE_SCRIPT.BATTLE_SPEED_LABELS
	var saved: float = Engine.time_scale
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child_autofree(host)
	var seen: Dictionary = {}
	for want in ["1x", "2x", "4x", "8x"]:
		var i: int = labels.find(want)
		assert_gte(i, 0, "CONTROL: the ladder must carry a %s label" % want)
		Engine.time_scale = float(speeds[i])
		BattleSpeechBubble._live.clear()
		seen[want] = BattleSpeechBubble.spawn(host, Vector2(320, 400), "Fighter", "A line.") != null
	Engine.time_scale = saved
	assert_true(seen["1x"], "a bubble must show at 1x")
	assert_true(seen["2x"], "a bubble must show at 2x — this was the invisible-dialogue complaint")
	assert_false(seen["4x"], "4x must suppress the bubble; the doc'd rule is 4x and up")
	assert_false(seen["8x"], "8x must suppress the bubble")
