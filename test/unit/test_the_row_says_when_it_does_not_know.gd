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


## [tokens, unreadable] — the three states kept apart.
##   a quoted literal with content -> a MEMBER
##   `return ""`                   -> readable, NOT a member (the healthy-backend case)
##   anything else returning       -> UNREADABLE, reported so the caller can refuse
## `[^"]*` cannot cross a quote, so the bound is structural rather than remembered. An imperative
## `find("\"", i)` walks to the next quote ANYWHERE and imports an unrelated string.
func _returned_literals(body: String) -> Array:
	var tokens: Array[String] = []
	var unreadable: Array[String] = []
	var literal := RegEx.create_from_string('^\\s*return\\s+"([^"]*)"\\s*$')
	var any_return := RegEx.create_from_string('^\\s*return\\b')
	for raw in body.split("\n"):
		var line: String = raw.split("#")[0]
		if any_return.search(line) == null:
			continue
		var m: RegExMatch = literal.search(line)
		if m == null:
			unreadable.append(line.strip_edges())
			continue
		var tok: String = m.get_string(1)
		if tok != "":
			tokens.append(tok)
	return [tokens, unreadable]


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
		var line: String = raw.split("#")[0]
		var m: RegExMatch = literal.search(line)
		if m != null:
			arms.append(m.get_string(1))
			continue
		var u: RegExMatch = ident.search(line)
		if u != null:
			unreadable.append(u.get_string(1))
	return [arms, unreadable]


# ── 1. the derivation: produced ⊆ branched ───────────────────────────────────────────────────────

func test_every_kind_the_backend_can_produce_has_its_own_row_message() -> void:
	var produced: Array = _returned_literals(_body_of(_read(BACKEND_SRC), PRODUCER))
	var kinds: Array = produced[0]
	assert_eq(produced[1], [], "the producer has a return this guard cannot read: %s — see the refusal arm" % [produced[1]])
	assert_gt(kinds.size(), 3,
		"CONTROL: derived only %d kinds from %s — the extractor is broken, and an empty set makes the assert below vacuous" % [kinds.size(), PRODUCER])
	var consumed: Array = _match_arms(_body_of(_read(SETTINGS_SRC), CONSUMER))
	var arms: Array = consumed[0]
	assert_eq(consumed[1], [],
		("the row has match patterns this guard cannot read: %s. They route exactly as a literal "
		+ "does, so a kind behind one would read as UNBRANCHED and this arm would blame the wrong "
		+ "thing. Use a literal, or teach the scan to resolve the const.") % [consumed[1]])
	assert_gt(arms.size(), 3, "CONTROL: found only %d match arms in %s" % [arms.size(), CONSUMER])
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
	var arms: Array = (_match_arms(_body_of(_read(SETTINGS_SRC), CONSUMER)))[0]
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

func test_the_extractor_refuses_a_return_it_cannot_read() -> void:
	## "I found no members" and "I cannot read this" must not share a value. A derivation that
	## silently skips an unparseable return reports a SHORT set and the produced⊆branched assert
	## then passes about the members it happened to see.
	var synthetic: String = ("func unavailable_kind() -> String:\n"
		+ "\tif _ready_flag:\n\t\treturn \"\"\n"
		+ "\tmatch _last_probe_code:\n"
		+ "\t\t0:\n\t\t\treturn \"unreachable\"\n"
		+ "\t\t_:\n\t\t\treturn _kind_for(_last_probe_code)\n")
	var got: Array = _returned_literals(synthetic)
	assert_eq(got[0], (["unreachable"] as Array[String]), "the readable member must still be found")
	assert_eq((got[1] as Array).size(), 1,
		"a NON-LITERAL return was skipped silently instead of reported — got unreadable=%s" % [got[1]])
	assert_true(str((got[1] as Array)[0]).contains("_kind_for"),
		"the refusal must name the return it could not read: %s" % [got[1]])


func test_an_empty_literal_is_readable_and_simply_not_a_kind() -> void:
	## ⛔ THE FALSE RED THIS ARM EXISTS FOR. `unavailable_kind` returns "" for an AVAILABLE backend —
	## an empty LITERAL, readable, and not a member. @cowir-overworld's first refusal used `[a-z_]+`
	## and fired on exactly this shape, on a clean tree: the refusal tripped on the case it exists to
	## allow. `[^"]*` reads it; the empty capture is then dropped as a non-member.
	var got: Array = _returned_literals("func f() -> String:\n\treturn \"\"\n")
	assert_eq(got[0], ([] as Array[String]), "an empty literal is not a kind")
	assert_eq(got[1], [], "an empty literal is READABLE — refusing it reds a correct producer")


func test_the_extractor_cannot_import_a_string_from_elsewhere_in_the_function() -> void:
	## The unbounded-scan defect, as a control. An imperative find() for the next quote walks past
	## the return and imports whatever string comes next — yielding a phantom member that either
	## fails naming something that does not exist, or passes because the phantom is in the other set.
	var hostile: String = ("func unavailable_kind() -> String:\n"
		+ "\t\t\treturn \"unreachable\"\n"
		+ "\tif debug:\n\t\tprint(\"MUST NOT BE IMPORTED AS A KIND\")\n")
	var got: Array = _returned_literals(hostile)
	assert_eq(got[0], (["unreachable"] as Array[String]),
		"the extractor imported a string that is not a return value: %s" % [got[0]])


func test_the_body_bound_stops_at_the_next_function() -> void:
	## CONTROL on the bound: a neighbouring function's returns must not enter the set, or adding a
	## function below the producer silently grows the derived kinds.
	var two: String = ("func unavailable_kind() -> String:\n\t\t\treturn \"unreachable\"\n"
		+ "\nfunc something_else() -> String:\n\t\t\treturn \"not_a_kind\"\n")
	var got: Array = _returned_literals(_body_of(two, PRODUCER))
	assert_eq(got[0], (["unreachable"] as Array[String]),
		"the bound leaked into the next function: %s" % [got[0]])


func test_the_arm_scan_reports_a_match_pattern_it_cannot_read() -> void:
	## Symmetry with the producer side: "no arm for X" and "an arm exists that I cannot read" are
	## different facts and must not share a value. A const pattern routes identically to a literal,
	## so without this the guard reds blaming a missing arm that is actually present.
	var synthetic: String = ("func _get_llm_status_subtitle() -> String:\n"
		+ "\tmatch str(info.get(\"kind\", \"\")):\n"
		+ "\t\t\"unreachable\":\n\t\t\treturn \"a\"\n"
		+ "\t\tKIND_KEY_REJECTED:\n\t\t\treturn \"b\"\n"
		+ "\t\t_:\n\t\t\treturn \"c\"\n")
	var got: Array = _match_arms(synthetic)
	assert_eq(got[0], (["unreachable"] as Array[String]), "the literal arm must still be read")
	assert_eq((got[1] as Array), ["KIND_KEY_REJECTED"],
		"a const match pattern was not reported as unreadable — got %s" % [got[1]])
	## And `_:` is NOT unreadable: it is the catch-all, read by its own arm above.
	assert_false(str(got[1]).contains("_:"), "the catch-all must not be reported as an unreadable pattern")
