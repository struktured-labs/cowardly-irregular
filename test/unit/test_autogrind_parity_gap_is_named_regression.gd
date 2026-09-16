extends GutTest

## THE RESOLVER-VS-LIVE PARITY LEDGER. abilities.json authors 70 keys; BattleManager reads far more of
## them than HeadlessBattleResolver does, and every gap is a way the grind silently simulates a
## different game from the one it claims to be testing. Six have been closed this way already —
## `heal_amount` (cure healed 20 instead of 1300), `mp_amount`, `hits`, `drain_percentage`,
## `secondary_effect`, `scales_with` — each found by hand, one at a time, by someone re-deriving the
## same census from scratch.
##
## ⛔ I TOLD THE FLEET THIS CENSUS WAS "NEARLY OUT" AND IT WAS NOT. I had been working from a view
## filtered to keys authored by 3+ abilities, which hid THIRTY single-ability keys — among them
## `crit_chance`, `ignores_defense`, `ignores_resistance`, `recoil_pct` and `damage_variance`, several
## of which look like real divergences. A filtered census reads exactly like a complete one. This file
## exists so the next person reads a list instead of rebuilding one, and so a NEW divergence announces
## itself instead of waiting to be stumbled over.
##
## WHAT THIS FILE IS NOT: it is not a claim that the unexamined keys are harmless. They are recorded
## as UNEXAMINED precisely because nobody has checked them, and saying so is the point.
##
## ⚠️ INSTRUMENT, STATED. A quoted-key search over two NAMED files is trustworthy only on ZEROES: a
## HIT can be a comment or an unrelated string, so "live reads it" is weak evidence, while "the grind
## contains this key nowhere" is strong. Every arm below fires on a zero. Corpus: exactly
## BattleManager.gd and HeadlessBattleResolver.gd, read whole — not a glob, after the globstar
## corpus failure @cowir-sprites published today.

const LIVE := "res://src/battle/BattleManager.gd"
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## Assessed, with the reason. You cannot silence an entry green here, only explain it green — and an
## entry that stops being true reds (arm 2), so a declaration cannot outlive its fact.
const DECLARED := {
	"name": "presentation only — the grind renders nothing",
	"description": "presentation only — the grind renders nothing",
	"target_type": "consumed UPSTREAM by AutobattleSystem, which hands _resolve_ability an already-resolved target list",
	"summon_id": "live's own spawn is SCENE-SIDE: _execute_summon only emits monster_summoned, and BattleScene builds the combatant. Porting it headless also decides whether summoned enemies grant EXP, which changes the grind's reward economy — struktured's call, not a repair",
	"summon_count": "see summon_id — same scene-side spawn",
	"summon_duration": "see summon_id — same scene-side spawn",
	"summon_message": "battle-log flavour for a spawn the grind does not perform",
	"corruption_risk": "SAVE corruption from meta abilities during automated play is a stakes ruling (CLAUDE.md: 'save corruption: actual mechanic, not just flavor'), not a parity repair",
	"corruption_amount": "see corruption_risk — same stakes ruling",
}

## Fixed and awaiting a fold. Named so arm 4 does not red on them, and asserted by NOTHING ELSE on
## purpose: they are transient, and an arm that reds the moment they land would put a red in
## cowir-main's fold for work that succeeded. When they land the live-only set simply shrinks, which
## arm 4 permits silently.
const CLOSED_PENDING_FOLD := [
	"drain_percentage",
	"secondary_effect", "secondary_chance", "secondary_modifier", "secondary_target",
	"scales_with", "max_multiplier",
]

## Today's gap, recorded rather than excused. This set may SHRINK freely — that is someone closing a
## gap — but it may not GROW without the new key being named here or in DECLARED.
const UNEXAMINED := [
	"absorb_amount", "ap_gain", "cost", "countdown", "crit_chance", "damage_to_self_pct",
	"damage_variance", "drain_mp", "element_boost", "element_boost_modifier", "evasion_bonus",
	"guaranteed_escape", "ignores_defense", "ignores_evasion", "ignores_resistance", "max_depth",
	"meta_effect", "mp_restore_percent", "multiplier", "next_attack_multiplier", "penalty",
	"priority", "recoil_pct", "regen_per_turn", "steals", "success_rate", "threat_class",
]


