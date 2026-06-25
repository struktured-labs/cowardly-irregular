extends GutTest

## tick 131 + tick 135 regression: AutogrindSummary's items-consumed
## list delegates through the shared ItemNameResolver.

const AUTOGRIND_SUMMARY := "res://src/ui/autogrind/AutogrindSummary.gd"
const RESOLVER := "res://src/items/ItemNameResolver.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _build_ui_body() -> String:
	var src := _read(AUTOGRIND_SUMMARY)
	var idx: int = src.find("func _build_ui")
	assert_gt(idx, -1, "_build_ui must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_items_consumed_loop_uses_resolver() -> void:
	var body := _build_ui_body()
	assert_true(body.contains("_resolve_item_display_name(item_id)"),
		"items_consumed loop must call _resolve_item_display_name")
	assert_false(body.contains("item_id.replace(\"_\", \" \").capitalize()"),
		"old direct prettifier must be gone")


func test_local_resolver_delegates_to_shared() -> void:
	var src := _read(AUTOGRIND_SUMMARY)
	var idx: int = src.find("func _resolve_item_display_name")
	assert_gt(idx, -1, "wrapper must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("ItemNameResolver.resolve(item_id)"),
		"local helper must delegate to shared ItemNameResolver.resolve")


func test_shared_resolver_prefers_item_system() -> void:
	var src := _read(RESOLVER)
	assert_true(src.contains("get_node_or_null(\"ItemSystem\")"),
		"shared resolver must look up ItemSystem first")
	assert_true(src.contains("item_sys.get_item(item_id)"),
		"shared resolver must call ItemSystem.get_item(item_id)")
	assert_true(src.contains("data.has(\"name\")"),
		"shared resolver must guard on data.has('name')")


func test_shared_resolver_fallback_uses_prettifier() -> void:
	var src := _read(RESOLVER)
	assert_true(src.contains("return item_id.replace(\"_\", \" \").capitalize()"),
		"shared resolver fallback must use prettifier")


func test_shared_resolver_empty_id_returns_empty_string() -> void:
	var src := _read(RESOLVER)
	assert_true(src.contains("if item_id == \"\":\n\t\treturn \"\""),
		"shared resolver must short-circuit on empty input")


func test_existing_items_used_format_preserved() -> void:
	var body := _build_ui_body()
	assert_true(body.contains("\"%s x%d\" % [_resolve_item_display_name(item_id), items_consumed[item_id]]"),
		"items_consumed format must remain '%s x%d'")
	assert_true(body.contains("\"label\": \"Items Used\""),
		"'Items Used' label preserved")
	assert_true(body.contains("\"value\": \"None\""),
		"'None' empty state preserved")


func test_resolver_isnt_called_with_no_items_consumed() -> void:
	var body := _build_ui_body()
	assert_true(body.contains("if not items_consumed.is_empty():"),
		"items_consumed loop must be guarded on is_empty")
