extends GutTest

## Playtest 2026-07-14: "sometimes a party member is fighting a monster on
## the rhs screen who the monster itself was finishing an attack on a party
## member, it needs to let the monster return back to position before the
## party attacks it."
##
## Root: _animate_melee_attack captured target_sprite.position at tween
## start — if the target was still mid-return from its own attack, the
## attacker lunged toward the transient position and visually chased empty
## space until the target's tween completed.
##
## Fix: spawn now stamps home_position meta on every party AND enemy
## sprite; the melee tween reads that first, falling back to current
## position only if unstamped. Attack lands where the target WILL be.


func test_party_spawn_stamps_home_position_meta() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("_party_base_positions.append(base_pos)")
	assert_gt(i, -1)
	var window := src.substr(maxi(0, i - 300), 400)
	assert_true("sprite.set_meta(\"home_position\", base_pos)" in window,
		"party spawn must stamp home_position meta — attack tweens use it to target the settled position")


func test_enemy_spawn_stamps_home_position_meta() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("_enemy_base_positions.append(base_enemy_pos)")
	assert_gt(i, -1)
	var window := src.substr(maxi(0, i - 300), 400)
	assert_true("sprite.set_meta(\"home_position\", base_enemy_pos)" in window,
		"enemy spawn must stamp home_position meta — otherwise a party attack lands where the enemy WAS mid-tween, not where it settles")


func test_melee_tween_reads_target_home_meta_not_transient_position() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _animate_melee_attack")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 800)
	assert_true("target_sprite.get_meta(\"home_position\"" in body,
		"melee tween must resolve target position via home_position meta — target_sprite.position is transient during the target's own attack tween")
	assert_false("var target_pos = target_sprite.position" in body,
		"the raw target_sprite.position read is the bug — must use the meta form so mid-tween targets don't cause visual chase")
