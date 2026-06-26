extends GutTest

## tick 191 regression: CutsceneDirector._step_update_item now
## guards add_item on remove_item success. Pre-fix the bool
## return from remove_item was ignored — a failed remove (qty
## race, save-format drift between get_item_count and remove
## semantics, future async flow) would leave the OLD item in
## inventory while add_item ran and granted the NEW item too.
## Player ends up with both (item duplication).
##
## Used by world1_orrery to swap "fool_card" → "wild_card"
## mid-cutscene. If the swap silently dups, the player can
## use both cards — sequence-break the orrery puzzle.
##
## Fix: check remove_item return. If false, push_warning and
## abort the swap (no add_item call). Empty inventory after
## the loop is a no-op for the player (warning surfaces it).

const CUTSCENE_DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _step_body() -> String:
	var src := _read(CUTSCENE_DIRECTOR)
	var idx: int = src.find("func _step_update_item")
	assert_gt(idx, -1, "_step_update_item must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


# ── Guard pattern ──────────────────────────────────────────────────────

func test_remove_item_return_is_checked() -> void:
	var body := _step_body()
	# Pin: the failure branch tests `not member.remove_item(...)`.
	assert_true(body.contains("if not member.remove_item(old_id, qty):"),
		"_step_update_item must check remove_item return value")


func test_add_item_only_runs_when_remove_succeeded() -> void:
	var body := _step_body()
	# Pin: the failure branch returns BEFORE add_item runs.
	# Locate the remove-failure if; locate the add_item call; assert
	# the failure if comes first AND its body has `return`.
	var fail_idx: int = body.find("if not member.remove_item(old_id, qty):")
	assert_gt(fail_idx, -1)
	var add_idx: int = body.find("member.add_item(new_id, qty)")
	assert_gt(add_idx, -1, "add_item call must still exist for happy path")
	assert_gt(add_idx, fail_idx,
		"add_item must appear AFTER the remove-failure check (early-return guards it)")
	# The window between fail_idx and add_idx must include a return.
	var window: String = body.substr(fail_idx, add_idx - fail_idx)
	assert_true(window.contains("return"),
		"remove-failure branch must early-return before add_item runs (prevents duplication)")


# ── Warning content ────────────────────────────────────────────────────

func test_failure_warning_states_no_duplication() -> void:
	var body := _step_body()
	# Pin: warning surfaces consequence + assures no dup.
	assert_true(body.contains("push_warning(\"CutsceneDirector update_item: remove_item"),
		"remove-failure must push_warning")
	assert_true(body.contains("no duplication"),
		"warning must state 'no duplication' (consequence reassurance)")


func test_warning_includes_id_qty_and_member_name() -> void:
	var body := _step_body()
	# Pin: warning includes failing id + qty + member combatant_name.
	assert_true(body.contains("remove_item('%s', %d) failed on %s"),
		"warning must include id, qty, and member name for diagnosis")


# ── has_method robustness ─────────────────────────────────────────────

func test_missing_method_branch_skips_swap_safely() -> void:
	# Pin: if member lacks remove_item OR add_item method, skip
	# safely (push_warning + return), not crash on attribute access.
	var body := _step_body()
	assert_true(body.contains("if not member.has_method(\"remove_item\") or not member.has_method(\"add_item\"):"),
		"_step_update_item must guard both has_method checks together")
	assert_true(body.contains("missing remove_item/add_item — swap skipped"),
		"missing-method warning must state 'swap skipped'")


# ── Negative pins: pre-fix shape gone ──────────────────────────────────

func test_old_unconditional_add_pattern_gone() -> void:
	var body := _step_body()
	# Negative pin: the bare add_item-after-conditional-remove
	# pattern (where add ran regardless of remove success) is gone.
	# Pre-fix had:
	#   if member.has_method("remove_item"):
	#       member.remove_item(old_id, qty)
	#   if member.has_method("add_item"):
	#       member.add_item(new_id, qty)
	# The independent `if member.has_method("remove_item"):`
	# branch must not exist anymore.
	assert_false(body.contains("if member.has_method(\"remove_item\"):\n\t\t\tmember.remove_item(old_id, qty)"),
		"old independent has_method('remove_item') branch must be gone")
	# Likewise the bare `if member.has_method("add_item"):` branch.
	assert_false(body.contains("if member.has_method(\"add_item\"):\n\t\t\tmember.add_item(new_id, qty)"),
		"old independent has_method('add_item') branch must be gone")


# ── Pre-existing safety preserved ──────────────────────────────────────

func test_missing_old_or_new_id_still_warned() -> void:
	# Pre-existing safety: missing 'item' or 'new_id' fields still
	# push_warning + early return.
	var body := _step_body()
	assert_true(body.contains("missing 'item' or 'new_id' field"),
		"existing missing-field guard preserved")


func test_no_party_member_has_item_still_warned() -> void:
	# Pre-existing safety: walking the party finds nothing → warning.
	var body := _step_body()
	assert_true(body.contains("no party member has item"),
		"existing 'no party member has item' guard preserved")


func test_first_match_wins_still_returns() -> void:
	# Pre-existing semantic: only the FIRST party member with the
	# old item gets the swap (avoids double-swap if dup exists).
	# Verified by the `return` after add_item.
	var body := _step_body()
	# Two returns expected in the success path (or one trailing).
	# The key invariant: add_item is followed by a return inside the loop.
	var add_idx: int = body.find("member.add_item(new_id, qty)")
	assert_gt(add_idx, -1)
	var post_add: String = body.substr(add_idx, 200)
	assert_true(post_add.contains("return"),
		"add_item must be followed by `return` to preserve 'first match wins'")
