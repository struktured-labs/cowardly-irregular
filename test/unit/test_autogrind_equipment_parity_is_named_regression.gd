extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"

## THE SECOND PARITY AXIS, and it exists because my FIRST one cannot see it.
## test_autogrind_parity_gap_is_named_regression censuses `abilities.json`'s 70 top-level keys. Gear
## carries its own battle behaviour in `equipment.json` -> `special_effects`, and NONE of those keys
## appears in abilities.json — so every one of them is invisible to that ledger's ratchet, which is
## the arm whose whole job is "a new divergence announces itself". It announced nothing for fifteen
## keys because they were never in its corpus.
##
## Found via @cowir-battle's resist_ring fix: `status_resistance` had one reader, on the ATTACKER's
## on-hit path, so the ring protected a player only from their own poison_dagger. Their repair is
## live-side. The grind-side question their finding raises is this file: a grinding party's GEAR does
## nothing at all, so the grind reports survivability and rewards for a party wearing no equipment
## effects — measured, it read 0 of 15 when this file was written. It reads 12 of 15 today.
##
## ⚠️ INSTRUMENT, STATED, and it cost me two wrong answers before this one.
##   (1) My first corpus was BattleManager + the resolver, TWO FILES. `fire_damage_bonus` and
##       `fire_resistance` are named in EquipmentSystem.gd, so that corpus called them "dead in both
##       engines" — a claim about a file I had not looked in. Corpus is now ALL of src/.
##   (2) Widening it then produced the opposite error: EquipmentSystem holds a HARDCODED FALLBACK
##       COPY of equipment.json, so the same two keys read as CONSUMED. A data copy in a .gd file is
##       indistinguishable from a consumer to a text search. CLAUDE.md documents this exact shape for
##       `autobattle_advanced`. The discriminator below is structural: a line of the form
##       `"key": value` is a dict-literal ENTRY, never a read.

## Real live behaviour the grind does not model. ONE key remains, down from all fifteen when this
## file was written on 2026-09-16. The set may SHRINK freely — that is someone closing a gap — but it
## may not GROW unnamed. (`exp_while_dead` grants EXP to a KO'd member; it is a REWARD key rather
## than a combat one, so it belongs with the grind's reward accounting rather than the damage path.)
## EMPTY as of 2026-09-17, and the empty list is the point: every gear effect equipment.json authors
## is now either modelled or declared with a reason. It was all FIFTEEN the day this file was
## written. Kept rather than deleted so a NEW authored key has somewhere honest to land.
const GRIND_IGNORES := []

## Modelled by the resolver now, each mirroring live's formula rather than a new one. The set above
## SHRANK into this one, which is the direction this file's ratchet permits silently — but the move
## must be explicit, because "the grind ignores all fifteen" was this file's headline claim and a
## silent shrink would leave it reading as still true.
## Behaviour is pinned in test_autogrind_a_party_wears_its_gear_regression, not here: this file is a
## census and says WHICH keys are modelled, never that they are modelled CORRECTLY.
const GRIND_MODELS := [
	"critical_bonus", "dark_damage_bonus", "evasion_bonus", "exp_while_dead", "familiar_weight_bonus",
	"fire_damage_bonus", "holy_damage_bonus", "ice_damage_bonus", "lightning_damage_bonus",
	"poison_chance", "sleep_chance", "status_resistance", "steal_bonus",
]

## ⛔ THIS CENSUS'S CORPUS IS `special_effects`, AND THAT IS A PREDICATE I CHOSE.
## @cowir-battle's "the predicate is a corpus" applied to this file found a whole category it cannot
## see: `familiar_weight_bonus` is a special_effect, but the monster list it gates on —
## `familiar_weight_static_seed` — is a TOP-LEVEL equipment field. Live reads both (:3123 and :3163).
## A census keyed on special_effects saw one half of a two-part mechanism and reported the other as
## absent, which is how the most grind-relevant gear effect in the game stayed unmodelled.
## Measured 2026-09-17: equipment entries carry 10 distinct fields. `stat_mods` reaches combatant
## stats at equip time, so the grind inherits it; `weapon_type` has ZERO battle reads;
## `familiar_weight_static_seed` was the one with behaviour, and it is now wired.
const NON_SPECIAL_EFFECT_FIELDS_WITH_BEHAVIOUR := ["familiar_weight_static_seed"]

