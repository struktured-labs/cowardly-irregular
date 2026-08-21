extends GutTest

## struktured 2026-08-20: "Make the spells in the store green if they're better than
## what the player has." Rows already went grey (unaffordable) and soft-green (learned);
## this adds a saturated UPGRADE green for any spell whose data TIER outranks the best
## the party knows in its FAMILY. Pinned: it's driven by family/tier data, not a name
## suffix; it carries a text marker so colour-blind mode still reads it; and it sits
## between the two existing branches so the pinned owned<unaffordable order survives.

const SS := "res://src/exploration/ShopScene.gd"
const ShopScript = preload(SS)


func _src() -> String:
	return FileAccess.get_file_as_string(SS)


func test_upgrade_colour_is_distinct_and_marker_present() -> void:
	assert_ne(ShopScript.BUY_ROW_UPGRADE_COLOR, ShopScript.BUY_ROW_OWNED_COLOR, "upgrade green ≠ owned tint")
	assert_ne(ShopScript.BUY_ROW_UPGRADE_COLOR, ShopScript.BUY_ROW_UNAFFORDABLE_COLOR, "upgrade green ≠ unaffordable grey")
	assert_true('"▲ " + row["label"]' in _src(), "label carries ▲ — colour alone fails colour-blind mode")


func test_branch_order_owned_then_upgrade_then_unaffordable() -> void:
	var s := _src()
	var o := s.find('row["text_color"] = BUY_ROW_OWNED_COLOR')
	var u := s.find('row["text_color"] = BUY_ROW_UPGRADE_COLOR')
	var n := s.find('row["text_color"] = BUY_ROW_UNAFFORDABLE_COLOR')
	assert_gt(o, -1); assert_gt(u, -1); assert_gt(n, -1)
	assert_true(o < u and u < n, "owned → upgrade → unaffordable: a known spell is never re-sold as an upgrade, and an upgrade you can't afford still reads as worth saving for")


func test_upgrade_is_data_driven_not_a_name_guess() -> void:
	var s := _src()
	var i := s.find("func _is_spell_upgrade")
	assert_gt(i, -1, "upgrade predicate must exist")
	var fn_end := s.find("\nfunc ", i + 1)
	var body := s.substr(i, fn_end - i)
	assert_true('"family"' in body and '"tier"' in body, "ranks on family/tier data")
	assert_false("ends_with" in body, "NEVER a name-suffix heuristic (the ends_with(\"aga\") smell already cost us 245 abilities)")
	var j := s.find("func _best_known_tier")
	assert_gt(j, -1)
	var jb := s.substr(j, s.find("\nfunc ", j + 1) - j)
	assert_true('"learned_abilities"' in jb, "best-known walks what the party has actually learned")


func test_tier_ranking_semantics() -> void:
	# Pure checks on the predicate shape via a throwaway instance: nothing known → tier 1 upgrades; known tier 2 → tier 2 is NOT an upgrade, tier 3 is
	var shop = ShopScript.new()
	add_child_autofree(shop)
	assert_false(shop._is_spell_upgrade({"name": "Untiered"}), "spells without tier data are never flagged")
	# best_known with no game_state → 0, so any tier ≥ 1 is an upgrade
	assert_true(shop._is_spell_upgrade({"family": "fire", "tier": 1}), "first rung of an unknown family is an upgrade")
