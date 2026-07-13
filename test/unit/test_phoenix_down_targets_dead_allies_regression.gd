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
	assert_true("effects" in body and "revive" in body,
		"SINGLE_ALLY branch must consult item.effects.revive to decide whether KO'd allies are eligible")
	assert_true("can_target_dead" in body,
		"there must be a can_target_dead gate — plain `not is_alive: continue` silently drops every revive item's target list")
	assert_true("not member.is_alive and not can_target_dead" in body,
		"filter must be conditional on revive capability — the whole point of a revive item is to target dead allies")
	# UX: KO'd allies should display as "KO'd" not "0/HP" so the target menu reads correctly.
	assert_true("\"KO'd\"" in body,
		"KO'd targets need a clear label (not '0/N HP') so the target picker is legible")


func test_phoenix_down_item_data_is_revive_shaped() -> void:
	# Anti-regression on the item data: someone dropping effects.revive from
	# phoenix_down would re-open the bug via a different door.
	var items = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	var pd: Dictionary = items.get("phoenix_down", {})
	assert_true(pd.has("effects") and pd["effects"].get("revive", false),
		"phoenix_down.effects.revive must be true — the SINGLE_ALLY dead-eligibility filter reads this")
