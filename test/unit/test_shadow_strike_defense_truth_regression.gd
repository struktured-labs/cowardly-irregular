extends GutTest

## Regression (2026-07-08, follow-up to F2): shadow_strike's log and comments
## claimed "defense ignored" but BOTH live and headless call take_damage()
## with full physical defense — no zero-defense path exists (is_magical only
## halves). The lying text is fixed; this pins BOTH truths:
##   1. the mechanic — defense measurably reduces shadow_strike damage
##      (if struktured later rules to honor the flavor, update this test WITH
##      that ruling so the buff is deliberate, not drift)
##   2. the text — neither battle path claims defense-ignored for it

const HBR := preload("res://src/autogrind/HeadlessBattleResolver.gd")


func _make(cname: String, attack: int, defense: int, hp: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = cname
	c.attack = attack
	c.defense = defense
	c.max_hp = hp
	c.current_hp = hp
	c.current_ap = 4
	c.is_alive = true
	return c


func _headless_shadow_damage(enemy_def: int) -> int:
	var hero := _make("Hero", 40, 0, 100)
	var enemy := _make("Foe", 0, enemy_def, 1_000_000)
	enemy.current_hp = 999_999  # off full HP so the 2x bonus stays out of the comparison
	var resolver = HBR.new()
	resolver._player_party = [hero]
	resolver._enemy_party = [enemy]
	resolver._execute_group_physical([hero], "shadow_strike")
	return 999_999 - enemy.current_hp


func test_shadow_strike_defense_actually_applies() -> void:
	var vs_no_def := _headless_shadow_damage(0)
	var vs_def := _headless_shadow_damage(30)
	assert_gt(vs_no_def, 0, "sanity: shadow_strike deals damage")
	assert_lt(vs_def, vs_no_def,
		"defense must reduce shadow_strike damage — it was never actually ignored (F2 finding)")


func test_no_battle_path_claims_defense_ignored_for_shadow_strike() -> void:
	for path in ["res://src/battle/BattleManager.gd", "res://src/autogrind/HeadlessBattleResolver.gd"]:
		var src := FileAccess.get_file_as_string(path)
		var i := src.find("\"shadow_strike\":")
		while i != -1:
			var block := src.substr(i, 900)
			assert_false("defense ignored" in block.to_lower() or "ignores defense" in block.to_lower(),
				"%s shadow_strike block must not claim defense is ignored (take_damage applies it)" % path)
			i = src.find("\"shadow_strike\":", i + 1)