## ⛔ THE THIRD SHAPE, AND I PUBLISHED A WRONG FINDING BEFORE @cowir-battle CORRECTED IT.
## This file first listed seven of the above as INERT_EVERYWHERE — "authored on gear a player can buy,
## consumed by nothing" — and had an ARM asserting it. The arm passed. It was false.
##   1. MISSING READ   the key is nowhere. What a literal search finds.
##   2. DATA COPY      the key appears in a .gd as `"key": value` — EquipmentSystem's hardcoded
##                     fallback copy of equipment.json. Looks consumed, is not. Discriminator below.
##   3. DERIVED KEY    the consumer never spells the key:
##                       BattleManager.gd:5080  _sum_equipment_special_effect(caster, element + "_damage_bonus")
##                       Combatant.gd:993       var key: String = element + "_resistance"
##                       BattleScene.gd:111     key.ends_with("_damage_bonus")
##                     Four of the five *_damage_bonus keys occur ZERO times in src/ and are fully
##                     consumed. flame_sword/ice_blade/holy_staff/thunder_rod/bone_staff and
##                     bone_armor/dragon_mail all land their values.
## 🔑 Shape 3 is the one where WIDENING THE CORPUS MOVES YOU FURTHER FROM THE ANSWER — a bigger sweep
## adds only more data copies and comments, and the structural discriminator rejects all of them
## CORRECTLY on its way to the wrong verdict. A literal census cannot answer "is this consumed"; only
## reading the consumer can. The suffix guard below is why this file's GRIND-side zero survives it.
const DERIVED_KEY_SUFFIXES := ["_damage_bonus", "_resistance"]

## ⛔ MODELLED BY CONSTRUCTION, NOT BY LITERAL. These five are read as `element + "_damage_bonus"`,
## mirroring BattleManager:5089 — so they are WIRED and ABSENT from the resolver's text at once,
## which is the exact combination that made an earlier version of this file publish "inert" about
## them. An entry here is a PROMISE that the construction exists, and the derived-key arm below
## verifies the promise rather than taking it.
## ⚠️ THE GRIND IS MORE THAN THE RESOLVER, and the liveness arm below scans only the resolver. The
## reward path lives in AutogrindSystem, so a key read there measures as ABSENT while it is working.
## Named here instead of widening the scan silently — a wider corpus would also stop the arm noticing
## a key that moved to a file nobody expected. Each entry names the FILE and the MARKER, because
## exp_while_dead is read by DELEGATION (BattleManager owns the predicate) and its own literal
## appears in neither grind file.
const MODELLED_ELSEWHERE := {
	"exp_while_dead": ["res://src/autogrind/AutogrindSystem.gd", "earns_exp_while_dead"],
}


const MODELLED_BY_CONSTRUCTION := {
	"fire_damage_bonus": 'element + "_damage_bonus"',
	"ice_damage_bonus": 'element + "_damage_bonus"',
	"holy_damage_bonus": 'element + "_damage_bonus"',
	"lightning_damage_bonus": 'element + "_damage_bonus"',
	"dark_damage_bonus": 'element + "_damage_bonus"',
}

## Assessed and deliberately not modelled, with the reason. You cannot silence an entry here, only
## explain it — and an explanation that stops being true is a red rather than a quiet drift.
const DECLARED := {
	## ⚠️ NOT A GAP — the two engines already AGREE, measured rather than assumed. These are read by
	## Combatant.take_elemental_damage (:929-985), which live calls ONLY from _tick_summon_followup —
	## a summon path the parity ledger already declares. Both engines' magic arms call
	## calculate_elemental_modifier (:914-928), which does NOT consult equipment resistance. Wiring
	## them into the resolver would make the grind resist where the real game does not.
	## The neighbouring *_damage_bonus keys look identical and ARE a gap; only reading which Combatant
	## function each path calls tells them apart.
	"fire_resistance": "read by Combatant.take_elemental_damage, which live calls only from _tick_summon_followup; both engines' magic arms use calculate_elemental_modifier, which does not consult it — so they agree",
	"dark_resistance": "see fire_resistance — same reader, same declared summon path",
}

