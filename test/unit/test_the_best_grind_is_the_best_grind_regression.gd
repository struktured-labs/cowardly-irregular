extends GutTest
## The Records page ranked "Best Grind" by exp_per_min. That rate divides by a duration which can be
## a fraction of a second, so it grows without bound as a session gets SHORTER -- and
## MIN_RATE_WINDOW_MINUTES floors the divisor at one second, far too small to make two sessions of
## different lengths comparable.
##
## Measured on struktured's own autogrind_history.json (10 entries, read-only):
##   ranked by exp_per_min   ->  2 battles ·  1.12s ·   913 EXP   (48,737/min)   <- shown as "best"
##   ranked by total_exp     -> 15 battles ·  9.32s ·  5539 EXP   (35,677/min)
## His best grind displayed as a session that fought twice and earned a sixth as much.
## Four of his ten entries fought NOTHING -- aborted starts, which are not grinds.
const RecordsMenuScript = preload("res://src/ui/RecordsMenu.gd")
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindState.restore(_ag)


func _menu() -> Node:
	var m: Node = RecordsMenuScript.new()
	add_child_autofree(m)
	return m


## The shape of his history: a sprint, a real session, and aborted starts.
func _history() -> Array:
	return [
		{"battles": 0, "total_exp": 0, "exp_per_min": 0.0, "duration_sec": 0.0001, "reason": "Manual stop"},
		{"battles": 2, "total_exp": 913, "exp_per_min": 48737.4, "duration_sec": 1.124, "reason": "HP threshold reached (20%)"},
		{"battles": 15, "total_exp": 5539, "exp_per_min": 35676.8, "duration_sec": 9.315, "reason": "HP threshold reached (20%)"},
		{"battles": 0, "total_exp": 0, "exp_per_min": 0.0, "duration_sec": 0.0003, "reason": "Manual stop"},
	]


func test_the_longer_grind_wins_over_a_faster_sprint() -> void:
	AutogrindSystem.session_history = _history()
	var h: Dictionary = _menu()._grind_highlights()
	var best: Dictionary = h["best"]
	assert_false(best.is_empty(), "FLOOR: a session with battles must be selectable")
	assert_eq(int(float(best.get("battles", 0))), 15,
		"the 15-battle session earned 5539 EXP and must outrank a 2-battle sprint that earned 913")
	assert_eq(int(float(best.get("total_exp", 0))), 5539, "and it is the one with the most EXP")


## CONTROL: the sprint really does win on the OLD metric, or this fixture proves nothing.
func test_the_sprint_would_have_won_on_the_rate() -> void:
	var by_rate: Dictionary = {}
	for e in _history():
		if by_rate.is_empty() or float(e["exp_per_min"]) > float(by_rate.get("exp_per_min", 0.0)):
			by_rate = e
	assert_eq(int(float(by_rate["battles"])), 2,
		"CONTROL: ranked by rate the 1.12s sprint wins -- that is the defect this fixture reproduces")


## A session that fought nothing is an aborted start, not a grind.
func test_a_session_that_fought_nothing_is_never_the_best() -> void:
	AutogrindSystem.session_history = [
		{"battles": 0, "total_exp": 0, "exp_per_min": 0.0, "duration_sec": 0.0001, "reason": "Manual stop"},
		{"battles": 0, "total_exp": 0, "exp_per_min": 0.0, "duration_sec": 0.0002, "reason": "Manual stop"},
	]
	var h: Dictionary = _menu()._grind_highlights()
	assert_true((h["best"] as Dictionary).is_empty(),
		"with nothing but aborted starts there is no best grind, and the page says so")


## CONTROL: a single real session is still selected -- the filter must not empty the pool.
func test_one_real_session_is_still_the_best() -> void:
	AutogrindSystem.session_history = [
		{"battles": 0, "total_exp": 0, "exp_per_min": 0.0, "duration_sec": 0.0001, "reason": "Manual stop"},
		{"battles": 3, "total_exp": 120, "exp_per_min": 900.0, "duration_sec": 8.0, "reason": "Max battles reached (3)"},
	]
	var best: Dictionary = _menu()._grind_highlights()["best"]
	assert_eq(int(float(best.get("battles", 0))), 3, "CONTROL: the one real session must be chosen")


## Time Automated counts EVERY session, aborted or not -- that is time the player left it running.
func test_time_automated_still_counts_every_session() -> void:
	AutogrindSystem.session_history = _history()
	var total: float = float(_menu()._grind_highlights()["total_sec"])
	assert_almost_eq(total, 10.4394, 0.01,
		"the duration row sums all four entries, including the aborted starts")
