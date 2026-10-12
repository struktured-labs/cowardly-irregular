extends GutTest

## .654's render smoke: 15k "Left operand of 'is' is a previously freed instance" and a shadow_dragon
## fight that never reached game over. Reproduced in a fresh sandbox, and the decisive evidence was an
## ABSENCE — `Battle commenced` appeared exactly twice in the whole run, for the first exploration
## battle and for the phantom. THE DUEL'S OWN BATTLE NEVER COMMENCED:
##
##   BOSS BATTLE! / Skeleton Knight appeared!   the duel scene builds, _start_test_battle takes the
##                                              _show_boss_intro_dialogue() branch, sets
##                                              _waiting_for_dialogue and does NOT start the battle
##   === VICTORY ===                            the smoke's end_battle(true) synthesises a win
##   [SPOTLIGHT] battle won                     the duel is RECORDED as won
##   >>> Battle commenced!                      a confirm dismisses the STALE intro, and
##                                              _on_dialogue_finished sees the latch still set
##
## `_waiting_for_dialogue` is a ONE-WAY LATCH — set in one place, cleared in one other, and nothing
## cleared it when a battle ended — feeding `_start_battle_after_dialogue`, which had no guard at all
## and is the only path that still starts a battle from this scene's own arrays. So the phantom ran
## with player_party=[duelist] and enemy_party=[freed], and the buff pass then ran `is` over them.
##
## Both halves are fixed because either alone leaves the other armed: clearing the latch fixes THIS
## ordering, the guard fixes every future path that ends a battle before its intro is dismissed.

const SCENE := "res://src/battle/BattleScene.tscn"
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _guard: RefCounted = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _scene() -> Node:
	var s = load(SCENE).instantiate()
	add_child_autofree(s)
	return s


## CONTROL, and it must pass on BOTH trees: the ordinary boss intro still starts its battle. A guard
## whose subject is an absence has no loud direction of its own — "the phantom was blocked" and "the
## start path is broken" both show an unchanged serial, and only this arm separates them.
func test_control_a_dismissed_intro_still_starts_its_battle() -> void:
	var scene := _scene()
	scene._battle_ended = false
	scene._waiting_for_dialogue = true
	var before: int = BattleManager.battle_serial
	scene._on_dialogue_finished()
	assert_eq(BattleManager.battle_serial, before + 1,
		"dismissing a live boss intro must still start the fight it introduced")


## The defect, through the REAL handler. Calling _start_battle_after_dialogue directly would abort on
## main after a passing assert and score the file green (CLAUDE.md's rung-3 trap); _on_dialogue_finished
## is the path the confirm press actually takes.
func test_a_confirm_after_the_battle_ended_starts_nothing() -> void:
	var scene := _scene()
	scene._battle_ended = true
	scene._waiting_for_dialogue = true
	var before: int = BattleManager.battle_serial
	scene._on_dialogue_finished()
	assert_eq(BattleManager.battle_serial, before,
		"a confirm arriving after the battle ended must not restart it (serial moved %d -> %d)" % [
			before, BattleManager.battle_serial])


## The latch itself: the real end handler has to put it down, or the guard above is the only thing
## standing between a finished battle and a confirm press.
func test_the_battle_end_puts_the_intro_latch_down() -> void:
	var scene := _scene()
	scene._waiting_for_dialogue = true
	scene._on_battle_ended(true)
	assert_false(scene._waiting_for_dialogue,
		"nothing else clears this latch, so a battle end has to")


## A freed enemy is the state the phantom actually ran in, and it is reachable independently of the
## latch — the duel scene's enemies are freed by the return to exploration.
func test_a_confirm_with_a_freed_enemy_starts_nothing() -> void:
	var scene := _scene()
	scene._battle_ended = false
	scene._waiting_for_dialogue = true
	var ghost := Combatant.new()
	ghost.initialize({"name": "Ghost", "max_hp": 1, "max_mp": 0,
		"attack": 1, "defense": 1, "magic": 1, "speed": 1})
	scene.test_enemies.append(ghost)
	ghost.free()
	var before: int = BattleManager.battle_serial
	scene._on_dialogue_finished()
	assert_eq(BattleManager.battle_serial, before,
		"a battle must not start against an enemy that has already been freed")
