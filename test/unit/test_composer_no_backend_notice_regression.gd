extends GutTest

## Web-player UX fix (2026-07-10): the Rule Composer opened its full compose
## UI with NO availability check — every web player (has_llm() is hard-false
## on web) typed a prompt into a dead end. open() now surfaces the
## no-backend notice upfront, pointing at BYOK/Ollama and reassuring that
## the grid + presets work without it. NOTE: test avoids touching
## /root/LLMService destructively (hermetic-contamination rule).

const OverlayScript := preload("res://src/ui/autobattle/RuleComposerOverlay.gd")


func test_open_surfaces_no_backend_notice_upfront() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/autobattle/RuleComposerOverlay.gd")
	var i := src.find("func open(")
	var body := src.substr(i, src.find("\nfunc ", i + 10) - i)
	assert_true("has_llm" in body, "open() checks availability via RuleComposer.has_llm")
	assert_true("No LLM backend reachable" in body, "the notice names the problem")
	assert_true("BYOK" in body and "Ollama" in body, "the notice points at both remedies")
	assert_true("work fine without it" in body, "the notice reassures — manual flows are unaffected")


func test_has_llm_is_hard_false_on_web() -> void:
	var src := FileAccess.get_file_as_string("res://src/llm/RuleComposer.gd")
	var i := src.find("func has_llm(")
	var body := src.substr(i, 300)
	assert_true("has_feature(\"web\")" in body and "return false" in body,
		"web builds must always report no-LLM — the notice fires for every itch web player")
