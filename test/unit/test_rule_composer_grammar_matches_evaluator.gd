extends GutTest

## Every vocabulary the LLM is handed must match what the game can execute.
##
## THE TWO SOURCES: the grammar constants in `DialoguePrompts` are hand-written
## lists sent to the model; the match statements in `AutobattleSystem` and
## `AutogrindSystem` are what actually run. Nothing connected them.
##
## FOUND LIVE (cowir-ai, 2026-07-29): `has_buff` and `not_has_buff` were
## implemented, validated, and used by the SHIPPED presets — and the autobattle
## grammar never mentioned them, so the Rule Composer could not produce them.
## "Buff only when the buff isn't already up" is one of the most common
## autobattle patterns and the game's own templates use it.
##
## THEN THE SIBLING SWEEP: fixing conditions and stopping there would have left
## four more vocabularies with the same shape and no guard — the exact "fixed one
## instance, left the class" trap. Measured all five; the other four agree today,
## and this file is what keeps them agreeing.
##
## BOTH DIRECTIONS FAIL DIFFERENTLY, so both are asserted per axis:
##   advertised but NOT implemented -> the domain system rejects the composition,
##     RuleComposer emits grammar_errors and the player gets the empty "LLM
##     unavailable" draft with no indication the verb was the problem.
##   implemented but NOT advertised -> the capability is simply unreachable from
##     the composer. Silent, permanent, and invisible to any test that only
##     exercises verbs the grammar already lists. This is the one that bit.
##
## DERIVED, NOT LISTED. AXES names where to look; every accepted VALUE is parsed
## from the dispatch arms and the grammar text. A reworded section header would
## silently empty an extraction, so each axis carries its own minimum-size
## control — a vacuous agreement of two empty sets must never pass.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const AUTOBATTLE_SRC: String = "res://src/autobattle/AutobattleSystem.gd"
const AUTOGRIND_SRC: String = "res://src/autogrind/AutogrindSystem.gd"

## One entry per advertised vocabulary. `head`/`tail` bound the list inside the
## grammar text; `needle` names the dispatch site; `floor` is the control.
const AXES: Array[Dictionary] = [
	{
		"name": "autobattle conditions",
		"grammar": "autobattle",
		"head": "Conditions (AND-chained). type is one of:",
		"tail": "Each numeric condition",
		"src": AUTOBATTLE_SRC,
		"needle": "func _evaluate_grid_condition",
		"floor": 12,
		"accessor": "condition",
	},
	{
		"name": "autobattle actions",
		"grammar": "autobattle",
		"head": "Actions (executed in order, up to 4 per rule). type is one of:",
		"tail": "ability requires id",
		"src": AUTOBATTLE_SRC,
		"needle": "match action_type:",
		"floor": 3,
		"accessor": "action",
	},
	{
		"name": "autobattle targets",
		"grammar": "autobattle",
		"head": "Targets. Values:",
		"tail": "weakest_to_ability aims",
		"src": AUTOBATTLE_SRC,
		"needle": "match target_type:",
		"floor": 8,
		"accessor": "",
	},
	{
		"name": "autogrind conditions",
		"grammar": "autogrind",
		"head": "Conditions (AND-chained). type is one of:",
		"tail": "Numeric conditions take",
		"src": AUTOGRIND_SRC,
		"needle": "func _evaluate_party_condition",
		"floor": 12,
		"accessor": "condition",
	},
	{
		"name": "autogrind actions",
		"grammar": "autogrind",
		"head": "Actions. type is one of:",
		"tail": "switch_profile requires",
		"src": AUTOGRIND_SRC,
		"needle": "match action_type:",
		"floor": 4,
		"accessor": "action",
	},
]


func _grammar(which: String) -> String:
	return DP.AUTOBATTLE_GRAMMAR_DESCRIPTION if which == "autobattle" else DP.AUTOGRIND_GRAMMAR_DESCRIPTION


