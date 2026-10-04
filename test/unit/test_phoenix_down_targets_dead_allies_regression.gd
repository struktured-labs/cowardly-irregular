extends GutTest

## Playtest 2026-07-13: Fighter couldn't use Phoenix Down on KO'd party.
## BattleCommandMenu's SINGLE_ALLY branch filtered out `not member.is_alive`
## unconditionally — silently dropped every KO'd target, so revive items had
## an empty target list ("cant use phoenix down on KO'ed players (which is
## whole point)"). Fix: include KO'd allies when the item's
## effects.revive is truthy.


func test_ally_filter_includes_dead_when_item_has_revive_effect() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	var i := src.find("if target_type == ItemSystem.TargetType.SINGLE_ALLY:")
	assert_gt(i, -1)
	var body := src.substr(i, 900)
	assert_true("_item_allows_any_ally_target" in body,
		"SINGLE_ALLY branch must consult _item_allows_any_ally_target (item.effects.revive/heal/cure) to decide whether KO'd allies are eligible")
	assert_true("can_target_any" in body,
		"there must be a can_target_any gate — plain `not is_alive: continue` silently drops every revive/heal item's target list")
	assert_true("not member.is_alive and not can_target_any" in body,
		"filter must be conditional on revive/heal capability — the whole point of a revive item is to target dead allies")
	var helper_idx := src.find("func _item_allows_any_ally_target(")
	assert_gt(helper_idx, -1, "_item_allows_any_ally_target must exist")
	var helper_body := src.substr(helper_idx, maxi(0, src.find("\nfunc ", helper_idx + 1) - helper_idx))
	assert_true("effects" in helper_body and "revive" in helper_body,
		"the helper must still read item.effects.revive")
	# UX: KO'd allies should display as "KO'd" not "0/HP" so the target menu reads correctly.
	## Each ally row is built by _item_ally_row (it also carries the ~+N heal quote), so the label lives there.
	assert_true("_item_ally_row(item_id, member, i)" in body,
		"the SINGLE_ALLY branch must build each row through _item_ally_row")
	var r := src.find("func _item_ally_row(")
	assert_gt(r, -1, "_item_ally_row must exist")
	var row_body := src.substr(r, maxi(0, src.find("\nfunc ", r + 1) - r))
	assert_true("\"KO'd\"" in row_body,
		"KO'd targets need a clear label (not '0/N HP') so the target picker is legible")


func test_phoenix_down_item_data_is_revive_shaped() -> void:
	# Anti-regression on the item data: someone dropping effects.revive from
	# phoenix_down would re-open the bug via a different door.
	var items = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	var pd: Dictionary = items.get("phoenix_down", {})
	assert_true(pd.has("effects") and pd["effects"].get("revive", false),
		"phoenix_down.effects.revive must be true — the SINGLE_ALLY dead-eligibility filter reads this")
