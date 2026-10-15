extends GutTest

## The daemon recorded five outcomes in proposal["status"] and printed NONE of them, so his play log
## carried three "considered … (awaiting LLM proposal)" lines and no word about any of them. Reading
## his SAVES was the only way to learn the answers.
##
## A `print` is invisible to a unit test, so the MESSAGE is a value (`outcome_line`) and only the
## printing is untestable -- @cowir-battle's split, applied here. That means a sixth outcome arriving
## without a line shows up as an empty string an arm can catch, rather than as a silent omission.

const Daemon := preload("res://src/llm/RebalanceDaemon.gd")

## Every status the request path can set, derived from the source rather than remembered, so a new
## one cannot be added without this file noticing.
func _statuses_in_source() -> Array:
	# COMMENT-STRIPPED, via the helper the MenuNav and leak guards already use. Every predicate here
	# is satisfied by a token's mere PRESENCE, so a comment merely naming a status would invent one --
	# @cowir-controller closed the same hole in their leak guard an hour ago. Quote-aware, so a `#`
	# inside a string literal is not treated as a comment.
	var src: String = GdSource.code_of("res://src/llm/RebalanceDaemon.gd")
	var i: int = src.find("func request_llm_proposal(")
	assert_gt(i, 0, "CONTROL: request_llm_proposal not found, so this file derives nothing")
	var body: String = src.substr(i, src.find("\nfunc ", i + 10) - i)
	# WHITESPACE-TOLERANT. The first version split on a one-space literal and missed
	# `proposal["status"]     = "proposed"` (aligned with padding at :264) -- the control caught it.
	var out: Array = []
	var re := RegEx.new()
	re.compile('proposal\\["status"\\]\\s*=\\s*"([a-z_]+)"')
	for m in re.search_all(body):
		var st: String = m.get_string(1)
		if st != "" and not out.has(st):
			out.append(st)
	# SECOND SHAPE, added 2026-10-14: a bad INDEX has no proposal to stamp, so that path passes its
	# status straight to outcome_line. Deriving only the stamped form left it outside this sweep.
	var lit := RegEx.new()
	lit.compile('outcome_line\\([^)]*?"(failed_[a-z_]+)"')
	for m2 in lit.search_all(body):
		var st2: String = m2.get_string(1)
		if st2 != "" and not out.has(st2):
			out.append(st2)
	return out


func test_every_outcome_the_request_path_sets_has_a_line() -> void:
	var statuses: Array = _statuses_in_source()
	gut.p("statuses derived from source: %s" % str(statuses))
	# NAMED, not a round-number floor. `size() > 3` would pass while the derivation silently dropped
	# half the outcomes -- @cowir-adhoc measured that exact shape costing 55% of a corpus under a
	# `> 500` control. A broken parser now reds with the missing name, and a NEW status is still
	# caught by the line arm below, which runs over whatever the derivation returns.
	for known in ["failed_no_tree", "failed_unavailable", "failed_fallback", "awaiting_llm", "proposed", "failed_bad_index"]:
		assert_true(statuses.has(known),
			"CONTROL: the derivation missed %s, so this arm judges a subset of the outcomes" % known)
	# EXEMPT, not skipped silently: :93 requires awaiting_llm to stay EMPTY because it is the
	# transient in-flight state and a line for it would fire on every request. The derivation must
	# still FIND it (asserted above), so an exemption here cannot hide a parser that missed it.
	var transient: Array = ["awaiting_llm"]
	for ex in transient:
		assert_true(statuses.has(ex),
			"CONTROL: %s must be DERIVED and then exempted, not absent from the derivation" % ex)
		assert_eq(Daemon.outcome_line("level_up", ex), "",
			"%s is transient; :93 pins it empty and this arm must agree rather than contradict it" % ex)
	var silent: Array = []
	for st in statuses:
		if transient.has(str(st)):
			continue
		var line: String = Daemon.outcome_line("level_up", str(st), {"verdict": "nudge_easier", "confidence": 0.6, "deltas": []})
		if line == "":
			silent.append(str(st))
	assert_eq(", ".join(silent), "",
		"these outcomes are recorded and never reach the log: %s" % ", ".join(silent))


func test_a_failure_line_names_the_trigger_and_the_reason() -> void:
	for pair in [["failed_no_tree", "no scene tree"],
			["failed_unavailable", "no LLM backend"],
			["failed_fallback", "not usable"]]:
		var line: String = Daemon.outcome_line("party_wipe", str(pair[0]))
		assert_string_contains(line, "party_wipe", "%s must name the trigger that produced nothing" % str(pair[0]))
		assert_string_contains(line, str(pair[1]), "%s must say WHY nothing came back" % str(pair[0]))
		assert_string_contains(line, "[REBALANCE]", "%s must carry the tag his log is grepped by" % str(pair[0]))


