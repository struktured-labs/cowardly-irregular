extends GutTest

## I added meta_bosses_spawned / meta_bosses_defeated last night, wired them through the stats dict
## to the session Summary, and did not add them to the grind SNAPSHOT.
##
## Their two closest siblings — collapse_count and fatigue_events_triggered — ARE snapshotted, and
## both are session tallies the Summary renders. So a player who paused and resumed got:
##
##   Collapses      2     survived the pause
##   Fatigue Events 7     survived the pause
##   Meta-Bosses    0 beaten / 0 met      <- reset, silently, next to two that did not
##
## Worse than a missing number: it is a WRONG number sitting beside correct ones, so nothing about
## the display suggests it is untrustworthy. Found by following my own change into a subsystem I had
## not touched, rather than by anyone hitting it.

var _ags: Node = null


func before_each() -> void:
	_ags = get_node_or_null("/root/AutogrindSystem")
	if _ags:
		_ags._test_disable_persistence = true
		_ags.meta_bosses_spawned = 0
		_ags.meta_bosses_defeated = 0
		_ags.collapse_count = 0


func after_each() -> void:
	if _ags:
		_ags.meta_bosses_spawned = 0
		_ags.meta_bosses_defeated = 0
		_ags.collapse_count = 0


func test_the_counters_survive_a_snapshot_round_trip() -> void:
	_ags.meta_bosses_spawned = 3
	_ags.meta_bosses_defeated = 2
	_ags.collapse_count = 1

	## The REAL writer. My first version hedged on has_method() and hand-built this dict when the
	## method was absent — which it was — so the "round trip" exercised the restorer against a
	## fixture I wrote myself and proved nothing about saving. Extracted the block instead of
	## enabling persistence, because _test_disable_persistence guards real player data.
	var snap: Dictionary = _ags.build_snapshot_system_block()
	assert_true(snap.has("collapse_count"),
		"precondition: this is the real system block, not a hand-built stand-in")
	_ags.meta_bosses_spawned = 0
	_ags.meta_bosses_defeated = 0
	_ags.collapse_count = 0

	_ags.restore_system_from_snapshot(snap)
	assert_eq(_ags.meta_bosses_spawned, 3, "spawned count must survive a resume")
	assert_eq(_ags.meta_bosses_defeated, 2, "defeated count too — met and beaten are separate facts")
	assert_eq(_ags.collapse_count, 1, "control: the sibling counter that already worked still does")


func test_the_restorer_defaults_to_zero_for_an_OLD_snapshot() -> void:
	## Backward compatibility: a snapshot written before this change has no such keys. It must load
	## as zero rather than erroring or carrying whatever was in memory — a resumed pre-change save
	## is exactly the case that will hit this in the wild.
	_ags.meta_bosses_spawned = 9
	_ags.meta_bosses_defeated = 9
	_ags.restore_system_from_snapshot({"collapse_count": 4})
	assert_eq(_ags.meta_bosses_spawned, 0, "an old snapshot restores the counters to zero, not to stale memory")
	assert_eq(_ags.meta_bosses_defeated, 0, "both of them")
	assert_eq(_ags.collapse_count, 4, "control: the keys that ARE present still restore")


func test_the_snapshot_writer_names_both_keys() -> void:
	## The writer half. A restorer that reads keys nobody writes restores zeros forever — the same
	## one-layer-up defect that made the counters invisible to the Summary in the first place.
	var src: String = FileAccess.get_file_as_string("res://src/autogrind/AutogrindSystem.gd")
	assert_ne(src, "", "control: the source must be readable")
	assert_true(src.contains('"meta_bosses_spawned": meta_bosses_spawned'),
		"save_grind_snapshot must write the spawn count")
	assert_true(src.contains('"meta_bosses_defeated": meta_bosses_defeated'),
		"and the defeat count")
