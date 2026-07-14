extends GutTest

## tick 187 regression: ShopScene's Buy + Sell menu labels now
## fall back through ItemNameResolver instead of the sentinel
## "???" string. Pre-fix items that EXIST in the shop's
## _get_item_data lookup but lack a "name" field surfaced as
## "??? - 50G" — non-informative noise. Now the resolver tries
## ItemSystem → JobSystem → EquipmentSystem → prettifier so
## the player sees a meaningful name.
##
## Affected sites:
##   - ShopScene Buy menu (line ~213)
##   - ShopScene Sell menu (line ~251)
##
## Audit results for tick 187 scope — clean:
##   - CutsceneDialogue speaker label: cutscene JSON entries
##     use proper-cased names ✓
##   - OverworldNPC / WanderingNPC: @export String npc_name
##     fields with author-set defaults ✓
##   - QuestLog objective text: author-written strings ✓
##   - VillageShop _format_inventory: already uses
##     _resolve_inventory_name (ticks 134-135) ✓
##
## Real impact: tick 184 fixed three MenuScene equipment+items
## sites. ShopScene was the symmetric SHOP-side gap — players
## browsing the shop saw "???" for any item the shop ID-mapped
## to a missing-name entry. Now consistent with menu treatment.

const SHOP_SCENE := "res://src/exploration/ShopScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Buy menu ────────────────────────────────────────────────────────────

func test_buy_menu_uses_resolver_fallback() -> void:
	var src := _read(SHOP_SCENE)
	# Pin: Buy menu line ~213's label format uses ItemNameResolver
	# fallback in place of the "???" sentinel.
	assert_true(src.contains("var label = \"%s - %dG\" % [item_data.get(\"name\", ItemNameResolver.resolve(item_id)), cost]"),
		"Buy menu must use ItemNameResolver fallback instead of '???' sentinel")


# ── Sell menu ───────────────────────────────────────────────────────────

func test_sell_menu_uses_resolver_fallback() -> void:
	var src := _read(SHOP_SCENE)
	# Pin: Sell menu line ~251 (with quantity).
	assert_true(src.contains("var label = \"%s - %dG (x%d)\" % [item_data.get(\"name\", ItemNameResolver.resolve(item_id)), sell_price, quantity]"),
		"Sell menu must use ItemNameResolver fallback (preserve x%d quantity format)")


# ── Negative pins: "???" sentinel paths gone ──────────────────────────

func test_old_question_mark_sentinel_paths_gone() -> void:
	var src := _read(SHOP_SCENE)
	# Negative: the specific old shape with "???" must be gone.
	# (Other "???" usages may legitimately exist elsewhere for
	# empty/none cases, but the item-data fallback specifically
	# is replaced.)
	assert_false(src.contains("item_data.get(\"name\", \"???\"), cost"),
		"Buy menu's old '???' sentinel fallback must be gone")
	assert_false(src.contains("item_data.get(\"name\", \"???\"), sell_price"),
		"Sell menu's old '???' sentinel fallback must be gone")


# ── Cross-pins: clean fallback sites preserved ─────────────────────────

func test_village_shop_resolver_preserved() -> void:
	# VillageShop's _resolve_inventory_name (ticks 134-135) still
	# in place — was the parity reference for this fix.
	var vs: String = FileAccess.get_file_as_string("res://src/exploration/VillageShop.gd")
	assert_true(vs.contains("_resolve_inventory_name(items[i])"),
		"VillageShop._format_inventory's _resolve_inventory_name preserved")


func test_menu_scene_resolver_pattern_preserved() -> void:
	# Tick 184's MenuScene resolver fallbacks preserved — parity
	# with the shop fix.
	var ms: String = FileAccess.get_file_as_string("res://src/ui/MenuScene.gd")
	assert_true(ms.contains("ItemNameResolver.resolve(item_id)"),
		"tick 184 MenuScene resolver fallback pattern preserved")


func test_format_skeleton_preserved() -> void:
	# Don't regress the label format itself ("X - Ng" / "X - Ng (xN)").
	var src := _read(SHOP_SCENE)
	assert_true(src.contains("\"%s - %dG\""),
		"Buy menu format string '%s - %dG' preserved")
	assert_true(src.contains("\"%s - %dG (x%d)\""),
		"Sell menu format string '%s - %dG (x%d)' preserved")
