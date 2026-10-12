extends GutTest

## The Settings "LLM Connection" row shared its catch-all with a REAL kind, so a kind it did not
## recognise printed "UNREACHABLE (model) — retrying every 30s": a confident, specific, actionable
## instruction for the one case it has no evidence about. The player waits for a retry that may
## never apply. Self-reported on 2026-10-12 after four lanes each found this shape in shipped code.
##
## Two guards, DISJOINT populations, because neither narrows the other:
##   1. DERIVATION — every kind the backend can PRODUCE has its own arm in the consumer.
##      Catches a sixth kind added without a sixth message, which no runtime arm can reach:
##      the consumer's input domain is CLOSED BY THE PRODUCER, so a new token does not exist
##      until someone edits the producer. Nothing to drive; the relation is the subject.
##   2. HONESTY — given a kind it does not know, the row SAYS it does not know.
##      Catches reverting the catch-all to a borrowed message, which the derivation cannot see
##      (it only checks that known tokens have arms, never what the unknown case prints).
##
## The extractor is the half with no arm on it unless one is written, so it gets three of its own
## (@cowir-deploy, @cowir-overworld, 2026-10-12): it is bounded by a NEGATED CHARACTER CLASS rather
## than an unbounded forward scan for a quote, it REFUSES a return it cannot read instead of
## silently skipping it, and it reads `return ""` as READABLE-AND-NOT-A-MEMBER rather than tripping
## the refusal on the shape the refusal exists to allow.

const BACKEND_SRC := "res://src/llm/HTTPBackend.gd"
const SETTINGS_SRC := "res://src/ui/SettingsMenu.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const PRODUCER := "unavailable_kind"
const CONSUMER := "_get_llm_status_subtitle"


## A backend answering exactly what LLMService.get_backend_status passes through, so the row can be
## driven with a kind the real producer cannot currently emit. This is a unit test of a total
## function over its declared input, NOT a claim that the system can reach this state.
## ⛔ MUST extend LLMBackend, not Node: `LLMService._backends` is `Array[LLMBackend]`, which
## REFUSES a non-conforming object at append — and the refusal is an error, not an exception, so
## the array stays empty, get_backend_status returns {}, and the row reads "No LLM backend
## configured". Measured: my first version extended Node and 4 arms failed on a premise that was
## never constructed. Hence _subtitle_for asserts the stub actually landed.
class StubBackend extends LLMBackend:
	var info: Dictionary = {}
	func backend_id() -> String: return "stub"
	func is_ready() -> bool: return false
	func get_availability_info() -> Dictionary: return info


func _read(path: String) -> String:
	var t: String = FileAccess.get_file_as_string(path)
	assert_ne(t, "", "CONTROL: %s must be readable" % path)
	return t


## A function's body, bounded at the next top-level `func ` — never a character count.
## A fixed width reds on an unrelated insertion and names the wrong file (@cowir-music's 24 cases).
func _body_of(src: String, fn: String) -> String:
	var at: int = src.find("func " + fn)
	if at == -1:
		return ""
	var nxt: int = src.find("\nfunc ", at + 1)
	return src.substr(at, nxt - at) if nxt > -1 else src.substr(at)


## The kinds the backend can produce, READ THROUGH THE CLASS rather than parsed out of its source.
## A const read cannot be defeated by prose, by a bracket in a type annotation, or by a bounding
## slip: the engine already parsed the declaration. Replaces a text extractor that needed four
## assertions to be trustworthy — three lanes converged on this as the top rung on 2026-10-12.
func _producible_kinds() -> Array[String]:
	var out: Array[String] = []
	for v in HTTPBackend.KIND_FOR_CODE.values():
		if not out.has(str(v)):
			out.append(str(v))
	if not out.has(HTTPBackend.KIND_FALLBACK):
		out.append(HTTPBackend.KIND_FALLBACK)
	return out


## The consumer's source with comments AND docstring regions removed, via the shared stripper.
## `split("#")[0]` was a private line-pass: a `#` inside a string truncated the line, and it could
## not touch a `"""` region at all — no tighter pattern reaches one, because the construct spans
## lines. Every arm and control below routes through HERE, never through GdSource directly.
func _consumer_code() -> String:
	return str(GdSource.split(_read(SETTINGS_SRC))["code"])