## Verbs the prompt advertises for one axis, from that section only.
func _advertised(axis: Dictionary) -> Array:
	var g: String = _grammar(str(axis["grammar"]))
	var start: int = g.find(str(axis["head"]))
	if start == -1:
		return []
	start += str(axis["head"]).length()
	var stop: int = g.find(str(axis["tail"]), start)
	if stop == -1:
		stop = g.length()
	var out: Array = []
	var re := RegEx.new()
	re.compile("[a-z_]{2,}")
	for m in re.search_all(g.substr(start, stop - start)):
		if not out.has(m.get_string(0)):
			out.append(m.get_string(0))
	return out


## Verbs the game implements, from the dispatch site's own match arms.
## Handles multi-id arms ("a", "b", "c":) and stops at the next top-level func.
func _implemented(axis: Dictionary) -> Array:
	var src: String = FileAccess.get_file_as_string(str(axis["src"]))
	if src.is_empty():
		return []
	var at: int = src.find(str(axis["needle"]))
	if at == -1:
		return []
	var out: Array = []
	var head := RegEx.new()
	head.compile('^\\t+("[a-z_]+"(?:,\\s*"[a-z_]+")*):\\s*$')
	var ids := RegEx.new()
	ids.compile('"([a-z_]+)"')
	var lines: PackedStringArray = src.substr(at).split("\n")
	for i in range(1, lines.size()):
		var line: String = lines[i]
		if line.begins_with("func "):
			break
		var m: RegExMatch = head.search(line)
		if m == null:
			continue
		for im in ids.search_all(m.get_string(1)):
			if not out.has(im.get_string(1)):
				out.append(im.get_string(1))
	return out


## Keys every entry carries; documented structurally, not per-verb.
const GENERIC_KEYS: Array[String] = ["type", "op", "value"]


## Extra fields each arm READS off its entry, e.g. item_count -> ["item_id"].
func _arm_fields(axis: Dictionary) -> Dictionary:
	var accessor: String = str(axis.get("accessor", ""))
	if accessor == "":
		return {}
	var src: String = FileAccess.get_file_as_string(str(axis["src"]))
	var at: int = src.find(str(axis["needle"]))
	if src.is_empty() or at == -1:
		return {}
	var out: Dictionary = {}
	var head := RegEx.new()
	head.compile('^\\t+("[a-z_]+"(?:,\\s*"[a-z_]+")*):\\s*$')
	var ids := RegEx.new()
	ids.compile('"([a-z_]+)"')
	var getter := RegEx.new()
	getter.compile(accessor + '\\.get\\("([a-z_]+)"')
	var open_ids: Array = []
	var lines: PackedStringArray = src.substr(at).split("\n")
	for i in range(1, lines.size()):
		var line: String = lines[i]
		if line.begins_with("func "):
			break
		var m: RegExMatch = head.search(line)
		if m != null:
			open_ids = []
			for im in ids.search_all(m.get_string(1)):
				open_ids.append(im.get_string(1))
				if not out.has(im.get_string(1)):
					out[im.get_string(1)] = []
			continue
		for fm in getter.search_all(line):
			var f: String = fm.get_string(1)
			if GENERIC_KEYS.has(f):
				continue
			for k in open_ids:
				var lst: Array = out[k]
				if not lst.has(f):
					lst.append(f)
	return out


# ── Positive controls — a vacuous pass must be impossible, per axis ──────────

func test_every_axis_extracts_a_plausible_vocabulary() -> void:
	# A reworded section header or a renamed dispatch site would empty an
	# extraction, and two empty sets agree perfectly. That must fail loudly.
	for axis in AXES:
		var adv: Array = _advertised(axis)
		var impl: Array = _implemented(axis)
		assert_gte(adv.size(), int(axis["floor"]),
			("[%s] parsed only %d advertised verbs (floor %d) — the grammar section markers have moved, " +
			"so any agreement below is between two things that were not read.")
			% [axis["name"], adv.size(), int(axis["floor"])])
		assert_gte(impl.size(), int(axis["floor"]),
			("[%s] parsed only %d dispatch arms from '%s' (floor %d) — the dispatch site moved or was " +
			"renamed, so this axis is guarding nothing.")
			% [axis["name"], impl.size(), int(axis["needle"]), int(axis["floor"])])


