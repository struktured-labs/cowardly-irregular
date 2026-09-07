extends GutTest

## Joins the session-GRADE thresholds to the escalation CURVE that decides whether they can
## ever be met. Two authored corpora, in two files, with nothing connecting them:
##
##   AutogrindSummary._compute_grade()   S = 50 battles AND 0 collapses
##                                       A = 30 battles AND <= 1 collapse
##   AutogrindSystem._increase_efficiency()  corruption += 0.02 * efficiency, collapse at
##                                       corruption >= corruption_threshold
##
## Measured 2026-08-06: the first collapse lands around battle 60-75, so S is reachable with
## roughly ten battles of margin. Nothing pins that. Retune corruption_threshold, the 0.02
## rate, efficiency_growth_rate or max_efficiency and the first collapse can move below 50 —
## at which point the S grade becomes UNREACHABLE and every other test still passes, because
## the grader is correct, the curve is correct, and only their relationship is broken.
##
## This drives BOTH real systems rather than re-encoding either: the escalation runs through
## AutogrindSystem.on_battle_victory, and the resulting stats go to the real
## AutogrindSummary._compute_grade. The thresholds are never copied here.
##
## Emulates the Controller's collapse round-trip (AutogrindController:397 calls
## apply_post_collapse_penalty after the collapse-boss battle) — without it corruption never
## resets and collapse re-fires every battle, which is a property of the harness, not the game.
##
## This is a REACHABILITY guard, not a balance opinion. If struktured retunes the curve and S
## legitimately moves, this reds and names what happened — it does not assert what the numbers
## should be.

const SummaryScript = preload("res://src/ui/autogrind/AutogrindSummary.gd")
const REGION: String = "grade_reachability_region"
const HARD_CAP: int = 600

var _saved: Dictionary = {}

const _FIELDS: Array[String] = [
	"battles_completed", "consecutive_wins", "battles_without_heal", "total_exp_gained",
	"efficiency_multiplier", "max_efficiency", "monster_adaptation_level",
	"meta_corruption_level", "corruption_threshold", "collapse_count",
	"post_collapse_debuff_battles", "meta_boss_spawn_chance", "current_region_id", "is_grinding",
]
const _DICTS: Array[String] = ["region_crack_levels", "_region_csi", "_csi_timestamps", "_grind_stats"]


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	for f in _FIELDS:
		_saved[f] = AutogrindSystem.get(f)
	for d in _DICTS:
		var v = AutogrindSystem.get(d)
		_saved[d] = v.duplicate(true) if v is Dictionary else v
	_saved["party"] = AutogrindSystem.grind_party.duplicate()

	AutogrindSystem.grind_party.clear()
	AutogrindSystem.battles_completed = 0
	AutogrindSystem.consecutive_wins = 0
	AutogrindSystem.efficiency_multiplier = 1.0
	AutogrindSystem.max_efficiency = 10.0
	AutogrindSystem.monster_adaptation_level = 0.0
	AutogrindSystem.meta_corruption_level = 0.0
	AutogrindSystem.corruption_threshold = 5.0
	AutogrindSystem.collapse_count = 0
	AutogrindSystem.post_collapse_debuff_battles = 0
	AutogrindSystem.region_crack_levels = {}
	AutogrindSystem._region_csi = {}
	AutogrindSystem.current_region_id = REGION


func after_each() -> void:
	for f in _FIELDS:
		AutogrindSystem.set(f, _saved[f])
	for d in _DICTS:
		AutogrindSystem.set(d, _saved[d])
	AutogrindSystem.grind_party.assign(_saved["party"])
	_saved.clear()


func _grader() -> Node:
	var s: Node = SummaryScript.new()
	add_child_autofree(s)
	return s


## Grades a hypothetical session through the REAL grader.
func _grade_for(battles: int, collapses: int) -> String:
	var s := _grader()
	s._stats = {"battles_won": battles, "collapse_count": collapses}
	return str(s._compute_grade()["letter"])


## Drives the real escalation and returns the battle number the FIRST collapse landed on.
func _battle_of_first_collapse() -> int:
	for b in range(1, HARD_CAP + 1):
		var before: int = AutogrindSystem.collapse_count
		AutogrindSystem.on_battle_victory(100)
		if AutogrindSystem.collapse_count > before:
			AutogrindSystem.apply_post_collapse_penalty()
			return b
	return -1


func test_the_S_grade_is_reachable_on_the_real_curve() -> void:
	var first: int = _battle_of_first_collapse()
	assert_gt(first, 0,
		"no collapse occurred within %d battles — the curve changed shape and this guard's premise is gone" % HARD_CAP)

	# The best a collapse-free player can do is every battle up to the one before the first.
	var best_clean_run: int = first - 1
	var grade: String = _grade_for(best_clean_run, 0)

	assert_eq(grade, "S",
		"the S grade is UNREACHABLE on the current escalation curve: the first collapse lands on battle %d, so the longest collapse-free session is %d battles, which the real grader scores '%s'. S needs 50 battles at 0 collapses. Nothing else fails when this breaks — the grader is fine, the curve is fine, only their relationship is broken." % [first, best_clean_run, grade])


func test_the_A_grade_is_reachable_on_the_real_curve() -> void:
	# A allows one collapse, so it is reachable strictly more easily than S — but only if the
	# battle floor (30) is still met before a SECOND collapse arrives.
	var first: int = _battle_of_first_collapse()
	assert_gt(first, 0, "premise: a collapse must occur for this to mean anything")

	var second_gap: int = 0
	for b in range(1, HARD_CAP + 1):
		var before: int = AutogrindSystem.collapse_count
		AutogrindSystem.on_battle_victory(100)
		second_gap += 1
		if AutogrindSystem.collapse_count > before:
			AutogrindSystem.apply_post_collapse_penalty()
			break

	var battles_at_one_collapse: int = first + second_gap - 1
	assert_eq(_grade_for(battles_at_one_collapse, 1), "A",
		"the A grade is unreachable: with one collapse a player reaches battle %d before the second, which the real grader scores '%s' rather than 'A'" % [battles_at_one_collapse, _grade_for(battles_at_one_collapse, 1)])


func test_the_grader_still_discriminates() -> void:
	# Control. Without it every assertion above passes on a grader that returns "S" always.
	assert_eq(_grade_for(0, 0), "F", "control: a session with no battles must grade F")
	assert_eq(_grade_for(1, 0), "C", "control: one battle must grade C")
	assert_eq(_grade_for(15, 0), "B", "control: 15 battles must grade B")
	assert_ne(_grade_for(50, 5), "S", "control: many collapses must NOT grade S")


func test_the_curve_actually_ran() -> void:
	# Control on the other half: the reachability tests are vacuous if the escalation never
	# moved and the collapse came from leftover state.
	var start: int = AutogrindSystem.battles_completed
	var first: int = _battle_of_first_collapse()
	assert_gt(AutogrindSystem.battles_completed, start,
		"no battles were driven — on_battle_victory did not register")
	assert_gt(AutogrindSystem.monster_adaptation_level, 0.0,
		"adaptation never moved, so the escalation path was not exercised")
	assert_lt(first, HARD_CAP,
		"the first collapse needed the full cap, which means the curve is far flatter than measured and the margins here are meaningless")
