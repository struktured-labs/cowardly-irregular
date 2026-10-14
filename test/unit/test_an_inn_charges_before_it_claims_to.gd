extends GutTest

## 🐛 `VillageInn._rest_party` DISCARDED `spend_gold`'s RESULT, restored the whole party, and
## announced "(-%d G)" naming a cost it had not confirmed taking. Three separate nothing-charged
## paths reached that receipt: no GameState, no `spend_gold` method, and `spend_gold` returning
## false (it refuses a NEGATIVE amount as well as an overdraft, and `rest_cost` is an @export the
## balance pre-check cannot screen for).
##
## 🔑 ITS SIBLING ALREADY CARRIED THE CONTRACT, which is how this was found and the reason it is
## worth a guard. `InnInterior._charge_for_rest` is documented *"False = the rest is refused (message
## shown, gold untouched); the caller must not restore the party"* and its caller honours it at
## `:1456`, above the restore. Same price — `InnInterior.REST_COST` IS `VillageInn.DEFAULT_REST_COST`
## — and two different levels of safety, one file apart. The repair sat beside the defect.
##
## ⛔ AND THE HONEST HEADLINE: THIS PATH IS UNREACHABLE IN SHIPPED PLAY. `VillageInn.interact():327`
## returns early whenever `interior_target != ""`, it defaults to "inn_interior", and NO village in
## `src/` clears it — so every inn in all six worlds routes to `InnInterior._do_rest()`. I found the
## charge bug by reading and spent the repair before learning that from a sibling guard's header.
## `test_village_inn_charges_gold_regression` is green over this same dead path, which is CLAUDE.md's
## own tell: a test named for the defect passing because it asks a different question.
##
## So the DEADNESS is the defect this file exists for, per that file's rule for divergent sources
## that are invisible at authoring time — guard the INVISIBILITY, not the collision, and require the
## annotation rather than permission to skip. You cannot silence this green, only explain it green.
## The charge arms remain because `interior_target` is an @export a village may legitimately clear,
## at which point this becomes the live path and must already be correct.

const InnRes = preload("res://src/exploration/VillageInn.gd")
const INN_SRC := "res://src/exploration/VillageInn.gd"

var _prior_gold: int = 0


## ⛔ CONSTANTS COME THROUGH THE SCRIPT'S CONSTANT MAP, NOT AS `InnRes.NAME` (@cowir-adhoc, who found
## this in four Text Size pins in this repo). A direct const read on a RENAMED name raises MID-ARM,
## and GUT scores an aborted body as a PASS — so a pin goes blind to exactly the thing it watches.
## It is worse than the general abort case because a pin is only ever exercised in the failure case:
## on a healthy tree it is a tautology, so nothing else would ever reveal it.
##
## The map yields the fallback instead, and the assert reds by comparison. 59 test files here already
## use this form, so it is the house idiom rather than a new one. ⚠️ Applied to EVERY reach, not just
## the two my rung audit flagged as silent: `REFUSED` was rung 1 in two arms (loud, EC=4) and rung 3
## in a third, and a uniform idiom cannot drift between arms as statement order changes.
## ⛔ `load(...)`, NOT the `const preload` — @cowir-autogrind lost three guard files to EC=3 on this
## exact line and flagged it before I spent a slot. `const X = preload(...)` is a CLASS reference, so
## `X.get_script_constant_map()` is a STATIC call and the engine refuses it at PARSE time:
##   "Cannot call non-static function ... on the class ... directly. Make an instance instead."
## `load()` returns a Script OBJECT and the call resolves. Same function, same constant, opposite
## outcome, decided by how the script was obtained. ⚠️ Their histogram showed four "precedents" for
## the broken form and all four were their own edits from twenty minutes earlier — a grep over a tree
## you just changed counts your own change as corroboration.
const INN_PATH := "res://src/exploration/VillageInn.gd"

func _inn_const(name: String, fallback: int) -> int:
	return int(load(INN_PATH).get_script_constant_map().get(name, fallback))


func before_each() -> void:
	_prior_gold = GameState.party_gold


func after_each() -> void:
	GameState.party_gold = _prior_gold


func _source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s must be readable" % path)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


## A bare VillageInn with just the label the charge paths write to. `dialogue_label` is a plain
## `var`, so the refusal arms would otherwise abort on a nil access and take their asserts with them.
func _inn() -> Node:
	var inn: Node = InnRes.new()
	add_child_autofree(inn)
	inn.dialogue_label = Label.new()
	add_child_autofree(inn.dialogue_label)
	return inn


# ── the deadness, ratcheted BOTH WAYS ────────────────────────────────────────

func test_the_dead_rest_path_says_what_outranks_it() -> void:
	var src := _source(INN_SRC)
	var villages := DirAccess.get_files_at("res://src/maps/villages")
	assert_gt(villages.size(), 0, "the village corpus must not be empty — an empty one cannot ratchet")

	## Is the outdoor rest reachable? Derived: the default must be empty, OR some village clears it.
	var default_empty := src.contains('@export var interior_target: String = ""')
	var cleared_by_a_village := false
	for v in villages:
		if not v.ends_with(".gd"):
			continue
		var vs := _source("res://src/maps/villages/" + v)
		if vs.contains('interior_target = ""'):
			cleared_by_a_village = true
			break
	var reachable := default_empty or cleared_by_a_village
	var annotated := src.contains("UNREACHABLE IN SHIPPED PLAY")

	if reachable:
		assert_false(annotated,
			"a village now clears interior_target, so _rest_party IS live — remove the dead-path note")
	else:
		assert_true(annotated,
			"_rest_party is unreachable (interior_target defaults non-empty, no village clears it) " +
			"and must say so, naming InnInterior as what outranks it")


