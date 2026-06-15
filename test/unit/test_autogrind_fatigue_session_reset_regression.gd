extends GutTest

## Regression: AutogrindSystem.start_autogrind() must reset
## `fatigue_events_triggered` so the lifetime counter doesn't leak
## across grind sessions.
##
## Bug shape:
##   • fatigue_events_triggered is a session-scoped counter — the
##     AutogrindSummary panel labels it "Fatigue Events" in the
##     per-session stats panel.
##   • check_fatigue_collapse gates system collapse on
##     `battles_completed >= 50 AND fatigue_events_triggered >= 5`,
##     both implicitly session-scoped (battles_completed IS reset in
##     start_autogrind alongside total_exp_gained etc.).
##   • But fatigue_events_triggered was NOT reset in start_autogrind.
##   • It's persisted to disk via the save block at line ~2017 and
##     restored at ~2078, so a lifetime tally accumulated across all
##     prior sessions.
##   • Result: a fresh grind that crosses battle 50 could trigger
##     fatigue collapse on the very first fatigue check, because the
##     lifetime tally had already crossed 5 months ago — no new
##     in-session fatigue events required. The collapse mechanic
##     intended to punish a stressed-this-session player instead
##     fired against players who'd merely grinded before.
##
## Fix: zero fatigue_events_triggered in start_autogrind alongside the
## other session-scoped counters that already get reset there.
##
## Tests:
##   • Source pin that start_autogrind resets fatigue_events_triggered
##   • Behavioural: pre-seed a nonzero count, call start_autogrind,
##     assert the counter is 0
##   • Existing already-grinding early-return doesn't clobber the
##     counter (preserves the pre-fix invariant for that case)

const AUTOGRIND_SYSTEM_PATH := "res://src/autogrind/AutogrindSystem.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pin ────────────────────────────────────────────────────────────────

func test_start_autogrind_resets_fatigue_events_triggered() -> void:
	var text := _read(AUTOGRIND_SYSTEM_PATH)
	var idx := text.find("func start_autogrind")
	assert_gt(idx, -1, "start_autogrind must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("fatigue_events_triggered = 0"),
		"start_autogrind must reset fatigue_events_triggered to 0 (session-scoped counter)")


# ── Behavioural ──────────────────────────────────────────────────────────────

func test_starting_a_grind_clears_lifetime_fatigue_carryover() -> void:
	# Snapshot the live autoload state so we can restore after — this
	# test mutates is_grinding and several counters.
	var prior_is_grinding: bool = AutogrindSystem.is_grinding
	var prior_fatigue: int = AutogrindSystem.fatigue_events_triggered
	var prior_battles: int = AutogrindSystem.battles_completed
	# Pre-seed: pretend a prior session left lifetime fatigue at 7.
	AutogrindSystem.is_grinding = false
	AutogrindSystem.fatigue_events_triggered = 7
	# Empty party is enough — start_autogrind doesn't validate further than that.
	var empty_party: Array[Combatant] = []
	AutogrindSystem.start_autogrind(empty_party, {}, {})
	assert_eq(int(AutogrindSystem.fatigue_events_triggered), 0,
		"start_autogrind must zero fatigue_events_triggered so the new session starts clean")
	# Cleanup — restore prior state so downstream tests see normal autoload.
	AutogrindSystem.is_grinding = prior_is_grinding
	AutogrindSystem.fatigue_events_triggered = prior_fatigue
	AutogrindSystem.battles_completed = prior_battles


func test_already_grinding_early_return_does_not_clobber_counter() -> void:
	# Defensive invariant: if start_autogrind is called while
	# is_grinding == true, it returns early and must NOT touch the
	# counter (which might be the live in-session value).
	var prior_is_grinding: bool = AutogrindSystem.is_grinding
	var prior_fatigue: int = AutogrindSystem.fatigue_events_triggered
	AutogrindSystem.is_grinding = true
	AutogrindSystem.fatigue_events_triggered = 3
	var empty_party: Array[Combatant] = []
	AutogrindSystem.start_autogrind(empty_party, {}, {})
	assert_eq(int(AutogrindSystem.fatigue_events_triggered), 3,
		"already-grinding early-return must NOT clobber the live counter")
	# Cleanup.
	AutogrindSystem.is_grinding = prior_is_grinding
	AutogrindSystem.fatigue_events_triggered = prior_fatigue
