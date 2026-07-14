extends GutTest

## tick 85 regression: _cull_far_monsters must call deactivate()
## before queue_free() — symmetric with _despawn_all. Pre-fix, only
## the all-clear path deactivated; the distance-based culling path
## queue_free'd straight, leaving a ~1-frame window where a queued
## body_entered signal could trigger a battle for a monster that
## was already being despawned.
##
## Concrete user-visible bug: player walks past the DESPAWN_DISTANCE
## edge and brushes a culling monster, getting a battle for an enemy
## that should have vanished from the overworld.

const MONSTER_SPAWNER := "res://src/exploration/MonsterSpawner.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body(fn_name: String) -> String:
	var src := _read(MONSTER_SPAWNER)
	var idx: int = src.find("func " + fn_name)
	assert_gt(idx, -1, "%s must exist in MonsterSpawner.gd" % fn_name)
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_cull_far_monsters_deactivates_before_queue_free() -> void:
	# Pin: deactivate() call must appear in _cull_far_monsters body
	# BEFORE queue_free() — order matters because queue_free is
	# end-of-frame.
	var body := _body("_cull_far_monsters")
	var deact_idx: int = body.find("m.deactivate()")
	var free_idx: int = body.find("m.queue_free()")
	assert_gt(deact_idx, -1,
		"_cull_far_monsters must call m.deactivate() — otherwise late body_entered signals trigger battles after the cull")
	assert_gt(free_idx, -1,
		"_cull_far_monsters must still call m.queue_free()")
	assert_lt(deact_idx, free_idx,
		"deactivate() must precede queue_free() — queue_free is end-of-frame, signals can fire in the gap")


func test_deactivate_call_guarded_by_has_method() -> void:
	# Defensive: matches the _despawn_all pattern. A future
	# RoamingMonster refactor that renames the method would otherwise
	# crash here on every cull tick.
	var body := _body("_cull_far_monsters")
	assert_true(body.contains("if m.has_method(\"deactivate\"):"),
		"_cull_far_monsters must guard m.deactivate() with has_method check — matches _despawn_all's defensive pattern")


func test_despawn_all_pattern_unchanged() -> void:
	# Don't regress the original _despawn_all sequence while fixing
	# the parallel _cull_far_monsters.
	var body := _body("_despawn_all")
	var deact_idx: int = body.find("m.deactivate()")
	var free_idx: int = body.find("m.queue_free()")
	assert_gt(deact_idx, -1, "_despawn_all must still call deactivate()")
	assert_gt(free_idx, -1, "_despawn_all must still call queue_free()")
	assert_lt(deact_idx, free_idx,
		"_despawn_all ordering: deactivate before queue_free (pre-existing pattern)")