## ⛔ KEYS AUTHORED IN BOTH CORPORA, WITH THE OWNER NAMED. The disjointness arm below found this on
## its first run, and it is the precise failure it was written to describe: `evasion_bonus` is an
## abilities.json key AND a gear special_effect, and the abilities ledger had already parked it in
## UNDECIDED_LIVE_SIDE for the reason "read off equipment rather than the ability" — correctly
## identifying that it did not own the key, at a time when no equipment census existed to pick it up.
## So it belonged to nobody. It belongs HERE: the read is equipment-side, and it is in GRIND_IGNORES.
const OVERLAP_OWNED := {
	"evasion_bonus": "read off EQUIPMENT, not off the ability — the abilities ledger parks it in UNDECIDED_LIVE_SIDE for exactly that reason, so this file owns it. Listed in GRIND_MODELS since it was wired; this line said GRIND_IGNORES until 2026-09-17, describing where it sat when the note was written",
}


func _authored_effect_keys() -> Array:
	var raw: String = FileAccess.get_file_as_string("res://data/equipment.json")
	var eq: Dictionary = JSON.parse_string(raw)
	var keys: Dictionary = {}
	for v in eq.values():
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var se: Variant = (v as Dictionary).get("special_effects")
		if typeof(se) == TYPE_DICTIONARY:
			for k in (se as Dictionary):
				keys[k] = true
		else:
			for v2 in (v as Dictionary).values():
				if typeof(v2) != TYPE_DICTIONARY:
					continue
				var se2: Variant = (v2 as Dictionary).get("special_effects")
				if typeof(se2) == TYPE_DICTIONARY:
					for k2 in (se2 as Dictionary):
						keys[k2] = true
	var out: Array = keys.keys()
	out.sort()
	return out


func _gd_files() -> Array:
	var found: Array = []
	var stack: Array = ["res://src"]
	while not stack.is_empty():
		var dir: String = str(stack.pop_back())
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			var full: String = "%s/%s" % [dir, name]
			if d.current_is_dir():
				stack.append(full)
			elif name.ends_with(".gd"):
				found.append(full)
			name = d.get_next()
		d.list_dir_end()
	return found


## A CONSUMER names the key somewhere other than a dict-literal entry or a comment. `"key": value` is
## data; `get("key")` is a read. This is the discriminator the two-file corpus did not have.
func _consumer_lines(key: String, files: Array) -> Array:
	var quoted: String = '"%s"' % key
	var hits: Array = []
	for f in files:
		var code: String = GdSource.code_of(str(f))
		if not code.contains(quoted):
			continue
		for line in code.split("\n"):
			if not line.contains(quoted):
				continue
			var t: String = line.strip_edges()
			if t.begins_with("#"):
				continue
			if RegEx.create_from_string('^"%s"\\s*:' % key).search(t) != null:
				continue   ## a dict-literal entry: DATA, not a read
			hits.append("%s: %s" % [str(f).get_file(), t.substr(0, 70)])
	return hits


## ⛔ CLAIMS THIS FILE HAS RETRACTED, AND THE SHA THAT RETRACTED EACH.
## @cowir-main lost time to this on the `.374` fold: my retraction REWROTE the arm rather than
## deleting the file, and kept the retracted name in the prose that explains it — deliberately, since
## the prose IS the lesson. So the obvious check ("is the file gone; does the phrase grep") reads
## IDENTICALLY to the un-retracted state. Their discriminator was right and is the structural one:
##     the grep answered about a SYMBOL   — "is INERT_EVERYWHERE present"  -> yes, in a comment
##     the question was about an ARM      — "does anything ASSERT it"      -> no
## This makes that answer come from a test instead of from whoever remembers to write the better
## pattern. It is @cowir-battle's DERIVED KEY pointed the other way: theirs is a consumer with no
## literal, so a search UNDER-reports; this is a literal with no consumer, so a search OVER-reports.
## Both are "the text is not the behaviour", and in both, widening the search makes it worse.
const RETRACTED_CLAIMS := {
	"INERT_EVERYWHERE": "db276f500 retracted it. Seven gear effects were listed as consumed by nothing in src/, with a passing arm asserting it. @cowir-battle showed all seven are read by a DERIVED key — BattleManager:5080 builds element + \"_damage_bonus\" and Combatant:993 builds element + \"_resistance\" — so four of them occur zero times in src/ and are fully live.",
}