## [arms, unreadable] — the consumer side gets the SAME three states as the producer side.
## A match pattern may legally be a CONST, which routes exactly as the literal does; that is
## invisible to a quoted-literal scan. Without the second return value the kind read as UNBRANCHED
## and the guard blamed the wrong thing — "no arm for key_rejected" when an arm existed and only
## the reader could not see it. Measured by planting one (@cowir-sfx hit the same shape, silently).
func _match_arms(body: String) -> Array:
	var arms: Array[String] = []
	var unreadable: Array[String] = []
	var literal := RegEx.create_from_string('^\\s*"([^"]*)"\\s*:\\s*$')
	var ident := RegEx.create_from_string('^\\t\\t([A-Za-z][A-Za-z0-9_]*)\\s*:\\s*$')
	for raw in body.split("\n"):
		var m: RegExMatch = literal.search(raw)
		if m != null:
			arms.append(m.get_string(1))
			continue
		var u: RegExMatch = ident.search(raw)
		if u != null:
			unreadable.append(u.get_string(1))
	return [arms, unreadable]


# ── 1. the derivation: produced ⊆ branched ───────────────────────────────────────────────────────

func test_every_kind_the_backend_can_produce_has_its_own_row_message() -> void:
	var kinds: Array[String] = _producible_kinds()
	## CONTENT floor, not a magnitude one: a wrong range can fake a count. SettingsMenu holds 9
	## quoted arm labels, 5 in this function and 4 in another match — so a shifted bound could
	## total 5 from the wrong place and pass `>= 5`. Naming two members cannot be faked that way.
	for must in ["key_rejected", "unreachable"]:
		assert_true(kinds.has(must),
			"CONTROL: %s is not in the producer's kind table — the read is broken, and an empty set makes the assert below vacuous" % must)
	var consumed: Array = _match_arms(_body_of(_consumer_code(), CONSUMER))
	var arms: Array = consumed[0]
	assert_eq(consumed[1], [],
		("the row has match patterns this guard cannot read: %s. They route exactly as a literal "
		+ "does, so a kind behind one would read as UNBRANCHED and this arm would blame the wrong "
		+ "thing. Use a literal, or teach the scan to resolve the const.") % [consumed[1]])
	for must in ["key_rejected", "unreachable"]:
		assert_true(arms.has(must),
			"CONTROL: the row's own %s arm was not read — the extraction is wrong, not the row" % must)
	var unbranched: Array[String] = []
	for k in kinds:
		if not arms.has(k):
			unbranched.append(str(k))
	assert_eq(unbranched, ([] as Array[String]),
		("%s can return these kinds and the Settings row has no arm for them: %s. A kind with no arm "
		+ "falls to the catch-all, and a reader never sees a symptom because the catch-all answers.") % [PRODUCER, unbranched])


func test_the_catch_all_is_not_shared_with_a_real_kind() -> void:
	## THE DEFECT ITSELF, as a relation: `unreachable` must have its OWN arm. While it lived in the
	## catch-all, an unknown kind inherited its message — and that message is an instruction.
	var arms: Array = (_match_arms(_body_of(_consumer_code(), CONSUMER)))[0]
	assert_true(arms.has("unreachable"),
		"'unreachable' has no arm of its own, so it is sharing the catch-all with every kind this screen does not know — got %s" % [arms])


# ── 2. honesty: the unknown case must not borrow a real kind's message ───────────────────────────

func _subtitle_for(kind: String, code: int) -> String:
	var svc: Node = get_node_or_null("/root/LLMService")
	assert_not_null(svc, "CONTROL: LLMService autoload must exist")
	var stub := StubBackend.new()
	add_child_autofree(stub)
	stub.info = {"available": false, "probed": true, "model": "test-model",
		"probe_interval_sec": 30.0, "probe_code": code}
	if kind != "<omitted>":
		stub.info["kind"] = kind
	var saved: Array = svc._backends.duplicate()
	var saved_active = svc._active_backend
	var saved_on: bool = svc.llm_enabled
	svc._backends.clear()
	svc._backends.append(stub)
	## PREMISE: a typed array refuses a non-conforming stub silently, and every assert downstream
	## then judges "No LLM backend configured" instead of the row this file is about.
	assert_eq(svc._backends.size(), 1, "PREMISE: the stub backend must actually be in _backends")
	svc._active_backend = stub
	svc.llm_enabled = true
	var menu = load(SETTINGS_SRC).new()
	add_child_autofree(menu)
	var out: String = menu._get_llm_status_subtitle()
	svc._backends.assign(saved)
	svc._active_backend = saved_active
	svc.llm_enabled = saved_on
	return out


