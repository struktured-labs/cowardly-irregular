extends GutTest

## A pass that repairs a MODEL ARTIFACT must be reachable from BOTH domains.
##
## RuleComposer runs ~15 normalisation passes over the model's reply. Two shipped reachable
## from one domain only, while the thing they repair is domain-independent, and both cost
## the player their whole composition in the domain that was left out:
##
##   _expand_or_conditions   an `or` survived to validate_rule -> the WHOLE set discarded
##   _drop_null_targets      a present null defeated .get(k, default) -> "<null>" at runtime
##
## 🔑 THE DISCRIMINATOR IS DERIVABLE. Ask where the type a pass FILTERS ON lives:
##
##   in exactly ONE grammar   grammar-specific vocabulary   gating it is CORRECT
##   in NEITHER grammar       a MODEL ARTIFACT              it must reach BOTH domains
##
## A model artifact is something the LLM invented that no grammar accepts — `or`, `any_of`,
## a null `target`. The model invents it for the same reason in both domains, so the repair
## is domain-independent by construction. `enemy_weak_to` / `item_count` / `member_status`
## are vocabulary one domain's PROMPT offered, so those gates are right.
##
## ⚠️ THE INVARIANT IS REACHABILITY, NOT "UNGATED" — and that distinction is the whole
## guard. The OR fix did not remove a gate; it added a call, because autogrind already
## reached the pass transitively through _normalise_autogrind_conditions. A guard asserting
## "not inside a gate block" would red on the correct code.
##
## Measured when written: 1 model-artifact pass, reachable from both. Every other gated
## pass filters vocabulary belonging to exactly one grammar.
##
## DERIVED from RuleComposer's own source and the two systems' own const tables — a rename
## cannot leave it stale, and a NEW pass is covered without editing this file.

const COMPOSER_PATH := "res://src/llm/RuleComposer.gd"

## EVERY table that names a type id, not the two that were obvious. TARGET_TYPES belongs
## here because the model writes target names INTO the type field — that is the whole
## reason _drop_target_shaped_conditions exists. Omitting it made a legitimately
## autobattle-specific pass classify as a model artifact, which would red this guard on a
## correct change. A registry cannot report a table it never opens (cowir-autogrind).
const AUTOBATTLE_TABLES := ["CONDITION_TYPES", "ACTION_TYPES", "TARGET_TYPES"]
const AUTOGRIND_TABLES := ["PARTY_CONDITION_TYPES", "AUTOGRIND_ACTION_TYPES"]

var _rc = null
var _ab = null
var _ag = null
var _src: String = ""


func before_each() -> void:
	_rc = get_tree().root.get_node_or_null("RuleComposer")
	_ab = get_tree().root.get_node_or_null("AutobattleSystem")
	_ag = get_tree().root.get_node_or_null("AutogrindSystem")
	var f := FileAccess.open(COMPOSER_PATH, FileAccess.READ)
	if f != null:
		_src = f.get_as_text()
		f.close()


## Every type id a system accepts, unioned across its own const tables.
func _vocabulary(system, names: Array) -> Dictionary:
	var out: Dictionary = {}
	if system == null:
		return out
	for n in names:
		if not (n in system):
			continue
		var table = system.get(n)
		if typeof(table) == TYPE_DICTIONARY:
			for k in (table as Dictionary):
				out[str(k)] = true
	return out


func _body(fn: String) -> String:
	var start: int = _src.find("func %s(" % fn)
	if start < 0:
		return ""
	var nxt: int = _src.find("\nfunc ", start + 1)
	return _src.substr(start, (nxt - start) if nxt > start else -1)


func _composer_funcs() -> Dictionary:
	var out: Dictionary = {}
	var rx := RegEx.new()
	rx.compile("(?m)^func (_[a-z_]+)\\(")
	for m in rx.search_all(_src):
		out[m.get_string(1)] = true
	return out


