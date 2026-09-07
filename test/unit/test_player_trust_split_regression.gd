extends GutTest

## Queue #4 (cowir-main msg 2152): Trust UI carryforward, foundational half.
## Splits the Trust semantics off the shared autobattle_locked field so:
##  1. _reconcile_spotlight_locks (story-owned) can't wipe player-set trust
##  2. save/load round-trips player_trust independently
##  3. BM routing gates on the OR of the two sources
##  4. BattleCommandMenu's Trust toggle now mutates player_trust (not the
##     shared field, so a subsequent reconciler cycle keeps player intent).
##
## The out-of-battle settings-side untrust surface is exercised by
## test_settings_menu_party_trust_regression.gd (sibling test).

const BM_PATH: String = "res://src/battle/BattleManager.gd"


func _combatant(job_id: String = "fighter", level: int = 1) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = job_id
	c.job = JobSystem.get_job(job_id)
	c.job_level = level
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	return c


## ── Field split ─────────────────────────────────────────────────────────

func test_player_trust_defaults_false_and_is_independent_of_autobattle_locked() -> void:
	var c := _combatant()
	assert_false(c.player_trust, "player_trust default false")
	c.autobattle_locked = true
	assert_false(c.player_trust, "flipping autobattle_locked leaves player_trust untouched")
	c.player_trust = true
	assert_true(c.autobattle_locked, "flipping player_trust leaves autobattle_locked untouched")
	c.free()


func test_player_trust_survives_save_and_load() -> void:
	var c := _combatant()
	c.player_trust = true
	c.autobattle_locked = false
	var dict = c.to_dict()
	assert_true(dict.has("player_trust"))
	assert_true(bool(dict["player_trust"]))
	var restored := _combatant()
	restored.from_dict(dict)
	assert_true(restored.player_trust, "player_trust must round-trip via save/load")
	c.free(); restored.free()


func test_spotlight_reconciler_does_not_clear_player_trust() -> void:
	# Simulate the reconciler's effect: story clears autobattle_locked when
	# the spotlight fires. player_trust must survive that mutation.
	var c := _combatant("cleric")
	c.autobattle_locked = true
	c.player_trust = true
	c.autobattle_locked = false  # reconciler
	assert_true(c.player_trust, "story-side unlock must NOT wipe player-set trust")
	c.free()


## ── BM routing: player_trust routes to autobattle ───────────────────────

func test_routing_treats_player_trust_like_spotlight_lock() -> void:
	# Textual pin on the routing gate — the added is_player_trusted branch
	# must live in _process_next_selection alongside is_spotlight_locked
	# or player-trusted turns will fall through to the manual menu.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	assert_string_contains(src, "is_player_trusted",
		"BM routing must gate on the new player_trust source")
	assert_string_contains(src, "player_trust",
		"BM routing must read the split field")


## ── BattleCommandMenu Trust toggle writes player_trust ──────────────────

func test_command_menu_trust_toggle_writes_player_trust() -> void:
	# Same textual-pin flavor as the routing test — the shipped toggle used
	# to mutate autobattle_locked (2026-06-04 UX). Split must move it.
	const CMD_PATH := "res://src/battle/BattleCommandMenu.gd"
	var src: String = FileAccess.get_file_as_string(CMD_PATH)
	assert_string_contains(src, "combatant_for_trust.player_trust = not combatant_for_trust.player_trust",
		"Trust toggle must flip player_trust, not autobattle_locked (spotlight field)")
	assert_string_contains(src, "\"Trust: ON\" if combatant.player_trust",
		"Trust label reflects player_trust so the row shows player intent")
