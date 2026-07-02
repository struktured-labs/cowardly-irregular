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
	var src := _read(BUBBLE_PATH)
	assert_true(src.contains("SUPPRESS_TIME_SCALE: float = 4.0"),
		"Bubble suppression must kick in at 4x, not 2x — 2x players must still see bubbles")
	assert_true(src.contains("Engine.time_scale >= SUPPRESS_TIME_SCALE"),
		"spawn must gate on the SUPPRESS_TIME_SCALE const")
	# The old hard-coded 2.0 gate must be gone from the delegate too.
	var scene := _read(BATTLE_SCENE_PATH)
	var fn_idx: int = scene.find("func _spawn_quip_bubble")
	var fn_end: int = scene.find("\n\nfunc ", fn_idx)
	var body: String = scene.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else scene.substr(fn_idx, 1500)
	assert_false(body.contains("time_scale >= 2.0"),
		"_spawn_quip_bubble must not re-add the 2x suppression — that was the invisible-dialogue bug")


func test_hold_time_scales_with_battle_speed() -> void:
	var src := _read(BUBBLE_PATH)
	assert_true(src.contains("hold_time / maxf(1.0, Engine.time_scale)"),
		"Bubble hold must shrink at faster battle speeds so bubbles never outlive their turn")


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
	assert_true(mgr.contains("event_kind if (not fallback.is_empty() and line == fallback) else \"\""),
		"LLM emit site must pass empty voice_trigger unless the line fell back to the deterministic one")
	# All five deterministic fallback sites must carry event_kind.
	var count: int = mgr.count("_emit_party_line(combatant, fallback, event_kind)")
	assert_eq(count, 5,
		"All 5 deterministic fallback emit sites must pass event_kind as voice_trigger (got %d)" % count)
