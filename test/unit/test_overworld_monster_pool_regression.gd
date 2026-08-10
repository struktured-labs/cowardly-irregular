extends GutTest

## Regression: only slimes spawned on W2+ overworlds (struktured, in-play 2026-08-09).
##
## MonsterSpawner._get_valid_pool_for_overworld() filtered the per-world roster against a
## hardcoded MEDIEVAL sprite whitelist (slime/bat/goblin/...). Every W2+ themed id failed
## the filter, so the pool collapsed to ["slime"] — wrong ART *and* wrong ENCOUNTER (the
## player fought slimes in the futuristic world). Silent: the suite was green because nothing
## asserted the pool's CONTENT. Fix: trust the curated roster, fall back to slime only when
## the roster is genuinely empty.

const SpawnerScript = preload("res://src/exploration/MonsterSpawner.gd")

const W2_ROSTER := ["spiteful_crow", "new_age_retro_hippie", "skate_punk", "unassuming_dog", "cranky_lady"]
const W4_ROSTER := ["memory_leak", "rogue_process", "recursive_loop", "data_wraith", "firewall_sentinel"]


func _spawner() -> Node:
	var s = SpawnerScript.new()
	add_child_autofree(s)
	return s


func test_themed_roster_survives_the_pool_filter() -> void:
	var s := _spawner()
	s.set_enemy_pool(W2_ROSTER)
	var pool: Array = s._get_valid_pool_for_overworld()
	# The discriminating assert: EVERY themed id must be spawnable, not just "not-slime".
	for id in W2_ROSTER:
		assert_true(id in pool, "%s must survive the pool filter — it was silently dropped to slime" % id)
	assert_false(pool == ["slime"], "the roster must not collapse to the slime fallback")


func test_second_world_roster_also_survives() -> void:
	# A different world, so a fix that hardcodes one roster's ids does not pass.
	var s := _spawner()
	s.set_enemy_pool(W4_ROSTER)
	var pool: Array = s._get_valid_pool_for_overworld()
	for id in W4_ROSTER:
		assert_true(id in pool, "%s (futuristic) must survive the filter" % id)


func test_empty_roster_still_falls_back_to_slime() -> void:
	# CONTROL: the fallback must remain for a genuinely empty pool, or the fix over-reached.
	# set_enemy_pool coerces empty -> default trio, so exercise the private field directly.
	var s := _spawner()
	s._enemy_pool = []
	assert_eq(s._get_valid_pool_for_overworld(), ["slime"],
		"an empty roster must still yield the slime safety net")
