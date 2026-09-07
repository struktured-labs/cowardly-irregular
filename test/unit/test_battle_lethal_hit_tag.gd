extends GutTest

## Feature 2026-07-05: the ability→enemy and attack→enemy submenus showed
## "Goblin (12 HP) ~15 dmg" but never flagged that the hit would KILL. The
## single most valuable targeting cue — finish this enemy — is now a " [KILL]"
## tag appended when the damage estimate meets or exceeds the target's current
## HP. Immune targets estimate 0 dmg (v3.33.3), so they never earn the tag.

const BCM := preload("res://src/battle/BattleCommandMenu.gd")


func _tag(est_dmg: int, current_hp: int) -> String:
	return BCM.new(null)._lethal_tag(est_dmg, current_hp)


func test_overkill_is_lethal() -> void:
	assert_eq(_tag(15, 12), " [KILL]", "an estimate above the target's HP flags a kill")


func test_exact_hp_is_lethal() -> void:
	assert_eq(_tag(12, 12), " [KILL]", "an estimate exactly equal to HP still flags a kill")


func test_nonlethal_is_blank() -> void:
	assert_eq(_tag(5, 12), "", "an estimate below HP shows no kill tag")


func test_immune_zero_estimate_never_kills() -> void:
	assert_eq(_tag(0, 30), "", "a 0-damage (immune) estimate must never read as lethal")


func test_dead_target_guard() -> void:
	assert_eq(_tag(100, 0), "", "a 0-HP target (already down) doesn't earn a redundant KILL tag")
