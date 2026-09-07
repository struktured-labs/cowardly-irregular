extends GutTest

## Regression coverage for the effects-driven Iron Vigil heal classifier.
## Pre-fix _track_item_consumed used a hardcoded 6-item list — a new healing item
## added to items.json would silently NOT break the battles_without_heal streak,
## making the achievement earnable while chugging the new potion variant.

var _system: Node


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true  # Prevent test writes to user://autogrind/*.json (leaked TestChar0 into struktured's save, 2026-07-14)
	_system.battles_without_heal = 10
	_system.items_consumed.clear()


func test_potion_breaks_streak() -> void:
	_system._track_item_consumed("potion")
	assert_eq(_system.battles_without_heal, 0, "heal_hp item must reset the streak")


func test_ether_breaks_streak() -> void:
	_system._track_item_consumed("ether")
	assert_eq(_system.battles_without_heal, 0, "heal_mp item must reset the streak")


func test_phoenix_down_breaks_streak_via_revive() -> void:
	# phoenix_down is category CURATIVE, not CONSUMABLE — classification must key
	# off effects (revive/heal_hp_percent), not category, or this regresses.
	_system._track_item_consumed("phoenix_down")
	assert_eq(_system.battles_without_heal, 0, "revive item must reset the streak")


func test_non_heal_item_preserves_streak() -> void:
	# antidote is category CURATIVE like phoenix_down but has only cure_status —
	# it proves classification keys off EFFECTS, not category. Streak = "no
	# restoration", and curing poison is not restoration.
	var item_system: Node = get_tree().root.get_node_or_null("ItemSystem")
	if item_system == null or item_system.get_item("antidote").is_empty():
		pass_test("antidote not in database; classifier falls back to hardcoded set")
		return
	_system._track_item_consumed("antidote")
	_system._track_item_consumed("remedy")
	assert_eq(_system.battles_without_heal, 10,
		"Status-cure items (antidote/remedy) must NOT reset the Iron Vigil streak")


func test_unknown_item_preserves_streak_without_crash() -> void:
	_system._track_item_consumed("definitely_not_an_item_xyz")
	assert_eq(_system.battles_without_heal, 10,
		"Unknown item id must neither crash nor reset the streak")


func test_consumption_still_tracked_regardless_of_classification() -> void:
	_system._track_item_consumed("potion")
	_system._track_item_consumed("definitely_not_an_item_xyz")
	assert_eq(int(_system.items_consumed.get("potion", 0)), 1)
	assert_eq(int(_system.items_consumed.get("definitely_not_an_item_xyz", 0)), 1,
		"items_consumed bookkeeping is independent of heal classification")


func test_every_hardcoded_legacy_item_still_classifies_as_healing() -> void:
	# The old hardcoded set defined the semantics; the effects-driven classifier
	# must be a superset of it, never a narrowing.
	for legacy_id in ["potion", "hi_potion", "mega_potion", "ether", "hi_ether", "phoenix_down"]:
		assert_true(_system._is_healing_item(legacy_id),
			"Legacy heal item '%s' must still classify as healing under the effects-driven path" % legacy_id)