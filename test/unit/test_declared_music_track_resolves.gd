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


func test_the_resolver_SELECTS_the_track_from_a_real_enemy() -> void:
	## 🔑 cowir-battle, retracting the day's "sharpest instance": "A TEST THAT
	## CALLS THE REPAIRED FUNCTION DIRECTLY CANNOT TELL EITHER. That demonstrates
	## EXECUTION and says nothing about SELECTION. Reachability is not a property
	## you can observe from inside the thing you are reaching."
	##
	## Their seven tests were behavioural, watched a real signal, had arms both
	## ways — and every one invoked the entry point BY HAND, so all seven were
	## green while Pyrroth could not SELECT a single fire ability.
	##
	## The arms above have that shape: they pass "ice_wolf" as a LITERAL. This
	## one hands the resolver a real Combatant carrying a monster_type meta and
	## makes it derive the id itself, so the chain under test is
	##     enemy meta -> _get_dominant_monster_type -> _declared_music_track
	## which is what _on_battle_started actually walks.
	##
	## ⚠️ RESIDUAL LIMIT, stated rather than left to be discovered: this still
	## cannot prove _on_battle_started RUNS that chain. Instantiating it needs
	## the full scene tree and its _ready() builds UI that has no viewport here
	## (measured: add_child gives "Cannot call method 'add_theme_font_size_override'
	## on a null value"). The ORDERING arm in
	## test_boss_music_routing_regression is the only evidence for that half,
	## and it is a source pin. Two instruments, two halves, neither sufficient.
	var script: Script = load(BATTLE_SCENE_SCRIPT)
	var scene: Node = script.new()
	scene._enemy_spawner = BattleEnemySpawner.new(scene)

	var wolf := Combatant.new()
	wolf.initialize({"name": "Ice Wolf", "max_hp": 30, "max_mp": 0, "attack": 5, "defense": 3, "magic": 1, "speed": 8})
	wolf.set_meta("monster_type", "ice_wolf")
	var pack: Array[Combatant] = [wolf]
	scene.test_enemies = pack

	## Control: the id must come from the ENEMY, not from anything this test typed.
	var derived: String = scene._get_dominant_monster_type()
	assert_eq(derived, "ice_wolf",
		"CONTROL FAILED: the resolver read '%s' from the enemy meta, so the selection below is not being driven by real game state" % derived)
	assert_false(scene._check_for_boss(),
		"CONTROL: this fixture must take the MONSTER branch, not the boss branch")

	var selected: String = scene._declared_music_track(derived)
	wolf.free()
	scene.free()

	assert_eq(selected, "battle_wolf",
		"a real ice_wolf enemy selected '%s', not battle_wolf — the mapping resolves for a hand-typed string but the enemy-driven path does not reach it" % selected)

