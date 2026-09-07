extends GutTest

## rotate_aggro was a live counter arm nobody exercised (2026-07-29).
##
## Found by closing a gap I had merely NAMED. I reported "every dispatch
## arm appears in a test file — 11/11, no orphans" and stated the limit
## in the same breath: appearing in a file is not being exercised. That
## caveat reads as rigour and leaves the claim exactly as unverified
## (@cowir-sfx msg-3469).
##
## The surface was bounded — 11 arms — so it was exhaustible. Splitting
## "exercised" from "mentioned" flagged four; READING them (rather than
## reporting the count) left one:
##
##   ice_resist / lightning_resist   FALSE POSITIVE — they share
##                                   fire_resist's arm, which is exercised
##   flee_target                     documented stub, returns false always
##   rotate_aggro                    REAL — own arm, live action, zero tests
##
## rotate_aggro returns a real attack action against a random living
## enemy. A boss whose counter-strategy resolves to it acts on this and
## nothing checked that it produced anything.

var _bm: Node


func before_each() -> void:
	_bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(_bm)


func _c(name: String) -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = name
	c.is_alive = true
	return c


## ── rotate_aggro: the uncovered arm ──────────────────────────────────

func test_rotate_aggro_returns_an_attack_action() -> void:
	var boss: Combatant = _c("Boss")
	var targets: Array = [_c("Fighter"), _c("Cleric"), _c("Mage")]
	var action: Dictionary = _bm._get_counter_action(boss, "rotate_aggro", [], targets, [])
	assert_false(action.is_empty(),
		"rotate_aggro must produce an action — an empty return means the caller falls through and the counter-strategy contributes nothing")
	assert_eq(str(action.get("type", "")), "attack",
		"rotate_aggro rotates AGGRO — it attacks, it does not cast")
	assert_true(action.get("target") in targets,
		"the target must be one of the living enemies passed in, not an arbitrary combatant")


func test_rotate_aggro_needs_no_abilities() -> void:
	# The distinguishing property vs every other counter arm: the resist
	# and defense_boost arms return {} when the kit lacks a matching
	# ability. rotate_aggro depends on TARGETS, not on the kit — so it is
	# the arm that still works for a boss with an empty ability list.
	var action: Dictionary = _bm._get_counter_action(_c("Boss"), "rotate_aggro", [], [_c("A")], [])
	assert_false(action.is_empty(),
		"rotate_aggro must fire with an empty ability array — it is the fallback that cannot be starved by a kit")


func test_rotate_aggro_with_no_targets_returns_empty() -> void:
	# Guarded by `if enemies.size() > 0`. Without that the modulo on an
	# empty array would divide by zero mid-battle.
	var action: Dictionary = _bm._get_counter_action(_c("Boss"), "rotate_aggro", [], [], [])
	assert_true(action.is_empty(),
		"with no living targets rotate_aggro must return empty rather than index an empty array")


## ── flee_target: a stub, pinned as a stub ────────────────────────────

func test_flee_target_delegates_rather_than_deciding() -> void:
	# Deliberately returns false: the arm exists so the win-condition
	# dispatch has a name for it, and delegates to the caller's standard
	# "all enemies dead" check. Pinned so that someone IMPLEMENTING it
	# has to update this test rather than silently changing what the
	# dispatch means. Not a claim that returning false is desirable.
	_bm._win_condition = {"type": "flee_target"}
	assert_false(_bm._evaluate_custom_win_condition(),
		"flee_target is a documented stub that delegates to the enemies-alive check; if you implement it, update this test deliberately")
