extends GutTest

## The Prismatic Construct's last words, captured on 2026-10-31, read "Automated victory. A triumph of predictability
## over potency." WITH the quote marks: the model wraps its whole reply despite the prompt's "no quotes", so the beat's
## box printed them and the battle log doubled them (""…""). The producer now strips one MATCHED outer pair, and only
## from the model's reply: authored fallbacks quote speech inside narration and must reach the screen unchanged.
## Fixture copied from test_a_boss_gloat_is_spoken_once_and_on_time, including its cache clear.

const TEST_BOSS_ID := "test_gloat_boss_quotes"
const SPOKEN := "Pass — though you let a script sit the exam."
const POOL := ["The Construct stills. 'You matched each face.'"]

var _bm: Node
var _dlg: Node
var _llm: Node
var _be = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true
var _orig_turbo: bool = false


class QuotingModel extends LLMBackend:
	var reply: String = ""
	func backend_id() -> String: return "quoting_model"
	func is_ready() -> bool: return true
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		get_tree().create_timer(0.05, true, false, true).timeout.connect(func(): request_finished.emit(id, true, reply, ""))


func before_each() -> void:
	_bm = get_tree().root.get_node("BattleManager")
	_dlg = get_tree().root.get_node("BossDialogue")
	_llm = get_tree().root.get_node("LLMService")
	_orig_enabled = _llm.llm_enabled
	_orig_backends = _llm._backends.duplicate()
	_orig_active = _llm._active_backend
	_orig_turbo = _bm.turbo_mode
	_bm.turbo_mode = false
	_llm.llm_enabled = true
	_llm.cancel_all("quote fixture isolation")
	_llm.clear_cache()
	_be = QuotingModel.new()
	_llm.add_child(_be)
	_llm._backends.clear()
	_llm._backends.append(_be)
	_be.request_finished.connect(_llm._on_backend_finished)
	_llm._active_backend = _be
	_dlg._data[TEST_BOSS_ID] = {"display_name": "The Quote Boss", "victory_lines": POOL.duplicate(), "defeat_lines": POOL.duplicate()}
	var boss := Combatant.new()
	autofree(boss)
	boss.combatant_name = "The Quote Boss"
	boss.max_hp = 300
	boss.current_hp = 0
	boss.is_alive = false
	boss.set_meta("is_boss", true)
	boss.set_meta("llm_persona_id", TEST_BOSS_ID)
	_bm.enemy_party.clear()
	_bm.enemy_party.append(boss)


func after_each() -> void:
	_bm.turbo_mode = _orig_turbo
	_bm.enemy_party.clear()
	_dlg._data.erase(TEST_BOSS_ID)
	_llm.cancel_all("quote fixture teardown")
	_be.request_finished.disconnect(_llm._on_backend_finished)
	_llm.remove_child(_be)
	_be.free()
	_llm._backends.clear()
	for b in _orig_backends:
		_llm._backends.append(b)
	_llm._active_backend = _orig_active
	_llm.llm_enabled = _orig_enabled
	_llm.clear_cache()


## The first gloat emitted after a real dispatch.
func _spoken_for(reply: String) -> String:
	_be.reply = reply
	_llm.clear_cache()
	var heard: Array = []
	var cb := func(text: String, _v: bool): heard.append(text)
	_bm.boss_gloat_line.connect(cb)
	_bm._dispatch_boss_gloat(true)
	var t0 := Time.get_ticks_msec()
	while heard.is_empty() and Time.get_ticks_msec() - t0 < int(_bm.GLOAT_WAIT_SEC * 1000.0) + 500:
		await get_tree().process_frame
	_bm.boss_gloat_line.disconnect(cb)
	return str(heard[0]) if not heard.is_empty() else "<nothing emitted>"


func test_a_quoted_reply_reaches_the_screen_unquoted() -> void:
	## THE DEFECT, through the real producer: a helper-only test would stay green if the producer stopped calling it.
	var spoken: String = await _spoken_for("\"%s\"" % SPOKEN)
	assert_eq(spoken, SPOKEN, "the model's own wrapping quotes reached the beat's box and the log")


func test_control_an_unquoted_reply_is_untouched() -> void:
	## CONTROL: without it, the arm above passes on a producer that mangles every line the same way.
	var spoken: String = await _spoken_for(SPOKEN)
	assert_eq(spoken, SPOKEN, "a clean reply must reach the screen exactly as the model wrote it")


func test_only_a_matched_outer_pair_is_removed() -> void:
	var cases := {
		"\"Pass.\"": "Pass.",
		"“Pass.”": "Pass.",
		"  \"Pass.\"  ": "Pass.",
		"The Construct stills. 'You matched each face.'": "The Construct stills. 'You matched each face.'",
		"He said \"no\" and fell.": "He said \"no\" and fell.",
		"\"Mismatched.”": "\"Mismatched.”",
		"\"": "\"",
		"": "",
	}
	for raw in cases:
		assert_eq(BattleManager.strip_wrapping_quotes(str(raw)), str(cases[raw]),
			"strip_wrapping_quotes(%s) — only a matched OUTER pair may go; quoted speech inside a line stays" % JSON.stringify(raw))
