extends GutTest

## The friendly-fire guard turned HARM into a SILENT NO-OP for every ability with no arm in
## HeadlessBattleResolver. Strictly better behaviour, strictly worse detection — "correctly
## handled" and "does nothing" became indistinguishable from outside. This names the population
## so the debt cannot quietly become "fine".
##
## BIDIRECTIONAL, deliberately: a NEW inert ability reds (document it), and a LISTED one that
## gains an arm ALSO reds (delete the entry). An exemption that outlives its reason is the exact
## failure cowir-sfx deleted a true-when-written comment for this morning.

const RESOLVER := "res://src/autogrind/HeadlessBattleResolver.gd"

## Enumerated, never pattern-matched. cowir-autogrind's census used substring markers and
## `"all_allies".contains("ally")` is FALSE — it contains "alli" — so every all_allies ability
## was invisible, including battle_hymn. Under-reporting reads as "fewer things broken", so no
## number on screen looked wrong.
const ALLY_TARGETS := ["self", "single_ally", "all_allies", "dead_ally", "all_rat_allies"]
const ENEMY_TARGETS := ["single_enemy", "all_enemies", "last_attacker"]

## Every ally-targeted ability that reaches the resolver's `_:` default and therefore does NOTHING
## in a grind. This is the meta-job kit plus Raise — routed to struktured as a design question
## (what SHOULD a headless undo_death do?), not a bug for a lane to invent an answer to.
const KNOWN_INERT := [
	"analyze_code", "bypass_puzzle", "create_autobattle_script", "edit_formula", "flee",
	"modify_constant", "new_game_plus_warp", "pack_call", "quicksave", "raise", "rat_swarm",
	"recursive_summon", "restore_point", "rewind", "rewind_turn", "royal_summon",
	"sequence_break", "skip_cutscene", "temporal_shield", "undo_death", "warp_to_boss",
]

## Parsed from the resolver rather than copied, so adding an arm updates this test for free.
## ⚠️ Must handle MULTI-VALUE arms — `"support", "song", "status":` is one arm covering three
## types. A parser requiring `"name":` silently drops it and reports 86 support abilities as
## inert; that is how the first version of this test got 73 instead of 21.
func _armed_types() -> Dictionary:
	var src := FileAccess.get_file_as_string(RESOLVER)
	assert_gt(src.length(), 1000, "CONTROL: read the resolver")
	var i := src.find("match category:")
	assert_gt(i, -1, "CONTROL: located the category match")
	var armed: Dictionary = {}
	var re := RegEx.new()
	re.compile("^\\t\\t((?:\"[a-z_]+\"\\s*,?\\s*)+):")
	var name_re := RegEx.new()
	name_re.compile("\"([a-z_]+)\"")
	for line in src.substr(i).split("\n"):
		if line.begins_with("\t\t_:"):
			break
		var m := re.search(line)
		if m == null:
			continue
		for nm in name_re.search_all(m.get_string(1)):
			armed[nm.get_string(1)] = true
	return armed

func _abilities() -> Dictionary:
	var raw := FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed = JSON.parse_string(raw)
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return parsed.get("abilities", parsed)

func _inert_ally_abilities() -> Array:
	var armed := _armed_types()
	var out: Array = []
	for id in _abilities():
		var a: Dictionary = _abilities()[id]
		if not (str(a.get("target_type", "")) in ALLY_TARGETS):
			continue
		if not armed.has(str(a.get("type", ""))):
			out.append(str(id))
	out.sort()
	return out

## Without this, a NINTH target_type falls outside both lists and leaves the walk silently — the
## same hole the substring matcher had, reached by a different route. `all_rat_allies` is why this
## is not hypothetical: it is an ally target that looks nothing like the other four, and my first
## version of this file omitted it.
func test_the_target_type_vocabulary_is_closed() -> void:
	var seen: Dictionary = {}
	for id in _abilities():
		var t := str(_abilities()[id].get("target_type", ""))
		if t != "":
			seen[t] = true
	var known: Dictionary = {}
	for t in ALLY_TARGETS + ENEMY_TARGETS:
		known[t] = true
	var unclassified: Array = []
	for t in seen:
		if not known.has(t):
			unclassified.append(t)
	unclassified.sort()
	assert_eq(unclassified.size(), 0,
		"an unclassified target_type leaves the census silently — add it to ALLY_TARGETS or ENEMY_TARGETS: " + str(unclassified))
	assert_gt(seen.size(), 5, "CONTROL: read a real vocabulary (%d values)" % seen.size())
	assert_true(seen.has("all_rat_allies"),
		"CONTROL: the odd-shaped ally target is present in the data — this test exists because it was missed")

