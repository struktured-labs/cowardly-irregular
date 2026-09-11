extends GutTest

## A schema type the validator does not recognise silently switches that key's
## validation OFF.
##
## _guard_json checks each schema key with _type_matches. Its fall-through arm
## returned `true` with the comment "Unknown type spec — pass through", so any
## spec outside the six known names — a typo like "Strng", a lowercase "string",
## a type nobody implemented — reported every value as valid. The guard kept
## running, kept looking green, and stopped defending that field.
##
## ⚠️ LATENT, MEASURED, NOT LIVE. All 16 string-typed specs across the 8 schema
## consts in src/ resolve today. Exactly one is outside the six:
##
##     SCHEMA_RULE_COMPOSITION["rules_json"] = "Variant"
##
## and that one is DELIBERATE — models emit the rule list as a nested array (20
## of 20 local-llama3 replies), so pinning "String" rejected all of them before
## validate_rule_composition could read it. The intent was documented in a
## comment at the SCHEMA; the mechanism was an unnamed fall-through at the
## VALIDATOR. Anyone tightening that arm to fail closed — a reasonable hardening
## — would have broken rule composition, and the comment sat in another file.
##
## So "Variant" is now a declared arm, and a genuinely unknown spec warns.
##
## THE RUNTIME WARNING IS NOT THE GUARD. Nobody reads warnings, and a typo is a
## development-time bug that should never reach a player. This test is the check:
## it walks every schema const in src/ and fails on a spec the validator cannot
## resolve, naming it. That is why it scans the CORPUS rather than testing
## _type_matches on a handful of literals — a unit test of the function cannot
## see a typo in a schema nobody thought to pass it.

const LS := preload("res://src/llm/LLMService.gd")

## Kept in sync with _type_matches by the round-trip test below, not by hand.
const KNOWN: Array[String] = ["String", "int", "float", "bool", "Array", "Dictionary", "Variant"]


func _svc():
	var s = LS.new()
	add_child_autofree(s)
	return s


## Every `const *SCHEMA*: Dictionary = { ... }` in src/, as {const_name: {key: spec}}.
## Parsed rather than listed — a hand-maintained list is a second source that
## drifts the first time someone adds a schema, which is the defect one layer up.
func _all_schemas() -> Dictionary:
	var out: Dictionary = {}
	var files: PackedStringArray = []
	_collect_gd("res://src", files)
	var const_re := RegEx.new()
	const_re.compile("const ([A-Z_]*SCHEMA[A-Z_]*)[^=]*=\\s*\\{")
	var pair_re := RegEx.new()
	pair_re.compile("\"([A-Za-z_0-9]+)\"\\s*:\\s*\"([A-Za-z_0-9]+)\"")
	for f in files:
		var txt: String = FileAccess.get_file_as_string(f)
		for cm in const_re.search_all(txt):
			var body_start: int = cm.get_end()
			var body_end: int = txt.find("\n}", body_start)
			if body_end == -1:
				continue
			var body: String = txt.substr(body_start, body_end - body_start)
			var specs: Dictionary = {}
			for pm in pair_re.search_all(body):
				specs[pm.get_string(1)] = pm.get_string(2)
			if not specs.is_empty():
				out[cm.get_string(1)] = specs
	return out


