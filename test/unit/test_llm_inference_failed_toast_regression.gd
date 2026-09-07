extends GutTest

## Regression: the "Dynamic dialogue unavailable" fallback toast must only
## surface for genuine backend-AVAILABILITY failures, not for per-response
## guard rejections from a HEALTHY backend.
##
## Pre-fix: GameLoop._on_llm_inference_failed latched its one-shot notice
## (_llm_notice_shown) and showed the toast for ANY inference_failed signal.
## But LLMService emits inference_failed as a BROAD telemetry signal — on
## every fallback, including "guard rejected response" when a perfectly
## working backend returns one refusal-pattern line or one schema-invalid
## JSON for a single NPC turn (LLMService.complete:176, complete_json:205,
## choose:236). A small local model commonly emits one malformed JSON on
## the first turn — which permanently and falsely told the player dynamic
## dialogue was unavailable (the latch is one-shot, so it could never be
## corrected even if every later turn succeeded).
##
## Fix: gate the toast on a whitelist of availability reasons. Per-response
## guard rejections stay quiet (no latch, no toast). See R9 / digest
## src/GameLoop.gd:179-191.
##
## Behavioral test — instantiates GameLoop WITHOUT adding it to the tree
## (so the heavy _ready never fires) and calls the handler directly. The
## observable is `_llm_notice_shown`: for non-availability reasons the
## handler returns BEFORE setting the latch, so it stays false; for
## availability reasons it latches. We park current_state on TITLE for the
## availability case so the latch sets but Toast.show is skipped (no
## orphan UI nodes in the test).


const GAMELOOP_PATH := "res://src/GameLoop.gd"


func _make_gameloop():
	# .new() alone does NOT fire _ready (only entering the tree does), so
	# this avoids the GameLoop bootstrap. autofree handles cleanup.
	var script = load(GAMELOOP_PATH)
	var gl = script.new()
	autofree(gl)
	return gl


func test_guard_rejection_does_not_latch_or_toast() -> void:
	var gl = _make_gameloop()
	# Healthy backend, single per-response guard rejection — NOT an outage.
	gl.current_state = gl.LoopState.EXPLORATION
	gl._on_llm_inference_failed("json", "guard rejected response")
	assert_false(gl._llm_notice_shown,
		"a single guard rejection from a healthy backend must NOT latch the 'unavailable' notice")


func test_availability_failure_latches_notice() -> void:
	var gl = _make_gameloop()
	# Park on TITLE so the latch sets but Toast.show is skipped (the TITLE
	# early-out is AFTER the latch is set), keeping the test UI-free.
	gl.current_state = gl.LoopState.TITLE
	gl._on_llm_inference_failed("json", "no ready backend")
	assert_true(gl._llm_notice_shown,
		"a genuine backend-availability failure ('no ready backend') must latch the notice")


func test_other_availability_reasons_latch() -> void:
	for reason in ["request failed or cancelled", "client_timeout"]:
		var gl = _make_gameloop()
		gl.current_state = gl.LoopState.TITLE
		gl._on_llm_inference_failed("text", reason)
		assert_true(gl._llm_notice_shown,
			"availability reason '%s' must latch the notice" % reason)


func test_handler_signature_is_reason_aware() -> void:
	# Source-pin: the second param must be named `reason` (used), not the
	# explicitly-unused `_reason` the pre-fix handler ignored, and the
	# whitelist must be present.
	var file = FileAccess.open(GAMELOOP_PATH, FileAccess.READ)
	assert_not_null(file, "GameLoop.gd should exist")
	var text = file.get_as_text()
	file.close()
	assert_true(text.find("func _on_llm_inference_failed(_mode: String, reason: String)") > -1,
		"handler must take a USED `reason` param (not the pre-fix unused `_reason`)")
	assert_true(text.find("_AVAILABILITY_REASONS") > -1,
		"handler must gate the toast on an availability-reason whitelist")
