extends GutTest

## ShopScene._attempt_magic_purchase used to spend gold first and ONLY
## append the spell to learned_abilities if it wasn't already there.
## So a duplicate-purchase (stale menu, post-job-change race, or any
## direct-call path that bypassed the char-select disable) silently
## consumed the gold and added nothing. The player paid for a spell
## they already had.
##
## Fix: pre-check `pending_spell_id in learned` BEFORE spend_gold.
## Show a 'X already knows Y' message and bail.

const SHOP_SCENE := "res://src/exploration/ShopScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_of(func_name: String) -> String:
	var src := _read(SHOP_SCENE)
	var idx := src.find("func " + func_name)
	assert_gt(idx, -1, func_name + " must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_already_known_check_runs_before_spend() -> void:
	# Critical ordering: the duplicate check must be BEFORE spend_gold,
	# otherwise the spend already happened and we'd need to refund.
	# Both work but pre-check is simpler and harder to break.
	var body := _body_of("_attempt_magic_purchase")
	var check_at := body.find("pending_spell_id in existing_learned")
	var spend_at := body.find("game_state.spend_gold(cost)")
	assert_gt(check_at, -1, "already-known guard must exist")
	assert_gt(spend_at, -1, "spend_gold must still be called for the success path")
	assert_lt(check_at, spend_at,
		"already-known check must run BEFORE spend_gold so the gold isn't consumed on duplicate purchase")


func test_already_known_path_surfaces_a_reason() -> void:
	# Silent failure was the original sin — a Toast or description
	# string must communicate why the click did nothing.
	var body := _body_of("_attempt_magic_purchase")
	assert_true(body.contains("already knows"),
		"already-known guard must surface a 'X already knows Y' message — not silently no-op")
