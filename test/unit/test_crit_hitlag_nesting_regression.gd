extends GutTest

## Crit hitlag drops Engine.time_scale to 0.1 for ~80ms, then a tween restores it.
## The scale to restore was captured PER CALL, so two crits inside that window both
## captured — and the second captured 0.1, because the first had already applied it.
## The outer tween then restored the true speed and the inner one immediately put it
## back to 0.1, where it stayed for the rest of the fight.
##
## Player-visible: struktured, 2026-07-30 — "spammed until game kinda froze after a
## battle." At 0.1x the fight and every input response crawl, which is what a freeze
## feels like. It self-heals only on leaving the scene, since _exit_tree forces 1.0,
## which is why it reads as intermittent rather than as a hard lock.
##
## Second defect on the same lines: _toggle_battle_speed wrote Engine.time_scale
## directly, so pressing X during hitlag was silently reverted 80ms later by the
## pending restore. struktured pressed exactly that button in the same report.
##
## Engine.time_scale is GLOBAL and GUT runs the whole suite in one process — a leak
## here would slow every later test toward the wall-clock watchdog. after_each
## restores unconditionally.

const BattleSceneScript := preload("res://src/battle/BattleScene.gd")

var _scene: Control = null


func before_each() -> void:
	_scene = BattleSceneScript.new()
	Engine.time_scale = 1.0


func after_each() -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(_scene):
		_scene.free()
	_scene = null


func test_overlapping_crits_restore_the_real_speed_not_the_hitlag_speed() -> void:
	Engine.time_scale = 0.25
	_scene._hitlag_enter()
	assert_almost_eq(Engine.time_scale, BattleSceneScript.HITLAG_SCALE, 0.0001,
		"first crit must apply hitlag")
	_scene._hitlag_enter()
	assert_almost_eq(Engine.time_scale, BattleSceneScript.HITLAG_SCALE, 0.0001,
		"a second crit inside the window is still hitlag")
	_scene._end_hitlag()
	assert_almost_eq(Engine.time_scale, BattleSceneScript.HITLAG_SCALE, 0.0001,
		"the inner restore must NOT end hitlag — the outer crit is still in its window")
	_scene._end_hitlag()
	assert_almost_eq(Engine.time_scale, 0.25, 0.0001,
		"the battle must return to its real speed; before the fix it stayed at 0.1 "
		+ "for the rest of the fight, which is what 'kinda froze' was")


func test_single_crit_still_restores() -> void:
	Engine.time_scale = 0.5
	_scene._hitlag_enter()
	_scene._end_hitlag()
	assert_almost_eq(Engine.time_scale, 0.5, 0.0001,
		"the ordinary one-crit path must be unchanged by the nesting fix")


func test_changing_battle_speed_during_hitlag_is_not_reverted() -> void:
	Engine.time_scale = 0.25
	_scene._hitlag_enter()
	# struktured pressed the speed button (Switch Y / Xbox X) mid-fight.
	_scene._set_battle_time_scale(1.0)
	_scene._end_hitlag()
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001,
		"the speed the player chose during hitlag must survive the pending restore; "
		+ "before the fix the tween reverted it to the pre-crit speed 80ms later")


func test_speed_change_outside_hitlag_applies_immediately() -> void:
	Engine.time_scale = 0.25
	_scene._set_battle_time_scale(2.0)
	assert_almost_eq(Engine.time_scale, 2.0, 0.0001,
		"with no hitlag pending a speed change must take effect now, not be deferred")


## Unbalanced restores must not drive depth negative — a later crit would then fail
## to apply hitlag at all, turning this fix into a silent loss of the effect.
func test_extra_restores_cannot_drive_depth_negative() -> void:
	Engine.time_scale = 0.25
	_scene._end_hitlag()
	_scene._end_hitlag()
	_scene._hitlag_enter()
	assert_almost_eq(Engine.time_scale, BattleSceneScript.HITLAG_SCALE, 0.0001,
		"hitlag must still engage after stray restores")
	_scene._end_hitlag()
	assert_almost_eq(Engine.time_scale, 0.25, 0.0001,
		"and must still hand back the real speed")


## Negative control: the assertions above are only meaningful if hitlag actually
## CHANGES time_scale. If HITLAG_SCALE ever equalled the battle speed under test,
## every assertion would pass while measuring nothing.
func test_hitlag_scale_differs_from_the_speeds_under_test() -> void:
	assert_ne(BattleSceneScript.HITLAG_SCALE, 0.25,
		"the test speeds must differ from the hitlag scale, else the assertions "
		+ "above cannot distinguish a restored scale from a stuck one")
	assert_true(BattleSceneScript.BATTLE_SPEEDS.has(0.25),
		"0.25 must be a real battle speed (label '1x', the default) so these tests "
		+ "exercise the configuration players actually run")
