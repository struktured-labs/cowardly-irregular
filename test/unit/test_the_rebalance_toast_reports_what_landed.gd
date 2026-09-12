extends GutTest

## The player got a success toast for a change that did not happen.
##
## `summarize_applied` built its line from `multiplier` — the LLM's REQUEST —
## while the write path clamps the result to the cumulative band. Measured on the
## real daemon, exp_multiplier already at the ceiling:
##
##     before 1.15    after 1.15    moved 0.0
##     applied_changes: {before: 1.15, after: 1.15, multiplier: 1.1, clamped: true}
##     player is told:  "Auto-rebalance: exp_multiplier +10%"
##
## ⛔ THE BAND EDGE IS NOT AN EDGE CASE — IT IS THE STEADY STATE THE BAND EXISTS
## TO PRODUCE. `CUMULATIVE_DELTA_MIN/MAX` bound total drift from the authored
## default precisely so repeated applies cannot walk a dial outward; the daemon's
## own comment notes the triggers are area-entered, party-wipe, boss-defeat and
## level-up, so "twenty applications is an ordinary playthrough". Once a dial pins
## at the limit, EVERY later proposal in that direction announces a change and
## moves nothing.
##
## 🔑 THE DATA TO TELL THE TRUTH WAS ALREADY THERE. `applied_changes` carried
## `before`, `after` AND a `clamped` flag — written at both apply sites and read
## NOWHERE in src/. The safety rail worked; only its report was wrong. That is why
## nothing caught it: every test asked "did the clamp hold", none asked "is the
## player told what held".
##
## Three player surfaces read this formatter — the history panel, the toast after
## the player force-applies from the review panel, and GameLoop's auto-apply toast.
## The force-apply one is the sharpest: the player reads the proposal, accepts it,
## and is congratulated on a change the clamp refused.

const RD := preload("res://src/llm/RebalanceDaemon.gd")

const CONST_NAME := "exp_multiplier"

var _daemon
var _gs: Node
var _saved: Dictionary = {}


func before_each() -> void:
	_gs = get_tree().root.get_node_or_null("GameState")
	assert_not_null(_gs, "CONTROL: GameState autoload must exist")
	if _gs == null:
		return
	_saved = (_gs.game_constants as Dictionary).duplicate(true)
	_daemon = RD.new()


func after_each() -> void:
	if _gs != null and not _saved.is_empty():
		_gs.game_constants = _saved.duplicate(true)


## Apply one high-confidence delta from `start` and hand back what the player sees.
func _apply_from(start: float, multiplier: float) -> Dictionary:
	_gs.game_constants[CONST_NAME] = start
	_daemon.pending.append({
		"verdict": "nudge_easier", "confidence": 0.95, "trigger": "party_wipe",
		"reason": "the party keeps wiping", "status": "ready",
		"deltas": [{"constant": CONST_NAME, "multiplier": multiplier, "reason": "grind"}],
	})
	var result: String = _daemon.try_auto_apply(0)
	return {
		"result": result,
		"after": float(_gs.game_constants[CONST_NAME]),
		"line": str(_daemon.summarize_applied(_daemon.applied[-1])),
		"changes": (_daemon.applied[-1].get("applied_changes", []) as Array),
	}


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_dial_that_did_not_move_is_not_announced_as_a_change() -> void:
	## THE ARM. At the ceiling the clamp erases the whole nudge. The old line read
	## "Auto-rebalance: exp_multiplier +10%".
	var ceiling: float = 1.0 * RD.CUMULATIVE_DELTA_MAX
	var got: Dictionary = _apply_from(ceiling, 1.10)
	assert_eq(float(got["after"]), ceiling,
		"CONTROL: the clamp must actually have refused the change")
	assert_false(str(got["line"]).contains("+10%"),
		("the player is told about a change that did not happen: %s" % str(got["line"])))
	assert_true(str(got["line"]).contains("safe limit"),
		"the line must say why nothing moved: %s" % str(got["line"]))


func test_a_partly_clamped_change_reports_the_part_that_landed() -> void:
	## Halfway to the ceiling, a +10% ask lands as less than +10%.
	var start: float = 1.10
	var got: Dictionary = _apply_from(start, 1.10)
	var landed: float = float(got["after"])
	assert_lt(landed, start * 1.10, "CONTROL: this fixture must actually be clamped")
	assert_gt(landed, start, "CONTROL: and must still have moved, or it is the arm above")
	var actual_pct: int = int(round((landed / start - 1.0) * 100.0))
	assert_true(str(got["line"]).contains("+%d%%" % actual_pct),
		"the line must carry the pct that landed (%d): %s" % [actual_pct, str(got["line"])])
	assert_true(str(got["line"]).contains("limited from +10%"),
		"and must say what was asked for: %s" % str(got["line"]))


