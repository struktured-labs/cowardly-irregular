extends GutTest

## tick 257: ShopScene → VillageShop item_purchased signal bridge.
##
## Pre-fix VillageShop had no public signal at all — purchase events
## lived purely inside ShopScene, so quest hooks / achievements / the
## tick 250 first_magic_shop_visited event flag had to reach into the
## inner ShopScene to listen. Now VillageShop exposes the same signal
## and bridges from ShopScene's emit.
##
## Pins:
##   - both classes declare item_purchased(item_id, cost)
##   - ShopScene.item_purchased fires on successful purchase (signal
##     declared with the right parameter shape)
##   - VillageShop has the bridge handler


const SHOP_SCENE := "res://src/exploration/ShopScene.gd"
const VILLAGE_SHOP := "res://src/exploration/VillageShop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Both classes declare the signal ────────────────────────────────

func test_shop_scene_declares_item_purchased_signal() -> void:
	var src := _read(SHOP_SCENE)
	assert_true(src.contains("signal item_purchased(item_id: String, cost: int)"),
		"ShopScene must declare signal item_purchased(item_id, cost)")


func test_village_shop_declares_item_purchased_signal() -> void:
	var src := _read(VILLAGE_SHOP)
	assert_true(src.contains("signal item_purchased(item_id: String, cost: int)"),
		"VillageShop must declare matching signal item_purchased(item_id, cost)")


# ── Runtime: signals exist on instances ────────────────────────────

func test_shop_scene_instance_has_signal() -> void:
	var script: GDScript = load(SHOP_SCENE)
	var inst: Object = script.new()
	add_child_autofree(inst)
	assert_true(inst.has_signal("item_purchased"),
		"ShopScene instance must expose item_purchased signal at runtime")


func test_village_shop_instance_has_signal() -> void:
	var script: GDScript = load(VILLAGE_SHOP)
	var inst: Object = script.new()
	add_child_autofree(inst)
	assert_true(inst.has_signal("item_purchased"),
		"VillageShop instance must expose item_purchased signal at runtime")


# ── Bridge wiring: VillageShop hooks ShopScene's signal ────────────

func test_village_shop_connects_to_shop_scene_signal() -> void:
	var src := _read(VILLAGE_SHOP)
	assert_true(src.contains("shop_scene.item_purchased.connect"),
		"VillageShop must connect to spawned ShopScene's item_purchased signal")
	assert_true(src.contains("func _on_shop_item_purchased"),
		"VillageShop must define _on_shop_item_purchased bridge handler")
	# Bridge re-emits as VillageShop's own signal
	assert_true(src.contains("item_purchased.emit(item_id, cost)"),
		"bridge handler must re-emit VillageShop.item_purchased(item_id, cost)")


# ── ShopScene emits only on successful purchase (not refund path) ──

func test_shop_scene_emits_only_after_successful_handoff() -> void:
	# Pin: emit happens AFTER _add_item_to_inventory returns true. If
	# we emitted on gold-spend without checking the handoff, a refunded
	# transaction would still fire the signal — quest hooks would fire
	# spuriously and gold-spend metrics would diverge from inventory.
	var src := _read(SHOP_SCENE)
	var emit_idx: int = src.find("item_purchased.emit(item_id, cost)")
	var refund_idx: int = src.find("game_state.add_gold(cost)  # Refund")
	assert_gt(emit_idx, -1, "ShopScene must emit item_purchased somewhere")
	assert_gt(refund_idx, -1, "ShopScene must still have the refund path")
	assert_gt(emit_idx, refund_idx,
		"item_purchased.emit MUST come AFTER the refund-path early return so refunded transactions don't spuriously fire")
