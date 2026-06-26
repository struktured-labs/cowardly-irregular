extends GutTest

## tick 184 regression: MenuScene's equipment + item display now
## uses ItemNameResolver for the unknown-id fallback. Pre-fix
## three sites in MenuScene fell back to raw `item_id` (snake_case
## leak) when EquipmentSystem/ItemSystem didn't know the id —
## same class as tick 140's EquipmentMenu fix.
##
## Also: BattleManager._execute_item's "doesn't have item" path
## now emits to battle_log so the player sees feedback when
## autobattle scripts hit an empty inventory mid-grind. Pre-fix
## print() only — character's turn silently wasted.
##
## Consumer-side audit results:
##   - EquipmentMenu uses ItemNameResolver (tick 140) ✓
##   - CutsceneDirector uses is_empty + push_warning (tick 145) ✓
##   - BattleCommandMenu uses is_empty + continue (line 205) ✓
##   - BattleScene uses is_empty + continue (line 1787) ✓
##   - BattleManager line 3332 uses defensive .get with default ✓
##
## Three sites in MenuScene + one BattleManager log fixed.

const MENU_SCENE := "res://src/ui/MenuScene.gd"
const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── MenuScene equipment + item display ──────────────────────────────────

func test_equipment_display_uses_resolver() -> void:
	# Pin: _get_equipment_name (line ~395) uses ItemNameResolver.
	var src := _read(MENU_SCENE)
	assert_true(src.contains("return item.get(\"name\", ItemNameResolver.resolve(item_id))"),
		"_get_equipment_name must use ItemNameResolver.resolve for unknown ids")
	assert_true(src.contains("return ItemNameResolver.resolve(item_id)"),
		"_get_equipment_name's empty-item fallback must also use resolver")


func test_available_equipment_view_uses_resolver() -> void:
	# Pin: line ~533 falls back via resolver.
	var src := _read(MENU_SCENE)
	assert_true(src.contains("var item_name = item.get(\"name\", ItemNameResolver.resolve(item_id)) if item.size() > 0 else ItemNameResolver.resolve(item_id)"),
		"available-equipment view must use ItemNameResolver for both branches of the size check")


func test_items_view_uses_resolver() -> void:
	# Pin: line ~981 falls back via resolver for the inventory view.
	var src := _read(MENU_SCENE)
	assert_true(src.contains("var item_name = item.get(\"name\", ItemNameResolver.resolve(item_id)) if item else ItemNameResolver.resolve(item_id)"),
		"items view must use ItemNameResolver for both truthy/falsy branches")


func test_old_raw_id_fallbacks_gone() -> void:
	# Negative pin: old raw-id fallbacks must be removed.
	var src := _read(MENU_SCENE)
	# The simple `return item_id` from _get_equipment_name's bottom.
	assert_false(src.contains("if item and item.size() > 0:\n\t\treturn item.get(\"name\", item_id)\n\treturn item_id"),
		"old raw-id fallback in _get_equipment_name must be gone")


# ── BattleManager _execute_item missing-item path ──────────────────────

func test_missing_item_emits_battle_log() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=gray]%s has no %s left.[/color]"),
		"_execute_item missing-item path must emit battle_log")


func test_missing_item_log_uses_prettified_id() -> void:
	# Pin: snake_case → Title Case prettifier on item_id.
	var src := _read(BATTLE_MANAGER)
	# The prettifier expression should be near the new battle_log emit.
	assert_true(src.contains("var item_display: String = item_id.replace(\"_\", \" \").capitalize()"),
		"item_display must use the standard prettifier (snake_case → Title Case)")


func test_missing_item_print_preserved() -> void:
	# Non-regression: print() preserved for debug overlay.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("print(\"%s doesn't have item: %s\""),
		"_execute_item missing-item print preserved for debug overlay")


# ── Cross-pin: existing tick 140 / 145 patterns preserved ──────────────

func test_equipment_menu_resolver_pattern_preserved() -> void:
	var em := _read("res://src/ui/EquipmentMenu.gd")
	assert_true(em.contains("ItemNameResolver.resolve(equipped_id)"),
		"tick 140's EquipmentMenu resolver pattern preserved")


func test_cutscene_director_orphan_warning_preserved() -> void:
	var cd := _read("res://src/cutscene/CutsceneDirector.gd")
	assert_true(cd.contains("push_warning(\"CutsceneDirector: item '%s' not defined in items.json"),
		"tick 145's CutsceneDirector orphan-item warning preserved")
