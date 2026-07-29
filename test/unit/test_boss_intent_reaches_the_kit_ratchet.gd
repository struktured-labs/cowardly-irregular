extends GutTest

## An authored boss intent must be able to change what the boss DOES.
##
## STATUS 2026-07-29: THIS RATCHET IS EXPECTED TO FAIL ON MAIN. It is an
## executable statement of a live defect (cowir-ai msg-3345/3348, confirmed and
## extended by cowir-main msg-3349), held on a branch rather than folded until
## cowir-battle rules on the fix. Do not silence it; the failures are the report.
##
## THE FEATURE: Settings → LLM Boss Strategy. The LLM picks a posture per phase
## and the deterministic ladder still owns ability choice, biased by that
## posture. The taunt half works and ships. The mechanical half is what this
## measures.
##
## THREE CLAUSES, because an intent can die at three different depths and the
## first two checks pass on the third failure:
##
##   1. BIAS ARM — `_bias_by_intent` must have an arm for the intent, else it
##      returns {} and the ladder is biased exactly as if no intent were chosen.
##
##   2. COUNTER ARM — an intent in `_COUNTER_INTENT_TAGS` forces the counter
##      path, so `_get_counter_action` must have an arm for it, else the path
##      is taken and yields nothing.
##
##   3. THE KIT (cowir-main's amendment, and the one that matters) — an arm that
##      selects an ability by id-substring can only fire if the boss AUTHORING
##      that intent owns a matching ability. Clauses 1 and 2 both pass on a boss
##      whose kit simply lacks the ability class, which is exactly today's
##      state: no W1 boss owns a defensive or resist ability in ANY
##      representation, so `fire_resist` and `defense_boost` are not failing to
##      FIND the right ability — there is no right ability to find. A guard
##      without this clause would go green on the current defect.
##
## DERIVED, NOT LISTED, at every level. Arms are parsed from the match
## statements; the id-substrings are parsed out of the arms' own filter lambdas.
## No table here can rot, and re-authoring an arm re-derives what it demands.

const BM_PATH: String = "res://src/battle/BattleManager.gd"
const DIALOGUE_PATH: String = "res://data/boss_dialogue.json"
const MONSTERS_PATH: String = "res://data/monsters.json"

## Fields a monster may use to point at a boss_dialogue section.
const PERSONA_ID_FIELDS: Array[String] = ["llm_persona_id", "boss_llm_persona_id"]


func _src() -> String:
	var s: String = FileAccess.get_file_as_string(BM_PATH)
	assert_false(s.is_empty(), "BattleManager must be readable")
	return s


func _json(path: String) -> Dictionary:
	var j := JSON.new()
	assert_eq(j.parse(FileAccess.get_file_as_string(path)), OK, "%s must parse" % path)
	return j.data as Dictionary if j.data is Dictionary else {}


## Body of a named func, bounded at the next top-level func.
func _func_body(fn: String) -> String:
	var s: String = _src()
	var start: int = s.find("func " + fn)
	assert_gt(start, -1, "%s must exist — if renamed, this ratchet measures nothing" % fn)
	if start == -1:
		return ""
	var end: int = s.find("\nfunc ", start + 1)
	return s.substr(start, (end if end != -1 else s.length()) - start)


## Map arm-id -> arm body text. Handles multi-id arms ("a", "b", "c":).
func _match_arms(body: String) -> Dictionary:
	var out: Dictionary = {}
	var lines: PackedStringArray = body.split("\n")
	var head := RegEx.new()
	head.compile('^\\t+("[a-z_]+"(?:,\\s*"[a-z_]+")*):\\s*$')
	var ids := RegEx.new()
	ids.compile('"([a-z_]+)"')
	var open_ids: Array = []
	for line in lines:
		var m: RegExMatch = head.search(line)
		if m != null:
			open_ids = []
			for im in ids.search_all(m.get_string(1)):
				open_ids.append(im.get_string(1))
				out[im.get_string(1)] = ""
			continue
		for k in open_ids:
			out[k] = str(out[k]) + line + "\n"
	return out


## Ability-id substrings an arm requires, parsed from its own filter lambda.
func _required_id_substrings(arm_body: String) -> Array:
	var out: Array = []
	if arm_body.find("abilities.filter") == -1:
		return out
	var re := RegEx.new()
	re.compile('"([a-z_]+)" in a\\.get\\("id"')
	for m in re.search_all(arm_body):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out


func _counter_tags() -> Array:
	var s: String = _src()
	var start: int = s.find("_COUNTER_INTENT_TAGS")
	assert_gt(start, -1, "_COUNTER_INTENT_TAGS must exist")
	if start == -1:
		return []
	var stop: int = s.find("]", start)
	var out: Array = []
	var re := RegEx.new()
	re.compile('"([a-z_]+)"')
	for m in re.search_all(s.substr(start, stop - start)):
		out.append(m.get_string(1))
	return out


