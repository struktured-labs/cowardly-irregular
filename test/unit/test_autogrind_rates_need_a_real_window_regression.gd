extends GutTest

## Every per-minute rate the grind shows — EXP/min, Gold/min, JP/min, Enc/min, Battles/min — is
## `total / minutes`, and `minutes` was floored at **0.0001**, which is SIX MILLISECONDS. Enough to
## avoid a division by zero and nothing else: a rate reported per MINUTE was extrapolated from a
## window up to 10,000x shorter than the one it named.
##
##     elapsed   total_exp   displayed EXP/min
##     0.005s    120         1200000
##     0.050s    120          144000
##     0.500s    500           60000
##     60.000s   3000            3000     <- the honest figure
##
## ⛔ REACHABLE, not theoretical: LUDICROUS mode resolves battles by math, so a real EXP total lands
## sub-second and the Monitor is on screen while it does.
##
## Floored at one second now, and the floor is ONE CONSTANT. Three divisors carried three different
## values for the same computation — 0.0001 in AutogrindSystem, 0.01 in the Dashboard and the Summary.
## A floor is a claim about when a rate becomes meaningful, and three claims about one thing drift.

var _sys


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_sys = AutogrindSystem


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false


## THE ARM THAT WOULD HAVE CAUGHT IT: a rate may not be extrapolated from a window this short.
func test_a_rate_is_not_extrapolated_from_milliseconds() -> void:
	var floor_min: float = _sys.MIN_RATE_WINDOW_MINUTES
	gut.p("  MIN_RATE_WINDOW_MINUTES = %.6f min (%.3f s)" % [floor_min, floor_min * 60.0])
	assert_gte(floor_min * 60.0, 1.0,
		"the rate window floor is %.4f s — a per-MINUTE figure extrapolated from that is noise, and 120 EXP at 5 ms read 1,200,000 EXP/min" % (floor_min * 60.0))
	## And it must not go the other way either: a floor of a whole minute would suppress real rates
	## for the first minute of every session.
	assert_lte(floor_min * 60.0, 10.0,
		"the floor is %.1f s, long enough to flatten genuine early-session rates" % (floor_min * 60.0))


## The inflation cap, stated as the property rather than as one example: dividing by the floor can
## exaggerate a total by at most 60x, not 10,000x.
func test_the_inflation_cap_is_sixty_not_ten_thousand() -> void:
	var cap: float = 1.0 / _sys.MIN_RATE_WINDOW_MINUTES
	gut.p("  worst-case exaggeration factor: %.0fx" % cap)
	assert_lte(cap, 60.0,
		"a total can still be exaggerated %.0fx by the rate divisor" % cap)


## ⛔ ONE floor, not three. Each of the three divisors must read the shared constant — a second copy
## is how they came to disagree in the first place.
func test_every_per_minute_divisor_reads_the_shared_floor() -> void:
	var files := {
		"AutogrindSystem": "res://src/autogrind/AutogrindSystem.gd",
		"AutogrindDashboard": "res://src/ui/autogrind/AutogrindDashboard.gd",
		"AutogrindSummary": "res://src/ui/autogrind/AutogrindSummary.gd",
	}
	var problems: Array = []
	for name in files.keys():
		var raw: String = FileAccess.get_file_as_string(files[name])
		assert_ne(raw, "", "CONTROL: %s must be readable or this arm is vacuous" % name)
		var code := ""
		for line in raw.split("\n"):
			code += line.split("#")[0] + "\n"
		if not code.contains("MIN_RATE_WINDOW_MINUTES"):
			problems.append("%s divides by 60 without the shared floor" % name)
		## The old magic values, banned by shape so they cannot come back under a new name.
		for stale in ["/ 60.0, 0.0001", "/ 60.0, 0.01"]:
			if code.contains(stale):
				problems.append("%s still carries a local floor `%s`" % [name, stale])
	assert_eq(problems, [],
		"a per-minute divisor has its own floor again — three divisors with three floors is what produced a 6 ms window: %s" % [problems])


## The rate itself, through the real function: a short session must not report a six-figure rate.
func test_get_grind_stats_reports_a_sane_rate_for_a_short_session() -> void:
	_sys._grind_stats["total_exp"] = 120
	_sys._grind_stats["total_gold"] = 60
	_sys._grind_stats["total_jp"] = 30
	_sys._grind_stats["total_encounters"] = 4
	_sys._grind_stats["elapsed_seconds"] = 0.005
	_sys._grind_stats["start_time"] = 0.0
	var was_grinding: bool = _sys.is_grinding
	_sys.is_grinding = false      ## so elapsed comes from the recorded value, not the wall clock
	var stats: Dictionary = _sys.get_grind_stats()
	_sys.is_grinding = was_grinding
	gut.p("  120 EXP at 5 ms -> EXP/min %.0f" % float(stats["exp_per_min"]))
	assert_lte(float(stats["exp_per_min"]), 120.0 * 60.0,
		"120 EXP over 5 ms reported %.0f EXP/min — the divisor floor is not holding" % stats["exp_per_min"])
	## CONTROL: the rate must still be NON-ZERO, or a floor could pass this by suppressing the metric.
	assert_gt(float(stats["exp_per_min"]), 0.0,
		"the rate collapsed to zero — the floor must bound the number, not erase it")


## A long session is untouched: the floor only ever binds below one second.
func test_a_long_session_is_unaffected_by_the_floor() -> void:
	_sys._grind_stats["total_exp"] = 3000
	_sys._grind_stats["elapsed_seconds"] = 60.0
	_sys._grind_stats["start_time"] = 0.0
	var was_grinding: bool = _sys.is_grinding
	_sys.is_grinding = false
	var stats: Dictionary = _sys.get_grind_stats()
	_sys.is_grinding = was_grinding
	assert_almost_eq(float(stats["exp_per_min"]), 3000.0, 1.0,
		"3000 EXP over 60 s must read 3000 EXP/min, got %.1f — the floor is binding when it should not" % stats["exp_per_min"])
