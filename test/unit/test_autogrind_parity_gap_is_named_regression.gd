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
## ⛔ TWO AXES, AND THE SECOND ONE EXISTS BECAUSE THE FIRST MISSED TWO OF MY OWN FIXES. Asking "does
## each engine read this key" is not enough: every ability type dispatches to ONE executor, so a key
## read in `_execute_physical_ability` does nothing for a `magic` ability. I wired `hits` into BOTH
## grind arms when live reads it only on the physical path, and `drain_percentage` into both when live
## reads it only on the magic path — so the grind hit harder than the game for `temporal_strike` and
## healed `bone_warden` where the game heals nothing. THIS LEDGER SCORED BOTH "CONSUMED IN BOTH
## ENGINES" and was right on axis 1 and blind on axis 2. @cowir-battle's 2d14d92d is the distinction.
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
	"ignores_resistance": "EXAMINED 2026-09-16 and UNREACHABLE in a grind, so deliberately not wired. Its two owners (exploit_weakness, fourth_wall_break) are cast only by meta_knight, which is in no enemy pool — and this lane's OWN extra spawn path does not reach it either: _spawn_meta_boss builds a procedural enemy with a generated name, it does not instantiate a monsters.json id. Wiring it would add a mechanism no grind can exercise, and the arm below reds if either caster becomes drawable",
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
	"absorb_amount", "ap_gain", "countdown", "crit_chance",
	"element_boost", "element_boost_modifier", "guaranteed_escape", "ignores_evasion", "max_depth",
	"meta_effect", "mp_restore_percent", "priority", "recoil_pct",
	"steals", "success_rate", "threat_class",
]

## ⛔ THE THIRD STATE, and it exists because I published a backlog number my instrument could not
## support. Axis 1 calls a key live-only when live CONTAINS it and the grind does not. The grind side
## is a ZERO and trustworthy; the LIVE side is a HIT, and a hit can be a string, a different subject's
## field, or prose. So "23 unexamined gaps" was 19 gaps plus 4 keys that may not be gaps at all.
##
## These four have the NAME in BattleManager and no `ability.get`/`[]`/`.has` access anywhere in it:
## `cost` is shop/ability-menu pricing, `multiplier` and `penalty` are local variables, `evasion_bonus`
## is read off equipment rather than the ability. UNDECIDED, not absolved — a text search cannot tell
## "read another way" from "not read", and saying so is the point.
##
## Taken from @cowir-sprites' three-state manifest census and @cowir-music's re-measurement of their
## own: both had drawn a conclusion from the non-zero side of an instrument they had correctly
## labelled trustworthy only on zeroes. Mine did the same thing to a number I put in a channel.
const UNDECIDED_LIVE_SIDE := ["cost", "evasion_bonus", "multiplier", "penalty"]


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
	for k in UNDECIDED_LIVE_SIDE:
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


## AXIS 2: which PATH each engine reads the key on.
##
## A key is realised in the grind by a symbol rather than by its own name — `hits` is read once at the
## top of _resolve_ability and consumed by a loop inside an arm — so the arm a key acts on cannot be
## found by searching for the key. This map says how each key shows up, and it is REQUIRED to cover
## every key both engines read (arm 7), so wiring a new one without declaring its path reds.
const GRIND_PATH_MARKER := {
	"hits": "for _h in hits",
	"drain_percentage": "_drain_to(",
	"scales_with": "_scaled_base(",
	"drain_mp": "_siphon_mp(",
	"ignores_defense": "ability.get(\"ignores_defense\"",
	"damage_to_self_pct": "_recoil_to(",
	"damage_variance": "ability.get(\"damage_variance\"",
	"regen_per_turn": "ability.get(\"regen_per_turn\"",
	## PRODUCER/CONSUMER key, so the marker is the PRODUCER. Live reads the authored field in
	## _execute_support_ability and consumes its stored effect in two OTHER executors (:4374 attack,
	## :4969 magic); axis 2 asks where the authored key is READ, not where its effect is spent. My
	## first marker pointed at a consumer and this arm caught it — the grind's support arm reads the
	## key exactly where live's support executor does.
	"next_attack_multiplier": "ability.get(\"next_attack_multiplier\"",
	## ⚠️ ALL FOUR secondary_* KEYS, AND THREE OF THEM WERE INVISIBLE TO THIS MAP UNTIL 2026-09-16.
	## They live in `_apply_secondary_effect`, which `_execute_support_ability` calls — but the old
	## walk-back skipped past any non-executor function, so a read inside a helper was credited to
	## whichever executor happened to precede it in the file and the count came out wrong. With the
	## walk-back fixed (see _executors_for_read) they resolve to the support executor, which is where
	## live reads them and where the resolver calls the same helper. One marker covers the four:
	## they are the same call, and a key that travelled alone would be the anomaly.
	"secondary_effect": "_apply_secondary_effect(",
	"secondary_chance": "_apply_secondary_effect(",
	"secondary_target": "_apply_secondary_effect(",
	"secondary_modifier": "_apply_secondary_effect(",
}

