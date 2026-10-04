extends GutTest

## Playtest 2026-07-14 (round 2): "Target no longer valid!" trying to bring
## Bard back to life with Phoenix Down.
##
## Root: v3.33.150 added revive-eligibility to the MENU BUILD (so KO'd
## allies show up in the Phoenix Down target list) — but the EXECUTE branch
## at BattleCommandMenu:913 still gated on `target.is_alive`, torching the
## intent at the last mile. Menu offered the target, execute rejected it.
##
## Fix: execute path mirrors the menu-build gate — item.effects.revive
## admits KO'd allies for ally targets.
##
## CTB ruling (struktured 2026-10-03) widened the same gate to admit a
## LIVING ally too (any ally is a guess at selection time), and factored the
## inline check into _is_valid_item_target so both the ability and item
## confirm gates share one shape. Pinned on the extracted function instead
## of a char window now that the logic lives one level away from the call.


func test_execute_item_gate_admits_ko_ally_when_item_revives() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	# Anchor on the exact log-message right before the fix so a rewrite
	# would move the anchor and force a look here.
	var i := src.find("BattleManager.player_item(i_id, [target])")
	assert_gt(i, -1)
	var window := src.substr(maxi(0, i - 200), 300)
	assert_true("_is_valid_item_target" in window,
		"item-execute path must route the confirm gate through _is_valid_item_target, not a raw is_alive check")
	assert_false("if is_instance_valid(target) and target.is_alive:\n\t\t\t\tBattleManager.player_item" in window,
		"the raw is_alive gate is the bug — must be replaced by a revive-aware check")
	var gate_idx := src.find("func _is_valid_item_target(")
	assert_gt(gate_idx, -1, "CONTROL: _is_valid_item_target must exist")
	var next_fn := src.find("\nfunc ", gate_idx + 1)
	var gate_body := src.substr(gate_idx, next_fn - gate_idx)
	assert_true("can_revive" in gate_body or "_item_allows_any_ally_target" in gate_body,
		"the gate must derive from item.effects.revive, directly or via _item_allows_any_ally_target")
	var helper_idx := src.find("func _item_allows_any_ally_target(")
	assert_gt(helper_idx, -1)
	var helper_next := src.find("\nfunc ", helper_idx + 1)
	var helper_body := src.substr(helper_idx, helper_next - helper_idx)
	assert_true("revive" in helper_body,
		"revive detection must consult ItemSystem.get_item(...).effects.revive")
