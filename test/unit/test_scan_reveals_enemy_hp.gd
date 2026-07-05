extends GutTest

## Bugfix 2026-07-05: the Scan ability (v3.33.11) set intel_revealed to surface an
## enemy's elemental weaknesses, but exact-HP display gated only on
## _revealed_enemies (populated by ATTACKING). So a Scan showed "Weak: Fire" while
## the HP line stayed the vague "Wounded" — a classic Scan reveals BOTH.
## _enemy_hp_revealed now also honors intel_revealed, so a Scanned enemy shows its
## exact HP: N/M.

const UIM := preload("res://src/battle/BattleUIManager.gd")


func _enemy() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Foe"
	c.max_hp = 100
	c.current_hp = 60
	return c


func test_unrevealed_enemy_hides_exact_hp() -> void:
	assert_false(UIM.new(null)._enemy_hp_revealed(_enemy()),
		"an untouched, unscanned enemy hides exact HP (shows the vague hint instead)")


func test_scanned_enemy_reveals_hp() -> void:
	var e := _enemy()
	e.set_meta("intel_revealed", true)  # exactly what _execute_scan_effect sets
	assert_true(UIM.new(null)._enemy_hp_revealed(e),
		"a Scanned enemy (intel_revealed) now shows exact HP, matching its revealed weaknesses")


func test_attacked_enemy_still_reveals_hp() -> void:
	var uim = UIM.new(null)
	var e := _enemy()
	uim._revealed_enemies[e] = true  # what reveal_enemy_stats sets on attack
	assert_true(uim._enemy_hp_revealed(e),
		"the existing attack-reveals-HP behavior is preserved")