## Read by both engines, live-confined to one executor, and NOT path-assessed by me. They are here
## rather than exempted by a cleverer rule: I narrowed the arm's heuristic twice to fit the answer and
## stopped, because a rule that keeps shrinking to match its result is how a guard stops meaning
## anything. Each of these reads differently in the grind by structure rather than by divergence —
## `mp_cost` is spent at the top of _resolve_ability BEFORE the match, where live spends it inside an
## executor — but "looks structural" is not "checked", and the difference is the whole point of axis 2.
const AXIS2_UNASSESSED := ["mp_cost", "stat_modifier", "element", "max_multiplier", "stat", "modifier"]

## ⛔ WHAT AXIS 2 DOES NOT CHECK, named because the arm's name implies more than it does.
## It compares ONE marker per key against ONE live executor: the site where the AUTHORED KEY IS READ.
## For a PRODUCER/CONSUMER key that is the producer only — `next_attack_multiplier` is read in live's
## support executor and its stored effect is SPENT in two others (:4374 attack, :4969 magic), and
## nothing here would notice if the grind spent it on one path or three.
##
## That coverage exists, in the fix's own file, and the map below pins WHERE so it cannot be deleted
## while this ledger keeps reporting green. @cowir-cutscenes' shape, an hour old: a guard naming the
## right subject, asserting a true thing, and covering one half reads greener than no guard at all —
## theirs tested `_set_choice_flag` while the menu it was named for went unguarded.
const CONSUMER_COVERAGE := {
	"next_attack_multiplier": [
		"res://test/unit/test_autogrind_charged_strike_lands_regression.gd",
		["test_a_charge_reaches_the_next_swing", "test_the_magic_path_consumes_it_too_and_only_once",
		 "test_the_charge_is_spent_once_and_not_kept"],
	],
}

## The live executor each key must be read from, measured out of BattleManager rather than listed —
## see _live_executor_of. The grind arm that must match it:
const ARM_FOR_EXECUTOR := {
	"_execute_physical_ability": '"physical":',
	"_execute_magic_ability": '"magic":',
	"_execute_support_ability": '"support", "song", "status":',
}


## ⛔ THE WALK-BACK USED TO SKIP PAST NON-EXECUTOR FUNCTIONS AND MIS-ATTRIBUTE. It did
## `rfind("func _execute_")`, so a key read inside an ordinary helper was credited to whichever
## executor happened to sit ABOVE that helper in the file. On 2026-09-16 the duplicated status block
## became `_apply_ability_status`, which sits just below `_execute_physical_ability` — and
## `effect_chance`, read by both damage executors, suddenly measured as physical-only and this file
## demanded a declaration for it. The fix stops at the NEAREST enclosing func of any name, and
## resolves a helper to every executor that calls it. Nothing about the ledger's subject changed.
func _enclosing_func(at: int, live: String) -> String:
	var owner: int = live.substr(0, at).rfind("\nfunc ")
	if owner < 0:
		return ""
	var line: String = live.substr(owner + 1, 80)
	var paren: int = line.find("(")
	return line.substr(5, paren - 5) if paren > 5 else ""


