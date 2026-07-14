extends GutTest

## Emergent-loop contract (2026-07-09, cowir-autogrind's cross-surface
## confirmation msg 2331): Scriptweaver's now-real constant_modification
## writes the SAME game_constants that autogrind's reward paths read
## (HBR ~807/810/836 — whose comment names Scriptweaver as the intended
## writer). Meta-job turns the dial -> autogrind reaps, headless + live,
## player-initiated + visible (no-hidden-yield-tax compliant). This pins the
## loop so neither side can silently drift: doubling exp_multiplier must
## double headless EXP yield.

const HBR := preload("res://src/autogrind/HeadlessBattleResolver.gd")


func _strong_party() -> Array:
	# assign_job RESETS stats to job-level-1 — level through the real growth
	# path (like the balance report) so the win is guaranteed, not assumed.
	var c := Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": "Weaver", "max_hp": 150, "max_mp": 50, "attack": 25,
		"defense": 15, "magic": 12, "speed": 12})
	JobSystem.assign_job(c, "fighter")
	c.gain_job_exp(100 * 15 * 14 / 2)  # -> level 15
	c.current_hp = c.max_hp
	c.current_ap = 2
	return [c]


func _weak_enemy() -> Array:
	var e := Combatant.new()
	add_child_autofree(e)
	e.initialize(EncounterSystem._create_enemy_data("goblin"))
	e.set_meta("monster_type", "goblin")
	return [e]


func _exp_for_multiplier(mult: float) -> int:
	var prev = GameState.game_constants.get("exp_multiplier", 1.0)
	GameState.game_constants["exp_multiplier"] = mult
	var resolver = HBR.new()
	var result: Dictionary = resolver.resolve_battle(_strong_party(), _weak_enemy())
	GameState.game_constants["exp_multiplier"] = prev
	assert_true(bool(result.get("victory", false)), "stacked-odds battle must be a win")
	return int(result.get("exp_gained", -1))


func test_scriptweaver_dial_reaches_autogrind_yield() -> void:
	var base := _exp_for_multiplier(1.0)
	var doubled := _exp_for_multiplier(2.0)
	assert_gt(base, 0, "baseline yield exists (result carries an exp field)")
	assert_eq(doubled, base * 2,
		"exp_multiplier 2.0 must exactly double headless EXP — the Scriptweaver->autogrind loop contract")