func test_a_kind_this_screen_does_not_know_says_so() -> void:
	var unknown: String = _subtitle_for("tls_handshake_failed", 525)
	assert_false(unknown.contains("UNREACHABLE"),
		"an unrecognised kind printed the UNREACHABLE message — a confident instruction for the one case with no evidence: %s" % unknown)
	assert_true(unknown.contains("tls_handshake_failed"),
		"the row must NAME the kind it does not know, so whoever added it learns where to add a message: %s" % unknown)
	assert_false(unknown.contains("retrying every"),
		"the unknown case promised the retry that only the unreachable case can promise: %s" % unknown)


func test_an_absent_kind_is_unknown_and_not_unreachable() -> void:
	## The payload default, which was the same lie one layer earlier: a backend without the field
	## read as "the server is down" rather than "I cannot tell".
	var absent: String = _subtitle_for("<omitted>", 0)
	assert_false(absent.contains("UNREACHABLE"),
		"an ABSENT kind defaulted to UNREACHABLE — a missing field is not a diagnosis: %s" % absent)


func test_the_real_kinds_still_read_as_before() -> void:
	## CONTROL for all four arms above: without it, a row that returned the unknown text for
	## everything would satisfy every assert in this file.
	assert_true(_subtitle_for("unreachable", 0).contains("UNREACHABLE"), "unreachable must keep its own message")
	assert_true(_subtitle_for("unreachable", 0).contains("retrying every"), "and must keep promising the retry")
	assert_true(_subtitle_for("key_rejected", 401).contains("KEY REJECTED"), "key_rejected must keep its message")
	assert_true(_subtitle_for("rate_limited", 429).contains("RATE LIMITED"), "rate_limited must keep its message")
	assert_true(_subtitle_for("not_found", 404).contains("404"), "not_found must keep its message")
	assert_true(_subtitle_for("http_error", 503).contains("503"), "http_error must name the status it got")


# ── 3. the extractor, which is the half nobody points an arm at ──────────────────────────────────

func test_the_body_bound_stops_at_the_next_function() -> void:
	## CONTROL on the bound, on a SYNTHETIC source that CONTAINS the hazard: a neighbouring match
	## must not leak in, or adding a function below the consumer silently grows the derived arms.
	var two: String = ("func " + CONSUMER + "() -> String:\n\tmatch x:\n\t\t\"mine\":\n\t\t\treturn \"a\"\n"
		+ "\nfunc something_else() -> String:\n\tmatch y:\n\t\t\"theirs\":\n\t\t\treturn \"b\"\n")
	var got: Array = _match_arms(_body_of(two, CONSUMER))
	assert_true((got[0] as Array).has("mine"), "the bound dropped the consumer's own arm: %s" % [got[0]])
	assert_false((got[0] as Array).has("theirs"), "the bound leaked into the next function: %s" % [got[0]])


# ── 4. the strip the consumer side rests on ──────────────────────────────────────────────────────

func test_the_strip_this_guard_rests_on_removes_prose_and_keeps_code() -> void:
	## FOUR ASSERTIONS, FOUR BLIND SPOTS — each satisfied by a defect in another direction, and all
	## routed through _consumer_code() rather than GdSource, because a control scoped to the HELPER
	## stays green when the caller is swapped back to a raw read (@cowir-battle measured that).
	var raw: String = _read(SETTINGS_SRC)
	var code: String = _consumer_code()
	## 1. a known CODE site SURVIVES — catches over-stripping; satisfied by a strip that never ran.
	assert_true(code.contains("func " + CONSUMER),
		"MUST-SURVIVE: the strip ate the consumer's own declaration, so every arm above judges nothing")
	## 2. a known # comment is GONE — catches no-strip; this is the arm a raw-read mutant trips.
	assert_true(raw.contains("# Naming the retry is the point"),
		"CONTROL: the raw source must still carry the comment this arm looks for")
	assert_false(code.contains("# Naming the retry is the point"),
		"the # pass did not run: prose reaches the extractor, so a kind named only in a comment would count")
	## 3. a PROPORTIONAL floor — catches a clever over-strip that kept the line assertion 1 names.
	assert_gt(code.length(), raw.length() / 2,
		"the strip kept %d of %d chars — it ate the bulk, which arm 1 cannot see if the one line it names survived" % [code.length(), raw.length()])
	## 4. a DOCSTRING token is GONE — catches a dropped REGION split, which the # pass alone passes.
	## Real for THIS subject: SettingsMenu carries 48 docstring lines. HTTPBackend has none, so the
	## same assert there would be decorative — a subject with no regions has nothing to miss.
	assert_true(raw.contains('\u0022\u0022\u0022'), "CONTROL: the subject must carry docstring regions for this arm to mean anything")
	assert_false(code.contains('\u0022\u0022\u0022'),
		"the region split did not run: docstring text reaches the extractor, and prose containing `func ` would forge a FALSE bound for _body_of")