## Every executor a read at `at` belongs to: the enclosing function when that IS an executor,
## otherwise every executor whose own body calls it.
func _executors_for_read(at: int, live: String) -> Array:
	var fn: String = _enclosing_func(at, live)
	if fn == "":
		return []
	if ARM_FOR_EXECUTOR.has(fn):
		return [fn]
	var out: Array = []
	for executor in ARM_FOR_EXECUTOR:
		var e_at: int = live.find("func %s(" % executor)
		if e_at < 0:
			continue
		var e_end: int = live.find("\nfunc ", e_at + 1)
		var body: String = live.substr(e_at, (e_end - e_at) if e_end > e_at else 4000)
		if body.contains(fn + "("):
			out.append(executor)
	return out


## The `func _execute_*` that encloses live's read of this key, or "" if it does not read it.
func _live_executor_of(key: String, live: String) -> String:
	var at: int = live.find('ability.get("%s"' % key)
	if at < 0:
		return ""
	var owners: Array = _executors_for_read(at, live)
	return str(owners[0]) if owners.size() > 0 else ""


## How many DISTINCT per-type executors read this key. Only a key live confines to exactly ONE has a
## path to match: `element`, `duration` and `damage_multiplier` are read by several, so "the same arm"
## is not a property they have. Getting this wrong made arm 7 demand a declaration for ten keys that
## cannot have one.
func _live_executor_count(key: String, live: String) -> int:
	var seen: Dictionary = {}
	var needle: String = 'ability.get("%s"' % key
	var at: int = live.find(needle)
	while at >= 0:
		for name in _executors_for_read(at, live):
			seen[name] = true
		at = live.find(needle, at + 1)
	return seen.size()


## The slice of the resolver belonging to one `match` arm, bounded by the next arm label.
func _grind_arm(code: String, label: String) -> String:
	var start: int = code.find(label)
	if start < 0:
		return ""
	var nxt: int = code.find('\n\t\t"', start + label.length())
	var default_arm: int = code.find("\n\t\t_:", start)
	if default_arm > 0 and (nxt < 0 or default_arm < nxt):
		nxt = default_arm
	return code.substr(start, (nxt - start) if nxt > start else 2000)


func test_every_shared_key_is_read_on_the_same_path_in_both_engines() -> void:
	## THE ARM THAT WOULD HAVE CAUGHT BOTH OF MINE. A key on the wrong arm makes the grind harsher or
	## softer than the game it simulates, and axis 1 cannot see it — both engines "read" the key.
	var live: String = GdSource.code_of(LIVE)
	var grind: String = GdSource.code_of(GRIND)
	assert_gt(live.length(), 50000, "CONTROL: BattleManager was actually read")
	var shared: Array = []
	for k in _authored_keys():
		var q: String = '"%s"' % k
		if live.contains(q) and grind.contains(q):
			shared.append(k)
	assert_gt(shared.size(), 5, "CONTROL: the engines must share a real set of keys")

	var checked: Array = []
	var wrong: Array = []
	for k in GRIND_PATH_MARKER:
		var executor: String = _live_executor_of(k, live)
		if executor == "" or not ARM_FOR_EXECUTOR.has(executor):
			continue  # live reads it outside a per-type executor; axis 2 does not apply
		var marker: String = str(GRIND_PATH_MARKER[k])
		assert_true(grind.contains(marker),
			"CONTROL: '%s' is mapped to marker '%s', which the resolver does not contain — the map is stale" % [k, marker])
		checked.append(k)
		for exec_name in ARM_FOR_EXECUTOR:
			var arm: String = _grind_arm(grind, str(ARM_FOR_EXECUTOR[exec_name]))
			assert_ne(arm, "", "CONTROL: the %s arm must be locatable" % exec_name)
			var present: bool = arm.contains(marker)
			var should: bool = exec_name == executor
			if present != should:
				wrong.append("%s: live reads it in %s, grind %s it in the %s arm" % [
					k, executor, "reads" if present else "does NOT read", exec_name])
	gut.p("    path-checked: %s" % str(checked))
	assert_gt(checked.size(), 2, "CONTROL: at least three keys must actually be path-checked")
	assert_eq(wrong, [],
		"a key is read on a different PATH in each engine, so the grind simulates a different game: %s" % str(wrong))


