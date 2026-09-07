extends GutTest

## tick 369: Combatant.spend_ap and gain_ap reject negative amounts.
##
## Pre-fix:
##   func can_brave(ap_cost) -> bool:
##       return (current_ap - ap_cost) >= -4   # NEVER false for negative cost
##   func spend_ap(amount) -> bool:
##       if not can_brave(amount): return false
##       current_ap = clampi(current_ap - amount, -4, 4)
##       return true
##
## spend_ap(-3) computed `current_ap - (-3) = current_ap + 3`, granted 3 AP,
## and returned true as if the AP cost had been paid. Callers using
## spend_ap as a "did the cost succeed?" gate would let a character act
## for free AND gain AP back — a hidden combo for any future code path
## (Scriptweaver mod, autobattle queue, group attack ap_cost computation
## with a sign bug) that fed a negative ap_cost.
##
## gain_ap(-2) symmetrically drained AP without going through the
## debt-check spend_ap performs.
##
## Symmetric defensive pair with tick 368's heal/restore_mp guard. No
## current production caller passes negatives; this is a footgun fix.

const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _make_combatant(name_str: String) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({
		"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	return c


# ── Source pin: spend_ap refuses negative ───────────────────────────

func test_spend_ap_source_pin() -> void:
	var src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	var fn_idx: int = src.find("func spend_ap(amount: int)")
	assert_gt(fn_idx, -1, "spend_ap must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if amount < 0"),
		"spend_ap must guard against negative amount")
	assert_true(body.contains("use gain_ap"),
		"spend_ap warning must point caller at gain_ap as the legitimate AP-gain path")


# ── Source pin: gain_ap refuses negative ────────────────────────────

func test_gain_ap_source_pin() -> void:
	var src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	var fn_idx: int = src.find("func gain_ap(amount: int)")
	assert_gt(fn_idx, -1, "gain_ap must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if amount < 0"),
		"gain_ap must guard against negative amount")
	assert_true(body.contains("use spend_ap"),
		"gain_ap warning must point caller at spend_ap as the legitimate AP-cost path")


# ── Behavioral: spend_ap(-3) does NOT grant AP and returns false ────

func test_spend_ap_negative_returns_false() -> void:
	var c: Combatant = _make_combatant("Hero")
	c.current_ap = 0
	var ret: bool = c.spend_ap(-3)
	assert_false(ret, "spend_ap(-3) must return false (refused), not true")
	assert_eq(c.current_ap, 0, "spend_ap(-3) must NOT grant 3 AP — pre-fix added 3")


# ── Behavioral: gain_ap(-2) does NOT drain AP ───────────────────────

func test_gain_ap_negative_does_not_drain() -> void:
	var c: Combatant = _make_combatant("Hero")
	c.current_ap = 2
	c.gain_ap(-2)
	assert_eq(c.current_ap, 2, "gain_ap(-2) must NOT drain — pre-fix dropped AP to 0")


# ── Behavioral: positive spend_ap still works ───────────────────────

func test_positive_spend_ap_still_works() -> void:
	var c: Combatant = _make_combatant("Hero")
	c.current_ap = 3
	var ret: bool = c.spend_ap(2)
	assert_true(ret, "spend_ap(2) must still return true when affordable")
	assert_eq(c.current_ap, 1, "spend_ap(2) at 3 AP must leave 1")


# ── Behavioral: positive gain_ap still works ────────────────────────

func test_positive_gain_ap_still_works() -> void:
	var c: Combatant = _make_combatant("Hero")
	c.current_ap = 0
	c.gain_ap(2)
	assert_eq(c.current_ap, 2, "gain_ap(2) at 0 must raise to 2")


# ── Behavioral: spend_ap(0) still works (no-op success) ─────────────

func test_spend_ap_zero_returns_true() -> void:
	# Free Move actions (Channel/Pray/Riff/Strike) cost 0 AP — must
	# continue to "succeed" without warning/refusal.
	var c: Combatant = _make_combatant("Hero")
	c.current_ap = 1
	var ret: bool = c.spend_ap(0)
	assert_true(ret, "spend_ap(0) must still return true (free action path)")
	assert_eq(c.current_ap, 1, "spend_ap(0) must NOT change AP")
