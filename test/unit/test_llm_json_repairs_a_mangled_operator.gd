extends GutTest

## The model ran the operator together with its key, and the composition died.
##
## `"op":">="` comes back as `"op">=`, `"op">="` or `"op">`. The value already
## looks like punctuation, so the model drops the JSON colon. The reply is then
## unparseable, complete_json returns the fallback, and the player gets a canned
## ruleset instead of the one they asked for.
##
## Measured across 100 local-llama3 rule compositions: 15 unparseable, 9 carrying
## this exact shape, 8 of the 9 parsing once repaired. Paired before/after on the
## same captured corpus, through the shipping extractor:
##
##     extracted a JSON object   BEFORE 17/24    AFTER 22/24
##
## It is the single largest cause of a composition never reaching the validator,
## and it is UNAMBIGUOUS: `"op"` followed by a comparison operator has exactly one
## valid reading. Nothing is invented — only the colon and quotes are restored.
##
## Runs only after every ordinary strategy has failed (direct parse, fence strip,
## brace slice, truncation repair), so it can turn a failure into a parse and can
## never alter a reply that already worked.

const LS := preload("res://src/llm/LLMService.gd")

var _svc = null


func before_each() -> void:
	_svc = LS.new()
	add_child_autofree(_svc)


func _obj(rules_json: String) -> String:
	return '{"name":"n","description":"d","rules_json":%s}' % rules_json


# ── the three shapes actually observed ────────────────────────────────────────

func test_bare_operator_with_no_colon_or_quotes() -> void:
	var raw := _obj('[{"conditions":[{"type":"mp_percent","op">=,"value":20}],"actions":[]}]')
	var got: Variant = _svc._extract_json_from_raw(raw)
	assert_true(got is Dictionary, '"op">= must be repaired — this shape killed 3 of 12 fighter samples')


func test_operator_with_a_trailing_quote_only() -> void:
	var raw := _obj('[{"conditions":[{"type":"mp_percent","op">=","value":15}],"actions":[]}]')
	assert_true(_svc._extract_json_from_raw(raw) is Dictionary, '"op">=" must be repaired')


func test_single_character_operator() -> void:
	var raw := _obj('[{"conditions":[{"type":"enemy_hp_percent","op">,"value":50}],"actions":[]}]')
	assert_true(_svc._extract_json_from_raw(raw) is Dictionary, '"op"> must be repaired')


func test_the_repaired_operator_carries_the_right_value() -> void:
	## The repair must restore the operator the model MEANT, not merely produce
	## something that parses — a rule with the wrong comparison is worse than none.
	var raw := _obj('[{"conditions":[{"type":"mp_percent","op">=,"value":20}],"actions":[]}]')
	var raw_got: Variant = _svc._extract_json_from_raw(raw)
	# Assert before casting: a null cast raises a GDScript error, and a GDScript
	# error does not fail a GUT test — the mutation arm showed this test going
	# quiet instead of red.
	assert_true(raw_got is Dictionary, "must parse before the value can be checked")
	if not (raw_got is Dictionary):
		return
	var got: Dictionary = raw_got as Dictionary
	var rules: Array = JSON.parse_string(str(got["rules_json"])) if got["rules_json"] is String \
		else got["rules_json"]
	assert_eq(str((rules[0]["conditions"] as Array)[0]["op"]), ">=",
		"the operator must survive as '>=', not as '>' with a stray '='")


func test_every_operator_in_the_vocabulary_is_repaired() -> void:
	## Longer operators must be tried first, or '>=' matches as '>' and leaves '='.
	for op in [">=", "<=", "==", "!=", ">", "<"]:
		var raw := _obj('[{"conditions":[{"type":"turn","op"%s,"value":3}],"actions":[]}]' % op)
		var got: Variant = _svc._extract_json_from_raw(raw)
		assert_true(got is Dictionary, "'%s' must be repaired" % op)
		if not (got is Dictionary):
			continue
		var d: Dictionary = got as Dictionary
		var rules: Array = JSON.parse_string(str(d["rules_json"])) if d["rules_json"] is String \
			else d["rules_json"]
		assert_eq(str((rules[0]["conditions"] as Array)[0]["op"]), op,
			"'%s' must round-trip exactly" % op)


# ── it must not disturb what already worked ───────────────────────────────────

func test_a_well_formed_reply_is_untouched() -> void:
	## CONTROL: the repair runs only after the ordinary strategies fail, so a valid
	## reply must never reach it.
	var raw := _obj('"[{\\"conditions\\":[{\\"type\\":\\"turn\\",\\"op\\":\\">=\\",\\"value\\":3}],\\"actions\\":[]}]"')
	var got: Variant = _svc._extract_json_from_raw(raw)
	assert_true(got is Dictionary, "a well-formed reply must still parse")
	assert_eq(str((got as Dictionary)["name"]), "n", "and be unaltered")


func test_the_repair_is_idempotent() -> void:
	## A correct `"op":">="` must not be re-mangled by the pass that fixes the
	## broken form — the fixed text is fed back through extraction.
	assert_eq(_svc._repair_mangled_operator('{"op":">=","value":7}'), '{"op":">=","value":7}',
		"an already-correct operator must be left exactly alone")


func test_prose_with_no_json_is_still_null() -> void:
	assert_null(_svc._extract_json_from_raw("I can't help with that."),
		"the repair must not make unparseable prose look like an object")


func test_a_reply_broken_some_other_way_is_still_refused() -> void:
	## CONTROL: this fixes ONE shape. An unquoted value elsewhere is a different
	## defect and must still fail rather than be guessed at — the corpus had one
	## (`"target":self`) and it should stay refused.
	var raw := _obj('[{"conditions":[],"actions":[{"type":"attack","target":self}]}]')
	assert_null(_svc._extract_json_from_raw(raw),
		"an unquoted value is a different malformation and must not be silently guessed")


func test_the_repair_only_touches_the_op_key() -> void:
	## Keyed to `op` deliberately: its vocabulary is six fixed tokens, so the
	## reading is forced. A generic key-followed-by-punctuation rule would start
	## guessing at fields whose values are not a closed set.
	var s: String = _svc._repair_mangled_operator('{"value">=,"other">=}')
	assert_eq(s, '{"value">=,"other">=}',
		"no key other than 'op' may be repaired")