func test_a_newly_wired_key_must_declare_its_path() -> void:
	## Without this, the map above is a list someone can forget to extend — and a key wired into the
	## grind with no entry would be silently exempt from axis 2, which is how axis 1 failed.
	var live: String = GdSource.code_of(LIVE)
	var grind: String = GdSource.code_of(GRIND)
	var undeclared: Array = []
	for k in _authored_keys():
		var q: String = '"%s"' % k
		if not (live.contains(q) and grind.contains(q)):
			continue
		## Exactly one executor, or the key has no single path to be on.
		if _live_executor_count(k, live) != 1:
			continue
		if not GRIND_PATH_MARKER.has(k) and not AXIS2_UNASSESSED.has(k):
			undeclared.append(k)
	assert_eq(undeclared, [],
		"these keys are read by both engines from a per-type executor and have no entry in GRIND_PATH_MARKER, so nothing checks they are on the same path: %s" % str(undeclared))


func test_the_axis_two_backlog_is_not_silently_empty() -> void:
	## Same guard axis 1 has: a list that quietly empties reads as a clean bill of health. If someone
	## assesses all six, this reds and asks for the list to be retired deliberately.
	assert_gt(AXIS2_UNASSESSED.size(), 0,
		"every axis-2 key has been assessed — move them into GRIND_PATH_MARKER and retire this list on purpose")
	var live: String = GdSource.code_of(LIVE)
	var stale: Array = []
	for k in AXIS2_UNASSESSED:
		if GRIND_PATH_MARKER.has(k):
			stale.append(k)
	assert_eq(stale, [], "these are listed as unassessed AND mapped — one of the two is wrong: %s" % str(stale))


## ⛔ THIS ARM ASSERTED LIVE WAS BROKEN AND IT IS NOT, ANY MORE — and that is the arm working, not
## failing. I examined `regen_per_turn` at 15:00, measured that NEITHER engine delivered it, declared
## it a LIVE defect and handed it to @cowir-battle. They took it (`dcfb2158`), and this arm went red
## in the fold where both halves met, naming the exact line that had changed.
##
## So the fact moved from "neither engine delivers it" to "live delivers, the grind does not" — a NEW
## parity gap that did not exist this morning — and the gap is closed in the same commit rather than
## re-declared. A declaration whose subject has been repaired is stale in the best possible way.
func test_regenerate_is_delivered_by_both_engines_now() -> void:
	var abilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var regen: Dictionary = abilities.get("regenerate", {})
	assert_false(regen.is_empty(), "CONTROL: regenerate must still exist")
	assert_eq(str(regen.get("type", "")), "healing", "CONTROL: it must still be healing-typed — that is what makes the routing load-bearing")
	assert_false(regen.has("heal_amount"), "CONTROL: and still author no heal_amount")
	var live: String = GdSource.code_of(LIVE)
	var at: int = live.find("func _execute_healing_ability")
	assert_gt(at, 0, "CONTROL: the healing executor must be locatable")
	var body: String = live.substr(at, live.find("\nfunc ", at + 10) - at)
	assert_true(body.contains('ability.get("effect"'),
		"live's healing executor no longer inspects `effect` — regenerate may be dead there again, and the grind now routes it expecting live does not")
	var grind: String = GdSource.code_of(GRIND)
	assert_true(grind.contains('category == "healing" and str(ability.get("effect", "")) != ""'),
		"the grind no longer re-points an over-time heal to its support arm, so it heals once and ticks nothing while live regenerates")
func _live_reads_it_as_an_ability_field(key: String, live: String) -> bool:
	var q: String = '"%s"' % key
	return live.contains("ability.get(%s" % q) or live.contains("ability[%s]" % q) or live.contains("ability.has(%s" % q)


