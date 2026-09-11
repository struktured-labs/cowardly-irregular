extends GutTest

## The Rule Composer returned the canned fallback for EVERY local-model reply.
##
## Measured end-to-end through the shipping path (LLMService._guard_json ->
## validate_rule_composition -> AutobattleSystem.validate_rule), 20 real llama3
## replies to the real autobattle prompt:
##
##     compositions the player receives   BEFORE 0/20     AFTER 18/20
##     grammar errors in surviving rules  --              0 of 47 rules
##
## Two independent consumer-side defects, neither of them the model's fault:
##
## 1. TRUNCATION. ~half of replies (10/20 and 11/20 on two fresh seed sets) stop
##    one '}' short of closing the outer object — the model finishes its nested
##    array, reports done_reason=stop, and never emits the final brace. The
##    brace-slice fallback cannot recover this: rfind('}') lands INSIDE the array,
##    so the slice is unbalanced too.
##
## 2. SHAPE. SCHEMA_RULE_COMPOSITION pinned rules_json to "String", but 20 of 20
##    replies emitted it as a nested ARRAY. The guard rejected all of them before
##    validate_rule_composition ever saw the rules.
##
## Neither is visible from a schema check: the reply has exactly the three
## required keys, and every rule inside was grammatically valid. The feature was
## shipped, advertised in CLAUDE.md, and produced nothing but fallbacks.
##
## Rate is model- and prompt-dependent; the SHAPES are what this pins.

const LS := preload("res://src/llm/LLMService.gd")
const DP := preload("res://src/llm/DialoguePrompts.gd")

## Captured verbatim from llama3 — the array shape, one '}' short.
const REAL_TRUNCATED_ARRAY := r"""{
"name": "heal_and_attack",
"description": "Caring for allies and taking down foes.",
"rules_json": [
  {"conditions":[{"type":"ally_hp_percent","op":"<=","value":40}],
   "actions":[{"type":"ability","id":"cure","target":"lowest_hp_ally"}],
   "enabled":true}
]"""

## Captured verbatim — the ENCODED-STRING shape, also one '}' short. The braces
## inside rules_json are escaped and must not be counted as structure.
const REAL_TRUNCATED_STRING := "{\n\"name\": \"Heal and Fight\",\n\"description\": \"Curing wounds and striking back at foes.\",\n\"rules_json\": \"[{\\\"conditions\\\":[{\\\"type\\\":\\\"hp_percent\\\",\\\"op\\\":\\\">=\\\",\\\"value\\\":40},{\\\"type\\\":\\\"has_status\\\",\\\"status\\\":\\\"poison\\\"}],\\\"actions\\\":[{\\\"type\\\":\\\"ability\\\",\\\"id\\\":\\\"cure\\\",\\\"target\\\":\\\"lowest_hp_ally\\\"},{\\\"type\\\":\\\"attack\\\",\\\"target\\\":\\\"lowest_hp_enemy\\\"}],\\\"enabled\\\":true},{\\\"conditions\\\":[{\\\"type\\\":\\\"hp_percent\\\",\\\"op\\\":\\\">=\\\",\\\"value\\\":40},{\\\"type\\\":\\\"has_status\\\",\\\"status\\\":\\\"poison\\\"}],\\\"actions\\\":[{\\\"type\\\":\\\"ability\\\",\\\"id\\\":\\\"esuna\\\",\\\"target\\\":\\\"lowest_hp_ally\\\"},{\\\"type\\\":\\\"attack\\\",\\\"target\\\":\\\"lowest_hp_enemy\\\"}],\\\"enabled\\\":true}]\""

const COMPLETE_REPLY := '{"name":"n","description":"d","rules_json":"[]"}'

var _svc = null


func before_each() -> void:
	_svc = LS.new()
	add_child_autofree(_svc)


# ── 1. truncation is repaired ─────────────────────────────────────────────────