# ── The guard, both directions, every axis ───────────────────────────────────

func test_every_advertised_verb_is_implemented() -> void:
	for axis in AXES:
		var impl: Array = _implemented(axis)
		for verb in _advertised(axis):
			assert_true(impl.has(verb),
				("[%s] the prompt tells the LLM it may use '%s', but the dispatch at '%s' has no arm for it. " +
				"validate_rule will reject any composition using it, so the player's request silently " +
				"resolves to the empty fallback draft. Implemented: %s")
				% [axis["name"], verb, axis["needle"], str(impl)])


func test_every_implemented_verb_is_advertised() -> void:
	for axis in AXES:
		var adv: Array = _advertised(axis)
		for verb in _implemented(axis):
			assert_true(adv.has(verb),
				("[%s] '%s' is implemented at '%s' and the grammar never mentions it, so the Rule Composer " +
				"can NEVER produce it — unreachable from the LLM path, and invisible to any test that only " +
				"uses advertised verbs. Add it to the grammar. Advertised: %s")
				% [axis["name"], verb, axis["needle"], str(adv)])


func test_field_scan_finds_the_known_field_bearing_arms() -> void:
	# Control for the clause below: if the getter regex or the accessor name
	# breaks, every arm reports zero extra fields and "all documented" passes
	# vacuously. These arms are known to read a field.
	var fields: Dictionary = _arm_fields(AXES[0])
	assert_true(fields.has("has_status") and (fields["has_status"] as Array).has("status"),
		"has_status must be seen reading 'status' — the field scan is broken, so the clause below proves nothing")
	assert_true(fields.has("item_count") and (fields["item_count"] as Array).has("item_id"),
		"item_count must be seen reading 'item_id' — the field scan is broken")


func test_every_field_the_evaluator_reads_is_documented() -> void:
	# ONE LAYER BELOW THE VERB. A verb can be advertised and implemented while
	# the FIELD it needs is undocumented — the type validates, the evaluator
	# reads a missing key, and the condition silently defaults.
	#
	# FOUND LIVE (2026-07-29): item_count reads condition.get("item_id", "") and
	# the grammar never named that field. A composed "use a potion when you have
	# one" emits no item_id, _get_item_count("") returns 0, and the rule NEVER
	# FIRES. validate_rule doesn't require it, so nothing is reported. The
	# shipped presets use item_id 15 times — it was always the real contract.
	for axis in AXES:
		var g: String = _grammar(str(axis["grammar"]))
		var fields: Dictionary = _arm_fields(axis)
		for verb in fields.keys():
			for f in (fields[verb] as Array):
				assert_true(g.find(str(f)) != -1,
					("[%s] '%s' reads the field '%s' off its entry and the grammar never names it. The LLM " +
					"cannot supply a key it was not told about, so the field arrives missing, the read " +
					"silently defaults, and the rule never fires — with no validation error.")
					% [axis["name"], verb, f])


func test_buff_conditions_reach_the_composer() -> void:
	# The specific regression. These shipped in the built-in presets while the
	# grammar omitted them, so "buff only when it isn't already up" — the reason
	# not_has_buff exists — was unreachable from a composed rule.
	var adv: Array = _advertised(AXES[0])
	for verb in ["has_buff", "not_has_buff"]:
		assert_true(adv.has(verb),
			"'%s' is implemented and used by the shipped rule templates; the composer must be able to emit it" % verb)
	assert_true(DP.AUTOBATTLE_GRAMMAR_DESCRIPTION.find("stat") != -1,
		"the grammar must document the 'stat' field, or the LLM will emit buff conditions with op/value and they will not match")