func test_the_backlog_distinguishes_a_real_gap_from_a_word_that_appears() -> void:
	## DERIVED, not transcribed: the split is recomputed and compared to the recorded lists, so a key
	## that changes status reds instead of sitting in the wrong bucket. That is the difference between
	## a classification and a note about one.
	var live: String = GdSource.code_of(LIVE)
	assert_gt(live.length(), 50000, "CONTROL: BattleManager was actually read")
	var misfiled: Array = []
	for k in UNEXAMINED:
		if not _live_reads_it_as_an_ability_field(k, live):
			misfiled.append("%s: listed as a real gap, but live never reads it off an ability" % k)
	for k in UNDECIDED_LIVE_SIDE:
		if _live_reads_it_as_an_ability_field(k, live):
			misfiled.append("%s: listed as UNDECIDED, but live DOES read it off an ability — it is a real gap" % k)
	gut.p("    confirmed gaps: %d   undecided: %d" % [UNEXAMINED.size(), UNDECIDED_LIVE_SIDE.size()])
	assert_eq(misfiled, [], "the backlog's own classification is out of date: %s" % str(misfiled))
	## Anti-vacuity in both directions: the discriminator must be able to say yes AND no.
	assert_true(_live_reads_it_as_an_ability_field("hits", live),
		"CONTROL: a key live demonstrably reads off an ability must classify as read")
	assert_false(_live_reads_it_as_an_ability_field("a_key_no_ability_has", live),
		"CONTROL: an invented key must not classify as read")


## ⛔ THE FOURTH STATE — composed-at-runtime — DOES NOT APPLY HERE, and that is measured rather than
## assumed. @cowir-sfx's cue audit has 212 keys absent from the corpus because `play_ability` builds
## `"ability_" + element` at runtime, so a literal scan cannot see a key that fires on every cast.
## An ability FIELD is not like that: both engines read fields with literal keys only, so a zero means
## the key is genuinely unread rather than reached by a name this instrument cannot construct.
##
## If either engine ever reads an ability field through a variable, every zero in this file becomes
## unsound at once — so it reds here rather than silently weakening the whole ledger.
func test_neither_engine_composes_an_ability_field_name() -> void:
	for path in [LIVE, GRIND]:
		var code: String = GdSource.code_of(path)
		assert_gt(code.length(), 20000, "CONTROL: %s was actually read" % path)
		var composed: Array = []
		for line in code.split("\n"):
			for form in ["ability.get(", "ability.has("]:
				var at: int = line.find(form)
				while at >= 0:
					var nxt: String = line.substr(at + form.length(), 1)
					if nxt != "\"":
						composed.append(line.strip_edges())
					at = line.find(form, at + 1)
		assert_eq(composed, [],
			"%s reads an ability field through a non-literal key, so a 'the grind never names it' zero in this ledger no longer means the field is unread: %s" % [path, str(composed)])
	## Anti-vacuity: the scan must be able to SEE a literal access, or an empty result proves nothing.
	assert_true(GdSource.code_of(GRIND).contains('ability.get("hits"'),
		"CONTROL: the scan must find a known literal access, or it is matching nothing")


func test_a_multi_site_key_keeps_its_consumer_coverage_elsewhere() -> void:
	## Axis 2 checks the producer. For a key whose effect is spent in other executors, the arms that
	## prove the SPENDING matches live live in the fix's own file — so this reds if that file or any of
	## those arms disappears, rather than this ledger going on reporting a green it did not earn.
	var missing: Array = []
	for key in CONSUMER_COVERAGE:
		var spec: Array = CONSUMER_COVERAGE[key]
		var path: String = str(spec[0])
		if not FileAccess.file_exists(path):
			missing.append("%s: the file carrying its consumer arms is gone (%s)" % [key, path])
			continue
		var body: String = GdSource.code_of(path)
		assert_gt(body.length(), 1000, "CONTROL: %s was actually read" % path)
		for arm in spec[1]:
			if not body.contains("func %s(" % arm):
				missing.append("%s: %s no longer defines %s" % [key, path, arm])
	assert_eq(missing, [],
		"axis 2 checks only where the authored key is READ; these keys rely on arms elsewhere to check where the effect is SPENT, and that coverage has moved: %s" % str(missing))
	## The map is only meaningful if every key in it is one axis 2 actually treats as producer-only.
	for key in CONSUMER_COVERAGE:
		assert_true(GRIND_PATH_MARKER.has(key),
			"'%s' claims consumer coverage but is not path-checked at all — one of the two is wrong" % key)
