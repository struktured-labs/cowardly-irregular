extends GutTest

## We cannot flip OS.has_feature("web") in-process; instead we exercise the
## has_llm() branches indirectly by disabling the LLM service.

var rc
var svc

func before_each() -> void:
	rc = get_node_or_null("/root/RuleComposer")
	svc = get_node_or_null("/root/LLMService")

func test_has_llm_false_when_service_disabled() -> void:
	var restore: bool = svc.llm_enabled
	svc.llm_enabled = false
	assert_false(rc.has_llm(), "has_llm must be false when LLMService.llm_enabled is false")
	svc.llm_enabled = restore

func test_compose_async_falls_back_when_llm_off() -> void:
	watch_signals(rc)
	var restore: bool = svc.llm_enabled
	svc.llm_enabled = false
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "anything", "mage", [])
	assert_eq(result.get("source", ""), "fallback")
	assert_signal_emitted_with_parameters(rc, "composition_failed", ["no_llm", {}])
	svc.llm_enabled = restore
