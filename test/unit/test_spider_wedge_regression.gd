extends GutTest

## struktured 2026-09-06, live log confirmed: a spider encounter's RADIAL_WIPE await hung on
## freed fragments, leaking GameLoop._battle_transition_starting FOREVER — 19 "BLOCKED — a
## battle transition is already starting" lines, monsters stopped fighting and vanished on
## touch (their fade was unconditional). Three defenses, each pinned here:
##  1. BattleTransition awaits liveness, never a signal a freed tween can't emit.
##  2. GameLoop arms a watchdog over the commence latch (it had NO expiry).
##  3. RoamingMonster fades only when ITS touch flipped the latch.

const BT_SRC := "res://src/transitions/BattleTransition.gd"
const GL_SRC := "res://src/GameLoop.gd"


func test_no_raw_tween_finished_awaits_remain_in_battle_transition() -> void:
	var src := FileAccess.get_file_as_string(BT_SRC)
	assert_gt(src.length(), 5000, "CONTROL: read a real file")
	assert_false(src.contains("await tween.finished"),
		"a raw tween.finished await hangs forever when a concurrent cleanup frees its targets")
	assert_false(src.contains("await flash_tween.finished"), "the flash variant too")
	assert_true(src.contains("func _await_tween_safe("), "the bounded helper must exist")
	var count := 0
	var i := src.find("_await_tween_safe(")
	while i != -1:
		count += 1
		i = src.find("_await_tween_safe(", i + 1)
	assert_gt(count, 12, "every former raw await must route through the helper (found %d refs)" % count)


func test_helper_is_bounded_by_wall_clock_and_liveness() -> void:
	var src := FileAccess.get_file_as_string(BT_SRC)
	var i: int = src.find("func _await_tween_safe(")
	var body: String = src.substr(i, 600)
	assert_true(body.contains("is_instance_valid(tween)"), "a freed tween must end the wait")
	assert_true(body.contains("tween.is_running()"), "a finished/killed tween must end the wait")
	assert_true(body.contains("Time.get_ticks_msec()"), "and a wall-clock ceiling caps everything else")


func test_gameloop_arms_a_watchdog_when_the_latch_is_set() -> void:
	var src := FileAccess.get_file_as_string(GL_SRC)
	assert_gt(src.length(), 10000, "CONTROL: read a real file")
	var i: int = src.find("_battle_transition_starting = true")
	assert_gt(i, -1, "CONTROL: the latch-set site must exist")
	assert_true(src.substr(i, 120).contains("_arm_battle_commence_watchdog()"),
		"the latch must never be set without its watchdog — it has no other expiry")
	var w: int = src.find("func _arm_battle_commence_watchdog(")
	assert_gt(w, -1, "the watchdog must exist")
	var body: String = src.substr(w, 900)
	assert_true(body.contains("_battle_transition_starting = false"), "and it must clear the latch")
	assert_true(body.contains("gut_cmdln"), "gut hard-off, matching the transition watchdog family")
	assert_true(body.contains("_battle_commence_wd_gen == gen"),
		"generation token so a stale timer never clears a LATER transition's latch")


class FakeGameLoop:
	extends Node
	var _battle_transition_starting: bool = false


func _make_monster_rig(latch_start: bool, flip_on_touch: bool) -> Dictionary:
	var gl := FakeGameLoop.new()
	gl.name = "GameLoop"
	gl._battle_transition_starting = latch_start
	get_tree().root.add_child(gl)
	var host := Node2D.new()
	add_child_autofree(host)
	var monster: Area2D = load("res://src/exploration/RoamingMonster.gd").new()
	host.add_child(monster)
	monster._active = true
	monster._fading = false
	if flip_on_touch:
		monster.touched.connect(func(_id, _types, _elite): gl._battle_transition_starting = true)
	return {"gl": gl, "monster": monster}


class FakePlayer:
	extends Node2D
	func set_can_move(_v: bool) -> void: pass


func test_monster_fades_when_its_touch_starts_the_battle() -> void:
	var rig := _make_monster_rig(false, true)
	var player := FakePlayer.new()
	add_child_autofree(player)
	rig["monster"]._on_body_entered(player)
	assert_true(rig["monster"]._fading, "latch flipped false->true = OUR battle — the monster fades into it")
	rig["gl"].free()


func test_monster_survives_a_blocked_touch() -> void:
	# The wedge state: latch already true, GameLoop will print BLOCKED and start nothing.
	var rig := _make_monster_rig(true, false)
	var player := FakePlayer.new()
	add_child_autofree(player)
	rig["monster"]._on_body_entered(player)
	assert_false(rig["monster"]._fading,
		"a touch the engine rejected must not spend the monster — pre-fix they vanished with no fight")
	rig["gl"].free()
