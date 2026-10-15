extends GutTest

## A refused Apply buzzed and said nothing, then the proposal vanished from the list.
##
## RebalanceReviewPanel._apply_current gated its Toast on APPLY_APPLIED, so the APPLY_REJECTED path
## played menu_error and showed no text at all. force_apply then set status="rejected", which
## _refresh() filters out of the needs_review list -- so from the player's seat: click Apply, hear
## an error, watch the proposal disappear, learn nothing.
##
## REACHABLE AT THE SHIPPED DEFAULT, which is why this is not a latent hole: REBALANCE_SCHEMA
## declares `"deltas": "Array"` and constrains NOTHING about the constant names inside it. So a
## model naming a dial outside ALLOWED_CONSTANTS passes the schema, lands in review, and is refused
## only at force_apply's safelist -- and an LLM inventing a plausible constant is the expected case,
## not an exotic one.
##
## The daemon now records the reason beside the status in ONE place (_reject), so a refused proposal
## cannot leave review without one, and the panel reads that reason.

const PANEL := "res://src/ui/RebalanceReviewPanel.gd"


func _daemon_with(deltas: Array) -> RebalanceDaemon:
	var d := RebalanceDaemon.new()
	d.pending.append({
		"trigger": "level_up", "ts": 0, "context_summary": "x",
		"status": "needs_review", "verdict": "nudge_easier",
		"confidence": 0.9, "reason": "r", "deltas": deltas,
	})
	return d


# ── the reason exists, is specific, and rides WITH the status ──

func test_an_unlisted_constant_is_refused_and_names_itself() -> void:
	var d := _daemon_with([{"constant": "enemy_hp_multiplier", "value": 1.1}])
	assert_eq(d.force_apply(0), d.APPLY_REJECTED, "an unlisted dial must be refused")
	var why: String = str(d.pending[0].get("reject_reason", ""))
	assert_ne(why, "", "THE DEFECT: refused with no reason, so the panel had nothing to show")
	assert_true(why.contains("enemy_hp_multiplier"),
		"the reason must name the offending constant, or the player cannot act on it: %s" % why)


func test_malformed_deltas_are_refused_with_their_own_reason() -> void:
	var d := _daemon_with(["not a dictionary"])
	assert_eq(d.force_apply(0), d.APPLY_REJECTED, "a malformed delta must be refused")
	var why: String = str(d.pending[0].get("reject_reason", ""))
	assert_ne(why, "", "a malformed delta must also record a reason")
	assert_false(why.contains("not a dial"),
		"it must not borrow the safelist's wording -- the two causes are different: %s" % why)


## The status and the reason are set together, so review cannot drop a proposal that has no reason.
func test_a_rejected_status_never_travels_without_a_reason() -> void:
	for deltas in [["bad"], [{"constant": "nope", "value": 1.0}], [{"no_constant_key": 1}]]:
		var d := _daemon_with(deltas)
		assert_eq(d.force_apply(0), d.APPLY_REJECTED, "fixture must be refused: %s" % str(deltas))
		assert_eq(str(d.pending[0].get("status", "")), "rejected", "status must say rejected")
		assert_ne(str(d.pending[0].get("reject_reason", "")), "",
			"a rejected proposal with no reason is the defect, for deltas %s" % str(deltas))


## CONTROL: an ALLOWED dial must still apply, or the refusal above proves only that nothing works.
func test_an_allowed_constant_still_applies() -> void:
	var d := _daemon_with([{"constant": "exp_multiplier", "value": 1.05}])
	var out: String = d.force_apply(0)
	assert_ne(out, d.APPLY_REJECTED, "a listed dial must not be refused by the safelist")
	assert_eq(str(d.pending[0].get("reject_reason", "")), "",
		"and a successful apply must not leave a stale refusal reason behind")


# ── the panel actually shows it. Source arms read code_of, never raw text: a presence assert over
# raw source is satisfied by prose about the code (@cowir-overworld measured a sibling lane's
# COMMENT capturing a guard's anchor, green, on this very release).

func test_the_panel_shows_a_toast_on_the_refused_path() -> void:
	var code: String = GdSource.code_of(PANEL)
	assert_gt(code.length(), 0, "FIXTURE: the panel source must be readable")
	# ANCHOR ON THE DEFINITION, not the name: `_apply_current` occurs twice (a call at :213 and
	# the func at :267), and find() takes the call -- my own banked tell is to COUNT the matches.
	assert_eq(code.count("func _apply_current"), 1, "FIXTURE: exactly one definition to anchor on")
	var at: int = code.find("func _apply_current")
	assert_gt(at, -1, "FIXTURE: the apply handler must exist")
	var body: String = code.substr(at, code.find("\nfunc ", at + 10) - at)
	assert_true(body.contains("_reject_reason("),
		"the refused path must read the daemon's reason")
	assert_true(body.contains("WARNING_COLOR"),
		"a refusal must be visually distinct from a success and from a no-change")


## The success path must NOT have been traded away for the new one.
func test_the_applied_toast_survives() -> void:
	var code: String = GdSource.code_of(PANEL)
	assert_true(code.contains("summarize_applied(last)"),
		"the applied summary must still be shown -- this fix adds a branch, it does not replace one")
	assert_true(code.contains("SUCCESS_COLOR if moved > 0 else Toast.DEFAULT_COLOR"),
		"and the moved-vs-clamped distinction from .694 must be intact")
