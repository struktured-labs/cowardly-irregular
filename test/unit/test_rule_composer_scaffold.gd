extends GutTest

var rc
var svc

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
	assert_not_null(rc, "RuleComposer autoload not available; check project.godot")
	assert_not_null(svc, "LLMService autoload not available; check project.godot")

func test_domain_constants_exposed() -> void:
	assert_eq(rc.DOMAIN_AUTOBATTLE, "autobattle")
	assert_eq(rc.DOMAIN_AUTOGRIND, "autogrind")

func test_signals_declared() -> void:
	assert_true(rc.has_signal("composition_ready"))
	assert_true(rc.has_signal("composition_failed"))

func test_has_llm_returns_bool() -> void:
	var v: Variant = rc.has_llm()
	assert_eq(typeof(v), TYPE_BOOL, "has_llm() must return a bool, not: %s" % [v])

func test_compose_async_returns_dict_shape() -> void:
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "test", "cleric", [])
	assert_true(result.has("name"))
	assert_true(result.has("description"))
	assert_true(result.has("rules"))
	assert_true(result.has("source"))
	assert_true(result.has("errors"))
	assert_true(result.has("domain"))
	assert_true(result.has("character_id"))
