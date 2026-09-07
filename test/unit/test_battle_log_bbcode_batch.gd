extends GutTest

## tick 238: continues tick 237's battle-log BBCode refactor.
##
## 10 more BattleManager emits now route through
## AccessibilityPalette.penalty_bbcode() / .bonus_bbcode():
##
##   Penalty (red default / magenta accessibility):
##     - All exposed (group debuff)
##     - Chaos Theory backfire
##     - Weakened (ATK debuff)
##     - Slows down (SPD debuff)
##     - Despair (all-stat debuff)
##     - PERMANENTLY KILLED (permadeath)
##
##   Bonus (lime default / cyan accessibility):
##     - Cleansed by Limit Break
##     - Hedged buff
##     - CIRCUIT BREAKER (band-reduce + AP gain)
##     - Regen buff
##
## Total post-237/238: ~15 emits use the palette helpers.
## BattleManager still has ~15 inline [color=red]/[color=lime]/
## [color=green] emits remaining (mostly boss taunts where
## red is intentional flavor, and a few smaller buffs/debuffs).

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Penalty refactors ────────────────────────────────────────────────

func test_all_exposed_uses_penalty_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]All participants are now exposed! (-2 AP, 1.5x damage taken)[/color]\" % AccessibilityPalette.penalty_bbcode()"),
		"'All exposed' must use penalty_bbcode()")


func test_chaos_theory_backfire_uses_penalty_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]★ Chaos Theory — BACKFIRE! Party takes recoil damage! ★[/color]\" % AccessibilityPalette.penalty_bbcode()"),
		"Chaos Theory backfire must use penalty_bbcode()")


func test_weakened_uses_penalty_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]%s is weakened![/color] (ATK -%d%% for %d turns)\" % [AccessibilityPalette.penalty_bbcode()"),
		"ATK debuff (weakened) must use penalty_bbcode()")


func test_slows_down_uses_penalty_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]%s slows down![/color] (SPD -%d%% for %d turns)\" % [AccessibilityPalette.penalty_bbcode()"),
		"SPD debuff (slows down) must use penalty_bbcode()")


func test_despair_uses_penalty_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]%s sinks into Despair![/color] (all stats -%d%% for %d turns)\" % [AccessibilityPalette.penalty_bbcode()"),
		"Despair (all-stat debuff) must use penalty_bbcode()")


func test_permadeath_uses_penalty_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]☠ %s has been PERMANENTLY KILLED![/color]\" % [AccessibilityPalette.penalty_bbcode(), target.combatant_name]"),
		"Permadeath must use penalty_bbcode()")


# ── Bonus refactors ──────────────────────────────────────────────────

func test_cleansed_uses_bonus_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]%s is cleansed by the Limit Break![/color]\" % [AccessibilityPalette.bonus_bbcode(), p.combatant_name]"),
		"Limit Break cleanse must use bonus_bbcode()")


func test_hedged_uses_bonus_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]%s is hedged![/color]\" % [AccessibilityPalette.bonus_bbcode(), target.combatant_name]"),
		"Hedge buff must use bonus_bbcode()")


func test_circuit_breaker_uses_bonus_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]CIRCUIT BREAKER![/color] Band reduced, %s gains +1 AP\" % [AccessibilityPalette.bonus_bbcode(), caster.combatant_name]"),
		"CIRCUIT BREAKER must use bonus_bbcode()")


func test_regen_uses_bonus_bbcode() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("[color=%s]%s gains Regen![/color] (HP restore for %d turns)\" % [AccessibilityPalette.bonus_bbcode(), target.combatant_name, duration]"),
		"Regen buff must use bonus_bbcode()")


# ── Coverage count: cumulative across ticks 237 + 238 ────────────────

func test_cumulative_palette_usage_count() -> void:
	var src := _read(BATTLE_MANAGER)
	var penalty_count: int = 0
	var idx: int = 0
	while true:
		var next: int = src.find("AccessibilityPalette.penalty_bbcode()", idx)
		if next < 0:
			break
		penalty_count += 1
		idx = next + 1
	var bonus_count: int = 0
	idx = 0
	while true:
		var next: int = src.find("AccessibilityPalette.bonus_bbcode()", idx)
		if next < 0:
			break
		bonus_count += 1
		idx = next + 1
	# Tick 237 = 4 penalty + 1 bonus. Tick 238 = 6 penalty + 4 bonus.
	# Total ≥10 penalty + ≥5 bonus.
	assert_gte(penalty_count, 10,
		"BattleManager must have ≥10 penalty_bbcode usages after tick 238 (got %d)" % penalty_count)
	assert_gte(bonus_count, 5,
		"BattleManager must have ≥5 bonus_bbcode usages after tick 238 (got %d)" % bonus_count)


# ── Cross-pin: tick 237 representative sites still wired ─────────────

func test_tick_237_sites_still_use_palette() -> void:
	var src := _read(BATTLE_MANAGER)
	# Spot-check tick 237's 5 representative refactors didn't regress.
	assert_true(src.contains("[color=%s]%s cannot defer while exposed![/color]\" % [AccessibilityPalette.penalty_bbcode(), current_combatant.combatant_name]"),
		"tick 237 cannot-defer site preserved")
	assert_true(src.contains("[color=%s]%s escaped successfully![/color]\" % [AccessibilityPalette.bonus_bbcode(), caster.combatant_name]"),
		"tick 237 escape-success site preserved")


# ── Cross-pin: helper definitions preserved in palette ───────────────

func test_palette_helpers_preserved() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/AccessibilityPalette.gd")
	assert_true(src.contains("static func bonus_bbcode() -> String:"),
		"AccessibilityPalette.bonus_bbcode still present")
	assert_true(src.contains("static func penalty_bbcode() -> String:"),
		"AccessibilityPalette.penalty_bbcode still present")
