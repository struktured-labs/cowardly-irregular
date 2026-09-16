extends GutTest

## MEASURED NULL, TURNED INTO A RATCHET. Closing seven parity gaps in the resolver moved what an
## ability DOES without touching how either engine CHOOSES one — so I went looking for the shape
## @cowir-cutscenes hit an hour ago, where a fix made one consumer derive while its siblings kept
## guessing and the two then disagreed exactly for the cases the fix was for.
##
## It is NOT here, and the reason is worth pinning rather than remembering:
##
##   live    _ability_power(ability)        -> ability.get("power", ability.get("damage_multiplier", 0.0))
##   grind   _find_attack_ability          -> ability.get("power", ability.get("damage_multiplier", 0.0))
##
## Both rank by the RAW multiplier, and neither accounts for `hits`, `ignores_defense`,
## `damage_to_self_pct`, `drain_mp` or `drain_percentage`. So a 3-hit 0.5x ability ranks below a
## 1-hit 0.6x one in BOTH engines, and stack_overflow's 3.0x ranks as though its 20% recoil were free
## in BOTH. The grind mirrors live including live's own looseness, which is what parity means here.
##
## ⚠️ WHETHER EITHER AI SHOULD ACCOUNT FOR THEM IS A BALANCE QUESTION, NOT A PARITY ONE, and it is
## @cowir-battle's — both engines agree today, so there is nothing for this lane to close. This file
## exists so that if ONE of them learns to, the other is obliged to follow instead of silently
## drifting: teaching the grind alone makes it out-play the game, teaching live alone makes the grind
## a worse simulation, and both are invisible to every arm that measures what an ability DOES.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const LIVE := "res://src/battle/BattleManager.gd"
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"

## The keys this lane wired into the resolver's damage arms. None of them should reach a SELECTION
## heuristic in either engine unless both learn it together.
const OUTCOME_KEYS := ["hits", "ignores_defense", "damage_to_self_pct", "drain_mp", "drain_percentage"]


## The body of a named function, bounded by the next top-level `func`.
func _body_of(code: String, fname: String) -> String:
	var at: int = code.find("func %s(" % fname)
	if at < 0:
		return ""
	var nxt: int = code.find("\nfunc ", at + 6)
	return code.substr(at, (nxt - at) if nxt > at else 2000)


func test_both_engines_rank_by_the_same_expression() -> void:
	var live_body: String = _body_of(GdSource.code_of(LIVE), "_ability_power")
	var grind_body: String = _body_of(GdSource.code_of(GRIND), "_find_attack_ability")
	assert_ne(live_body, "", "CONTROL: live's ranking helper must be locatable")
	assert_ne(grind_body, "", "CONTROL: CONTROL: the grind selector _find_attack_ability must be locatable")
	var expr := 'ability.get("power", ability.get("damage_multiplier"'
	assert_true(live_body.contains(expr),
		"live no longer ranks abilities by the raw multiplier — the grind still does, so the two AIs now choose differently")
	assert_true(grind_body.contains(expr),
		"the grind no longer ranks abilities by the raw multiplier — live still does, so the grind out-plays or under-plays the game")


func test_neither_selector_has_learned_an_outcome_key() -> void:
	## The ratchet. If one selector starts accounting for what an ability actually does, it reds and
	## names the key — and the fix is to teach BOTH or neither, never whichever lane noticed.
	var pairs := [[LIVE, "_ability_power"], [GRIND, "_find_attack_ability"]]
	var learned: Array = []
	for pair in pairs:
		var body: String = _body_of(GdSource.code_of(str(pair[0])), str(pair[1]))
		assert_ne(body, "", "CONTROL: %s must be locatable" % pair[1])
		for k in OUTCOME_KEYS:
			if body.contains('"%s"' % k):
				learned.append("%s reads %s" % [pair[1], k])
	assert_eq(learned, [],
		"a selection heuristic now accounts for what the ability DOES while its counterpart does not: %s — teach both engines or neither" % str(learned))
	## Anti-vacuity: the scan must be able to SEE a key in a body that has one, or an empty result
	## proves only that the slices were empty.
	var arm: String = GdSource.code_of(GRIND)
	assert_true(arm.contains('ability.get("hits", 1)'),
		"CONTROL: the resolver demonstrably reads an outcome key somewhere — if this fails the scan is matching nothing")


func test_the_outcome_keys_are_the_ones_this_lane_actually_wired() -> void:
	## The list above is only meaningful if it names keys the resolver really reads. A stale entry
	## would make the ratchet guard a key nobody uses and quietly shrink its own corpus.
	var code: String = GdSource.code_of(GRIND)
	assert_gt(code.length(), 5000, "CONTROL: the resolver was actually read")
	var missing: Array = []
	for k in OUTCOME_KEYS:
		if not code.contains('"%s"' % k):
			missing.append(k)
	assert_eq(missing, [],
		"these are listed as outcome keys the grind reads, and it does not read them: %s" % str(missing))
