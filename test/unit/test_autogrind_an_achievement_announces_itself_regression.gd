extends GutTest

const GdSource = preload("res://test/unit/helpers/gd_source.gd")

## Autogrind achievements were awarded in exactly one place: inside AutogrindSummary._build_ui().
## Persistence was therefore a side effect of RENDERING A SCREEN — a player crossing 100 battles
## in a three-hour session was told nothing until the session ended, and a summary that never
## built (GameLoop:6225 early-returns when one is already up) banked nothing at all.
## The award now runs per battle in AutogrindController.award_pending_achievements().
##
## That move breaks the old "new" test by construction: the summary decided a badge was NEW by
## asking whether its flag was unset, and the per-battle award sets every flag before the summary
## exists. Every badge would render dim. split_session_new() is the replacement and the arms below
## pin both directions of it — a dim-only summary is the regression this fix could have shipped.

const ControllerScript = preload("res://src/autogrind/AutogrindController.gd")
const SummaryScript = preload("res://src/ui/autogrind/AutogrindSummary.gd")
const AchievementsScript = preload("res://src/autogrind/AutogrindAchievements.gd")

const FIRST_GRIND := "achievement_autogrind_first_grind"

## Session fields this file mutates; restored verbatim in after_each.
const TOUCHED := [
	"battles_completed", "total_exp_gained", "battles_without_heal",
	"collapse_count", "achievements_earned_this_session", "is_grinding",
]

var _ctrl
var _saved: Dictionary = {}


class FakeGameState extends RefCounted:
	var story_flags: Dictionary = {}

	func is_story_flag_set(flag: String) -> bool:
		return story_flags.get(flag, false)

	func set_story_flag(flag: String, value: bool) -> void:
		story_flags[flag] = value


func before_each() -> void:
	AchievementsScript._reset_cache_for_test()
	AutogrindSystem._test_disable_persistence = true
	for f in TOUCHED:
		_saved[f] = AutogrindSystem.get(f)
	AutogrindSystem.battles_completed = 0
	AutogrindSystem.total_exp_gained = 0
	AutogrindSystem.battles_without_heal = 0
	AutogrindSystem.collapse_count = 0
	AutogrindSystem.achievements_earned_this_session = []
	_ctrl = ControllerScript.new()
	add_child_autofree(_ctrl)


func after_each() -> void:
	for f in _saved:
		AutogrindSystem.set(f, _saved[f])
	_saved.clear()


# ── The award no longer needs a screen ───────────────────────────────────────

func test_an_achievement_is_awarded_with_no_summary_screen_in_existence() -> void:
	# Nothing in this test instantiates AutogrindSummary. That is the point.
	var gs := FakeGameState.new()
	AutogrindSystem.battles_completed = 1
	var newly: Array = _ctrl.award_pending_achievements(gs)
	assert_eq(newly.size(), 1,
		"one battle must earn exactly first_grind (threshold 1); got %d" % newly.size())
	assert_eq(str(newly[0].get("id", "")), FIRST_GRIND,
		"the earned achievement must be first_grind")
	assert_true(gs.is_story_flag_set(FIRST_GRIND),
		"the flag must be PERSISTED by the per-battle award, with no summary anywhere — that coupling was the bug")


func test_no_battles_earns_nothing() -> void:
	# Control: the arm above must be able to report zero, or it proves nothing.
	var gs := FakeGameState.new()
	AutogrindSystem.battles_completed = 0
	assert_eq(_ctrl.award_pending_achievements(gs).size(), 0,
		"control: a grind with no battles won must earn no achievement")
	assert_false(gs.is_story_flag_set(FIRST_GRIND),
		"control: no flag may be written when nothing was earned")


func test_the_awarded_id_lands_in_the_session_ledger() -> void:
	var gs := FakeGameState.new()
	AutogrindSystem.battles_completed = 1
	_ctrl.award_pending_achievements(gs)
	assert_true(AutogrindSystem.achievements_earned_this_session.has(FIRST_GRIND),
		"the id must be recorded as earned THIS session — the summary's gold tier reads this list")


