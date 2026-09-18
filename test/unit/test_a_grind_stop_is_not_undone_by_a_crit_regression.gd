extends GutTest

const BS := preload("res://src/battle/BattleScene.gd")

## Stop or pause a grind in the 80ms after a critical hit and the engine goes back to the battle
## speed on its own. `_begin_hitlag(0.008)` drops `Engine.time_scale` to 0.1 and schedules a restore
## to the captured pre-hitlag value; at 0.1 that 8ms of SCALED time is ~80ms of wall clock, which is
## several frames of button window. GameLoop._stop_autogrind and AutogrindController's pause /
## stop / resume all write `Engine.time_scale` DIRECTLY, so the pending restore lands afterwards and
## reinstates the battle speed the player just left.
##
## 🔑 BattleScene ALREADY SOLVED THIS FOR ITS OWN WRITER and never covered anyone else's.
## `_set_battle_time_scale` retargets `_hitlag_base_scale`, with the comment "Retarget the pending
## restore, else pressing X mid-crit reverts to the old speed 80ms later." That is this defect,
## fixed for the speed key and open for every external writer.
##
## The repair is precedence, not another retarget point: a presentation effect must not overwrite an
## explicit intent expressed while it was running. `_end_hitlag` restores only if nothing else
## claimed the scale.
##
## ⚠️ SCOPE, NARROWED 2026-09-18 AFTER MEASURING THE LINK I HAD LEFT OPEN. This said the
## end-to-end scenario was not driven. The DELIVERY half now is: the arm below runs the real
## `_begin_hitlag` tween, writes 1.0 the way `_stop_autogrind` does, and lets the tween fire with
## the scene alive. Pre-fix it came back at 2.0; post-fix at 1.0. @cowir-music's point that
## measuring an open link can change the REPAIR and not just the priority — here it did not change
## the repair, it removed the last code-side assumption from it.
## What remains undriven is only the human half: a player pressing exit inside the ~80ms window.

var _saved_scale: float = 1.0


func before_each() -> void:
	_saved_scale = Engine.time_scale


func after_each() -> void:
	Engine.time_scale = _saved_scale


func _scene() -> Node:
	var s = BS.new()
	add_child_autofree(s)
	return s


## ⛔ THE DEFECT. An external writer's value must survive the pending restore.
func test_a_stop_written_during_hitlag_survives_the_restore() -> void:
	var scene := _scene()
	Engine.time_scale = 2.0
	scene._hitlag_enter()
	assert_almost_eq(Engine.time_scale, 0.1, 0.0001,
		"CONTROL: hitlag must actually take the scale down, or nothing below is being tested")
	assert_almost_eq(scene._hitlag_base_scale, 2.0, 0.0001,
		"CONTROL: the pre-hitlag speed must be the captured restore target")

	## Exactly what GameLoop._stop_autogrind and AutogrindController.pause/stop do.
	Engine.time_scale = 1.0
	scene._end_hitlag()
	gut.p("    after the pending restore: time_scale=%.3f" % Engine.time_scale)
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001,
		"the hitlag restore overwrote a stop/pause written while it was pending — the player left the grind and the engine kept running at the battle speed")


## The path BattleScene uses for its own speed key, which already retargets. Must stay immune.
func test_the_retargeting_setter_is_still_immune() -> void:
	var scene := _scene()
	Engine.time_scale = 2.0
	scene._hitlag_enter()
	scene._set_battle_time_scale(1.0)
	scene._end_hitlag()
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001,
		"CONTROL: _set_battle_time_scale must keep surviving a pending restore")


## ⛔ THE ORDINARY CASE MUST NOT REGRESS: with nobody else writing, hitlag restores the speed.
func test_an_undisturbed_hitlag_still_restores_the_battle_speed() -> void:
	var scene := _scene()
	Engine.time_scale = 2.0
	scene._hitlag_enter()
	scene._end_hitlag()
	gut.p("    undisturbed restore: time_scale=%.3f" % Engine.time_scale)
	assert_almost_eq(Engine.time_scale, 2.0, 0.0001,
		"with no external write, hitlag must put the battle speed back — this is the effect working")


## Nesting: only the outermost restores, and an inner end must not release the scale early.
func test_nested_hitlag_still_restores_only_at_depth_zero() -> void:
	var scene := _scene()
	Engine.time_scale = 2.0
	scene._hitlag_enter()
	scene._hitlag_enter()
	scene._end_hitlag()
	assert_almost_eq(Engine.time_scale, 0.1, 0.0001,
		"CONTROL: an inner hitlag end must leave the scale down")
	scene._end_hitlag()
	assert_almost_eq(Engine.time_scale, 2.0, 0.0001, "the outermost end restores")


## ⛔ THE DELIVERY MECHANISM, not the depth arithmetic. The arms above call `_end_hitlag` directly,
## which proves the PRECEDENCE rule; this proves the real pending tween is what arrives to enforce
## it, with the scene alive, after an external write. Measured both ways: with the guard reverted
## this arm reports 2.000.
func test_the_real_pending_tween_does_not_undo_the_write() -> void:
	var scene := _scene()
	Engine.time_scale = 2.0
	scene._begin_hitlag(0.008)
	assert_eq(scene._hitlag_depth, 1, "CONTROL: the real hitlag must have armed, or nothing is pending")

	Engine.time_scale = 1.0
	for _i in range(40):
		await get_tree().process_frame

	gut.p("    after the real tween window: scale=%.3f depth=%d" % [Engine.time_scale, scene._hitlag_depth])
	assert_eq(scene._hitlag_depth, 0,
		"CONTROL: the pending tween must actually have fired inside the window, or this arm measures nothing")
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001,
		"the real pending tween overwrote the stop — the player left the grind and the engine went back to the battle speed on its own")