## The type literals a pass matches on. TWO forms, and the second is the one the historical
## bug used — a const array tested with .has(), which a comparison-only scan cannot see.
func _filter_types(fn: String) -> Array:
	var b: String = _body(fn)
	var out: Array = []
	var direct := RegEx.new()
	direct.compile("get\\(\"type\", \"\"\\)\\)? *[!=]= *\"([a-z_]+)\"")
	for m in direct.search_all(b):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	var consts := RegEx.new()
	consts.compile("(?s)const ([A-Z_]+) *:= *\\[(.*?)\\]")
	var lit := RegEx.new()
	lit.compile("\"([a-z_]+)\"")
	for m in consts.search_all(b):
		var uses := RegEx.new()
		uses.compile("%s\\.has\\([^)]*get\\(\"type\"" % m.get_string(1))
		if uses.search(b) == null:
			continue
		for l in lit.search_all(m.get_string(2)):
			if not out.has(l.get_string(1)):
				out.append(l.get_string(1))
	return out


## Passes named directly inside an `if domain == DOMAIN_X:` block, per domain.
func _gate_roots() -> Dictionary:
	var funcs: Dictionary = _composer_funcs()
	var out: Dictionary = {"autobattle": {}, "autogrind": {}}
	var gate := RegEx.new()
	gate.compile("^(\\t*)if domain == DOMAIN_(AUTOBATTLE|AUTOGRIND)")
	var call := RegEx.new()
	call.compile("(_[a-z_]+)\\(")
	var lines: PackedStringArray = _src.split("\n")
	var i: int = 0
	while i < lines.size():
		var m := gate.search(lines[i])
		if m == null:
			i += 1
			continue
		var depth: int = m.get_string(1).length()
		var dom: String = m.get_string(2).to_lower()
		var j: int = i + 1
		while j < lines.size():
			var line: String = lines[j]
			if line.strip_edges() == "":
				j += 1
				continue
			if line.length() - line.lstrip("\t").length() <= depth:
				break
			## A COMMENT NAMING A PASS IS NOT A CALL. Without this, "## runs before
			## _supply_missing_mp_guards(...)" inside a gate registers a phantom root — and a
			## phantom root makes _reachable() report a pass as reaching a domain it does not,
			## which SILENCES a real defect. Zero instances today; the existing comments simply
			## lack the "(" this regex needs, which is a coincidence and not a guarantee.
			if line.strip_edges().begins_with("#"):
				j += 1
				continue
			for c in call.search_all(line):
				if funcs.has(c.get_string(1)):
					(out[dom] as Dictionary)[c.get_string(1)] = true
			j += 1
		i = j
	return out


## Transitive closure — a pass reached through another pass is reached.
func _reachable(seed: Dictionary) -> Dictionary:
	var funcs: Dictionary = _composer_funcs()
	var seen: Dictionary = seed.duplicate()
	var stack: Array = seen.keys()
	var call := RegEx.new()
	call.compile("(_[a-z_]+)\\(")
	while stack.size() > 0:
		var fn: String = str(stack.pop_back())
		for m in call.search_all(_body(fn)):
			var c: String = m.get_string(1)
			if funcs.has(c) and c != fn and not seen.has(c):
				seen[c] = true
				stack.append(c)
	return seen


# ── floor ─────────────────────────────────────────────────────────────────────

func test_the_pieces_this_file_derives_from_are_reachable() -> void:
	assert_not_null(_rc, "RuleComposer autoload missing — nothing below runs")
	assert_not_null(_ab, "AutobattleSystem autoload missing — one half of the vocabulary")
	assert_not_null(_ag, "AutogrindSystem autoload missing — the other half")
	assert_gt(_src.length(), 0, "RuleComposer.gd unreadable at %s" % COMPOSER_PATH)