# ── the charge itself, driven on a real instance ─────────────────────────────

func test_charging_reports_the_gold_it_actually_took() -> void:
	var inn := _inn()
	GameState.party_gold = inn.rest_cost + 7
	var charged: int = inn._charge_for_rest()
	assert_eq(charged, inn.rest_cost, "a successful charge reports the amount it took")
	assert_eq(int(GameState.get_gold()), 7, "and the gold actually moved by that amount")


func test_an_unpayable_rest_is_refused_with_the_gold_untouched() -> void:
	var inn := _inn()
	GameState.party_gold = inn.rest_cost - 1
	var charged: int = inn._charge_for_rest()
	assert_eq(charged, _inn_const("REFUSED", -9999), "an unpayable rest must be REFUSED, not charged")
	assert_eq(int(GameState.get_gold()), inn.rest_cost - 1, "and the gold must be untouched")
	assert_ne(inn.dialogue_label.text, "", "the refusal must be surfaced, not silent")


func test_refused_cannot_be_mistaken_for_an_amount() -> void:
	## The caller compares against this sentinel, so it must not collide with a real outcome:
	## `rest_cost` on a charge, or 0 on the no-GameState path where the rest is allowed free.
	assert_lt(_inn_const("REFUSED", -9999), 0, "REFUSED must be negative — 0 is the charged-nothing case")
	assert_ne(_inn_const("REFUSED", -9999), _inn_const("DEFAULT_REST_COST", -9998), "and must not collide with a real charge")


func test_spend_gold_really_refuses_the_case_the_fix_now_honours() -> void:
	## CONTROL. The arms above are about honouring a refusal; this one proves the refusal exists,
	## on the real autoload. Without it they could pass because `spend_gold` always succeeds.
	GameState.party_gold = 500
	assert_false(bool(GameState.spend_gold(-5)), "spend_gold refuses a negative amount")
	assert_eq(int(GameState.get_gold()), 500, "and takes nothing when it refuses")
	assert_false(bool(GameState.spend_gold(501)), "spend_gold refuses an overdraft")
	assert_eq(int(GameState.get_gold()), 500, "and takes nothing then either")
	assert_true(bool(GameState.spend_gold(10)), "and still succeeds when it can — the control's control")
	assert_eq(int(GameState.get_gold()), 490, "taking exactly what it was asked for")


# ── the caller's half: order, and the receipt ────────────────────────────────

func test_the_rest_consults_the_charge_before_it_restores_or_claims() -> void:
	## ⛔ CODE, NOT RAW SOURCE. `_source` reads the file verbatim, and .695's refused-revive fix
	## added a COMMENT containing the phrase "fully rested" ABOVE the receipt — so `find` anchored
	## i_receipt in prose, the tail swallowed the lines between, and this arm went green measuring
	## nothing. GdSource strips comments and docstrings for exactly this.
	var src := GdSource.code_of(INN_SRC)
	var at := src.find("func _rest_party(")
	assert_gt(at, -1, "_rest_party must still exist")
	var fn := src.substr(at)
	var nxt := fn.find("\nfunc ", 1)
	if nxt > -1:
		fn = fn.substr(0, nxt)

	var i_charge := fn.find("_charge_for_rest()")
	var i_restore := fn.find("max_hp")
	var i_receipt := fn.find("fully rested")
	assert_gt(i_charge, -1, "_rest_party must consult _charge_for_rest")
	assert_gt(i_restore, -1, "_rest_party must still restore the party")
	assert_gt(i_receipt, -1, "_rest_party must still print a receipt")
	assert_lt(i_charge, i_restore, "the charge must be consulted BEFORE the party is restored")
	assert_lt(i_charge, i_receipt, "and before the receipt is written")
	assert_string_contains(fn, "== REFUSED", "and the refusal must be acted on, not discarded")

	## THE RECEIPT NAMES WHAT WAS CHARGED. Naming `rest_cost` is the defect: it is the inn's PRICE,
	## which is what the old line printed on all three nothing-charged paths.
	var tail := fn.substr(i_receipt)
	assert_false(tail.contains("% rest_cost"),
		"the receipt must not name rest_cost — that is the price, not the charge")
	## ⛔ WAS `tail.contains("charged")`, WHICH PINNED STATEMENT ORDER RATHER THAN THE CLAIM. .695's
	## refused-revive fix made the receipt two-branched, so the gold clause has to be built ABOVE
	## both branches -- which moved `charged` before i_receipt and red an assert about behaviour
	## that had not changed. Pin the RELATIONSHIP: whatever prints the gold figure is fed by the
	## amount actually taken, wherever that line sits.
	assert_string_contains(fn, "(-%d G)\" % charged",
		"the printed gold figure must be fed by `charged`, the amount actually taken")
	assert_string_contains(tail, "paid", "and the receipt must interpolate that figure")
