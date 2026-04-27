extends GutTest

## Regression: Phoenix Down's heal_hp_percent was ignored.
##
## Pre-fix bug: ItemSystem._apply_item_effects() processed heal_hp_percent
## BEFORE revive. With the target dead, heal() returned 0 (no-op). Then
## revive() was called with no argument and set HP to 50% max_hp by
## default. Phoenix Down's authored "25% HP" was silently dead code,
## and the actual revive landed at 50% — contradicting the in-game item
## description "Revives a fallen ally with 25% HP".
##
## Post-fix: revive runs first; if heal_hp_percent is also set, it's
## consumed as the revive HP target (so the percent in the data drives
## the actual revival amount). The redundant heal step is then skipped
## via a local _heal_consumed_by_revive flag.
##
## This test exercises the ItemSystem.gd code path directly with a fresh
## Combatant — no battle scene, no autoload coupling.


const CombatantScript = preload("res://src/battle/Combatant.gd")
const ItemSystemScript = preload("res://src/items/ItemSystem.gd")


func _make_combatant(max_hp: int = 100) -> Combatant:
	var c = CombatantScript.new()
	c.combatant_name = "RevivalTester"
	c.max_hp = max_hp
	c.current_hp = max_hp
	c.max_mp = 30
	c.current_mp = 30
	c.attack = 10
	c.defense = 10
	c.magic = 10
	c.speed = 10
	add_child_autofree(c)
	return c


func _make_item_system() -> Node:
	var sys = ItemSystemScript.new()
	# Don't add as child — _ready loads JSON which would fail in test
	# context without proper autoload state. Just use directly.
	return sys


func test_phoenix_down_revives_at_25_percent() -> void:
	# Phoenix Down has effects = {revive: true, heal_hp_percent: 25}.
	# After fix, this must revive at 25 HP (25% of max=100), NOT 50.
	var target = _make_combatant(100)
	target.is_alive = false
	target.current_hp = 0

	var sys = _make_item_system()
	# Construct effects manually since _ready() may not have run.
	var phoenix_down = {
		"id": "phoenix_down",
		"name": "Phoenix Down",
		"effects": {
			"revive": true,
			"heal_hp_percent": 25,
		},
	}
	sys._apply_item_effects(target, target, phoenix_down)

	assert_true(target.is_alive, "Phoenix Down should revive the target")
	assert_eq(target.current_hp, 25,
		"Phoenix Down should revive at 25%% HP (got %d, expected 25)" % target.current_hp)


func test_revive_without_percent_uses_default_50_percent() -> void:
	# A revive item with NO heal_hp_percent should fall back to revive()'s
	# default of 50% max_hp. This protects against breaking other revive
	# items (e.g. Phoenix Tail Feather) that don't author a percent.
	var target = _make_combatant(100)
	target.is_alive = false
	target.current_hp = 0

	var sys = _make_item_system()
	var bare_revive = {
		"id": "bare_revive",
		"name": "Generic Revive",
		"effects": {"revive": true},
	}
	sys._apply_item_effects(target, target, bare_revive)

	assert_true(target.is_alive, "Bare revive should still revive")
	assert_eq(target.current_hp, 50,
		"Bare revive should default to 50%% HP (got %d, expected 50)" % target.current_hp)


func test_revive_with_flat_heal_hp() -> void:
	# A revive item with heal_hp (flat) instead of percent should use that
	# as the revive amount.
	var target = _make_combatant(100)
	target.is_alive = false
	target.current_hp = 0

	var sys = _make_item_system()
	var flat_revive = {
		"id": "flat_revive",
		"name": "Flat Revive",
		"effects": {"revive": true, "heal_hp": 80},
	}
	sys._apply_item_effects(target, target, flat_revive)

	assert_true(target.is_alive, "Flat revive should still revive")
	assert_eq(target.current_hp, 80,
		"Flat revive should grant heal_hp directly (got %d, expected 80)" % target.current_hp)


func test_phoenix_down_no_double_apply() -> void:
	# Regression guard: heal_hp_percent must NOT be applied AGAIN as a
	# bonus on top of the revive. Pre-fix, if revive ran first, heal
	# would then add another 25% on top → 50% HP. Post-fix, the heal
	# step is skipped via _heal_consumed_by_revive.
	var target = _make_combatant(100)
	target.is_alive = false
	target.current_hp = 0

	var sys = _make_item_system()
	var phoenix_down = {
		"id": "phoenix_down",
		"effects": {"revive": true, "heal_hp_percent": 25},
	}
	sys._apply_item_effects(target, target, phoenix_down)

	# Strict: must equal 25, not 50 (50 would mean heal applied on top).
	assert_eq(target.current_hp, 25,
		"Phoenix Down must not double-apply heal (got %d, expected exactly 25)" % target.current_hp)


func test_revive_skipped_on_living_target() -> void:
	# Using a Phoenix Down on a living target: revive is no-op (target
	# already alive), but heal_hp_percent still applies as a normal heal.
	# This matches both old and new behavior — only the revive path
	# changed. Verify the heal still works (60 → 60+25 = 85).
	var target = _make_combatant(100)
	target.is_alive = true
	target.current_hp = 60

	var sys = _make_item_system()
	var phoenix_down = {
		"id": "phoenix_down",
		"effects": {"revive": true, "heal_hp_percent": 25},
	}
	sys._apply_item_effects(target, target, phoenix_down)

	# heal_hp_percent applied (revive didn't consume since target was alive).
	assert_eq(target.current_hp, 85,
		"Phoenix Down on living target should heal 25%% as normal (got %d, expected 85)" % target.current_hp)
	assert_true(target.is_alive, "Target should still be alive (no harm done)")


func test_potion_still_heals_living_target() -> void:
	# Make sure my reorder didn't break basic potions (no revive flag).
	var target = _make_combatant(100)
	target.current_hp = 40

	var sys = _make_item_system()
	var potion = {
		"id": "potion",
		"effects": {"heal_hp": 50},
	}
	sys._apply_item_effects(target, target, potion)

	assert_eq(target.current_hp, 90,
		"Potion should heal flat 50 HP (got %d, expected 90)" % target.current_hp)
