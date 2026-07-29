extends GutTest

## Defer does NOT grant AP. Player-facing text must not say it does.
##
## BattleManager._execute_defer halves incoming damage and grants nothing else —
## the only AP it can add is a conditional `bp_regen_bonus` from the optional
## bp_recovery passive, and its own comment says that sits "on top of the natural
## +1 next-turn gain". That +1 is unconditional — granted at turn start, before an
## action is chosen, whatever the combatant does. That half is LOAD-BEARING and is
## now asserted structurally below rather than claimed here against a line number.
##
## (Caveat found 2026-07-29, does not change the rule: under the bp_instability
## corruption effect the natural gain jitters 0/+1/+2 for player turns. The battle
## log announces it — "the economy is corrupted" — so the baseline hint text stays
## honest; corruption declaring itself is the point of corruption.)
##
## So "Defer — gain +1 AP" credits Defer with a per-turn regen every action
## receives, and hides Defer's actual benefit (halved damage). That exact false
## belief already shipped one bug: the Defer button was greyed out at max AP,
## gated on `current_ap >= 4` because a comment claimed Defer granted AP.
##
## DELIBERATELY NOT BANNED: "defer to build AP", "deferring builds AP". Those are
## strategically true — you accumulate because you SPEND none, which is different
## from receiving a grant. This pins the numeric-grant claim only.

const HINTS := "res://src/ui/TutorialHints.gd"
const BATTLE_MGR := "res://src/battle/BattleManager.gd"

## "Defer … gain/grant/give N AP" — a specific amount attributed to the action.
const GRANT_CLAIM := "(defer|deferring)[^.]{0,60}(gain|grant|give|award)[a-z]*[^.]{0,20}\\+?[0-9]+[^.]{0,10}ap"


func test_control_hint_corpus_loads_and_mentions_defer() -> void:
	var src := FileAccess.get_file_as_string(HINTS)
	assert_gt(src.length(), 500, "TutorialHints must load — an empty read would pass every check below")
	assert_true(src.to_lower().contains("defer"),
		"corpus must actually discuss Defer, else this file guards nothing")


func test_premise_defer_grants_no_unconditional_ap() -> void:
	var bm := FileAccess.get_file_as_string(BATTLE_MGR)
	var i: int = bm.find("func _execute_defer")
	assert_gt(i, -1, "_execute_defer must exist")
	var body: String = bm.substr(i, bm.find("\nfunc ", i + 1) - i)
	# The ONLY gain_ap in the body must be the conditional passive bonus.
	assert_false(body.contains("gain_ap(1)"),
		"if Defer ever grants a flat +1 AP, this whole rule is wrong and the hints should be revised, not this test silenced")
	assert_true(body.contains("bp_regen_bonus"),
		"the sole AP path in _execute_defer is the optional bp_recovery passive")


## THE OTHER HALF OF THE PREMISE — the half that would invert the rule.
## "Defer grants no AP" only means anything because EVERY combatant receives the +1
## at turn start regardless of what they chose. Move that gain inside a conditional
## — award it only to non-deferrers, say — and "Defer gives you +1 AP" becomes TRUE,
## while the guard below goes on banning it and stays green the whole time.
## Asserted structurally: the call must sit at function-body indentation, so any
## nesting under a condition trips it. Anchored on the comment, not a line number.
func test_premise_natural_ap_gain_is_action_independent() -> void:
	var lines := FileAccess.get_file_as_string(BATTLE_MGR).split("\n")
	var idx := -1
	for i in lines.size():
		if lines[i].contains("# Natural AP gain"):
			idx = i
			break
	assert_gt(idx, -1, "the natural AP gain block must exist — if it was renamed or removed, "
		+ "re-anchor this premise before trusting anything below it")

	var call_line := -1
	for i in range(idx, mini(idx + 20, lines.size())):
		if lines[i].contains("current_combatant.gain_ap("):
			call_line = i
			break
	assert_gt(call_line, -1, "the natural gain block must still call gain_ap")

	var raw: String = lines[call_line]
	var indent: int = raw.length() - raw.lstrip("\t").length()
	assert_eq(indent, 1, "the natural +1 must be granted at function-body level, unconditionally. "
		+ "It is now nested under a condition, so it is no longer universal regen — "
		+ "\"Defer grants +1 AP\" may have become TRUE and the ban below would be silencing "
		+ "honest text. Revisit the rule, not this assertion.")


func test_no_player_text_claims_defer_grants_ap() -> void:
	var src := FileAccess.get_file_as_string(HINTS)
	var re := RegEx.new()
	assert_eq(re.compile(GRANT_CLAIM), OK, "pattern must compile")
	var liars: Array = []
	for m in re.search_all(src.to_lower()):
		liars.append(m.get_string())
	assert_eq(liars, [], "Defer grants no AP — the +1 is unconditional per-turn regen every action "
		+ "receives. Crediting it to Defer hides Defer's real benefit (halved damage) and is the "
		+ "belief that shipped the greyed-at-max-AP bug. Offending text: %s" % [liars])
