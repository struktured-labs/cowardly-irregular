extends GutTest

## We cannot flip OS.has_feature("web") in-process; instead we exercise the
## has_llm() branches indirectly by disabling the LLM service.

var rc
var svc
var _orig_enabled: bool = true

func before_each() -> void:
	var root := get_tree().root
	rc = root.get_node_or_null("RuleComposer")
	if rc == null:  # survives a freed autoload from an earlier contaminating test
		rc = preload("res://src/llm/RuleComposer.gd").new()
		rc.name = "RuleComposer"
		root.add_child(rc)
	svc = root.get_node_or_null("LLMService")
	if svc == null:  # has_llm()/compose_async look this up by absolute path
		svc = preload("res://src/llm/LLMService.gd").new()
		svc.name = "LLMService"
		root.add_child(svc)
	_orig_enabled = svc.llm_enabled

func after_each() -> void:
	if svc != null:
		svc.llm_enabled = _orig_enabled  # never free svc — leaving it heals later tests too

func test_has_llm_false_when_service_disabled() -> void:
	svc.llm_enabled = false
	assert_false(rc.has_llm(), "has_llm must be false when LLMService.llm_enabled is false")

func test_compose_async_falls_back_when_llm_off() -> void:
	watch_signals(rc)
	svc.llm_enabled = false
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "anything", "mage", [])
	assert_eq(result.get("source", ""), "fallback")
	assert_signal_emitted_with_parameters(rc, "composition_failed", ["no_llm", {}])
