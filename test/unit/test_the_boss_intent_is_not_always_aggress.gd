extends GutTest

## The boss chose `aggress` on every board, and I am the one who broke it.
##
## My own earlier fix added this to build_boss_intent, to stop the model reading
## the player's party as its own roster (inverted reasoning, 3 of 5 samples):
##
##     "...YOUR ENEMIES. You are fighting them; you
##      do not command, protect or heal them. Their weakness is your opportunity."
##
## It fixed the inversion and collapsed the strategy layer. Measured against live
## llama3 on the shipped prompt, 6 samples per board:
##
##     board                                      ships    after
##     boss 95% hp, 3 AP, party at 14/21%         aggress  aggress   (correct both)
##     boss 60/60/2, party healthy (ambiguous)    aggress  —
##     boss 45% hp, 8% MP, 0 AP                   aggress  turtle
##     boss  9% hp, 15% MP, 0 AP                  aggress  turtle 5 / aggress 1
##
## 24 of 24 `aggress` before, across boards spanning 95%→9% boss HP and 3→0 AP.
## The prompt's OWN rule says turtle is "Best when YOU are hurt, low on MP or out
## of AP" — all three true on the last board, and it never picked it.
##
## NOT an unreachable branch: withhold `aggress` from the offered list and turtle
## is chosen 6 of 6. The model could always pick it and never did.
##
## ⚠️ THE CAUSE IS THE UNSCOPED PROHIBITION, and I mis-diagnosed it twice before
## measuring it. "Their weakness is your opportunity" looked like the aggression
## nudge; removing it alone left aggress 6/6. Removing the whole block restored
## turtle 6/6; relabelling "Enemy party state:" changed nothing. What drives it is
## "do not command, protect or heal them" — a ban on protective verbs the model
## generalises from THE PARTY to DEFENSIVE POSTURE AS SUCH. Scoping the ban to
## THEM and stating that guarding itself is available restores the spread without
## reintroducing a single inverted sample (0 of 18 after).

const DP := preload("res://src/llm/DialoguePrompts.gd")


func _prompt() -> String:
	return DP.build_boss_intent("Chancellor Mordaine", {
		"persona": "The usurper.",
		"phase": 3,
		"boss_hp_pct": 9.0, "boss_mp_pct": 15.0, "boss_ap": 0,
		"party": [{"name": "Rilla", "job_id": "cleric", "hp_pct": 88.0, "is_alive": true}],
		"available_intents": ["aggress", "turtle", "exploit_pattern"],
	})


# ── the defect ────────────────────────────────────────────────────────────────

func test_the_refusal_is_scoped_to_the_party_not_to_defending_at_all() -> void:
	## The arm. An unscoped "do not protect" reads as "never guard", and every
	## board collapsed to aggress.
	var p: String = _prompt()
	assert_eq(p.find("do not command, protect or heal them"), -1,
		"the unscoped prohibition is back — it collapsed 24 of 24 boards to aggress")


func test_the_boss_is_told_it_may_guard_itself() -> void:
	var p: String = _prompt()
	assert_true(p.find("YOURSELF") != -1,
		"the prompt must name YOURSELF as something the boss may guard — without it a boss at 9% HP still charges 6 of 6")


func test_the_prohibition_still_names_the_party_as_its_object() -> void:
	## Scoping is the whole repair: the verbs stay forbidden, but only toward THEM.
	var p: String = _prompt()
	var at: int = p.find("command, protect or heal")
	assert_true(at != -1, "the protective verbs must still be refused")
	assert_true(p.substr(at, 40).find("THEM") != -1,
		"the refusal must name THEM as its object — unscoped is what broke it")


# ── the earlier fix must survive this one ─────────────────────────────────────

func test_the_party_is_still_identified_as_the_enemy() -> void:
	## CONTROL. This repair must not reintroduce the defect the block was added
	## for: 3 of 5 samples had Mordaine protecting and healing the player's party.
	assert_true(_prompt().find("YOUR ENEMIES") != -1,
		"the side-identification must survive — without it the boss healed the player's party")


func test_the_intent_menu_still_states_when_turtle_applies() -> void:
	## CONTROL: the repair works by letting the model apply the prompt's own rule.
	## If that rule stops being stated, the fix has nothing to act on.
	var p: String = _prompt()
	assert_true(p.find("turtle") != -1, "turtle must still be offered")
	assert_true(p.find("Best when YOU are hurt") != -1,
		"turtle's condition must still be stated — it is the rule the boss now follows")


func test_the_boss_own_state_is_still_in_the_prompt() -> void:
	## CONTROL: the model cannot apply a self-referring rule to a state it cannot
	## see. This is the input the whole repair depends on.
	var p: String = _prompt()
	assert_true(p.find("Your state:") != -1, "the boss's own state must be present")
	assert_true(p.find("HP 9%") != -1, "and carry the HP the rule is evaluated against")
