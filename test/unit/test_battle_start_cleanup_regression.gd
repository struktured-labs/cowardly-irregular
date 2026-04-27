extends GutTest

## Regression test for per-battle state leak.
##
## Found via audit: GameLoop reuses the same Combatant instances for the
## player party across all battles. BattleManager.start_battle() was not
## clearing active_buffs / active_debuffs / status_effects / status_durations
## / is_defending / doom_counter — so a Protect buff from battle A would
## carry over into battle B, along with Armor Break debuffs, Doom counters,
## and mid-turn defending state.
##
## BattleScene._restart_battle() only cleared status_effects, missing the
## other state.
##
## Fix: BattleManager.start_battle() now clears all per-battle state
## on every combatant (both party and enemies) at the top of the function.
##
## Tested structurally (source-level) because calling start_battle() in an
## isolated GUT test crashes with "data.tree is null" — GUT's run context
## for single-test runs doesn't always guarantee scene-tree access.


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_start_battle_clears_active_buffs() -> void:
	var text = _read("res://src/battle/BattleManager.gd")
	# Find start_battle body
	var idx = text.find("func start_battle(")
	assert_gt(idx, -1, "start_battle must exist")
	var body = text.substr(idx, 3000)  # Read generous body chunk
	assert_true(body.find("active_buffs.clear()") != -1,
		"start_battle must clear active_buffs (regression: buff leak across encounters)")


func test_start_battle_clears_active_debuffs() -> void:
	var text = _read("res://src/battle/BattleManager.gd")
	var idx = text.find("func start_battle(")
	var body = text.substr(idx, 3000)
	assert_true(body.find("active_debuffs.clear()") != -1,
		"start_battle must clear active_debuffs")


func test_start_battle_clears_status_effects() -> void:
	var text = _read("res://src/battle/BattleManager.gd")
	var idx = text.find("func start_battle(")
	var body = text.substr(idx, 3000)
	assert_true(body.find("status_effects.clear()") != -1,
		"start_battle must clear status_effects")


func test_start_battle_clears_status_durations() -> void:
	var text = _read("res://src/battle/BattleManager.gd")
	var idx = text.find("func start_battle(")
	var body = text.substr(idx, 3000)
	assert_true(body.find("status_durations.clear()") != -1,
		"start_battle must clear status_durations")


func test_start_battle_resets_is_defending() -> void:
	var text = _read("res://src/battle/BattleManager.gd")
	var idx = text.find("func start_battle(")
	var body = text.substr(idx, 3000)
	assert_true(body.find("is_defending = false") != -1,
		"start_battle must reset is_defending")


func test_start_battle_resets_doom_counter() -> void:
	var text = _read("res://src/battle/BattleManager.gd")
	var idx = text.find("func start_battle(")
	var body = text.substr(idx, 3000)
	assert_true(body.find("doom_counter = 0") != -1,
		"start_battle must reset doom_counter")


func test_start_battle_does_not_reset_hp_or_mp() -> void:
	# HP/MP preservation is critical — players shouldn't be fully healed between
	# battles automatically (inn/items do that). Verify start_battle doesn't
	# contain `current_hp = max_hp` or `current_mp = max_mp`.
	var text = _read("res://src/battle/BattleManager.gd")
	var idx = text.find("func start_battle(")
	# Find next func to cap the body
	var next_func = text.find("\nfunc ", idx + 1)
	if next_func == -1:
		next_func = text.length()
	var body = text.substr(idx, next_func - idx)

	assert_eq(body.find("current_hp = max_hp"), -1,
		"start_battle must NOT reset current_hp to max_hp (regression: no auto-heal between battles)")
	assert_eq(body.find("current_mp = max_mp"), -1,
		"start_battle must NOT reset current_mp to max_mp")


func test_cleanup_uses_defensive_in_guards() -> void:
	# Per CLAUDE.md: "Check 'active_buffs' in combatant before accessing buff
	# arrays" — defensive coding in case non-Combatant objects slip into the
	# array. Verify the cleanup loop uses `in combatant` guards.
	var text = _read("res://src/battle/BattleManager.gd")
	var idx = text.find("func start_battle(")
	var body = text.substr(idx, 3000)
	assert_true(body.find('"active_buffs" in combatant') != -1,
		"Cleanup must guard with \"active_buffs\" in combatant per CLAUDE.md convention")


func test_start_battle_resets_current_ap() -> void:
	# Defensive guard: GameLoop's victory paths reset current_ap to 0, but
	# edge cases (load-save mid-battle, flee, debug warp) can leave the
	# party with +4 AP heading into a fresh encounter. start_battle should
	# normalize AP to 0 as a centralized safety net.
	var text = _read("res://src/battle/BattleManager.gd")
	var idx = text.find("func start_battle(")
	var body = text.substr(idx, 3000)
	assert_true(body.find("current_ap = 0") != -1,
		"start_battle must reset current_ap to 0 (regression: AP leak via edge-case battle entry)")
	# Verify the same `in combatant` defensive guard is applied.
	assert_true(body.find('"current_ap" in combatant') != -1,
		"current_ap reset must use the in-combatant guard pattern")


func test_start_battle_clears_queued_actions() -> void:
	# Less critical (queued_actions on Combatant is dead state currently —
	# the live queue lives in Win98Menu) but unbounded growth is still a
	# leak. start_battle.clear() prevents accumulation.
	var text = _read("res://src/battle/BattleManager.gd")
	var idx = text.find("func start_battle(")
	var body = text.substr(idx, 3000)
	assert_true(body.find("queued_actions.clear()") != -1,
		"start_battle must clear queued_actions (prevent unbounded growth across battles)")
