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


## ⛔ THESE FOUR ASSERTS USED TO PIN THE IMPLEMENTATION AND SO FORBADE THE FIX.
## They required the loop to call `_resolve_item_display_name(item_id)`, required that wrapper to
## exist, pinned the exact `"%s x%d" % [...]` expression, and required the `is_empty()` branch. Every
## one of those is satisfied ONLY by the Summary keeping its own copy of the formatter — the fourth in
## this lane, and .301 extracted the shared one precisely because a third copy shipped RAW IDS to the
## History screen. A guard that pins a duplicate in place is a guard against consolidating it.
##
## Rewritten to assert the BEHAVIOUR the guard exists for — canonical names, "<Name> x<N>", "None"
## when empty — through the shared formatter that now produces it, plus ONE source assert that the
## Summary calls it. The original defect (a raw-id prettifier) is still banned by name.
func test_the_shared_formatter_renders_canonical_names() -> void:
	assert_eq(AutogrindSystem.format_items_consumed({"potion": 3}), "Potion x3",
		"a single item must render as its canonical name and count")
	assert_eq(AutogrindSystem.format_items_consumed({}), "None",
		"the empty state must read None")
	var many: String = AutogrindSystem.format_items_consumed({"potion": 3, "hi_potion": 1})
	assert_true(many.contains("Potion x3") and many.contains("Hi-Potion x1") and many.contains(", "),
		"multiple items must be comma-joined with canonical names, got '%s'" % many)
	## The original bug: a raw id reaching the player. `potion` lower-case would be the tell.
	assert_false(AutogrindSystem.format_items_consumed({"potion": 1}).begins_with("potion"),
		"a raw item id reached the output — this is the History-screen defect .301 fixed")
	## JSON-loaded snapshots carry floats; the count must not render as "3.0".
	assert_eq(AutogrindSystem.format_items_consumed({"potion": 3.0}), "Potion x3",
		"a float count from a snapshot rendered with a decimal point")


func test_the_summary_uses_the_shared_formatter_and_keeps_no_copy() -> void:
	var body := _build_ui_body()
	assert_true(body.contains("AutogrindSystem.format_items_consumed("),
		"the Summary builds its Items Used row without the shared formatter — that is how the fourth copy got here")
	var src := _read(AUTOGRIND_SUMMARY)
	assert_false(src.contains("func _resolve_item_display_name"),
		"the Summary carries its own name resolver again; ItemNameResolver is reached through the shared formatter")
	assert_false(body.contains("item_id.replace(\"_\", \" \").capitalize()"),
		"old direct prettifier must be gone")


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


## The row's LABEL is still the player-facing contract; the value's shape is asserted above through
## the formatter rather than by pinning an expression. `"value": "None"` and the `is_empty()` branch
## are gone from the Summary on purpose — the shared formatter returns "None" for an empty dict, which
## is the same guarantee with one implementation instead of two.
func test_the_items_used_row_is_still_labelled() -> void:
	var body := _build_ui_body()
	assert_true(body.contains("\"label\": \"Items Used\""),
		"'Items Used' label preserved")
