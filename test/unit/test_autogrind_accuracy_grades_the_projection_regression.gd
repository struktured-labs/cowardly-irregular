extends GutTest

## The Dashboard shows "Accuracy: N%" — it grades its own EXP projection by recording a prediction
## every 5 battles and comparing it five battles later. It compared CUMULATIVE totals:
##
##     predicted = _total_exp + avg_exp_per_battle * 5        <- a running total
##     actual    = _total_exp (five battles later)            <- a running total
##     error     = |actual - predicted| / predicted           <- denominator GROWS all session
##
## ⛔ So the same projection error reports better and better the longer a player grinds. Measured with
## a projection that is over by exactly 20% EVERY time:
##
##     at battle    5    10    15    20    25    30    35    40    45    50
##     shipped     80%   89    92    94    95    96    97    97    97    98%    climbs to ~perfect
##     deltas      80%   80    80    80    80    80    80    80    80    80%    the real error
##
## A number that flatters itself with session length tells the player nothing about the thing it is
## grading. Fixed by comparing the DELTA the projection claimed against the DELTA that happened.
##
## These arms call the Dashboard's OWN `projection_accuracy` rather than driving the whole panel —
## standing the panel up to read a Label would test Godot, not the formula. The formula was extracted
## for exactly this reason: my first draft reimplemented it in the test, which would keep passing if
## the shipped one changed. The cumulative version stays a local copy here because it no longer exists
## in src/ and is what this file exists to keep out.

const BATCH := 5


## The shipped formula and the fixed one, as pure functions, so the divergence is the assertion.
func _cumulative_accuracy(total_at_pred: int, avg: float, actual_total: int) -> float:
	var predicted: int = total_at_pred + int(avg * BATCH)
	var err: float = abs(actual_total - predicted) / max(float(predicted), 1.0) * 100.0
	return max(0.0, 100.0 - err)


## ⛔ Calls the SHIPPED function. My first draft reimplemented the formula here, which means the test
## and the code could drift apart silently — the arms would keep passing on a copy while the dashboard
## computed something else. Only the cumulative form below stays a local copy, because it no longer
## exists in src/ and is what this file exists to keep out.
func _delta_accuracy(total_at_pred: int, avg: float, actual_total: int) -> float:
	var dash = preload("res://src/ui/autogrind/AutogrindDashboard.gd").new()
	add_child_autofree(dash)
	return dash.projection_accuracy(int(avg * BATCH), actual_total - total_at_pred)


## THE ARM THAT WOULD HAVE CAUGHT IT: a CONSTANT projection error must report a CONSTANT accuracy.
func test_a_constant_projection_error_reports_a_constant_accuracy() -> void:
	var avg := 100.0          ## what the dashboard believes a battle yields
	var real := 80.0          ## what a battle actually yields — the projection is 25% over, always
	var total := 0
	var shipped: Array = []
	var deltas: Array = []
	for _i in range(10):
		var at_pred: int = total
		total += int(real * BATCH)
		shipped.append(_cumulative_accuracy(at_pred, avg, total))
		deltas.append(_delta_accuracy(at_pred, avg, total))
	gut.p("  cumulative: %s" % [shipped.map(func(x): return "%.0f" % x)])
	gut.p("  deltas:     %s" % [deltas.map(func(x): return "%.0f" % x)])

	## ⛔ FLAT IS NOT ENOUGH — it must be flat AT THE RIGHT VALUE. Measured: inflating the denominator
	## makes accuracy constantly ~100%, which satisfies "does not drift" perfectly. The mutation scored
	## GREEN on this arm; predicted Failing 3, got 1. avg 100 vs real 80 is a 500-vs-400 delta, so the
	## only correct answer is 80% — pin that, or "constant" is satisfied by "constantly perfect".
	assert_almost_eq(float(deltas[0]), 80.0, 1.0,
		"a projection claiming 500 EXP where 400 arrived must read 80%%, got %.0f%% — the denominator is not the predicted delta" % deltas[0])

	## The delta metric must not move: the error never changed.
	for i in range(1, deltas.size()):
		assert_almost_eq(float(deltas[i]), float(deltas[0]), 0.51,
			"the delta metric drifted from %.0f to %.0f while the projection error stayed identical" % [deltas[0], deltas[i]])
	## CONTROL: the OLD metric must really drift, or this arm is comparing two correct things and
	## proves nothing about the fix.
	assert_gt(float(shipped[-1]) - float(shipped[0]), 10.0,
		"CONTROL: the cumulative metric did not inflate (%.0f -> %.0f), so this scenario cannot tell the two apart" % [shipped[0], shipped[-1]])


## A perfect projection must read 100% under the fixed metric, at any point in a session.
func test_a_perfect_projection_reads_one_hundred() -> void:
	var total := 0
	for _i in range(6):
		var at_pred: int = total
		total += int(100.0 * BATCH)
		assert_almost_eq(_delta_accuracy(at_pred, 100.0, total), 100.0, 0.01,
			"a projection that was exactly right did not read 100%")


## And a badly wrong projection must read low even late in a long session — the case the old metric
## could not express, because by then the denominator dwarfed the error.
func test_a_wrong_projection_reads_low_even_late() -> void:
	var total := 100000     ## deep into a session
	var at_pred: int = total
	total += int(10.0 * BATCH)          ## reality: 10 exp/battle
	var acc: float = _delta_accuracy(at_pred, 200.0, total)   ## claim: 200 exp/battle
	gut.p("  late session, claim 200/battle, reality 10/battle -> %.0f%%" % acc)
	assert_lt(acc, 10.0,
		"a projection 20x too high read %.0f%% — a late-session error must still read low" % acc)
	## The old metric on the same numbers, to show what was being displayed.
	var old: float = _cumulative_accuracy(at_pred, 200.0, total)
	gut.p("  the same case under the OLD metric -> %.0f%%" % old)
	assert_gt(old, 90.0,
		"CONTROL: the old metric should have reported this 20x miss as near-perfect; it gave %.0f%%" % old)


## The shipped code must use the delta arithmetic, not the cumulative form.
func test_the_dashboard_stores_a_delta_and_a_baseline() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindDashboard.gd")
	var code := ""
	for line in src.split("\n"):
		code += line.split("#")[0] + "\n"
	assert_true(code.contains("\"predicted_delta\""),
		"the prediction record stores no delta — accuracy is grading cumulative totals again")
	assert_true(code.contains("\"baseline_exp\""),
		"the prediction record stores no baseline, so the actual delta cannot be computed")
	assert_true(code.contains("_total_exp - int(pred[\"baseline_exp\"])"),
		"the actual side is not a delta from the baseline")
	## ⛔ Ban the cumulative form by its shape, so the defect cannot come back wearing new names.
	assert_false(code.contains("_total_exp + int(avg_exp_per_battle * 5)"),
		"the cumulative predicted total is back — the denominator grows and accuracy inflates with session length")