func test_a_real_truncated_reply_is_recovered() -> void:
	var got: Variant = _svc._extract_json_from_raw(REAL_TRUNCATED_ARRAY)
	assert_true(got is Dictionary,
		"a reply one '}' short must parse — half of all local-model replies end this way")
	assert_eq(str((got as Dictionary).get("name", "")), "heal_and_attack",
		"and must carry the fields the model did emit")


func test_escaped_braces_inside_a_string_are_not_counted_as_structure() -> void:
	## The encoded-string shape puts dozens of '{' inside a JSON string. A repair
	## that counted them would append that many closers and produce garbage.
	var got: Variant = _svc._extract_json_from_raw(REAL_TRUNCATED_STRING)
	assert_true(got is Dictionary,
		"the encoded-string shape must repair too, without miscounting escaped braces")
	var rules_json: String = str((got as Dictionary).get("rules_json", ""))
	assert_true(JSON.parse_string(rules_json) is Array,
		"the nested payload must survive the repair intact, not merely parse")


func test_a_truncated_array_of_several_rules_keeps_them_all() -> void:
	var raw := '{"name":"n","description":"d","rules_json":[{"a":1},{"b":2},{"c":3}]'
	var got: Variant = _svc._extract_json_from_raw(raw)
	assert_true(got is Dictionary, "must repair")
	assert_eq(((got as Dictionary).get("rules_json", []) as Array).size(), 3,
		"repair must not drop content that WAS emitted")


# ── the repair must not invent ────────────────────────────────────────────────

func test_mismatched_closers_are_refused_not_patched() -> void:
	assert_null(_svc._extract_json_from_raw('{"a": [1, 2}]'),
		"a mismatched closer is corruption, not truncation — repairing it would fabricate structure")


func test_an_unterminated_string_is_refused() -> void:
	## Closing an open string would invent the rest of a value the model never sent.
	assert_null(_svc._extract_json_from_raw('{"name": "heal_and'),
		"an unterminated string must not be closed — that fabricates a value")


func test_prose_with_no_json_is_still_null() -> void:
	assert_null(_svc._extract_json_from_raw("I'm sorry, I can't help with that."),
		"text containing no object must still fail")
	assert_null(_svc._extract_json_from_raw(""), "and so must an empty reply")


# ── it must not disturb replies that already worked ───────────────────────────

func test_a_complete_reply_is_unchanged() -> void:
	## CONTROL: the repair runs only after every other strategy fails, so a
	## well-formed reply must take the direct-parse path exactly as before.
	var got: Variant = _svc._extract_json_from_raw(COMPLETE_REPLY)
	assert_true(got is Dictionary, "a complete reply must still parse")
	assert_eq(str((got as Dictionary).get("name", "")), "n", "and be unaltered")


func test_a_fenced_reply_with_prose_still_works() -> void:
	## CONTROL: the pre-existing fence and brace-slice strategies must survive.
	var got: Variant = _svc._extract_json_from_raw(
		"Here is the JSON:\n```json\n" + COMPLETE_REPLY + "\n```\nHope that helps!")
	assert_true(got is Dictionary, "fence stripping must be untouched by the repair")


# ── 2. the rules_json shape ───────────────────────────────────────────────────

func test_the_schema_guard_accepts_the_array_shape_models_actually_send() -> void:
	## The gate that rejected 20 of 20 replies. The reply has all three required
	## keys and valid rules; only the declared TYPE of rules_json refused it.
	var raw := '{"name":"n","description":"d","rules_json":[{"conditions":[],"actions":[]}]}'
	var got: Variant = _svc._guard_json(raw, DP.SCHEMA_RULE_COMPOSITION, "FALLBACK")
	assert_true(got is Dictionary,
		"a nested rules_json array must pass the guard — pinning 'String' rejected every real reply")


func test_the_documented_string_shape_still_passes_the_guard() -> void:
	## CONTROL: loosening the type must not break the contract the prompt asks for.
	var got: Variant = _svc._guard_json(COMPLETE_REPLY, DP.SCHEMA_RULE_COMPOSITION, "FALLBACK")
	assert_true(got is Dictionary, "the encoded-string shape must still be accepted")