func test_the_derivation_is_not_empty_in_any_of_its_four_parts() -> void:
	## ANTI-VACUITY, and it is the arm that matters: the guard below is a loop over derived
	## sets, so an empty derivation scores GREEN having checked nothing. The first version
	## of this file did exactly that — its extractor missed the const-array form, so the
	## one pass it exists to watch derived zero filter types and the file passed.
	var ab: Dictionary = _vocabulary(_ab, AUTOBATTLE_TABLES)
	var ag: Dictionary = _vocabulary(_ag, AUTOGRIND_TABLES)
	assert_gt(ab.size(), 0, "derived ZERO autobattle types — a const table was renamed")
	assert_gt(ag.size(), 0, "derived ZERO autogrind types — a const table was renamed")
	## EVERY NAMED TABLE MUST ACTUALLY OPEN. A renamed table silently shrinks the
	## vocabulary, and a shrunken vocabulary makes grammar-specific passes look like
	## model artifacts — a FALSE RED on correct code. The union being non-empty cannot
	## see that; only a per-table check can.
	for pair in [[_ab, AUTOBATTLE_TABLES], [_ag, AUTOGRIND_TABLES]]:
		for tname in (pair[1] as Array):
			var one: Dictionary = _vocabulary(pair[0], [tname])
			assert_gt(one.size(), 0,
				("the const table %s contributed ZERO keys — renamed or moved. The guard "
				+ "below would then classify its vocabulary as model artifacts and red a "
				+ "correct change.") % tname)
	var roots: Dictionary = _gate_roots()
	assert_gt((roots["autobattle"] as Dictionary).size(), 0, "no autobattle-gated passes found")
	assert_gt((roots["autogrind"] as Dictionary).size(), 0, "no autogrind-gated passes found")
	assert_gt(_filter_types("_expand_or_conditions").size(), 0,
		"the extractor derives no filter types for _expand_or_conditions — it matches its "
		+ "construct through a const array, and an extractor blind to that form makes this "
		+ "whole file vacuous while it reports green")


# ── the guard ─────────────────────────────────────────────────────────────────

func test_every_model_artifact_repair_reaches_both_domains() -> void:
	## THE DEFECT CLASS, and it shipped twice. A pass whose filter types are in NEITHER
	## grammar repairs something the MODEL invented, not something a grammar defines — so
	## it is domain-independent, and reaching only one domain leaves the other holding it.
	var ab: Dictionary = _vocabulary(_ab, AUTOBATTLE_TABLES)
	var ag: Dictionary = _vocabulary(_ag, AUTOGRIND_TABLES)
	var roots: Dictionary = _gate_roots()
	var reach_ab: Dictionary = _reachable(roots["autobattle"])
	var reach_ag: Dictionary = _reachable(roots["autogrind"])
	var checked: int = 0
	var offenders: Array = []
	for fn in _composer_funcs():
		if not (reach_ab.has(fn) or reach_ag.has(fn)):
			continue
		var types: Array = _filter_types(fn)
		if types.is_empty():
			continue
		var artifact: bool = true
		for t in types:
			if ab.has(t) or ag.has(t):
				artifact = false
				break
		if not artifact:
			continue
		checked += 1
		if not (reach_ab.has(fn) and reach_ag.has(fn)):
			offenders.append("%s repairs %s but reaches only %s"
				% [fn, types, "autobattle" if reach_ab.has(fn) else "autogrind"])
	assert_gt(checked, 0,
		"found NO model-artifact passes to check — either every repair is now grammar-keyed "
		+ "or the classifier broke; either way this arm stopped defending anything")
	assert_eq(offenders, [],
		("a repair for a construct NEITHER grammar accepts reaches only one domain: %s. "
		+ "The model invents these for the same reason in both domains, so the repair is "
		+ "domain-independent — this is exactly how an unexpanded `or` discarded autobattle "
		+ "players' whole composition while autogrind expanded it correctly. Call the pass "
		+ "from the other domain too; it does not need a gate removed.") % [offenders])


func test_a_gated_pass_never_filters_only_the_other_domains_vocabulary() -> void:
	## The other direction: a pass gated to one domain that only matches the OTHER domain's
	## vocabulary can never fire at all — dead code that reads as coverage.
	var vocab: Dictionary = {
		"autobattle": _vocabulary(_ab, AUTOBATTLE_TABLES),
		"autogrind": _vocabulary(_ag, AUTOGRIND_TABLES),
	}
	var roots: Dictionary = _gate_roots()
	var wrong: Array = []
	for dom in ["autobattle", "autogrind"]:
		var other: String = "autogrind" if dom == "autobattle" else "autobattle"
		for fn in (roots[dom] as Dictionary):
			for t in _filter_types(fn):
				if (vocab[other] as Dictionary).has(t) and not (vocab[dom] as Dictionary).has(t):
					wrong.append("%s is gated to %s but filters \"%s\", which only %s defines"
						% [fn, dom, t, other])
	assert_eq(wrong, [],
		"a gated pass filters only the other domain's vocabulary, so it can never match: %s"
			% [wrong])