func test_the_proposed_line_carries_what_a_reader_needs() -> void:
	var line: String = Daemon.outcome_line("boss_defeat", "proposed", {
		"verdict": "nudge_easier", "confidence": 0.62,
		"deltas": [{"constant": "exp_multiplier"}, {"constant": "encounter_rate"}],
	})
	gut.p("proposed line: %s" % line)
	assert_string_contains(line, "boss_defeat", "the trigger")
	assert_string_contains(line, "nudge_easier", "the verdict")
	assert_string_contains(line, "62%", "the confidence, which is what gates auto-apply")
	assert_string_contains(line, "2 delta(s)", "how many dials it wants to move")
	# @cowir-sfx measured a bare Array operand to `%` rendering a LITERAL specifier at 0 and 2+
	# elements, destroying the message exactly when it matters. These lines use wrapped operands.
	assert_false(line.contains("%s"), "a format specifier survived into the rendered line: %s" % line)
	assert_false(line.contains("%d"), "a format specifier survived into the rendered line: %s" % line)


## A malformed proposal must still produce a usable line rather than abort the caller mid-exit.
func test_a_proposal_missing_its_fields_still_renders() -> void:
	var line: String = Daemon.outcome_line("area_entered", "proposed", {})
	assert_string_contains(line, "area_entered", "the trigger survives an empty proposal")
	assert_string_contains(line, "0 delta(s)", "an absent deltas key reads as none, not as a crash")
	var bad: String = Daemon.outcome_line("area_entered", "proposed", {"deltas": "not an array"})
	assert_string_contains(bad, "0 delta(s)", "a non-Array deltas value must not be counted or crash")


## One-directional: an unknown status returns "" rather than inventing a line. That empty string is
## what the completeness arm above reads, so it must stay empty.
func test_an_unknown_status_says_nothing_rather_than_guessing() -> void:
	assert_eq(Daemon.outcome_line("level_up", "awaiting_llm"), "",
		"awaiting_llm is a transient state, not an outcome; a line for it would fire on every request")
	assert_eq(Daemon.outcome_line("level_up", "no_such_status"), "",
		"an unknown status must not be given a line")


func test_the_daemon_still_has_what_this_file_drives() -> void:
	var d = Daemon.new()
	for m in ["request_llm_proposal", "summarize_applied", "try_auto_apply", "force_apply"]:
		assert_true(d.has_method(m), "RebalanceDaemon has no %s(), so this file's premises are stale" % m)
	# outcome_line is reached through the class, so a rename is a PARSE error (EC=3), not an abort --
	# louder than a floor. This line is the fixture's claim about which spelling it depends on.
	assert_ne(Daemon.outcome_line("t", "failed_no_tree"), "", "outcome_line() is gone or silent")


## The exit that said nothing. Measured in struktured's own logs 2026-10-14: across six sessions
## the daemon printed 31 "considered ... (awaiting LLM proposal)" lines and ZERO outcome lines, and
## the index guard was the only return in request_llm_proposal that did not log. Whatever path he
## hit, the log could not name it, so the next one must.
func test_the_bad_index_exit_is_not_silent() -> void:
	var line: String = Daemon.outcome_line("", "failed_bad_index", {"idx": 7, "pending": 3})
	assert_ne(line, "", "THE DEFECT: the one unlogged exit must reach the log like its four siblings")
	assert_true(line.contains("7") and line.contains("3"),
		"it must name the index AND the pending size, or it cannot be diagnosed: %s" % line)


## And the source must actually call it there -- outcome_line rendering is half the fix.
## THE ANCHOR IS NOT UNIQUE: the identical index guard appears in try_auto_apply (:313), force_apply
## (:390) and dismiss (:442), so the old bare find() reached MINE only because request_llm_proposal
## happens to be declared first. Slice the function first, then search inside it -- immune by shape.
func test_the_index_guard_prints() -> void:
	# code_of, not raw text: a comment quoting the guard would otherwise satisfy a presence assert.
	var src: String = GdSource.code_of("res://src/llm/RebalanceDaemon.gd")
	var guard := "if proposal_idx < 0 or proposal_idx >= pending.size():"
	# The slice is load-bearing, pinned as its own claim so the reason cannot be lost to a tidy-up.
	assert_gt(src.count(guard), 1,
		"FIXTURE: were the guard unique the slice below would be decoration; it is not")
	var fi: int = src.find("func request_llm_proposal(")
	assert_gt(fi, 0, "FIXTURE: request_llm_proposal not found, so this arm measures nothing")
	var nf: int = src.find("\nfunc ", fi + 10)
	var body: String = src.substr(fi) if nf < 0 else src.substr(fi, nf - fi)
	var at: int = body.find(guard)
	assert_gt(at, -1, "FIXTURE: the index guard must exist inside request_llm_proposal")
	# A relationship, not a 240-char window: the print must precede the guard's OWN return.
	var ret: int = body.find("return", at)
	assert_gt(ret, at, "FIXTURE: the guard must return, or this arm bounds nothing")
	assert_true(body.substr(at, ret - at).contains("print(outcome_line("),
		"the index guard must log before returning, like every other exit in this function")
