extends GutTest

## GLACIUS CASTS FROST ARMOR AND NOTHING HAPPENS TO THE PARTY.
##
## 2026-09-11. `frost_armor` ships this description: *"Encases itself in frost,
## raising defense and damaging attackers."* Its `effect` is `defense_up` — a defence
## buff and nothing else — and the key that carries the other half,
## `reflect_damage_element: "ice"`, is read by no code in the game.
##
## It is not latent. Glacius, the Frozen Sovereign owns it, and BattleManager's
## `defense_boost` intent selects it deliberately (`effect == "defense_up"`), so the
## cast happens in the fight. The engine HAS the mechanic — `_execute_support_ability`
## writes `add_status("reflect", …)`, and `_execute_attack` and `_execute_physical_ability`
## both consume it; four other abilities use it (magic_reflect, port_block,
## prismatic_reflect, reflect_shield). Frost Armor is the one that declares reflection in
## data and never asks for it.
##
## 📌 Those three were `BattleManager:5699 / 4356 / 4779` when written, and on 2026-09-12 all
## three pointed at unrelated code — a uniform +14 drift from folds nobody in this lane made.
## Symbols now, per the rule that a citation living in a FILE is read by everyone after the
## next fold and is wrong in their face. Each was checked for existence AND for the claim
## being true of it, which are two conditions, not one.
##
## 🔑 THE DISCRIMINATOR THIS FILE IS BUILT ON, because "unread key" alone is too blunt
## a subject — @cowir-sfx's line, earned by nearly filing 313 live manifest entries as
## orphaned: an unread key is only a defect when it STATES SOMETHING THAT HAS NOT
## HAPPENED. The five unread keys in abilities.json split cleanly on that test:
##
##   REDUNDANT   damage_reduction on `default` — take_damage's is_defending arm hardcodes
##               `* 0.5` and the data says 0.5, so they agree TODAY by coincidence
##               of both being 0.5. Editing the data would not move the game.
##   REDUNDANT   next_crit on shadow_step — the behaviour is real, it just lives on
##               the STATUS, not the key. _calculate_crit_chance returns 1.0 for
##               has_status("shadow_step"). Nothing is missing.
##   DEFERRED    bp_gain, bp_cost — the BP bank is unbuilt, and BattleManager says so
##               in a comment at the default_stance arm: "not implemented yet … when
##               BP lands, this arm grows by one line." A recorded decision.
##   MISSING     reflect_damage_element — the description promises it, the engine can
##               do it, and nothing connects them. This is the only one that is a bug.
##
## Which way to settle it is a BALANCE call and deliberately not made here: wiring the
## reflection makes a shipped boss harder; trimming the description makes it weaker
## than authored. Both are one edit. The pin holds the state until someone chooses.

