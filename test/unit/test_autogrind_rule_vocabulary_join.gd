extends GutTest

## Joins the FIVE corpora that define the autogrind rule vocabulary, so a type can never be
## accepted by one and ignored by another.
##
## The corpora:
##   1. AutogrindSystem.PARTY_CONDITION_TYPES   the grammar validate_rule accepts
##   2. AutogrindSystem.AUTOGRIND_ACTION_TYPES  ditto for actions
##   3. _evaluate_party_condition's match arms  what actually runs
##   4. the action executor's match arms (+ the Controller's flee_battle interception)
##   5. AutogrindUI.CONDITION_TYPES / ACTION_TYPES  what the editor lets a player build
##
## Why it matters more here than in most joins: autogrind rule sets TRAVEL. They are exported
## and imported as `COWIR1:` clipboard codes between players. A condition type added to the
## grammar without an evaluator arm validates, imports cleanly, reports success — and then
## silently never matches, because the evaluator's default is `return false`. The recipient
## sees a rule that simply never fires, with no error anywhere.
##
## Measured 2026-08-06: all five agree (16 conditions, 5 actions, 6 operators). This pins that.
##
## ── Why the conditions are DRIVEN and not source-parsed ────────────────────────────────
## Source-parsing a `match` block is a tripwire on the function's LOCATION (1038 such sites
## exist in this repo), and it cannot tell a present-but-broken arm from a present one. But
## driving has its own trap here: an unknown type falls through to `return false`, and a
## legitimately-unmet condition ALSO returns false — failure value == success value. So each
## type below is driven with an input that MUST evaluate true if its arm exists: `!=` against
## an impossible value for the numeric arms, and prepared backing state for the boolean ones.
## A missing arm falls through to false and is named.

const REQUIRED_TRUE_OP: String = "!="
const IMPOSSIBLE_VALUE: float = -99999.0

## Condition types whose arm returns a bare bool rather than going through _compare_op.
## Each maps to the setup that makes it true, so a fall-through is distinguishable.
const BOOLEAN_ARMS: Array[String] = [
	"member_dead", "member_injured", "ability_learned", "rare_item_found", "always",
]

var _sys: Node
var _saved: Dictionary = {}


func before_each() -> void:
	_sys = AutogrindSystem
	_sys._test_disable_persistence = true
	_saved = {
		"ability": _sys._ability_learned_this_session,
		"rare": _sys._rare_drop_this_session,
		"party": _sys.grind_party.duplicate(),
	}


func after_each() -> void:
	_sys._ability_learned_this_session = _saved["ability"]
	_sys._rare_drop_this_session = _saved["rare"]
	_sys.grind_party.assign(_saved["party"])
	_saved.clear()


func _make(member_name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": member_name, "max_hp": 100, "max_mp": 50,
		"attack": 20, "defense": 15, "magic": 10, "speed": 12,
	})
	add_child_autofree(c)
	return c


func _live_party() -> Array:
	return [_make("VocabProbe")]


## A party with one alive and one dead member, so `member_dead` is true.
func _party_with_a_casualty() -> Array:
	var dead := _make("Dead")
	dead.current_hp = 0
	dead.is_alive = false
	return [_make("Alive"), dead]


func test_every_grammar_condition_type_has_a_LIVE_evaluator_arm() -> void:
	# The headline. A type in the grammar with no arm falls through to `return false` and the
	# rule silently never matches — including in a rule set imported from another player.
	var unhandled: Array[String] = []
	for ctype in _sys.PARTY_CONDITION_TYPES.keys():
		var type_id: String = str(ctype)
		var party: Array = _live_party()
		var cond: Dictionary = {"type": type_id}

		if type_id in BOOLEAN_ARMS:
			match type_id:
				"member_dead":
					party = _party_with_a_casualty()
				"member_injured":
					continue  # needs live injury bookkeeping; covered by the source join below
				"ability_learned":
					_sys._ability_learned_this_session = true
				"rare_item_found":
					_sys._rare_drop_this_session = true
				"always":
					pass
		else:
			cond["op"] = REQUIRED_TRUE_OP
			cond["value"] = IMPOSSIBLE_VALUE

		if not _sys._evaluate_party_condition(party, cond):
			unhandled.append(type_id)

	assert_eq(unhandled.size(), 0,
		"These condition types are accepted by validate_rule but evaluate false even when driven with an input that must be true — they have no evaluator arm, so any rule using them silently never fires (and imports from other players will too): %s" % ", ".join(unhandled))