func test_a_retracted_claim_survives_as_prose_and_never_as_an_arm() -> void:
	## The retracted name is ALLOWED here — in comments, where the lesson lives. What must never come
	## back is a declaration or an assertion, which is what "the claim is still being made" means.
	var own: String = GdSource.code_of(get_script().resource_path)
	assert_gt(own.length(), 1000, "CONTROL: this file's own source was actually read")

	## Scope out the registry itself: its KEYS are these names, on code lines, by construction.
	var reg_at: int = own.find("const RETRACTED_CLAIMS")
	assert_gt(reg_at, 0, "CONTROL: the registry must be locatable, or the slice below is the whole file")
	var reg_end: int = own.find("\n}", reg_at)
	assert_gt(reg_end, reg_at, "CONTROL: the registry's end must be locatable")
	var scanned: String = own.substr(0, reg_at) + own.substr(reg_end)

	var still_asserted: Array = []
	for name in RETRACTED_CLAIMS:
		for line in scanned.split("\n"):
			if not line.contains(str(name)):
				continue
			if line.strip_edges().begins_with("#"):
				continue   ## prose: this is where a retraction is SUPPOSED to live
			still_asserted.append("%s <- %s" % [name, line.strip_edges().substr(0, 60)])
	assert_eq(still_asserted, [],
		"a retracted claim is being made again in CODE, not merely explained in prose: %s" % str(still_asserted))


func test_the_retraction_check_can_actually_see_code() -> void:
	## LIVENESS, per @cowir-controller: an empty result is ambiguous between "no code occurrences" and
	## "the scan found nothing at all". A name that IS live code must be found on a non-comment line,
	## or the arm above is green for the wrong reason.
	var own: String = GdSource.code_of(get_script().resource_path)
	var code_hits: int = 0
	var prose_hits: int = 0
	for line in own.split("\n"):
		if not line.contains("GRIND_IGNORES"):
			continue
		if line.strip_edges().begins_with("#"):
			prose_hits += 1
		else:
			code_hits += 1
	gut.p("    liveness: GRIND_IGNORES on %d code lines, %d prose lines" % [code_hits, prose_hits])
	assert_gt(code_hits, 0,
		"CONTROL: a name that IS live code must register on a code line, else the retraction arm's empty result means nothing")


func test_every_retraction_names_the_commit_that_made_it() -> void:
	## A bare list would rot into "someone said this was wrong once". The SHA is what lets the next
	## reader go and read the correction rather than re-deriving it, or re-publishing the claim.
	assert_gt(RETRACTED_CLAIMS.size(), 0,
		"the registry has emptied — delete it deliberately rather than leaving it asserting nothing")
	var unexplained: Array = []
	for name in RETRACTED_CLAIMS:
		var why: String = str(RETRACTED_CLAIMS[name])
		if why.length() < 60 or RegEx.create_from_string("[0-9a-f]{7,}").search(why) == null:
			unexplained.append(str(name))
	assert_eq(unexplained, [],
		"a retraction must name the commit that made it and say what was wrong: %s" % str(unexplained))


func test_the_sweep_actually_reads_the_tree() -> void:
	## CONTROL. Every arm below fires on a ZERO, and a zero is what an empty corpus looks like too.
	var files: Array = _gd_files()
	gut.p("    swept %d .gd files under res://src" % files.size())
	assert_gt(files.size(), 50, "CONTROL: the walk must find the source tree, or every 'nothing reads this' below is vacuous")
	var probe: Array = _consumer_lines("status_resistance", files)
	assert_gt(probe.size(), 0, "CONTROL: a key with a KNOWN reader must be found by this instrument, or its zeroes mean nothing")


