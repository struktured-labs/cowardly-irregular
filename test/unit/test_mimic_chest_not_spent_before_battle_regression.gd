extends GutTest

## MimicChest used to set chest_<id> before the ambush existed, so leaving the floor during the teeth line deleted the chest with no fight.

const ContrarianDepthsScript = preload("res://src/maps/dungeons/ContrarianDepths.gd")
const MimicChestScript = preload("res://src/exploration/MimicChest.gd")


func test_a_mimic_left_before_the_ambush_is_not_spent() -> void:
	var cid := "zz_mimic_leave_%d" % Time.get_ticks_usec()
	var chest := MimicChestScript.new()
	chest.chest_id = cid
	chest.mimic_monster_id = "treasure_mimic"
	var fake_cave := ContrarianDepthsScript.new()
	autofree(fake_cave)
	chest.cave_ref = fake_cave
	add_child(chest)

	var battle_fired := [false]
	fake_cave.battle_triggered.connect(func(_enemies: Array) -> void:
		battle_fired[0] = true
	)

	chest._open_chest(null)
	assert_false(GameState.get_story_flag("chest_" + cid),
		"opening a mimic must not mark it spent until the ambush battle is actually emitted")

	# Floor change queue_frees the chest while the 0.6s teeth line is still up.
	chest.queue_free()
	await get_tree().create_timer(0.8).timeout

	assert_false(GameState.get_story_flag("chest_" + cid),
		"a mimic removed before its battle must still be closed on the next visit")
	assert_false(battle_fired[0], "a freed mimic must not start a battle after it is gone")
	GameState.story_flags.erase("chest_" + cid)
