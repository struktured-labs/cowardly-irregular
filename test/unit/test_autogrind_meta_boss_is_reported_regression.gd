extends GutTest

## "System fatigue spawns unpredictable meta-bosses" is a design pillar, and a player could grind
## straight past one without ever learning it happened.
##
## Every meta-boss surface was AutogrindUI — the spawn signal, and the victory line in the battle
## result. _close_ui() disconnects all six autogrind signals, and closing the console mid-grind is
## the normal way to watch the overworld while grinding. In HEADLESS mode the fight resolves with no
## BattleScene at all, so there is not even a boss on screen.
##
## Worse than the collapse case, which at least reached the end-of-session Summary via
## collapse_count: meta bosses had NO COUNTER AT ALL, so the Summary could not have reported them.
## Invisible at the moment AND at session end.
##
## Found by censusing the other five signals after fixing system_collapse. Of those five,
## interrupt_triggered turned out FINE — GameLoop's _on_grind_complete plays a stop SFX, shows a
## notification and passes the reason to the Summary, all independent of the console. Reporting
## that negative because the census is only worth what its negatives are worth.

var _ags: Node = null


func before_each() -> void:
	_ags = get_node_or_null("/root/AutogrindSystem")
	if _ags:
		_ags._test_disable_persistence = true
		_ags.meta_bosses_spawned = 0
		_ags.meta_bosses_defeated = 0


func after_each() -> void:
	if _ags:
		_ags.meta_bosses_spawned = 0
		_ags.meta_bosses_defeated = 0


func test_spawning_a_meta_boss_is_counted() -> void:
	assert_eq(_ags.meta_bosses_spawned, 0, "precondition: the counter starts clean")
	var data: Dictionary = _ags._spawn_meta_boss()
	assert_false(data.is_empty(), "precondition: a boss was actually built")
	assert_eq(_ags.meta_bosses_spawned, 1,
		"a spawn must be counted — with no counter the Summary cannot report what the console missed")


func test_defeating_one_is_counted_separately() -> void:
	## Met and beaten are different facts: a player who ran from three and beat none should not
	## read the same as one who beat three.
	_ags._spawn_meta_boss()
	_ags.on_meta_boss_victory({"name": "Probe Boss"})
	assert_eq(_ags.meta_bosses_spawned, 1, "one met")
	assert_eq(_ags.meta_bosses_defeated, 1, "one beaten")

	_ags._spawn_meta_boss()
	assert_eq(_ags.meta_bosses_spawned, 2, "two met")
	assert_eq(_ags.meta_bosses_defeated, 1, "still one beaten — the counts must not move together")


func test_the_counters_ride_the_stats_dict_the_summary_reads() -> void:
	## The wiring, not just the counter. The Summary reads _stats; if the controller does not carry
	## the keys, a correct counter still reports nothing — which is the whole defect one layer up.
	var ctrl = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(ctrl)
	_ags._spawn_meta_boss()
	var stats: Dictionary = ctrl.get_grind_stats()
	assert_true(stats.has("meta_bosses_spawned"),
		"get_grind_stats must carry the spawn count to the Summary: %s" % str(stats.keys()))
	assert_true(stats.has("meta_bosses_defeated"), "and the defeat count")
	assert_eq(int(stats["meta_bosses_spawned"]), 1, "and carry the real value, not a placeholder")


func test_the_summary_renders_a_meta_boss_row() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindSummary.gd")
	assert_ne(src, "", "control: the summary source must be readable or this assertion is vacuous")
	assert_true(src.contains("meta_bosses_defeated") and src.contains("meta_bosses_spawned"),
		"the Summary must read both counters — it is the surface that always runs, unlike the console")


func test_starting_a_new_session_clears_them() -> void:
	## Session-scoped like collapse_count — a stale count would report last session's bosses as
	## this session's. Driven through start_autogrind, which is where the reset actually lives.
	## (My first version hedged on a reset_session_state() that does not exist and took a
	## pass_test branch — an arm that asserts nothing is worse than no arm.)
	_ags._spawn_meta_boss()
	_ags.on_meta_boss_victory({"name": "Probe Boss"})
	assert_gt(_ags.meta_bosses_spawned, 0, "precondition: counts exist before the new session")

	var party: Array[Combatant] = []
	var c := Combatant.new()
	c.initialize({"name": "Reset Probe", "max_hp": 500, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	party.append(c)
	_ags.is_grinding = false
	var started: bool = _ags.start_autogrind(party, {}, {})
	assert_true(started, "precondition: the new session actually started, or nothing was reset")

	assert_eq(_ags.meta_bosses_spawned, 0, "a new session starts from zero")
	assert_eq(_ags.meta_bosses_defeated, 0, "both counters")
	_ags.is_grinding = false
