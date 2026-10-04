extends GutTest

## Regression 2026-10-03: two status lines ran off their panels. The Rule Composer's no-LLM notice (every web player sees it)
## did not wrap, so it set the panel's minimum width and pushed it past the screen; BYOK's failure status ran past its frame.

const OverlayScene := preload("res://src/ui/autobattle/RuleComposerOverlay.tscn")
const PanelScript := preload("res://src/ui/BYOKConfigPanel.gd")
const LONG_FAILURE := "Status: FAILED — llama3.1:8b-instruct-q4_K_M @ https://api.example-provider.com/v1: HTTP 401 Unauthorized — invalid API key provided"

var _llm_was_enabled := true


func before_each() -> void:
	_llm_was_enabled = LLMService.llm_enabled


func after_each() -> void:
	LLMService.llm_enabled = _llm_was_enabled


func _settle() -> void:
	for _i in 3:
		await get_tree().process_frame


func test_the_composers_no_llm_notice_keeps_the_panel_on_screen() -> void:
	LLMService.llm_enabled = false
	var o = OverlayScene.instantiate()
	add_child_autofree(o)
	o.open("autobattle", "fighter", [])
	await _settle()
	var label: Label = o.get_node("Panel/VBox/StatusLabel")
	assert_string_contains(label.text, "No LLM backend reachable", "CONTROL: with no LLM the composer must show its notice, or this measures nothing")
	var screen_w: float = get_viewport().get_visible_rect().size.x
	assert_gt(screen_w, 600.0, "CONTROL: the test viewport has a real width (%.0f)" % screen_w)
	var panel_right: float = (o.get_node("Panel") as Control).get_global_rect().end.x
	assert_lte(panel_right, screen_w, "the no-LLM notice pushed the composer panel off the screen (right edge %.0f of %.0f)" % [panel_right, screen_w])
	assert_gte(label.get_visible_line_count(), label.get_line_count(), "part of the no-LLM notice is cut off")


func test_a_long_byok_failure_wraps_inside_its_frame() -> void:
	var p = PanelScript.new()
	add_child_autofree(p)
	await _settle()
	p._set_status(LONG_FAILURE, Color(1, 0.4, 0.4))
	await _settle()
	var label: Label = p._status_label
	assert_gt(label.get_line_count(), 1, "CONTROL: a failure naming model, endpoint and error must need more than one line at this width")
	assert_gte(label.get_visible_line_count(), label.get_line_count(), "part of the failure status is cut off")
	assert_lte(label.get_rect().end.y, p._test_btn.position.y, "the wrapped failure status runs into the buttons")
	assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the failure status does not wrap, so it runs past the frame")