func test_the_ledger_reaches_the_stats_dict() -> void:
	# The summary never sees AutogrindSystem; it only sees the stats dict GameLoop hands it.
	AutogrindSystem.achievements_earned_this_session = [FIRST_GRIND]
	var stats: Dictionary = _ctrl.get_grind_stats()
	assert_true(stats.has("achievements_earned_this_session"),
		"get_grind_stats() must emit the ledger or the summary cannot tell new from old")
	assert_true((stats["achievements_earned_this_session"] as Array).has(FIRST_GRIND),
		"the emitted ledger must carry the id, not an empty array")


func test_the_ledger_in_the_stats_dict_is_a_copy() -> void:
	# A live alias would let the summary's own bookkeeping mutate session state.
	AutogrindSystem.achievements_earned_this_session = [FIRST_GRIND]
	var stats: Dictionary = _ctrl.get_grind_stats()
	(stats["achievements_earned_this_session"] as Array).append("zzz_injected")
	assert_false(AutogrindSystem.achievements_earned_this_session.has("zzz_injected"),
		"the emitted ledger must be a duplicate, not an alias of the session array")


func test_the_same_achievement_is_not_announced_twice() -> void:
	# Every battle calls this. Without idempotence the toast fires on every battle forever.
	var gs := FakeGameState.new()
	AutogrindSystem.battles_completed = 1
	assert_eq(_ctrl.award_pending_achievements(gs).size(), 1,
		"the first crossing must announce")
	AutogrindSystem.battles_completed = 2
	assert_eq(_ctrl.award_pending_achievements(gs).size(), 0,
		"a later battle must NOT re-announce an achievement already earned")
	assert_eq(AutogrindSystem.achievements_earned_this_session.size(), 1,
		"the ledger must not accumulate duplicates of one id")


