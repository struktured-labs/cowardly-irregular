extends GutTest

## tick 368: Combatant.heal() and restore_mp() reject negative amounts.
##
## Pre-fix:
##   func heal(amount):
##       ...
##       current_hp = min(max_hp, current_hp + amount)
##
## A negative `amount` (e.g. heal(-30)) silently SUBTRACTED HP via the
## min(max, hp + -30) arithmetic without going through the damage path:
##   - No die() check on lethal drain
##   - No damage_dealt signal (no shake / hit popup)
##   - Returned a negative int, which BattleManager.healing_done.emit
##     would forward to BattleScene's "+%d HP" popup as "+(-30) HP"
##
## No production data currently authors negative amounts, but a typo'd
## ability/item entry, a Scriptweaver mod, or save-state drift could
## trigger this silently exploitable drain.
##
## Post-fix: heal(-N) and restore_mp(-N) push a warning and return 0.
## Use take_damage / spend_mp for legitimate drain.

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


# ── Source pin: heal refuses negative amounts ───────────────────────

func test_heal_source_pin() -> void:
	var src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	var fn_idx: int = src.find("func heal(amount: int)")
	assert_gt(fn_idx, -1, "heal must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if amount < 0"),
		"heal must guard against negative amount")
	assert_true(body.contains("use take_damage"),
		"heal warning must point caller at take_damage as the legitimate drain path")


# ── Source pin: restore_mp refuses negative amounts ─────────────────

func test_restore_mp_source_pin() -> void:
	var src: String = FileAccess.get_file_as_string(COMBATANT_PATH)
	var fn_idx: int = src.find("func restore_mp(amount: int)")
	assert_gt(fn_idx, -1, "restore_mp must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if amount < 0"),
		"restore_mp must guard against negative amount")
	assert_true(body.contains("use spend_mp"),
		"restore_mp warning must point caller at spend_mp as the legitimate drain path")


# ── Behavioral: heal(-30) doesn't drain HP ──────────────────────────

func test_heal_negative_does_not_drain_hp() -> void:
	var c: Combatant = _make_combatant("Hero")
	c.current_hp = 80
	var ret: int = c.heal(-30)
	assert_eq(ret, 0, "heal(-30) must return 0 (refused, not -30)")
	assert_eq(c.current_hp, 80, "heal(-30) must NOT drain current_hp")


# ── Behavioral: restore_mp(-15) doesn't drain MP ────────────────────

func test_restore_mp_negative_does_not_drain_mp() -> void:
	var c: Combatant = _make_combatant("Mage")
	c.current_mp = 40
	var ret: int = c.restore_mp(-15)
	assert_eq(ret, 0, "restore_mp(-15) must return 0 (refused)")
	assert_eq(c.current_mp, 40, "restore_mp(-15) must NOT drain current_mp")


# ── Behavioral: heal(0) is a clean no-op (still returns 0) ──────────

func test_heal_zero_is_noop() -> void:
	var c: Combatant = _make_combatant("Hero")
	c.current_hp = 70
	var ret: int = c.heal(0)
	assert_eq(ret, 0, "heal(0) returns 0 (no-op, not warning-rejected)")
	assert_eq(c.current_hp, 70, "heal(0) leaves HP unchanged")


# ── Behavioral: positive heal still works (regression guard) ────────

func test_positive_heal_still_works() -> void:
	var c: Combatant = _make_combatant("Hero")
	c.current_hp = 50
	var ret: int = c.heal(20)
	assert_gt(ret, 0, "positive heal must still return a positive amount")
	assert_gt(c.current_hp, 50, "positive heal must still raise HP")


# ── Behavioral: positive restore_mp still works ─────────────────────

func test_positive_restore_mp_still_works() -> void:
	var c: Combatant = _make_combatant("Mage")
	c.current_mp = 10
	var ret: int = c.restore_mp(20)
	assert_eq(ret, 20, "positive restore_mp must return amount restored")
	assert_eq(c.current_mp, 30, "positive restore_mp must raise MP")