## ⚠️ WHAT THIS CHECK CANNOT SEE — and it caught me writing the file. It matches a key
## by SPELLING anywhere in src/, so a key read for a DIFFERENT SUBJECT counts as
## consumed. `evasion_bonus` is the live instance: abilities author it, and the only
## reader is `_sum_equipment_special_effect(target, "evasion_bonus")` — EQUIPMENT
## special_effects, a different corpus that happens to share the word. I listed it as
## unread on that reasoning and this file's own ratchet corrected me within a minute.
## So "consumed" here means "the string is read somewhere in the engine", never "read
## for abilities". Wrong symbol, same spelling — @cowir-ai's trap, in the guard written
## while reading about it.
##
## ⚠️ SECOND LIMIT, same shape one level out: the corpus is every .gd under src/, and
## src/ CONTAINS UNREACHABLE CODE. `src/ui/MenuScene.gd` is 1,500 lines of hub menu that
## nothing instantiates — MenuScene.tscn is referenced by no file — so a key read only
## there would score CONSUMED while no player can reach the read. @cowir-controller's
## line: a ratchet whose corpus is src/ inherits src/'s dead code, permanently.
## Measured 2026-09-11: 0 of the 70 ability keys have the dead hub as their only
## consumer, so nothing is wrong today. It is stated because a one-level reachability
## check is a claim about the graph's EDGES, not about the player, and this file makes
## the weaker claim.
##
## ⛔ THIRD LIMIT, AND THE ONE THAT BITES: THIS FILE SAYS "THE ENGINE". THERE ARE TWO.
## `HeadlessBattleResolver` is a 1,042-line reimplementation of a 9,207-line BattleManager
## — it reads `ability.get(...)` itself and does NOT delegate ability resolution, borrowing
## BattleManager only for round counts, AP rules and party registration. So a key consumed
## by the live engine and ignored by the grind scores CONSUMED here, and the grind is where
## a player spends hours. Measured on 1f5c8d2d, by literal key spelling in each file (unchanged from b621a0e0):
##
##     read by BOTH engines        13
##     read by the LIVE engine only 45   incl. effect_chance (68 abilities), secondary_effect,
##                                       hits, drain_percentage, corruption_risk, summon_*
##     read by NEITHER               5   <- exactly UNREAD_EFFECT_KEYS, so that part is sound
##
## Two lanes found real defects in precisely this gap in two releases: vanish/shadow_step
## applied and never read (.330), and cleanse writing a status named "cleanse" onto an ally
## while the blind it was cast to cure stayed on. **This file could not have found either** —
## both effects are read by BattleManager, so both score CONSUMED. The verdict below is a
## claim about the LIVE engine and nothing more; the grind's coverage is a separate subject
## and wants its own guard, which is @cowir-battle's census, not this.

const ABILITIES := "res://data/abilities.json"
const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"

## ability effect key -> why it is not read. Every entry is a claim about the ENGINE,
## so each has to be false before its line can be deleted.
##   grows   -> a new ability shipped with an effect key nothing consumes
##   shrinks -> someone wired one; delete the line
const UNREAD_EFFECT_KEYS := {
	"damage_reduction": "REDUNDANT but DIVERGENCE-PRONE — Combatant.take_damage's is_defending arm hardcodes `* 0.5` for is_defending, which happens to equal default's authored 0.5. Edit the data and nothing moves",
	"next_crit": "REDUNDANT — shadow_step's crit is guaranteed via has_status('shadow_step') in _calculate_crit_chance",
	"bp_gain": "DEFERRED — the BP bank is unbuilt; BattleManager's default_stance arm records the decision",
	"bp_cost": "DEFERRED — same BP bank",
	"reflect_damage_element": "MISSING — frost_armor's shipped description promises it, the reflect status exists, nothing connects them. A balance call, not an oversight to silently fix",
}

## Keys that are structure rather than effect, and are read by the loader or by name.
const NON_EFFECT_KEYS := ["id"]

var _cache: Dictionary = {}


func _abilities() -> Dictionary:
	if _cache.has("a"):
		return _cache["a"]
	var raw: String = FileAccess.get_file_as_string(ABILITIES)
	assert_ne(raw, "", "abilities.json must be readable")
	var parsed: Variant = JSON.parse_string(raw)
	var root: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
	var inner: Variant = root.get("abilities", root)
	var out: Dictionary = inner as Dictionary if inner is Dictionary else {}
	_cache["a"] = out
	return out