func test_a_fresh_grind_clears_the_ledger() -> void:
	# Without this, last session's badges render gold in the next session's summary.
	var prior_grinding: bool = AutogrindSystem.is_grinding
	AutogrindSystem.achievements_earned_this_session = [FIRST_GRIND]
	AutogrindSystem.is_grinding = false
	var member := Combatant.new()
	member.initialize({"name": "T", "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 5, "magic": 5, "speed": 10})
	add_child_autofree(member)
	var party: Array[Combatant] = [member]
	AutogrindSystem.start_autogrind(party, {}, {})
	assert_eq(AutogrindSystem.achievements_earned_this_session.size(), 0,
		"start_autogrind must clear the ledger — it is session-scoped, like collapse_count beside it")
	AutogrindSystem.is_grinding = prior_grinding


# ── The summary's gold tier, both directions ─────────────────────────────────

func test_the_summary_calls_a_pre_awarded_achievement_new() -> void:
	# THE regression this fix could have shipped: the per-battle award sets the flag, so by the
	# time the summary builds, check_and_award reports it as "already earned" and it renders dim.
	var badge := {"id": FIRST_GRIND, "name": "First Grind", "icon": "*"}
	var split := [[], [badge]]  # awarded-now EMPTY, flag already set — exactly the new world
	var tiers: Array = SummaryScript.split_session_new(split, [FIRST_GRIND])
	assert_eq((tiers[0] as Array).size(), 1,
		"an achievement earned earlier in THIS session must still render as new, not dim")
	assert_eq((tiers[1] as Array).size(), 0,
		"it must not also appear in the already-earned tier")


func test_an_older_sessions_achievement_still_renders_dim() -> void:
	# Opposite direction — without this, "everything is new" would pass the arm above.
	var badge := {"id": FIRST_GRIND, "name": "First Grind", "icon": "*"}
	var tiers: Array = SummaryScript.split_session_new([[], [badge]], [])
	assert_eq((tiers[0] as Array).size(), 0,
		"an achievement earned in an EARLIER session must not render as new")
	assert_eq((tiers[1] as Array).size(), 1,
		"it belongs in the already-earned tier")


func test_an_achievement_awarded_at_the_summary_is_still_new() -> void:
	# The backstop path: a threshold crossed on the final battle arrives in split[0].
	var badge := {"id": FIRST_GRIND, "name": "First Grind", "icon": "*"}
	var tiers: Array = SummaryScript.split_session_new([[badge], []], [])
	assert_eq((tiers[0] as Array).size(), 1,
		"an achievement awarded by the summary's own backstop call must render as new")


func test_every_badge_survives_the_split() -> void:
	# Losing one to neither tier drops it off the screen silently.
	var a := {"id": "a", "name": "A", "icon": "*"}
	var b := {"id": "b", "name": "B", "icon": "*"}
	var c := {"id": "c", "name": "C", "icon": "*"}
	var tiers: Array = SummaryScript.split_session_new([[a], [b, c]], ["b"])
	assert_eq((tiers[0] as Array).size() + (tiers[1] as Array).size(), 3,
		"every input badge must land in exactly one tier")


# ── GameLoop announces what it awards ────────────────────────────────────────

func test_the_battle_hook_announces_what_it_awards() -> void:
	# GameLoop is the MAIN SCENE, not an autoload — absent from the tree under GUT, so this
	# reads the source. Located by the CALL, not by a line number.
	var code := _code_only("res://src/GameLoop.gd", "award_pending_achievements(")
	var at := code.find("award_pending_achievements(")
	assert_gt(at, -1, "control: the per-battle award call must be findable in GameLoop")
	var window := code.substr(at, 600)
	assert_true(window.contains("_show_autogrind_toast("),
		"an achievement earned mid-grind must reach the player as a toast — awarding silently is the bug this fixes")
	assert_true(window.contains("_autogrind_battle_summaries.append("),
		"it must also land in the console ring buffer, like every other autogrind event")


func test_the_award_call_sits_inside_the_battle_ended_hook() -> void:
	# Reachability: a call in a function nothing invokes per battle announces nothing.
	var code := _code_only("res://src/GameLoop.gd", "func _on_autogrind_battle_ended")
	var hook := code.find("func _on_autogrind_battle_ended")
	assert_gt(hook, -1, "control: the battle-ended hook must be findable")
	var next_func := code.find("\nfunc ", hook + 10)
	assert_gt(next_func, hook, "control: the hook must have an end")
	var body := code.substr(hook, next_func - hook)
	assert_true(body.contains("award_pending_achievements("),
		"the award must run from the per-battle hook, or it is back to firing once at the summary")


# ── helpers ──────────────────────────────────────────────────────────────────

func _read(path: String) -> String:
	var src := FileAccess.get_file_as_string(path)
	assert_gt(src.length(), 0, "control: %s must be readable" % path)
	return src


## must_survive is REQUIRED, not optional — no call site can skip the positive control.
## Order matters: '#' lines go first (line-addressable, stateless), THEN the docstring parity
## split. Splitting first lets a '"""' inside a comment flip parity and eat real code.
func _code_only(path: String, must_survive: String) -> String:
	## PATH-taking by construction: a literal source string cannot reach this wrapper, which is what
	## makes the blank-control floor below safe (cowir-sprites' rule, 2026-09-12). A source-taking
	## wrapper must NOT floor — it would red on correct literal-input self-test rows.
	assert_gt(must_survive.length(), 0,
		"CONTROL: must_survive must name a real code site — an empty control asserts nothing")
	var raw: String = FileAccess.get_file_as_string(path)
	assert_gt(raw.length(), 0, "CONTROL: %s must be readable" % path)
	var stripped: String = str(GdSource.split(raw)["code"])
	assert_true(stripped.contains(must_survive),
		"CONTROL: the stripper removed load-bearing code (%s) — every arm below it is vacuous" % must_survive)
	return stripped
