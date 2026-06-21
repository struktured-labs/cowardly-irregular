extends GutTest

## Regression: the FIRST successful non-fallback LLM response in a session
## must surface a one-shot "Dynamic dialogue active" toast so desktop+Ollama
## players know the LLM is wired up. Symmetric to the inference_failed toast.


const GAMELOOP_PATH := "res://src/GameLoop.gd"


func _make_gameloop():
	var script = load(GAMELOOP_PATH)
	var gl = script.new()
	autofree(gl)
	return gl


func test_first_success_latches_notice() -> void:
	var gl = _make_gameloop()
	gl.current_state = gl.LoopState.TITLE  # suppress Toast.show; we only check the latch
	gl._on_llm_inference_succeeded("json")
	assert_true(gl._llm_success_notice_shown,
		"first successful LLM response must latch _llm_success_notice_shown")


func test_subsequent_success_does_not_re_latch() -> void:
	var gl = _make_gameloop()
	gl.current_state = gl.LoopState.TITLE
	gl._llm_success_notice_shown = true  # simulate "already latched"
	gl._on_llm_inference_succeeded("text")
	# Handler is a no-op when already latched; assert state unchanged.
	assert_true(gl._llm_success_notice_shown,
		"latch should remain set; no spam toasts on subsequent successes")
