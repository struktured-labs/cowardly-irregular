extends GutTest

## cowir-main 20637 (under struktured's standing rule): "live AI-line voicing = YES after the recorded lines".
## cowir-sfx cast the Cave Rat King on the free engine; his LLM last words had no voice, only blips.
##
## Spec 2b.3: the voice is chosen ONCE, at the first emit, and a late voice is never played late (the boss
## would speak twice, or over the rewards). A recorded clip for the same text outranks the live voice.

const SceneScript := preload("res://src/battle/BattleScene.gd")
const DialogueScript := preload("res://src/ui/BattleDialogue.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const Replay := preload("res://tools/replay_tts_backend.gd")
const DIR := "user://test_gloat_live_voice_cache"
const BOSS_ID := "cave_rat_king"
const BOSS_NAME := "Cave Rat King"
const LINE := "Fine. Keep your cheese. The throne remembers."
const VOICE_SEC := 1.5


class ProbeScene extends "res://src/battle/BattleScene.gd":
	var results_at: int = -1
	func _show_victory_results() -> void:
		results_at = Time.get_ticks_msec()
	func _show_victory_quip() -> void:
		pass


var _saved: Dictionary = {}
var _replay = null
var _scene: Node = null
var _dialogue: Node = null
var _bm_guard = BattleStateGuard.new()


func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


func before_each() -> void:
	_bm_guard.snapshot()
	_wipe()
	_saved = {
		"cast": VoiceService._cast.duplicate(true), "cache": VoiceService.cache, "web": VoiceService.is_web,
		"tts": GameState.tts_live_enabled, "speed": SceneScript._battle_speed_index,
		"pending": BattleManager.boss_gloat_pending,
	}
	SceneScript._battle_speed_index = 0
	BattleManager.boss_gloat_pending = false
	VoiceService.cache = VoiceCache.new(DIR, 10_000_000)
	VoiceService._cast = {BOSS_ID: {"voice": "cave_rat_king.wav", "rev": 1}}
	VoiceService.is_web = false
	_replay = Replay.new()
	_replay.next_wav = WavFixture.tone(VOICE_SEC, 8000)
	VoiceService.install_backend(_replay)
	GameState.tts_live_enabled = true


func after_each() -> void:
	SoundManager.stop_voiced_line()
	VoiceService._cast = _saved["cast"]
	VoiceService.cache = _saved["cache"]
	VoiceService.is_web = bool(_saved["web"])
	VoiceService.apply_config()
	GameState.tts_live_enabled = bool(_saved["tts"])
	SceneScript._battle_speed_index = int(_saved["speed"])
	BattleManager.boss_gloat_pending = bool(_saved["pending"])
	Input.action_release("ui_accept")
	InputLockManager.pop_all()
	_wipe()
	_bm_guard.restore()


## A bare scene with a real BattleDialogue and one boss whose monster id is `monster_id`.
func _make_scene(monster_id: String = BOSS_ID) -> Node:
	_scene = ProbeScene.new()
	add_child_autofree(_scene)
	_dialogue = DialogueScript.new()
	_scene.add_child(_dialogue)
	_scene._battle_dialogue = _dialogue
	var boss := Combatant.new()
	boss.combatant_name = BOSS_NAME
	boss.set_meta("is_boss", true)
	boss.set_meta("monster_type", monster_id)
	add_child_autofree(boss)
	_scene.test_enemies.append(boss)
	return _scene


func _wait_until(cond: Callable, cap_ms: int) -> bool:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < cap_ms:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _show_cap_ms() -> int:
	return int((BattleManager.GLOAT_WAIT_SEC + SceneScript.BOSS_BEAT_LIVE_VOICE_WAIT_SEC) * 1000.0) + 1500


func test_a_cast_boss_speaks_its_llm_last_words() -> void:
	var s: Node = _make_scene()
	BattleManager._emit_boss_gloat(LINE, true)
	s._finish_victory_after_boss_beat()
	assert_true(await _wait_until(func() -> bool: return _dialogue.visible, _show_cap_ms()), "the beat shows")
	assert_eq(_replay.requests.size(), 1, "one synthesis for the last words")
	if _replay.requests.size() != 1:
		return
	assert_eq(str(_replay.requests[0]["voice"]), "cave_rat_king.wav", "in the boss's own cast voice")
	assert_eq(str(_replay.requests[0]["text"]), DialoguePrompts.spoken_line(LINE), "speaking the line on screen")
	assert_almost_eq(_dialogue.line_voice_seconds(), VOICE_SEC, 0.1, "THE DEFECT: the LLM last words played no voice")
	assert_true(SoundManager.is_voiced_line_playing(), "and it is actually playing")


func test_the_voice_is_chosen_once() -> void:
	var s: Node = _make_scene()
	s._on_boss_gloat_line(LINE, true)
	s._on_boss_gloat_line(LINE + " Again.", true)
	assert_eq(_replay.requests.size(), 1, "a second emit must not start a second voice")


func test_a_late_voice_is_dropped_not_played_late() -> void:
	_replay.silent = true
	var s: Node = _make_scene()
	BattleManager._emit_boss_gloat(LINE, true)
	s._finish_victory_after_boss_beat()
	assert_true(await _wait_until(func() -> bool: return _dialogue.visible, _show_cap_ms()),
		"a voice that never comes must not hold the line past its bound")
	assert_eq(_dialogue.line_voice_seconds(), 0.0, "the line shows unvoiced, with its blips")
	assert_eq(_replay.requests.size(), 1, "FIXTURE: the synthesis was asked for")
	if _replay.requests.size() != 1:
		return
	_replay._emit(str(_replay.requests[0]["id"]))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(SoundManager.is_voiced_line_playing(), "a voice arriving after the line showed must never speak it")


func test_a_recorded_line_outranks_the_live_voice() -> void:
	var recorded: String = ""
	SoundManager._load_sfx_manifest()
	for key in SoundManager._sfx_manifest:
		var e = SoundManager._sfx_manifest[key]
		if e is Dictionary and str(e.get("speaker", "")) == BOSS_NAME and e.has("line"):
			recorded = str(e["line"])
			break
	assert_ne(recorded, "", "FIXTURE: the Rat King has recorded lines in the manifest")
	var s: Node = _make_scene()
	assert_ne(SoundManager.voiced_line_clip(BOSS_NAME, DialoguePrompts.spoken_line(recorded)), "",
		"FIXTURE: that line resolves to its clip as the beat will ask for it")
	s._on_boss_gloat_line(recorded, true)
	assert_eq(_replay.requests.size(), 0, "a line with a recording must not be synthesized as well")


## CONTROLS: each gate alone keeps the old, unvoiced behaviour; each must also be able to fire (arm 1).
func test_an_uncast_boss_is_not_voiced() -> void:
	var s: Node = _make_scene("goblin_chief")
	s._on_boss_gloat_line(LINE, true)
	assert_eq(_replay.requests.size(), 0, "a boss with no cast voice stays on blips")


func test_live_voice_off_is_not_voiced() -> void:
	GameState.tts_live_enabled = false
	var s: Node = _make_scene()
	s._on_boss_gloat_line(LINE, true)
	assert_eq(_replay.requests.size(), 0, "the player's Live Voice setting is respected")


func test_a_web_build_is_not_voiced() -> void:
	VoiceService.is_web = true
	var s: Node = _make_scene()
	s._on_boss_gloat_line(LINE, true)
	assert_eq(_replay.requests.size(), 0, "web builds never reach a voice server")


func test_a_suppressed_beat_is_not_voiced() -> void:
	SceneScript._battle_speed_index = SceneScript.BATTLE_SPEED_LABELS.find("4x")
	assert_gt(SceneScript._battle_speed_index, -1, "FIXTURE: the 4x rung exists")
	var s: Node = _make_scene()
	s._on_boss_gloat_line(LINE, true)
	assert_eq(_replay.requests.size(), 0, "no beat at 4x, so no voice is synthesized for one")


## cowir-music: the .542 freeze was a generator freed under a shared player; the line player refuses one outright.
func test_the_line_player_refuses_a_generator() -> void:
	var gen := AudioStreamGenerator.new()
	assert_eq(SoundManager.play_line_stream(gen), 0.0, "a generator must not reach the line player")
	assert_ne(SoundManager._line_player.stream, gen, "and the player must not hold it")
