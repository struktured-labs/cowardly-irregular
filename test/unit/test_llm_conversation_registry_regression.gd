extends GutTest

## Regression: a scene-change must abort live DynamicConversations, not just
## cancel their in-flight LLM requests. Before this fix nothing called
## DynamicConversation.abort() so the choice menu + frozen player could remain
## on screen after the player walked through an area transition.


class DummyConv:
	extends Node
	var aborted: bool = false
	func abort() -> void:
		aborted = true


func test_register_and_abort_all() -> void:
	var svc_script = load("res://src/llm/LLMService.gd")
	var svc: Node = svc_script.new()
	autofree(svc)
	# Ensure the registry array exists without firing _ready (no autoload bootstrap).
	if not ("_active_conversations" in svc):
		fail_test("LLMService is expected to declare _active_conversations")
		return
	svc._active_conversations = []
	var a := DummyConv.new()
	var b := DummyConv.new()
	autofree(a)
	autofree(b)
	svc.register_conversation(a)
	svc.register_conversation(b)
	# Idempotent — duplicate register is a no-op.
	svc.register_conversation(a)
	assert_eq(svc._active_conversations.size(), 2,
		"duplicate register must be deduped")
	svc.abort_all_conversations()
	assert_true(a.aborted, "abort() must have been called on every registered conv")
	assert_true(b.aborted, "abort() must have been called on every registered conv")
	assert_eq(svc._active_conversations.size(), 0, "registry must be cleared after abort_all")


func test_unregister_keeps_others() -> void:
	var svc_script = load("res://src/llm/LLMService.gd")
	var svc: Node = svc_script.new()
	autofree(svc)
	svc._active_conversations = []
	var a := DummyConv.new()
	var b := DummyConv.new()
	autofree(a)
	autofree(b)
	svc.register_conversation(a)
	svc.register_conversation(b)
	svc.unregister_conversation(a)
	svc.abort_all_conversations()
	assert_false(a.aborted, "a was unregistered — must NOT be aborted")
	assert_true(b.aborted, "b must still be aborted")


func test_inference_succeeded_signal_exists() -> void:
	var svc_script = load("res://src/llm/LLMService.gd")
	var svc: Node = svc_script.new()
	autofree(svc)
	assert_true(svc.has_signal("inference_succeeded"),
		"LLMService must emit inference_succeeded so GameLoop can toast 'Dynamic dialogue active'")
