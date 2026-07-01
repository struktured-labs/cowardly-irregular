extends GutTest

var rc

func before_each() -> void:
	rc = get_node_or_null("/root/RuleComposer")
	assert_not_null(rc, "RuleComposer autoload not available; check project.godot")

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
