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
const ALLY_TARGETS := ["self", "single_ally", "all_allies", "dead_ally"]

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