## boss_dialogue section key -> that boss's ability id list.
func _boss_kits() -> Dictionary:
	var mons: Dictionary = _json(MONSTERS_PATH)
	var out: Dictionary = {}
	for mid in mons.keys():
		var m: Variant = mons[mid]
		if not (m is Dictionary):
			continue
		var section: String = str(mid)
		for f in PERSONA_ID_FIELDS:
			var ref: String = str((m as Dictionary).get(f, ""))
			if ref != "":
				section = ref
		var kit: Array = []
		for a in ((m as Dictionary).get("abilities", []) as Array):
			kit.append(str(a))
		out[section] = kit
	return out


## boss_dialogue section key -> authored intent ids.
func _authored_intents() -> Dictionary:
	var out: Dictionary = {}
	var d: Dictionary = _json(DIALOGUE_PATH)
	for key in d.keys():
		var v: Variant = d[key]
		if not (v is Dictionary):
			continue
		var ids: Array = []
		for si in ((v as Dictionary).get("scripted_intents", []) as Array):
			if si is Dictionary and str((si as Dictionary).get("id", "")) != "":
				ids.append(str((si as Dictionary).get("id")))
		if not ids.is_empty():
			out[str(key)] = ids
	return out


# ── Positive controls — every parse must be proven non-vacuous ───────────────

func test_bias_arms_are_parsed() -> void:
	var arms: Dictionary = _match_arms(_func_body("_bias_by_intent"))
	assert_gt(arms.size(), 4, "parsed only %d bias arms — the parse broke" % arms.size())
	assert_true(arms.has("aggress"), "aggress is the canonical bias arm; missing it means the parse is wrong")


func test_counter_arms_and_their_filters_are_parsed() -> void:
	var arms: Dictionary = _match_arms(_func_body("_get_counter_action"))
	assert_gt(arms.size(), 3, "parsed only %d counter arms — the parse broke" % arms.size())
	assert_true(arms.has("defense_boost"), "defense_boost arm must be found")
	var subs: Array = _required_id_substrings(str(arms.get("defense_boost", "")))
	assert_true(subs.has("defense") or subs.has("guard"),
		"the defense_boost arm selects abilities by id-substring; parsing it yielded %s" % str(subs))


func test_authored_intents_and_kits_are_parsed() -> void:
	assert_gt(_authored_intents().size(), 3, "boss_dialogue must yield several intent-bearing bosses")
	var kits: Dictionary = _boss_kits()
	assert_true(kits.has("pyrroth"), "the persona join must resolve pyrroth to a monster kit")
	assert_gt((kits.get("pyrroth", []) as Array).size(), 2, "pyrroth's kit must be non-empty or clause 3 proves nothing")


# ── Clause 1: the intent reaches a bias arm ──────────────────────────────────

func test_every_authored_intent_has_a_bias_arm() -> void:
	var arms: Dictionary = _match_arms(_func_body("_bias_by_intent"))
	var offenders: Array = []
	for boss in _authored_intents().keys():
		for intent in (_authored_intents()[boss] as Array):
			if not arms.has(intent):
				offenders.append("%s/%s" % [boss, intent])
	assert_eq(offenders.size(), 0,
		("%d authored intents have no arm in _bias_by_intent, so choosing them biases the ladder exactly " +
		"as if no intent were chosen — the LLM's strategic pick is dialogue-only for these: %s")
		% [offenders.size(), str(offenders)])


# ── Clause 2: a counter-forcing intent reaches a counter arm ─────────────────

func test_every_counter_forcing_intent_has_a_counter_arm() -> void:
	var arms: Dictionary = _match_arms(_func_body("_get_counter_action"))
	for tag in _counter_tags():
		assert_true(arms.has(tag),
			("'%s' is in _COUNTER_INTENT_TAGS so it FORCES the counter path, but _get_counter_action has no " +
			"arm for it — the path is taken and yields nothing.") % tag)


# ── Clause 3: the arm can fire given the authoring boss's actual kit ─────────

func test_counter_arms_can_fire_for_the_bosses_that_author_them() -> void:
	# cowir-main's amendment. Clauses 1 and 2 pass on a boss whose kit lacks the
	# ability class entirely, which is today's state — so this is the clause that
	# sees the live defect.
	var arms: Dictionary = _match_arms(_func_body("_get_counter_action"))
	var kits: Dictionary = _boss_kits()
	var tags: Array = _counter_tags()
	var offenders: Array = []
	for boss in _authored_intents().keys():
		var kit: Array = kits.get(boss, []) as Array
		if kit.is_empty():
			continue
		for intent in (_authored_intents()[boss] as Array):
			if not tags.has(intent):
				continue
			var subs: Array = _required_id_substrings(str(arms.get(intent, "")))
			if subs.is_empty():
				continue
			var ok: bool = false
			for ability in kit:
				for sub in subs:
					if str(ability).find(str(sub)) != -1:
						ok = true
			if not ok:
				offenders.append("%s/%s needs an ability id containing one of %s; kit is %s"
					% [boss, intent, str(subs), str(kit)])
	assert_eq(offenders.size(), 0,
		("%d boss/intent pairs force the counter path into an arm that selects an ability their kit cannot " +
		"supply, so the intent silently does nothing. A better FILTER would not fix these — the ability " +
		"class is absent from the kit, so either the kit needs the ability or the intent should not be " +
		"authored on that boss:\n  %s") % [offenders.size(), "\n  ".join(offenders)])
