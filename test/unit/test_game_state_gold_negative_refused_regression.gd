extends GutTest

## tick 372: GameState.add_gold / spend_gold reject negative amounts.
##
## Pre-fix:
##   func add_gold(amount):
##       var multiplied_amount = int(amount * multiplier)
##       party_gold += multiplied_amount    # += -50 drains 50
##
##   func spend_gold(amount) -> bool:
##       if party_gold < amount: return false   # always false for negative
##       party_gold -= amount                   # -= -50 GRANTS 50
##       return true                            # caller thinks spent
##
## Symmetric with ticks 368-371's negative-amount footgun guards. A
## typo'd reward table, Scriptweaver mod, or sign-bug in computed
## gold could silently bankrupt or stuff the party's gold.

const GAME_STATE_PATH := "res://src/meta/GameState.gd"


# ── Source pin: add_gold refuses negative ───────────────────────────

func test_add_gold_source_pin() -> void:
	var src: String = FileAccess.get_file_as_string(GAME_STATE_PATH)
	var fn_idx: int = src.find("func add_gold(amount: int)")
	assert_gt(fn_idx, -1, "add_gold must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if amount < 0"),
		"add_gold must guard against negative amount")
	assert_true(body.contains("use spend_gold"),
		"add_gold warning must point caller at spend_gold as the drain path")


# ── Source pin: spend_gold refuses negative ─────────────────────────

func test_spend_gold_source_pin() -> void:
	var src: String = FileAccess.get_file_as_string(GAME_STATE_PATH)
	var fn_idx: int = src.find("func spend_gold(amount: int)")
	assert_gt(fn_idx, -1, "spend_gold must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if amount < 0"),
		"spend_gold must guard against negative amount")
	assert_true(body.contains("use add_gold"),
		"spend_gold warning must point caller at add_gold as the gain path")


# ── Behavioral: add_gold(-50) does NOT drain ────────────────────────

func test_add_gold_negative_does_not_drain() -> void:
	var script: GDScript = load(GAME_STATE_PATH)
	var gs: Object = script.new()
	add_child_autofree(gs)
	gs.party_gold = 200
	gs.add_gold(-50)
	assert_eq(gs.party_gold, 200,
		"add_gold(-50) must NOT drain — pre-fix dropped party_gold to 150")


# ── Behavioral: spend_gold(-50) does NOT grant ──────────────────────

func test_spend_gold_negative_does_not_grant() -> void:
	var script: GDScript = load(GAME_STATE_PATH)
	var gs: Object = script.new()
	add_child_autofree(gs)
	gs.party_gold = 100
	var ret: bool = gs.spend_gold(-50)
	assert_false(ret,
		"spend_gold(-50) must return false (refused, not true)")
	assert_eq(gs.party_gold, 100,
		"spend_gold(-50) must NOT grant 50 gold — pre-fix bumped party_gold to 150")


# ── Behavioral: positive add_gold still works ───────────────────────

func test_positive_add_gold_still_works() -> void:
	var script: GDScript = load(GAME_STATE_PATH)
	var gs: Object = script.new()
	add_child_autofree(gs)
	gs.party_gold = 100
	gs.add_gold(50)
	assert_eq(gs.party_gold, 150,
		"positive add_gold(50) must still raise party_gold by 50 (multiplier 1.0 default)")


# ── Behavioral: positive spend_gold still works ─────────────────────

func test_positive_spend_gold_still_works() -> void:
	var script: GDScript = load(GAME_STATE_PATH)
	var gs: Object = script.new()
	add_child_autofree(gs)
	gs.party_gold = 100
	var ret: bool = gs.spend_gold(30)
	assert_true(ret, "positive spend_gold(30) at 100 gold must succeed")
	assert_eq(gs.party_gold, 70, "positive spend_gold(30) must drop party_gold to 70")


# ── Behavioral: insufficient spend_gold still returns false ─────────

func test_spend_gold_insufficient_still_returns_false() -> void:
	# Regression guard — don't break the existing positive-too-high branch.
	var script: GDScript = load(GAME_STATE_PATH)
	var gs: Object = script.new()
	add_child_autofree(gs)
	gs.party_gold = 10
	var ret: bool = gs.spend_gold(50)
	assert_false(ret, "spend_gold(50) at 10 gold must still return false")
	assert_eq(gs.party_gold, 10,
		"insufficient spend_gold must NOT change party_gold")
