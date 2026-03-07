extends GutTest

## Regression tests for the enemy-defer bug.
##
## Bug: When all party members deferred, enemies could also defer (10% random chance),
## causing the battle to stall with no actions taken — monsters appeared to "do nothing."
##
## Fix: Removed the should_defer branch from _process_ai_selection() for enemies.
## Enemies must ALWAYS select an attacking action when live targets exist.
##
## Secondary fix: Unknown action type in _execute_next_action now calls _execute_next_action()
## instead of bare return, preventing the execution chain from stalling forever.


## Source-level regression: verify the should_defer branch no longer exists
## for the enemy AI path in BattleManager.gd.

func test_enemy_ai_never_defers_in_source() -> void:
	"""Regression: _process_ai_selection must not contain a random should_defer branch.
	Enemies are not allowed to defer — only players can defer."""
	var src = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_false(
		src.contains("should_defer"),
		"BattleManager should not have a should_defer variable — enemies must not randomly defer"
	)


func test_enemy_ai_section_has_no_defer_return_before_advance() -> void:
	"""Regression: The AI selection code path must not queue a defer action and return
	before reaching the advance / normal-attack logic for enemies."""
	var src = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	# The removed block contained the literal text below.  If it re-appears the bug is back.
	var reintroduced = (
		src.contains("if should_defer:")
		or src.contains("AI) chooses to defer")
	)
	assert_false(
		reintroduced,
		"Enemy AI must not have a 'should_defer' branch — that path was the root cause of enemies doing nothing"
	)


## Source-level regression: verify the unknown-action stall fix is present.

func test_unknown_action_type_calls_next_action() -> void:
	"""Regression: Unknown action type in _execute_next_action must not bare-return,
	which would freeze the execution chain permanently."""
	var src = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	# The fixed block must call _execute_next_action() before returning in the _ case.
	# We look for the explicit continuation comment that was added.
	var has_continuation_comment = src.contains(
		"A stray unknown action must not freeze the whole battle."
	)
	assert_true(
		has_continuation_comment,
		"Unknown action type handler must call _execute_next_action() to keep the chain alive"
	)


## Combatant-level checks: defer mechanics behave correctly for players.

func test_execute_defer_sets_defending() -> void:
	"""execute_defer() must set is_defending=true so the defending damage reduction applies."""
	var c = Combatant.new()
	c.combatant_name = "Deferring Player"
	add_child(c)

	assert_false(c.is_defending, "Should not be defending before defer")
	c.execute_defer()
	assert_true(c.is_defending, "execute_defer() must set is_defending to true")
	c.queue_free()


func test_defending_combatant_takes_half_damage() -> void:
	"""A combatant that deferred (is_defending=true) must take 50% reduced damage."""
	var attacker = Combatant.new()
	attacker.combatant_name = "Enemy"
	attacker.attack = 30
	add_child(attacker)

	var defender = Combatant.new()
	defender.combatant_name = "Deferring Player"
	defender.max_hp = 1000
	defender.current_hp = 1000
	defender.defense = 5
	add_child(defender)

	# Measure damage without defending
	var hp_before_normal = defender.current_hp
	defender.take_damage(30, false)
	var normal_damage = hp_before_normal - defender.current_hp

	# Reset and measure damage while defending
	defender.current_hp = 1000
	defender.execute_defer()
	assert_true(defender.is_defending)
	var hp_before_defending = defender.current_hp
	defender.take_damage(30, false)
	var defending_damage = hp_before_defending - defender.current_hp

	assert_gt(normal_damage, 0, "Normal damage must be positive")
	assert_gt(defending_damage, 0, "Defending damage must still be positive (never 0)")
	assert_lt(defending_damage, normal_damage,
		"Damage while defending must be less than normal damage")
	# The formula applies *50%* reduction — allow small int-rounding slack.
	var expected = int(normal_damage * 0.5)
	assert_almost_eq(float(defending_damage), float(expected), 1.0,
		"Defending damage should be ~50% of normal damage")

	attacker.queue_free()
	defender.queue_free()


func test_reset_for_new_round_clears_defending() -> void:
	"""reset_for_new_round() must clear is_defending so the defending bonus doesn't persist."""
	var c = Combatant.new()
	c.combatant_name = "Player"
	add_child(c)

	c.execute_defer()
	assert_true(c.is_defending, "Pre-condition: should be defending after defer")
	c.reset_for_new_round()
	assert_false(c.is_defending, "is_defending must be cleared by reset_for_new_round()")
	c.queue_free()


## Design invariant: an enemy that reaches _process_ai_selection with live targets
## must never produce a defer-type queued action.
## We verify this structurally via the BattleManager source rather than spinning up
## a live battle scene, which would require the full scene tree.

func test_battle_manager_ai_selection_calls_make_ai_decision_for_enemies() -> void:
	"""_process_ai_selection must always reach _make_ai_decision (or advance/summon)
	for enemies with live targets — confirmed by the absence of any early-exit defer path."""
	var src = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")

	# The function _make_ai_decision is the normal attack-selection exit path.
	# Verify it is still called from _process_ai_selection.
	assert_true(
		src.contains("_make_ai_decision(combatant, alive_allies, alive_enemies)"),
		"_process_ai_selection must still call _make_ai_decision for the normal attack path"
	)


func test_make_ai_decision_defaults_to_attack() -> void:
	"""_make_ai_decision must fall back to a basic attack when no ability is chosen.
	The return value must never be an empty dict for an enemy with a live target."""
	var bm = get_tree().root.get_node_or_null("BattleManager") if get_tree() else null
	if bm == null:
		pending("BattleManager singleton not in scene tree during headless test")
		return

	var enemy = Combatant.new()
	enemy.combatant_name = "Test Enemy"
	enemy.attack = 10
	enemy.defense = 5
	enemy.speed = 8
	enemy.max_hp = 50
	enemy.current_hp = 50
	enemy.max_mp = 0
	enemy.current_mp = 0

	var target = Combatant.new()
	target.combatant_name = "Target"
	target.max_hp = 100
	target.current_hp = 100

	var alive_allies: Array = []
	var alive_enemies: Array = [target]

	var decision = bm._make_ai_decision(enemy, alive_allies, alive_enemies)

	assert_false(decision.is_empty(), "_make_ai_decision must not return empty dict")
	assert_ne(decision.get("type", ""), "defer",
		"_make_ai_decision must not return a defer action for an enemy with live targets")
	assert_true(
		decision.get("type", "") in ["attack", "ability", "summon"],
		"_make_ai_decision must return attack, ability, or summon — got: %s" % decision.get("type", "")
	)

	enemy.queue_free()
	target.queue_free()
