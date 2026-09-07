extends GutTest

## Juice fix 2026-07-04: the floating enemy HP bar refreshed only in
## _update_ui() (called at action boundaries), so when a hit landed the
## damage number popped + the screen shook, but the enemy's HP bar didn't
## deplete until a beat later. _on_damage_dealt now refreshes the bar so
## it tracks the hit in real time.

const SCENE := "res://src/battle/BattleScene.gd"


func _read() -> String:
	return FileAccess.get_file_as_string(SCENE)


func test_damage_handler_refreshes_enemy_hp_bar() -> void:
	var src := _read()
	var fn: int = src.find("func _on_damage_dealt")
	assert_gt(fn, -1, "_on_damage_dealt must exist")
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_true(body.contains("_update_enemy_hp_bars()"),
		"_on_damage_dealt must refresh the floating enemy HP bar so it depletes with the damage number, not a beat later")


func test_hp_bar_update_still_guards_freed_enemies() -> void:
	# Calling it every damage means it must stay defensive against
	# already-freed enemies (a killing blow frees the target).
	var src := _read()
	var fn: int = src.find("func _update_enemy_hp_bars")
	assert_gt(fn, -1)
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_true(body.contains("is_instance_valid(enemy)"),
		"per-damage refresh must skip freed enemies (killing blow frees the target mid-loop)")
	assert_true(body.contains("max(1, enemy.max_hp)"),
		"ratio must guard divide-by-zero on a 0-max-HP enemy")
