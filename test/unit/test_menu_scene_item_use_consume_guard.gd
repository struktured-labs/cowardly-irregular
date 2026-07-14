extends GutTest

## tick 190 regression: MenuScene._on_item_use_pressed now only
## consumes the item when ItemSystem.use_item succeeds. Pre-fix
## the bool return was ignored — if use_item returned false
## (unknown item_id, item has no "effects" field, save-format
## drift, Scriptweaver custom items removed from items.json),
## the item was STILL removed from inventory but no effect
## applied. Player lost a Potion for nothing.
##
## Parity with the existing handling in:
##   - ItemsMenu._handle_item_use (line ~698): if/erase pattern
##   - BattleManager._execute_item (line ~3372): if/remove_item pattern
##
## MenuScene was the third path and the only one with the gap.
## Tick 181's push_warning at the ItemSystem side already tells
## the dev WHY use_item failed; tick 190's MenuScene-side warning
## tells WHERE in the UI the call was made.

const MENU_SCENE := "res://src/ui/MenuScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _item_use_body() -> String:
	var src := _read(MENU_SCENE)
	var idx: int = src.find("func _on_item_use_pressed")
	assert_gt(idx, -1, "_on_item_use_pressed must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


# ── Guard pattern ──────────────────────────────────────────────────────

func test_use_item_return_value_is_checked() -> void:
	var body := _item_use_body()
	# Pin: use_item is wrapped in an if-check, not called bare.
	assert_true(body.contains("if ItemSystem.use_item(source_member, item_id, [member]):"),
		"_on_item_use_pressed must check ItemSystem.use_item return value")


func test_remove_item_only_runs_on_use_success() -> void:
	var body := _item_use_body()
	# Pin: remove_item is INSIDE the success branch (no bare call).
	# We verify there's exactly one remove_item call AND it's
	# preceded within 100 chars by the use_item if-check.
	var remove_idx: int = body.find("source_member.remove_item(item_id, 1)")
	assert_gt(remove_idx, -1, "remove_item call must still exist for success path")
	# Look backward for the use_item if-check.
	var pre_window: String = body.substr(max(0, remove_idx - 200), 200)
	assert_true(pre_window.contains("if ItemSystem.use_item"),
		"remove_item must be inside the use_item success branch (within 200 chars before)")


func test_failure_branch_pushes_warning() -> void:
	var body := _item_use_body()
	# Pin: failure branch surfaces via push_warning.
	assert_true(body.contains("push_warning(\"[MenuScene] _on_item_use_pressed: ItemSystem.use_item"),
		"failure branch must push_warning")
	assert_true(body.contains("item NOT consumed"),
		"warning must state the consequence: 'item NOT consumed'")


func test_warning_includes_item_id_and_user_name() -> void:
	var body := _item_use_body()
	# Pin: warning surfaces both the failing item_id AND the user's
	# combatant_name so devs can correlate with save state.
	assert_true(body.contains("failed for %s"),
		"warning must include user combatant_name")
	assert_true(body.contains("ItemSystem.use_item('%s')"),
		"warning must include the failed item_id")


# ── Negative pins: pre-fix shape gone ──────────────────────────────────

func test_old_unconditional_consume_pattern_gone() -> void:
	var body := _item_use_body()
	# Negative pin: the bare use_item-then-remove sequence must
	# be gone. (If it returns the body contains both lines
	# back-to-back with no if-check between them.)
	var bad_pattern := "ItemSystem.use_item(source_member, item_id, [member])\n\t\tsource_member.remove_item(item_id, 1)"
	assert_false(body.contains(bad_pattern),
		"old unconditional consume pattern must be gone (use_item followed by remove_item with no guard)")


# ── Cross-pin: parity sites preserved ──────────────────────────────────

func test_items_menu_parity_preserved() -> void:
	# ItemsMenu uses an if/erase pattern — the parity reference.
	var im: String = FileAccess.get_file_as_string("res://src/ui/ItemsMenu.gd")
	assert_true(im.contains("if ItemSystem and ItemSystem.use_item(user, item.get(\"id\", \"\"), targets):"),
		"ItemsMenu's if-checked use_item parity site preserved")


func test_battle_manager_parity_preserved() -> void:
	# BattleManager wraps use_item in an if-check (tick 184).
	var bm: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(bm.contains("if ItemSystem and ItemSystem.use_item(user, item_id, retargeted):"),
		"BattleManager._execute_item's if-checked use_item parity site preserved")


# ── Cross-pin: tick 181 ItemSystem warnings still emit cause ──────────

func test_tick_181_item_system_warnings_preserved() -> void:
	# Tick 181's ItemSystem-side push_warning still in place — tells
	# WHY the use failed (unknown id / no effects). MenuScene's
	# warning tells WHERE (which UI call site).
	var is_src: String = FileAccess.get_file_as_string("res://src/items/ItemSystem.gd")
	assert_true(is_src.contains("push_warning(\"[ItemSystem] use_item: item_id"),
		"tick 181 ItemSystem unknown-id warning preserved")
	assert_true(is_src.contains("push_warning(\"[ItemSystem] use_item: item '%s' has no 'effects' field"),
		"tick 181 ItemSystem no-effects warning preserved")
