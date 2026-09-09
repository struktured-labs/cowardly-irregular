extends GutTest

## _declared_music_track must RETURN the mapping, not merely be called (2026-09-09).
##
## test_boss_music_routing_regression pins the wiring with SOURCE-TEXT arms:
## the call appears, and it precedes the masterite arm. Those certify that the
## code EXISTS. They say nothing about whether it resolves.
##
## Measured, not argued — stub the helper to `return ""` and:
##     test_boss_music_routing_regression   3/3 GREEN
## while every one of the 12 monster mappings is dead: ice_wolf drops back to
## the generic world bed, giant_bat drops back, and nothing reports it.
##
## cowir-battle demonstrated the identical blind spot in their own landed fix
## the same day, and cowir-main's Mode-7 line is why it matters: "a fix that
## swaps one dead lookup for another is indistinguishable from a fix" — the
## 2026-07-18 audit replaced a dead detector with is_mode7(), which had the
## same defect, and the symptom came back for ten weeks.
##
## So this file calls the resolver and checks the VALUE.

const CASES := {
	"ice_wolf": "battle_wolf",
	"giant_bat": "battle_bat",
	"treasure_mimic": "battle_rogue_mailbox",
}


const BATTLE_SCENE_SCRIPT := "res://src/battle/BattleScene.gd"


func _resolver() -> Node:
	## BattleScene has no class_name, so it must be loaded by path — referencing
	## it bare drops the whole script and GUT exits 3 (nothing ran), which is
	## how this file failed on its first run.
	var script: Script = load(BATTLE_SCENE_SCRIPT)
	assert_not_null(script, "SCOPE control: BattleScene.gd did not load; nothing below measures anything")
	var scene: Node = script.new()
	scene._enemy_spawner = BattleEnemySpawner.new(scene)
	return scene


func test_declared_tracks_actually_resolve() -> void:
	var scene := _resolver()
	assert_not_null(scene._enemy_spawner,
		"SCOPE control: no spawner, so the helper would return \"\" for every input and this test would prove nothing")

	## Control FIRST: a monster with NO music_track must return empty, and one
	## WITH one must not. If both come back the same the probe is inert.
	var unmapped: String = scene._declared_music_track("slime")
	assert_eq(unmapped, "",
		"CONTROL: an unmapped monster returned %s — the helper is inventing values" % [unmapped])

	var failures: Array[String] = []
	for mid in CASES.keys():
		var got: String = scene._declared_music_track(str(mid))
		if got != str(CASES[mid]):
			failures.append("%s -> %s (expected %s)" % [mid, got if got != "" else "<empty>", CASES[mid]])
	scene.free()

	assert_eq(failures.size(), 0,
		"declared music_track did not RESOLVE (%d): %s — the source-text guard stays green on this, so a dead helper ships silently and every mapped monster falls back to the generic world bed" % [failures.size(), failures])


func test_an_unmapped_boss_falls_through_rather_than_erroring() -> void:
	var scene := _resolver()
	assert_eq(scene._declared_music_track("chancellor_mordaine"), "",
		"Mordaine has no music_track key; a non-empty answer means the helper is reading the wrong field")
	assert_eq(scene._declared_music_track("no_such_monster_zzz"), "",
		"an unknown id must return empty, not crash or invent")
	scene.free()
