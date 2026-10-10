extends GutTest

## Three enemies stood on markers 100px apart while their sprites are ~200px tall, so they overlapped into one pile, and
## slot = index put a lone boss on the TOP marker, up in the sky. Markers are now spread down the field and the slot
## depends on how many enemies there are.

const BattleSceneRes := preload("res://src/battle/BattleScene.tscn")
const BattleScene := preload("res://src/battle/BattleScene.gd")


func _marker_ys() -> Array:
	var scene = BattleSceneRes.instantiate()
	var ys: Array = []
	for n in ["Enemy1Pos", "Enemy2Pos", "Enemy3Pos"]:
		var m: Node = scene.find_child(n, true, false)
		ys.append((m as Marker2D).position.y if m else -1.0)
	scene.free()
	return ys


func test_the_three_markers_leave_room_for_a_sprite_each() -> void:
	var ys := _marker_ys()
	assert_eq(ys.size(), 3, "CONTROL: three enemy markers")
	for i in range(1, ys.size()):
		assert_gt(float(ys[i]) - float(ys[i - 1]), 130.0, "marker %d sits well below marker %d (%s)" % [i + 1, i, str(ys)])


func test_a_lone_enemy_takes_the_middle_of_the_field() -> void:
	assert_eq(BattleScene.formation_slot(0, 1), 1, "one enemy stands on the middle marker, not the top one")


func test_two_enemies_take_the_ends() -> void:
	assert_eq([BattleScene.formation_slot(0, 2), BattleScene.formation_slot(1, 2)], [0, 2], "two enemies stand as far apart as the field allows")


func test_every_count_gives_each_enemy_its_own_slot() -> void:
	for count in range(1, 4):
		var seen := {}
		for i in count:
			var s: int = BattleScene.formation_slot(i, count)
			assert_true(s >= 0 and s < 3, "enemy %d of %d lands on a real marker (%d)" % [i, count, s])
			seen[s] = true
		assert_eq(seen.size(), count, "%d enemies take %d distinct slots" % [count, count])