func _collect_gd(dir_path: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		var full: String = dir_path + "/" + n
		if d.current_is_dir():
			if not n.begins_with("."):
				_collect_gd(full, out)
		elif n.ends_with(".gd"):
			out.append(full)
		n = d.get_next()
	d.list_dir_end()


# ── the ratchet ───────────────────────────────────────────────────────────────

func test_every_authored_schema_spec_resolves_in_the_validator() -> void:
	var schemas: Dictionary = _all_schemas()
	var svc = _svc()
	var offenders: Array[String] = []
	var checked: int = 0
	for cname in schemas:
		for key in (schemas[cname] as Dictionary):
			var spec: String = str((schemas[cname] as Dictionary)[key])
			checked += 1
			if not (spec in KNOWN):
				offenders.append("%s[%s] = \"%s\"" % [cname, key, spec])
			# and the validator must actually agree, not just the list
			elif spec != "Variant" and svc._type_matches(42, spec) and svc._type_matches("x", spec):
				offenders.append("%s[%s] = \"%s\" accepts BOTH an int and a String — not a real type check"
					% [cname, key, spec])
	gut.p("  checked %d specs across %d schema consts" % [checked, schemas.size()])
	assert_eq(offenders, [] as Array[String],
		"a schema names a type the guard cannot resolve, so that key is unvalidated: %s"
			% [", ".join(offenders)])


func test_the_scan_actually_found_the_schemas() -> void:
	## VACUITY CONTROL. A parser that silently matched nothing would make the
	## ratchet above trivially green — the failure mode is indistinguishable from
	## a clean corpus, which is the whole reason this file exists.
	## Floors are deliberately WELL BELOW today's counts (8 consts / 16 specs). Their
	## job is to catch a parser that matched nothing, not to forbid a lane from
	## deleting a schema — a floor pinned to the current count reds on a correct
	## change, which is how a ratchet becomes another lane's fold problem.
	var schemas: Dictionary = _all_schemas()
	assert_gte(schemas.size(), 4,
		"the parser found %d schema consts — it is broken, not the corpus" % schemas.size())
	var total: int = 0
	for c in schemas:
		total += (schemas[c] as Dictionary).size()
	assert_gte(total, 8, "the parser found %d string-typed specs — it is broken" % total)
	assert_true(schemas.has("SCHEMA_RULE_COMPOSITION"),
		"CONTROL: the scan must find the one const carrying the deliberate Variant")
	assert_true(schemas.has("REBALANCE_SCHEMA"),
		"CONTROL: and the one NOT named SCHEMA_* — my first pass missed it by pattern")


# ── the validator's own contract ──────────────────────────────────────────────

func test_variant_is_a_declared_arm_not_a_fall_through() -> void:
	## The discriminator. Before, "Variant" worked because it was UNKNOWN. That is
	## indistinguishable from a typo, and it broke the moment anyone hardened the
	## fall-through — with the intent documented in a different file.
	var src: String = FileAccess.get_file_as_string("res://src/llm/LLMService.gd")
	assert_false(src.is_empty(), "CONTROL: source must load")
	var body_at: int = src.find("func _type_matches")
	assert_true(body_at != -1, "CONTROL: the validator must exist")
	var body: String = src.substr(body_at, 700)
	assert_true(body.contains("\"Variant\":"),
		"Variant must be a named arm — relying on the unknown branch makes intent and typo identical")


func test_an_unknown_spec_is_no_longer_silent() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/llm/LLMService.gd")
	var body_at: int = src.find("func _type_matches")
	var body: String = src.substr(body_at, 700)
	assert_true(body.contains("push_warning"),
		"the fall-through must announce that it is switching validation off for a key")


func test_the_known_list_matches_what_the_validator_accepts() -> void:
	## Round-trip: KNOWN is used by the ratchet, so it must not drift from the
	## validator it claims to mirror. A stale KNOWN would let a removed type pass
	## the ratchet while the guard rejected it at runtime.
	var svc = _svc()
	for t in ["String", "int", "float", "bool", "Array", "Dictionary"]:
		assert_true(t in KNOWN, "%s must be in KNOWN" % t)
	assert_true(svc._type_matches("s", "String"), "String accepts a String")
	assert_false(svc._type_matches(1, "String"), "String rejects an int — the arm is real")
	assert_true(svc._type_matches([], "Array"), "Array accepts an Array")
	assert_false(svc._type_matches({}, "Array"), "Array rejects a Dictionary")
	assert_true(svc._type_matches({}, "Variant"), "Variant accepts anything")
	assert_true(svc._type_matches(1, "Variant"), "including an int")