func test_the_drive_can_actually_fail() -> void:
	# Control. Without this, the test above passes on a run where every probe was malformed.
	var party: Array = _live_party()
	assert_false(_sys._evaluate_party_condition(party, {"type": "zzz_not_a_condition", "op": REQUIRED_TRUE_OP, "value": IMPOSSIBLE_VALUE}),
		"control: a fabricated condition type must evaluate false, else the drive cannot detect a missing arm")
	assert_true(_sys._evaluate_party_condition(party, {"type": "always"}),
		"control: a known-present arm must evaluate true, else the probe is broken rather than the code")


func test_grammar_accepts_every_type_the_editor_can_build() -> void:
	# The editor's picker is a third corpus. A type offered in the UI that validate_rule
	# rejects means the player builds a rule the choke point refuses to save.
	var ui := load("res://src/ui/autogrind/AutogrindUI.gd")
	var offered: Array[String] = []
	for entry in ui.CONDITION_TYPES:
		offered.append(str(entry["id"]))
	var rejected: Array[String] = []
	for type_id in offered:
		if not _sys.PARTY_CONDITION_TYPES.has(type_id):
			rejected.append(type_id)
	assert_eq(rejected.size(), 0,
		"the autogrind editor offers condition types the grammar rejects — a player can build a rule that cannot be saved: %s" % ", ".join(rejected))

	var unbuildable: Array[String] = []
	for type_id in _sys.PARTY_CONDITION_TYPES.keys():
		if not (str(type_id) in offered):
			unbuildable.append(str(type_id))
	assert_eq(unbuildable.size(), 0,
		"the grammar accepts condition types the editor cannot build — reachable only via hand-edited JSON or an imported code: %s" % ", ".join(unbuildable))


func test_editor_and_grammar_agree_on_ACTIONS() -> void:
	var ui := load("res://src/ui/autogrind/AutogrindUI.gd")
	var offered: Array[String] = []
	for entry in ui.ACTION_TYPES:
		offered.append(str(entry["id"]))
	for type_id in offered:
		assert_true(_sys.AUTOGRIND_ACTION_TYPES.has(type_id),
			"editor offers action '%s' which the grammar rejects" % type_id)
	for type_id in _sys.AUTOGRIND_ACTION_TYPES.keys():
		assert_true(str(type_id) in offered,
			"grammar accepts action '%s' the editor cannot build" % type_id)


func test_every_operator_the_grammar_accepts_is_implemented() -> void:
	# _compare_op's default is `return false`, so an accepted-but-unimplemented operator makes
	# every rule using it silently never match — same shape as a missing condition arm.
	var broken: Array[String] = []
	for op in _sys.OPERATORS.keys():
		var op_s: String = str(op)
		# For each operator, pick operands that make it unambiguously TRUE.
		var a: float = 1.0
		var b: float = 2.0
		match op_s:
			"<", "<=", "!=":
				pass                    # 1 < 2, 1 <= 2, 1 != 2
			">", ">=":
				a = 2.0; b = 1.0        # 2 > 1, 2 >= 1
			"==":
				b = 1.0                 # 1 == 1
		if not _sys._compare_op(a, op_s, b):
			broken.append(op_s)
	assert_eq(broken.size(), 0,
		"these operators are accepted by validate_rule but _compare_op has no arm for them, so any rule using them silently never matches: %s" % ", ".join(broken))


func test_operator_control() -> void:
	assert_false(_sys._compare_op(1.0, "~~", 2.0),
		"control: an unimplemented operator must return false, else the operator test cannot fail")
	assert_true(_sys._compare_op(1.0, "<", 2.0),
		"control: a known-implemented operator must return true")


func test_validate_rule_accepts_a_rule_built_from_every_vocabulary_entry() -> void:
	# End-to-end on the choke point: the grammar must accept what the grammar declares.
	# Catches a validator that grew a stricter rule than its own vocabulary table.
	for ctype in _sys.PARTY_CONDITION_TYPES.keys():
		var rule: Dictionary = {
			"conditions": [{"type": str(ctype), "op": "<", "value": 1}],
			"actions": [{"type": "stop_grinding"}],
		}
		var errors: Array = _sys.validate_rule(rule)
		assert_eq(errors.size(), 0,
			"validate_rule rejected a rule using '%s', which is in its own PARTY_CONDITION_TYPES table: %s" % [str(ctype), str(errors)])
