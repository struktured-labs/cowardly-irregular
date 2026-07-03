extends GutTest

## Regression: the FIRST successful non-fallback LLM response in a session
## must surface a one-shot "Dynamic dialogue active" toast so desktop+Ollama
## players know the LLM is wired up. 2026-07-03 defer-semantics: the one-shot
## latches only when the toast actually SHOWS — TITLE and in-battle successes
## defer (the old latch-before-show ate the notice silently if the first
## inference happened on the title screen or mid-duel).


const GAMELOOP_PATH := "res://src/GameLoop.gd"


func _make_gameloop():
	var script = load(GAMELOOP_PATH)
	var gl = script.new()
	autofree(gl)
	return gl


func test_title_state_defers_without_consuming_oneshot() -> void:
	var gl = _make_gameloop()
	gl.current_state = gl.LoopState.TITLE
	gl._on_llm_inference_succeeded("json")
	assert_false(gl._llm_success_notice_shown,
		"a title-screen inference must DEFER the notice, not eat the one-shot silently")


func test_subsequent_success_does_not_re_latch() -> void:
	var gl = _make_gameloop()
	gl.current_state = gl.LoopState.TITLE
	gl._llm_success_notice_shown = true
	gl._on_llm_inference_succeeded("text")
	assert_true(gl._llm_success_notice_shown,
		"latch should remain set; no spam toasts on subsequent successes")


func test_latch_happens_only_where_toast_shows() -> void:
	var src: String = FileAccess.get_file_as_string(GAMELOOP_PATH)
	var idx: int = src.find("func _on_llm_inference_succeeded")
	var body: String = src.substr(idx, src.find("\nfunc ", idx + 1) - idx)
	var title_gate: int = body.find("LoopState.TITLE")
	var battle_gate: int = body.find("BattleState.INACTIVE")
	var consume: int = body.find("_llm_success_notice_shown = true")
	assert_gt(title_gate, -1)
	assert_gt(battle_gate, -1)
	assert_true(consume > title_gate and consume > battle_gate,
		"the one-shot must be consumed AFTER both defer gates — latch-before-show eats the notice")