func test_the_arm_parser_sees_multi_value_arms() -> void:
	## The control that caught the broken version: `support` lives in a grouped arm, so a parser
	## that misses grouping reports it unarmed. If this fails, every count below is inflated.
	var armed := _armed_types()
	assert_true(armed.has("support"), "support is armed via the grouped arm — a parser that misses it inflates the census")
	assert_true(armed.has("song"), "song shares that arm")
	assert_true(armed.has("healing"), "CONTROL: a plain single-value arm is found too")
	assert_false(armed.has("meta"), "CONTROL: meta genuinely has no arm — the parser can say NO")

func test_no_new_ability_is_silently_inert() -> void:
	var unlisted: Array = []
	for id in _inert_ally_abilities():
		if not (id in KNOWN_INERT):
			unlisted.append(id)
	assert_eq(unlisted.size(), 0,
		"these ally-targeted abilities do NOTHING in a grind and are undocumented — add an arm, or list them with a reason: " + str(unlisted))

func test_no_listed_ability_has_quietly_been_fixed() -> void:
	## The expiring half. Without this the list outlives its reason and converts debt into "fine".
	var still_inert := _inert_ally_abilities()
	var stale: Array = []
	for id in KNOWN_INERT:
		if not (id in still_inert):
			stale.append(id)
	assert_eq(stale.size(), 0,
		"these now have a real arm — delete them from KNOWN_INERT so the list keeps meaning what it says: " + str(stale))

func test_the_census_is_not_vacuous() -> void:
	## Guards the whole file: if the walk stops finding anything, both assertions above pass
	## trivially and the ratchet is decorative.
	assert_gt(_inert_ally_abilities().size(), 15,
		"CONTROL: the walk still resolves real abilities (%d)" % _inert_ally_abilities().size())
	assert_gt(_abilities().size(), 200, "CONTROL: read the whole ability corpus")

## The two that a REAL party reaches. cowir-autogrind corrected my framing: reporting "21 inert
## abilities" is accurate for the corpus and misleading about impact, because 19 belong to advanced
## and meta jobs a grinding party cannot have. Smaller and worse is the right direction — these two
## are owned by STARTER jobs, so they are live for every player.
##   raise  Cleric revival  -> a downed member stays down; the party grinds on with a corpse
##   flee   Rogue escape    -> a flee rule cannot disengage
const STARTER_REACHABLE := ["flee", "raise"]

func test_the_starter_reachable_subset_is_named_not_buried() -> void:
	var jobs_parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	assert_not_null(jobs_parsed, "CONTROL: jobs.json parses")
	var jobs: Dictionary = jobs_parsed.get("jobs", jobs_parsed)
	var starter_kit: Dictionary = {}
	for jid in ["fighter", "cleric", "mage", "rogue", "bard"]:
		var j: Dictionary = jobs.get(jid, {})
		for a in (j.get("abilities", []) as Array):
			starter_kit[str(a)] = true
		var at_level = j.get("abilities_at_level", {})
		if at_level is Dictionary:
			for lv in (at_level as Dictionary).keys():
				for a in ((at_level as Dictionary)[lv] as Array):
					starter_kit[str(a)] = true
		var fm = j.get("free_move", {})
		if fm is Dictionary and str((fm as Dictionary).get("ability_id", "")) != "":
			starter_kit[str((fm as Dictionary)["ability_id"])] = true
	assert_gt(starter_kit.size(), 10, "CONTROL: the starter kits read non-empty (%d)" % starter_kit.size())

	var reachable: Array = []
	for id in _inert_ally_abilities():
		if starter_kit.has(id):
			reachable.append(id)
	reachable.sort()
	assert_eq(reachable, STARTER_REACHABLE,
		"the inert abilities a REAL party can reach changed — these are the ones that hurt a player, the other 19 need an advanced or meta job: " + str(reachable))


func test_the_meta_job_kit_is_the_bulk_of_it() -> void:
	## Records WHY this matters rather than just that it is true: CLAUDE.md calls the meta jobs a
	## design pillar and "all five REAL", and in autogrind their kit is inert.
	var ab := _abilities()
	var meta := 0
	for id in _inert_ally_abilities():
		if str(ab[id].get("type", "")) == "meta":
			meta += 1
	assert_gt(meta, 10,
		"CONTROL: the inert population is dominated by meta-job abilities (%d) — that is the finding, not an accident of counting" % meta)