func _src_blob() -> String:
	if _cache.has("src"):
		return _cache["src"]
	# The consumer corpus: every .gd under src/. A key read anywhere in the engine is
	# read. Walking the tree rather than naming files, so a consumer that moves house
	# does not turn into a false finding.
	var blob: String = ""
	var stack: Array[String] = ["res://src"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name: String = dir.get_next()
		while name != "":
			var full: String = dir_path + "/" + name
			if dir.current_is_dir():
				if not name.begins_with("."):
					stack.append(full)
			elif name.ends_with(".gd"):
				blob += FileAccess.get_file_as_string(full)
			name = dir.get_next()
		dir.list_dir_end()
	_cache["src"] = blob
	return blob


## PREMISE. Both corpora have to be real, or every arm below passes on nothing.
func test_premise_both_corpora_loaded() -> void:
	assert_gt(_abilities().size(), 200,
		"only %d abilities parsed — the walk is not reading abilities.json" % _abilities().size())
	# NAMED MEMBER. The blob is every .gd under src/; a floor of 1M chars still passes
	# if a whole directory stops being walked. BattleManager is the consumer this file
	# is actually about, so its absence must be loud rather than arithmetic.
	assert_true(_src_blob().contains("func _check_one_shot"),
		"the consumer corpus no longer contains BattleManager (its _check_one_shot is absent) — the walk is covering less than it did, and a key would read as unconsumed for that reason")
	assert_gt(_src_blob().length(), 1000000,
		"the src/ walk collected only %d chars — a key would read as unconsumed because the corpus is missing, not because the engine ignores it" % _src_blob().length())


## CONTROL, both directions, on keys whose status is not in dispute.
func test_the_consumption_check_answers_both_ways() -> void:
	var blob: String = _src_blob()
	assert_true(blob.contains("\"stat_modifier\""),
		"CONTROL: stat_modifier is read all over BattleManager; if this reads as unconsumed the corpus walk is broken and every finding below is noise")
	assert_false(blob.contains("\"zzz_not_a_real_ability_key\""),
		"CONTROL: a fabricated key must read as unconsumed, or the check cannot return a positive")


## THE RATCHET, bidirectional over every key authored on an ability.
func test_every_authored_ability_key_is_consumed_or_named() -> void:
	var blob: String = _src_blob()
	var counts: Dictionary = {}
	for aid in _abilities().keys():
		var a: Variant = _abilities()[aid]
		if not (a is Dictionary):
			continue
		for k in (a as Dictionary).keys():
			var key: String = str(k)
			if NON_EFFECT_KEYS.has(key):
				continue
			counts[key] = int(counts.get(key, 0)) + 1

	var unconsumed: Array[String] = []
	var newly_consumed: Array[String] = []
	for k in counts.keys():
		var key: String = str(k)
		var is_read: bool = blob.contains("\"%s\"" % key)
		if is_read and UNREAD_EFFECT_KEYS.has(key):
			newly_consumed.append(key)
		elif not is_read and not UNREAD_EFFECT_KEYS.has(key):
			unconsumed.append("%s (on %d abilities)" % [key, int(counts[k])])
	unconsumed.sort()

	assert_eq(unconsumed.size(), 0,
		"an ability authors an effect key the engine never reads: %s — wire it, or add it to UNREAD_EFFECT_KEYS saying whether it is REDUNDANT, DEFERRED or MISSING" % ", ".join(unconsumed))
	# STALE-EXEMPTION arm. The ratchet above only compares keys the corpus still
	# AUTHORS, so a key that disappears entirely leaves its debt entry behind with
	# nothing to notice — an inert suppression created by deletion rather than by
	# being written wrong. @cowir-autogrind's class, arriving from the other end.
	var orphaned: Array[String] = []
	for k in UNREAD_EFFECT_KEYS.keys():
		if not counts.has(str(k)):
			orphaned.append(str(k))
	orphaned.sort()
	assert_eq(orphaned.size(), 0,
		"UNREAD_EFFECT_KEYS names a key no ability authors any more: %s — the entry is describing a corpus that has moved on. Delete the line." % ", ".join(orphaned))

	assert_eq(newly_consumed.size(), 0,
		"GOOD NEWS, STALE LIST: %s is now read in src/. Delete the key(s) from UNREAD_EFFECT_KEYS so this file stops claiming the engine ignores them." % ", ".join(newly_consumed))


## The one that is a bug rather than bookkeeping, pinned by NAME so a reader of the
## debt list above cannot mistake it for the redundant ones. Fails when frost_armor
## gains a reflecting effect — at which point the description is finally true and the
## UNREAD_EFFECT_KEYS entry has to go with it.
func test_frost_armor_still_promises_a_reflection_it_does_not_perform() -> void:
	var a: Variant = _abilities().get("frost_armor", null)
	# NOT pending(). Measured 2026-09-11 under @cowir-sprites' READER axis: removing
	# frost_armor from abilities.json made this arm go PENDING and the suite stayed
	# GREEN — a skipped arm is indistinguishable from a passing one, and the ability
	# vanishing is exactly the event that makes the debt entry below a lie. If it is
	# genuinely retired, delete this arm AND its UNREAD_EFFECT_KEYS line together.
	assert_true(a is Dictionary,
		"frost_armor is gone from abilities.json — this arm and the reflect_damage_element entry in UNREAD_EFFECT_KEYS are both now claims about an ability that does not exist. Delete them together, or restore the fixture.")
	if not (a is Dictionary):
		return
	var ability: Dictionary = a as Dictionary

	assert_eq(str(ability.get("reflect_damage_element", "")), "ice",
		"fixture drift: frost_armor should still declare reflect_damage_element")
	assert_true(str(ability.get("description", "")).to_lower().contains("damaging attackers"),
		"fixture drift: the description this file is about has changed — re-read it before trusting the verdict below")
	assert_eq(str(ability.get("effect", "")), "defense_up",
		"GOOD NEWS or BAD: frost_armor's effect is no longer defense_up. If it now reflects, delete this arm and the reflect_damage_element entry above. If it changed for another reason, re-derive the verdict.")

	# The engine's reflect vocabulary, named so this arm cannot pass by the mechanic
	# quietly disappearing instead of frost_armor gaining it.
	var blob: String = _src_blob()
	assert_true(blob.contains("\"reflect\""),
		"the reflect status is gone from the engine — frost_armor's missing half is now missing for everyone, which is a different and larger finding")


## CODE ONLY — BOTH HALVES, because this file's arms are PRESENCE ASSERTS and prose satisfies
## a presence assert exactly as well as code does.
##
## The risk, MEASURED rather than asserted — and my first version of this paragraph was wrong,
## which is why the measurement is here instead of the reasoning. The arm asserts `hr` does NOT
## contain the token, and the token it looks for is QUOTED:
##
##     # TODO: honour effect_chance here            raw read -> still GREEN. Not the exposure.
##     # TODO: read the "effect_chance" key here    raw read -> RED, "GOOD NEWS: the headless
##                                                  resolver now reads effect_chance… re-measure
##                                                  the 13/45/5 split"
##     …same comment, stripped                      GREEN
##
## So a bare mention is harmless and a QUOTED one is not — and quoting a key name in a comment
## is an ordinary thing to write. cowir-autogrind is wiring effect_chance into the grind now, so
## the collision is near-term rather than theoretical. The failure is in the GOOD-NEWS
## direction, which is the bad one here: the message instructs the reader to update a count,
## and they would update it from prose.
##
## TWO HALVES, because either alone leaves the hole (cowir-overworld's split, cowir-autogrind's
## retraction of "strip by line, never with a state machine"):
##   `#` lines      line-addressable  -> stateless line drop, nothing to desync
##   `"""` regions  NOT line-addressable, and both files use them (BattleManager 94 delimiter
##                  lines, HeadlessBattleResolver 4). A `#`-only strip cannot touch a docstring,
##                  which is the .325 defect verbatim.
##
## The region half splits on the delimiter and keeps alternate chunks — no toggle, no state, so
## it cannot desync the way my own precedence-bugged state machine did an hour ago (`A or (B and
## C)` swallowed five files whole and reported five confident false positives). It also cannot
## answer "is this line inside a region", which this file never asks.
func _code_only(raw: String) -> String:
	var no_lines: PackedStringArray = []
	for line in raw.split("\n"):
		if not line.strip_edges().begins_with("#"):
			no_lines.append(line)
	var chunks: PackedStringArray = "\n".join(no_lines).split("\"\"\"")
	var kept: PackedStringArray = []
	for i in chunks.size():
		if i % 2 == 0:
			kept.append(chunks[i])
	return "\n".join(kept)


## The two-engine split above is prose, and prose rots. This makes it a checked fact: both
## engines must be IN the corpus, and the corpus must be able to tell them apart. Named
## members, not counts — a count reds when someone correctly wires a key into the grind,
## which is the good direction and must not be a failure.
func test_the_corpus_holds_two_engines_and_can_tell_them_apart() -> void:
	var bm: String = _code_only(FileAccess.get_file_as_string(BATTLE_MANAGER))
	var hr: String = _code_only(FileAccess.get_file_as_string("res://src/autogrind/HeadlessBattleResolver.gd"))
	# POSITIVE CONTROL ON THE STRIPPER ITSELF. An over-aggressive strip and a correct one are
	# the same green: every `contains` below would read false and every assert_false would pass.
	# A known CODE site must survive, in each file, or the strip is measuring an empty string.
	assert_true(bm.contains("func _check_one_shot"),
		"the comment/docstring strip removed a known CODE site from BattleManager — every presence assert below is now reading prose-free nothing, and the assert_false arms would pass for that reason alone")
	assert_true(hr.contains("func _resolve_ability"),
		"the strip removed a known CODE site from HeadlessBattleResolver — same failure, and it is the file this arm's live-only claim is ABOUT")

	assert_gt(bm.length(), 100000,
		"BattleManager did not load — the live half of the split below is measuring an empty string")
	assert_gt(hr.length(), 10000,
		"HeadlessBattleResolver did not load — every key would read as live-only and the split would look worse than it is")

	# READ BY BOTH: the shared floor. If these stop appearing in the resolver the grind has
	# lost basic ability resolution, which is a much larger finding than any key below.
	for shared in ["\"heal_amount\"", "\"mp_amount\"", "\"element\""]:
		assert_true(bm.contains(shared) and hr.contains(shared),
			"%s must be read by BOTH engines — it is part of the shared floor, and if the grind stopped reading it the split this file describes has changed shape entirely" % shared)

	# LIVE ONLY: the finding itself, pinned by a named member rather than by the count 45.
	# Reds in the GOOD direction — someone taught the grind about effect_chance.
	assert_true(bm.contains("\"effect_chance\""),
		"effect_chance is authored on 68 abilities and read by the live engine; if BattleManager stopped reading it this file's premise is stale")
	assert_false(hr.contains("\"effect_chance\""),
		"GOOD NEWS: the headless resolver now reads effect_chance, so the live-only set has shrunk. Re-measure the 13/45/5 split in the third limit above and update it — the number is the whole point of that paragraph.")

	# ⛔ THERE WAS A THIRD ASSERT HERE AND IT WAS REDUNDANT. It re-checked the five
	# UNREAD_EFFECT_KEYS against each engine separately. @cowir-story's asymmetry, and they
	# are right: BattleManager and HeadlessBattleResolver are SUBSETS of the src/ walk, so
	# "in bm or in hr" implies "in the blob" and the arm could never fire without the
	# ratchet above it firing too. My own mutation run said so and I did not read it —
	# adding an UNREAD key to BattleManager scored Failing 2, never Failing 1.
	#
	#     whole-src NEGATIVE  "X is read by nothing"  sound as written. Emptiness over the
	#                         corpus is emptiness over every engine in it, by construction.
	#                         Splitting the corpus cannot change an empty result.
	#     whole-src POSITIVE  "X is consumed"         conflates. WHICH consumer? That is the
	#                         defect this file was repaired for, and it is the only direction
	#                         that needed repairing.
	#
	# So UNREAD_EFFECT_KEYS needs no per-engine arm and never did. What DOES inherit the
	# defect is the ratchet's newly_consumed message: it says "now read in src/ — delete the
	# line", and if that reader landed in the live engine only, deleting the line hides that
	# the grind still ignores the key. Read it as "consumed by SOMETHING" and check which.