func test_every_authored_gear_effect_is_named_here() -> void:
	## The ratchet, and the reason this file exists: the abilities ledger's equivalent arm could never
	## fire on these, because equipment.json is not in its corpus.
	var known: Dictionary = {}
	for k in GRIND_IGNORES:
		known[k] = true
	for k in GRIND_MODELS:
		known[k] = true
	for k in DECLARED:
		known[k] = true
	var authored: Array = _authored_effect_keys()
	assert_gt(authored.size(), 10, "CONTROL: equipment.json must actually yield special_effects keys")
	var unnamed: Array = []
	for k in authored:
		if not known.has(k):
			unnamed.append(k)
	gut.p("    authored gear effects: %d | ignored %d + modelled %d + declared %d = %d named" % [authored.size(), GRIND_IGNORES.size(), GRIND_MODELS.size(), DECLARED.size(), GRIND_IGNORES.size() + GRIND_MODELS.size() + DECLARED.size()])
	assert_eq(unnamed, [],
		"a gear effect is authored and named nowhere in this file: %s — add it to GRIND_IGNORES, or to DECLARED with a reason" % str(unnamed))


func test_no_gear_key_is_read_by_a_derived_key_in_the_grind() -> void:
	## ⛔ THE ARM THAT SURVIVES SHAPE 3, now that the grind legitimately reads equipment. Its first
	## version asked "does the resolver touch equipment at all", which was the right question while
	## the answer was no and became useless the moment it was yes — it fired on the helper's own name.
	## The real question is narrower and stays true: is any gear key assembled by CONCATENATION, which
	## the literal census in this file would miss? The helper takes its key as an ARGUMENT, so every
	## call site spells the key and the census sees it.
	var grind: String = GdSource.code_of(GRIND)
	assert_gt(grind.length(), 10000, "CONTROL: the resolver was actually read")
	## ⚠️ ITS JOB CHANGED AGAIN when the resolver gained a DELIBERATE construction mirroring
	## BattleManager:5089. Forbidding all concatenation would forbid parity, so the question narrowed
	## once more: is every construction DECLARED? An undeclared one is what makes the literal census
	## silently blind; a declared one is a key wired the way live wires it.
	var declared_forms: Dictionary = {}
	for k in MODELLED_BY_CONSTRUCTION:
		declared_forms[str(MODELLED_BY_CONSTRUCTION[k])] = true
	var undeclared: Array = []
	for line in grind.split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("#"):
			continue   ## the helper's own annotation NAMES the shape; that is prose, not a read
		for suffix in DERIVED_KEY_SUFFIXES:
			if RegEx.create_from_string('\\+\\s*"%s"' % suffix).search(t) == null:
				continue
			var matched: bool = false
			for form in declared_forms:
				if t.contains(str(form)):
					matched = true
			if not matched:
				undeclared.append(t.substr(0, 70))
	assert_eq(undeclared, [],
		"a gear key is built by concatenation and is NOT declared in MODELLED_BY_CONSTRUCTION, so this file's literal census is blind to it: %s" % str(undeclared))
	var empty_promises: Array = []
	for form in declared_forms:
		if not grind.contains(str(form)):
			empty_promises.append(str(form))
	assert_eq(empty_promises, [],
		"a construction is DECLARED and the resolver does not contain it — the promise is empty: %s" % str(empty_promises))


func test_the_modelled_keys_are_actually_present_in_the_resolver() -> void:
	## LIVENESS for the list above: a key can be moved into GRIND_MODELS by editing this file alone,
	## and then the census would claim a gap was closed that nobody closed.
	var grind: String = GdSource.code_of(GRIND)
	## ⚠️ A key read by CONSTRUCTION is exempt from the literal check and pays for the exemption by
	## naming its construction in MODELLED_BY_CONSTRUCTION, which the derived-key arm verifies.
	var absent: Array = []
	for k in GRIND_MODELS:
		if MODELLED_BY_CONSTRUCTION.has(k):
			continue
		if MODELLED_ELSEWHERE.has(k):
			var where: Array = MODELLED_ELSEWHERE[k]
			var other: String = GdSource.code_of(str(where[0]))
			assert_gt(other.length(), 1000, "CONTROL: %s was actually read" % str(where[0]))
			if not other.contains(str(where[1])):
				absent.append("%s (expected marker '%s' in %s)" % [k, str(where[1]), str(where[0])])
			continue
		if not grind.contains('"%s"' % k):
			absent.append(k)
	gut.p("    modelled: %d — %d literal, %d by construction, %d elsewhere" % [GRIND_MODELS.size(), GRIND_MODELS.size() - MODELLED_BY_CONSTRUCTION.size() - MODELLED_ELSEWHERE.size(), MODELLED_BY_CONSTRUCTION.size(), MODELLED_ELSEWHERE.size()])
	assert_eq(absent, [],
		"a key is listed as modelled and the resolver does not name it — the list moved without the code: %s" % str(absent))