func test_a_missing_rules_json_is_still_rejected() -> void:
	## CONTROL: the key is still REQUIRED — only its type was relaxed.
	var got: Variant = _svc._guard_json(
		'{"name":"n","description":"d"}', DP.SCHEMA_RULE_COMPOSITION, "FALLBACK")
	assert_eq(str(got), "FALLBACK", "a reply with no rules_json must still fall back")


func test_the_other_keys_are_still_type_checked() -> void:
	## CONTROL: relaxing one key must not relax the schema generally.
	var got: Variant = _svc._guard_json(
		'{"name":123,"description":"d","rules_json":[]}', DP.SCHEMA_RULE_COMPOSITION, "FALLBACK")
	assert_eq(str(got), "FALLBACK", "a non-String name must still be refused")


# ── the validator reads both shapes ───────────────────────────────────────────

func test_validate_reads_an_array_rules_json() -> void:
	var v: Dictionary = DP.validate_rule_composition(
		{"name": "n", "description": "d", "rules_json": [{"conditions": [], "actions": []}]},
		"autobattle")
	assert_true(bool(v["parse_ok"]), "the array shape must parse")
	assert_eq((v["rules"] as Array).size(), 1, "and yield its rules")


func test_validate_still_reads_an_encoded_string_rules_json() -> void:
	var v: Dictionary = DP.validate_rule_composition(
		{"name": "n", "description": "d", "rules_json": '[{"conditions":[],"actions":[]}]'},
		"autobattle")
	assert_true(bool(v["parse_ok"]), "CONTROL: the encoded shape must keep working")
	assert_eq((v["rules"] as Array).size(), 1, "and still yield its rules")


func test_an_array_rules_json_survives_a_null_field() -> void:
	## DISCRIMINATOR for reading the Array directly instead of re-encoding it.
	## str() on an Array renders a null as `<null>`, which is not JSON — so a
	## round-trip through str() loses the ENTIRE composition to one optional field
	## the model left null. Every other value type happens to survive str(), which
	## is why this is the case that decides whether the branch earns its place.
	var v: Dictionary = DP.validate_rule_composition(
		{"name": "n", "description": "d",
		 "rules_json": [{"type": "has_status", "status": null}]}, "autobattle")
	assert_true(bool(v["parse_ok"]),
		"a null field must not sink the composition — str() would emit <null> and fail to parse")
	assert_eq((v["rules"] as Array).size(), 1, "and the rule must survive intact")


func test_a_rules_json_that_is_neither_shape_fails_parse() -> void:
	## CONTROL: accepting two shapes must not mean accepting anything. A bare
	## object is not a rule list, and a caller treats parse_ok=false as invalid_json.
	var v: Dictionary = DP.validate_rule_composition(
		{"name": "n", "description": "d", "rules_json": {"not": "a list"}}, "autobattle")
	assert_false(bool(v["parse_ok"]), "a Dictionary rules_json must not be read as a rule list")
	var v2: Dictionary = DP.validate_rule_composition(
		{"name": "n", "description": "d", "rules_json": "not json at all"}, "autobattle")
	assert_false(bool(v2["parse_ok"]), "and unparseable text must still fail")


# ── the two defects compose ───────────────────────────────────────────────────

func test_a_truncated_array_shaped_reply_survives_the_whole_guard() -> void:
	## Both defects at once, which is what 10 of the 20 measured replies were:
	## truncated AND array-shaped. Either fix alone still yields a fallback.
	var guarded: Variant = _svc._guard_json(
		REAL_TRUNCATED_ARRAY, DP.SCHEMA_RULE_COMPOSITION, "FALLBACK")
	assert_true(guarded is Dictionary, "the real reply must clear the guard")
	var v: Dictionary = DP.validate_rule_composition(guarded as Dictionary, "autobattle")
	assert_true(bool(v["parse_ok"]), "and its rules must parse")
	assert_eq((v["rules"] as Array).size(), 1, "and arrive intact")
