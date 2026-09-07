extends GutTest

## tick 370: Combatant.spend_mp rejects negative amounts.
##
## Pre-fix:
##   func spend_mp(amount: int) -> bool:
##       if not is_alive: return false
##       if current_mp < amount: return false    # negative always false
##       current_mp -= amount                    # current_mp -= -5 = +5
##       return true
##
## spend_mp(-5) returned true AND boosted current_mp by 5 — beyond the
## max_mp clamp, even, since this path doesn't run through restore_mp's
## min(max_mp, ...) cap. Callers using the bool return as "MP cost
## paid?" gate would let a character cast a spell for free AND gain
## MP back, potentially exceeding their max.
##
## Symmetric with tick 368's restore_mp guard and tick 369's spend_ap
## guard. No current production caller passes negatives, but it's a
## latent footgun for any future Scriptweaver mod / data typo / sign
## bug in computed MP cost.

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


# ── Source pin: spend_mp refuses negative ───────────────────────────

func test_spend_mp_source_pin() -> void:
	var src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	var fn_idx: int = src.find("func spend_mp(amount: int)")
	assert_gt(fn_idx, -1, "spend_mp must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if amount < 0"),
		"spend_mp must guard against negative amount")
	assert_true(body.contains("use restore_mp"),
		"spend_mp warning must point caller at restore_mp as the legitimate MP-gain path")


# ── Behavioral: spend_mp(-5) does NOT grant MP and returns false ────

func test_spend_mp_negative_returns_false() -> void:
	var c: Combatant = _make_combatant("Mage")
	c.current_mp = 10
	var ret: bool = c.spend_mp(-5)
	assert_false(ret, "spend_mp(-5) must return false (refused), not true")
	assert_eq(c.current_mp, 10, "spend_mp(-5) must NOT grant 5 MP — pre-fix added 5 (bypassing max_mp clamp)")


# ── Behavioral: spend_mp(-50) would have exceeded max_mp pre-fix ────

func test_spend_mp_negative_does_not_exceed_max_mp() -> void:
	# The most important consequence: spend_mp bypasses max_mp because
	# it just does `current_mp -= amount`. A negative input would push
	# current_mp above max_mp, leaving the player with "extra" MP that
	# restore_mp could never reach.
	var c: Combatant = _make_combatant("Mage")
	c.current_mp = 40  # max_mp = 50
	var ret: bool = c.spend_mp(-50)
	assert_false(ret, "spend_mp(-50) must be refused, not silently overflow")
	assert_eq(c.current_mp, 40,
		"spend_mp(-50) must NOT push current_mp above max_mp (40 → 90 pre-fix)")


# ── Behavioral: positive spend_mp still works ───────────────────────

func test_positive_spend_mp_still_works() -> void:
	var c: Combatant = _make_combatant("Mage")
	c.current_mp = 20
	var ret: bool = c.spend_mp(10)
	assert_true(ret, "spend_mp(10) at 20 MP must succeed")
	assert_eq(c.current_mp, 10, "spend_mp(10) at 20 MP must leave 10")


# ── Behavioral: spend_mp(0) still works (no-op success) ─────────────

func test_spend_mp_zero_returns_true() -> void:
	var c: Combatant = _make_combatant("Mage")
	c.current_mp = 5
	var ret: bool = c.spend_mp(0)
	assert_true(ret, "spend_mp(0) must return true (free ability path)")
	assert_eq(c.current_mp, 5, "spend_mp(0) must NOT change MP")


# ── Behavioral: insufficient MP still returns false ─────────────────

func test_spend_mp_insufficient_returns_false() -> void:
	# Regression guard — don't break the existing positive-cost-too-high
	# branch when adding the negative-amount guard.
	var c: Combatant = _make_combatant("Mage")
	c.current_mp = 5
	var ret: bool = c.spend_mp(10)
	assert_false(ret, "spend_mp(10) at 5 MP must still return false")
	assert_eq(c.current_mp, 5, "insufficient spend_mp must NOT change MP")