func _authored_keys() -> Array:
	var ab: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var keys: Dictionary = {}
	for a in ab.values():
		for k in (a as Dictionary).keys():
			keys[k] = true
	return keys.keys()


func _live_only() -> Array:
	var live: String = GdSource.code_of(LIVE)
	var grind: String = GdSource.code_of(GRIND)
	var out: Array = []
	for k in _authored_keys():
		var q: String = '"%s"' % k
		if live.contains(q) and not grind.contains(q):
			out.append(k)
	out.sort()
	return out


func test_the_instrument_can_tell_the_two_engines_apart() -> void:
	## Anti-vacuity, both directions. Without this a stripper that returned "" would report every key
	## as read by neither and the ratchet below would pass on an empty world.
	var live: String = GdSource.code_of(LIVE)
	var grind: String = GdSource.code_of(GRIND)
	assert_gt(live.length(), 50000, "CONTROL: BattleManager was actually read")
	assert_gt(grind.length(), 20000, "CONTROL: the resolver was actually read")
	assert_gt(_authored_keys().size(), 40, "CONTROL: abilities.json must still author a real key set")
	## A key both engines read, so "live-only" is discriminating rather than matching everything.
	assert_true(live.contains('"heal_amount"') and grind.contains('"heal_amount"'),
		"CONTROL: heal_amount is read by BOTH — if this reads as live-only the search is matching nothing")
	## And a key neither can contain, so a hit is not universal.
	assert_false(live.contains('"a_key_no_engine_has_ever_read"'), "CONTROL: the search must be able to miss")


func test_every_declaration_is_explained_not_just_listed() -> void:
	for k in DECLARED:
		assert_gt(str(DECLARED[k]).length(), 20,
			"'%s' is declared with no reason — an entry here must explain itself, never merely appear" % k)


func test_a_declaration_that_stopped_being_true_reds() -> void:
	## @cowir-sprites' rule, taken: a DECLARED-inert key that the runtime later starts reading is worse
	## than an undeclared one, because the next reader trusts the declaration. If the grind learns to
	## read one of these, the reason above is stale and must be removed rather than left standing.
	var gap: Array = _live_only()
	for k in DECLARED:
		assert_true(gap.has(k),
			"'%s' is declared as a live-only gap and the grind now reads it — delete the declaration, or say why that hit is a coincidence" % k)


func test_no_new_divergence_arrives_unnamed() -> void:
	## The ratchet, and the whole point of the file. GROWTH reds by name; a shrink is someone closing
	## a gap and is allowed silently.
	var gap: Array = _live_only()
	var known: Dictionary = {}
	for k in DECLARED:
		known[k] = true
	for k in UNEXAMINED:
		known[k] = true
	for k in CLOSED_PENDING_FOLD:
		known[k] = true
	var unnamed: Array = []
	for k in gap:
		if not known.has(k):
			unnamed.append(k)
	gut.p("    live-only keys: %d   declared: %d   unexamined: %d" % [gap.size(), DECLARED.size(), UNEXAMINED.size()])
	assert_eq(unnamed, [],
		"a key the live engine reads and the grind does not has appeared unnamed: %s — add it to UNEXAMINED, or to DECLARED with a reason, or close the gap" % str(unnamed))


func test_the_ledger_does_not_claim_the_backlog_is_empty() -> void:
	## A ledger whose UNEXAMINED list has quietly emptied while divergences remain would read as "all
	## clear". If someone closes them all, this arm reds and asks for the file to be retired honestly
	## rather than left asserting nothing.
	var gap: Array = _live_only()
	var unexamined_still_open: Array = []
	for k in UNEXAMINED:
		if gap.has(k):
			unexamined_still_open.append(k)
	if unexamined_still_open.is_empty():
		assert_true(false,
			"every unexamined divergence has been closed — retire this ledger deliberately rather than leaving an empty list that reads as a clean bill of health")
	else:
		gut.p("    still open: %s" % str(unexamined_still_open))
		assert_gt(unexamined_still_open.size(), 0, "the backlog is real and named")


## A gap that REOPENS needs no arm of its own: it leaves DECLARED / UNEXAMINED / CLOSED_PENDING_FOLD
## unmatched, so arm 4 reds on it by name. A hand-written "these are closed" list would have to be
## edited every time one lands, which is how a ledger starts lying.