func test_an_ignored_key_is_really_ignored() -> void:
	## ⛔ RETIRED AND REPLACED 2026-09-17, by its own demand. This arm used to assert the ignore list
	## was SHRINKING — `modelled.size() < GRIND_IGNORES.size()` — which is exactly right while a gap
	## is being closed and cannot hold once it IS closed: at zero it reads `0 < 0` and reds. It fired
	## the moment exp_while_dead moved out, saying "retire this list deliberately rather than leaving
	## it asserting nothing". That is the trigger working, not a failure, and this is the retirement.
	##
	## The successor keeps the question worth asking and drops the one that expired: a key listed as
	## IGNORED must genuinely be absent from the grind. True at any list size, including zero, and it
	## reds on the real mistake — labelling a key ignored while the code models it, which would let
	## this census under-report its own progress the way it once over-reported the gap.
	var grind: String = GdSource.code_of(GRIND)
	assert_gt(grind.length(), 10000, "CONTROL: the resolver was actually read")
	## ⚠️ THE POSITIVE CONTROL CARRIES THE ARM WHILE THE LIST IS EMPTY. A loop over nothing passes
	## whatever it asserts, and an empty GRIND_IGNORES is the expected state now — so without this,
	## a broken pattern and a closed gap produce the same green forever.
	var probe: String = "critical_bonus"
	assert_true(GRIND_MODELS.has(probe), "CONTROL: the probe key must be one this file calls modelled")
	assert_true(grind.contains('"%s"' % probe),
		"CONTROL: the pattern must be able to MATCH — if it cannot find a key the resolver demonstrably reads, every absence below is an artifact")
	var mislabelled: Array = []
	for k in GRIND_IGNORES:
		if grind.contains('"%s"' % k):
			mislabelled.append(k)
	gut.p("    ignored keys: %d · of those the grind actually names: %s" % [GRIND_IGNORES.size(), str(mislabelled)])
	assert_eq(mislabelled, [],
		"a key is listed as IGNORED and the resolver names it — either it was wired and the list never moved, or the label is wrong: %s" % str(mislabelled))


func test_this_axis_is_invisible_to_the_abilities_ledger() -> void:
	## ⛔ THE ARM THAT JUSTIFIES A SECOND FILE. If a gear key ever also appeared in abilities.json, the
	## two censuses would overlap and each could assume the other covered it. They are disjoint today,
	## which is exactly why the abilities ratchet stayed green through fifteen unmodelled keys.
	var ab: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var ability_keys: Dictionary = {}
	for a in ab.values():
		for k in (a as Dictionary):
			ability_keys[k] = true
	assert_gt(ability_keys.size(), 50, "CONTROL: abilities.json keys were actually collected")
	var unnamed: Array = []
	var overlap: Array = []
	for k in _authored_effect_keys():
		if ability_keys.has(k):
			overlap.append(k)
			if not OVERLAP_OWNED.has(k):
				unnamed.append(k)
	gut.p("    ability keys: %d | gear effect keys: %d | overlap: %s" % [ability_keys.size(), _authored_effect_keys().size(), str(overlap)])
	assert_eq(unnamed, [],
		"a key is authored in BOTH corpora and neither census claims it, so each may assume the other owns it: %s" % str(unnamed))
	assert_gt(OVERLAP_OWNED.size(), 0,
		"the overlap has emptied — if no key is shared any more, delete OVERLAP_OWNED deliberately rather than leaving it asserting nothing")
