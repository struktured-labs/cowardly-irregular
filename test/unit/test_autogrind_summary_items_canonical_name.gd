extends GutTest

## tick 131 regression: AutogrindSummary's items-consumed list must
## prefer ItemSystem's canonical display name over the raw
## prettifier. Pre-fix, the autogrind session-end summary surfaced
## "Hi Potion x3" instead of the canonical "Hi-Potion x3" (with
## hyphen) — mismatches the in-game-text in the item menu / battle
## log / inventory for the same item.
##
## Mirror of tick 130's BestiaryMenu fix. Autogrind doesn't track
## equipment use (items_consumed is consumables-only), so no
## EquipmentSystem branch needed.

const AUTOGRIND_SUMMARY := "res://src/ui/autogrind/AutogrindSummary.gd"


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


func _resolver_body() -> String:
	var src := _read(AUTOGRIND_SUMMARY)
	var idx: int = src.find("func _resolve_item_display_name")
	assert_gt(idx, -1, "_resolve_item_display_name must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_items_consumed_loop_uses_resolver() -> void:
	# Pin: the loop calls _resolve_item_display_name, not the raw
	# prettifier.
	var body := _build_ui_body()
	assert_true(body.contains("_resolve_item_display_name(item_id)"),
		"items_consumed loop must call _resolve_item_display_name — uses canonical names from ItemSystem")
	# Negative pin: the OLD direct prettifier path must be gone.
	assert_false(body.contains("item_id.replace(\"_\", \" \").capitalize()"),
		"old direct `item_id.replace('_', ' ').capitalize()` must be gone — replaced by the resolver")


func test_resolver_prefers_item_system() -> void:
	# Pin: ItemSystem lookup is the first-choice resolution path.
	var body := _resolver_body()
	assert_true(body.contains("get_node_or_null(\"/root/ItemSystem\")"),
		"resolver must look up ItemSystem first")
	assert_true(body.contains("item_sys.get_item(item_id)"),
		"resolver must call ItemSystem.get_item(item_id)")
	assert_true(body.contains("data.has(\"name\")"),
		"resolver must guard on data.has('name') before reading the canonical name")


func test_resolver_fallback_uses_prettifier() -> void:
	# Pin: fallback path when ItemSystem doesn't resolve the id.
	var body := _resolver_body()
	assert_true(body.contains("return item_id.replace(\"_\", \" \").capitalize()"),
		"resolver fallback must use replace+capitalize — graceful for debug/custom items")


func test_resolver_empty_id_returns_empty_string() -> void:
	# Defensive: empty item_id no-ops.
	var body := _resolver_body()
	assert_true(body.contains("if item_id == \"\":\n\t\treturn \"\""),
		"resolver must short-circuit on empty input")


func test_existing_items_used_format_preserved() -> void:
	# Don't regress the format string "X x3" or the "Items Used"
	# label / "None" empty-state.
	var body := _build_ui_body()
	assert_true(body.contains("\"%s x%d\" % [_resolve_item_display_name(item_id), items_consumed[item_id]]"),
		"items_consumed format must remain '%s x%d' with the new resolver in the name slot")
	assert_true(body.contains("\"label\": \"Items Used\""),
		"'Items Used' label preserved")
	assert_true(body.contains("\"value\": \"None\""),
		"'None' empty state preserved")


func test_resolver_isnt_called_with_no_items_consumed() -> void:
	# Pin the if/else structure — when items_consumed is empty, we
	# show "None" and don't iterate. Important because resolver does
	# a /root lookup per call; iterating an empty dict would still
	# be fine but the if/else is clearer.
	var body := _build_ui_body()
	assert_true(body.contains("if not items_consumed.is_empty():"),
		"items_consumed loop must be guarded on is_empty — show 'None' otherwise")


func test_bestiary_resolver_pattern_still_present() -> void:
	# Cross-check: tick 130's bestiary resolver still exists. Both
	# files implement the SAME helper independently; this isn't
	# duplication because they have different fallback paths
	# (bestiary checks EquipmentSystem too).
	var bestiary_src := _read("res://src/ui/BestiaryMenu.gd")
	assert_true(bestiary_src.contains("func _resolve_item_display_name"),
		"tick 130's bestiary resolver must still exist — both files have their own (intentional, different fallbacks)")
