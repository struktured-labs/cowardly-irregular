extends GutTest

## Defer does NOT grant AP. Player-facing text must not say it does.
##
## BattleManager._execute_defer halves incoming damage and grants nothing else —
## the only AP it can add is a conditional `bp_regen_bonus` from the optional
## bp_recovery passive, and its own comment says that sits "on top of the natural
## +1 next-turn gain". That +1 is unconditional (BattleManager ~1447, "natural
## gain"), awarded whatever the combatant did.
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