# ── it must not disturb the ordinary case ─────────────────────────────────────

func test_an_unclamped_change_still_reports_its_real_percentage() -> void:
	## CORRECT-WORK. Most applies are nowhere near the band edge and their line
	## must be unchanged — a truthful formatter that hedged every time would be
	## just as useless as one that lied.
	var got: Dictionary = _apply_from(1.0, 1.10)
	assert_almost_eq(float(got["after"]), 1.10, 0.0001, "CONTROL: this must NOT be clamped")
	assert_eq(str(got["line"]), "Auto-rebalance: exp_multiplier +10%",
		"an unclamped apply reads exactly as before")


func test_a_downward_nudge_keeps_its_sign() -> void:
	var got: Dictionary = _apply_from(1.0, 0.90)
	assert_almost_eq(float(got["after"]), 0.90, 0.0001, "CONTROL: not clamped")
	assert_true(str(got["line"]).contains("-10%"),
		"a nudge_easier downward must not render as +: %s" % str(got["line"]))


func test_no_change_and_empty_change_lines_are_untouched() -> void:
	## CONTROL: the two early returns are not part of this fix and must not move.
	assert_eq(str(_daemon.summarize_applied({"verdict": "no_change"})),
		"Auto-rebalance: no change needed.", "the no_change line is unchanged")
	assert_eq(str(_daemon.summarize_applied({"verdict": "nudge_easier", "applied_changes": []})),
		"Auto-rebalance: proposed but no changes applied.", "the empty line is unchanged")


func test_the_player_reset_line_is_untouched() -> void:
	## CONTROL: reset entries take their own branch above the changed code.
	var line: String = str(_daemon.summarize_applied({
		"status": "reset", "applied_changes": [{"constant": CONST_NAME}]}))
	assert_true(line.begins_with("Player reset:"), "reset framing survives: %s" % line)


# ── the premise ───────────────────────────────────────────────────────────────

func test_the_cumulative_band_is_what_does_the_clamping() -> void:
	## THE PREMISE. Every fixture above is positioned against these two constants.
	## If the band widens, the ceiling fixture stops being a ceiling and the arms
	## would pass by never being clamped at all.
	assert_lt(RD.CUMULATIVE_DELTA_MAX, 1.10 * RD.CUMULATIVE_DELTA_MAX,
		"CONTROL: trivially true, pins that the constant is readable")
	assert_true(RD.CUMULATIVE_DELTA_MAX < 1.21,
		("the cumulative ceiling widened to %.2f, so 'at the ceiling, +10%% is fully "
		+ "clamped' may no longer hold — re-derive this file's fixtures.")
		% RD.CUMULATIVE_DELTA_MAX)
	assert_true(RD.SAFE_DELTA_MAX >= 1.10,
		("the per-step safe band narrowed to %.2f, so a +10%% delta now goes to review "
		+ "instead of auto-applying and every arm here stops exercising the write path.")
		% RD.SAFE_DELTA_MAX)


func test_the_clamped_flag_still_records_what_the_line_now_says() -> void:
	## The flag was written at both apply sites and read nowhere. It is still the
	## machine-readable form of this line; if it ever disagrees, one of them is
	## wrong and this arm says which.
	var got: Dictionary = _apply_from(1.0 * RD.CUMULATIVE_DELTA_MAX, 1.10)
	var changes: Array = got["changes"] as Array
	assert_eq(changes.size(), 1, "CONTROL: one delta in, one change out")
	assert_true(bool((changes[0] as Dictionary).get("clamped", false)),
		"the clamped flag must agree with the line saying 'safe limit'")


# ── controls ──────────────────────────────────────────────────────────────────

func test_the_apply_path_really_ran() -> void:
	## CONTROL: every arm reads the line off applied[-1]. A proposal that went to
	## review instead of applying would leave a stale entry and the arms would be
	## measuring the wrong proposal — or nothing.
	var got: Dictionary = _apply_from(1.0, 1.10)
	assert_eq(str(got["result"]), RD.APPLY_APPLIED,
		"the fixture must reach the write path, not the review queue")
	assert_eq(_daemon.pending.size(), 0, "and the proposal must have left pending")
	assert_eq(_daemon.applied.size(), 1, "and landed in applied exactly once")
