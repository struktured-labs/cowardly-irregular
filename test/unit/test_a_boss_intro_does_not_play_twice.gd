extends GutTest

## MY OWN .654 FIX CAUSED A ROLLBACK. This is the repair and the guard.
##
## `lane/audio-hourly-0725` taught the encounter spawn path to translate
## monsters.json's `boss` flag into the is_boss/is_miniboss meta, which was
## right and fixed boss music, the BOSS BATTLE banner and the victory card. It
## ALSO copied spawn_forced_enemies' next line:
##     if monster_data.has("dialogue"):
##         _scene._boss_dialogue_data = monster_data["dialogue"]
## I listed that in my own READY as one of the nine readers coming back on. What
## I did not check is what an `intro` key DOES:
##
##     BattleScene:885
##         if _boss_dialogue_data.has("intro") and _boss_dialogue_data["intro"].size() > 0:
##             _show_boss_intro_dialogue()        # sets _waiting_for_dialogue
##         else:
##             BattleManager.start_battle(party_members, test_enemies)
##
## **The intro branch does not call start_battle.** It is deferred until the
## panel is dismissed — and start_battle is what used to overwrite the previous
## battle within a frame. So a dungeon boss now left BattleManager holding the
## finished fight while an intro sat open, and cowir-deploy's render smoke took
## 15k freed-instance errors on a spotlight duel's corpse.
##
## THE PRODUCT QUESTION cowir-main put to me — should a dungeon boss that
## already has a boss_cutscene_id ALSO get the monsters.json intro? — is
## answered by the data, unanimously: **12 of 12 dungeons that declare a
## boss_cutscene_id have intro lines for their boss.**
##     FireDragonCave   world1_pyrroth_intro    + fire_dragon intro=7
##     CastleHarmonia   world1_mordaine_intro   + chancellor_mordaine intro=2
##     ShadowDragonCave world1_umbraxis_intro   + shadow_dragon intro=10
## So the in-battle panel was a SECOND intro immediately after a full staged
## cutscene, for every dungeon boss in the game. No.
##
## The exploration path therefore carries `defeat` and `low_hp` — which are
## real, were genuinely dark before .654, and gate nothing — and not `intro`.
## The FORCED path is untouched: a scripted battle with no cutscene in front of
## it still gets its intro, which is the only place it was ever the first one.

const MONSTERS := "res://data/monsters.json"
const DUNGEON_DIR := "res://src/maps/dungeons"


class SpawnHost:
	extends Node
	var encounter_enemies: Array = []
	var forced_enemies: Array = []
	var autogrind_enemy_data: Array = []
	var force_miniboss: bool = false
	var enemy_positions: Array = [0, 0, 0]
	var test_enemies: Array = []
	## Typed exactly as BattleScene:269 declares it, so the assignment under test
	## behaves here the way it behaves in the scene.
	var _boss_dialogue_data: Dictionary = {}
	var log_lines: Array[String] = []

	func log_message(message: String) -> void:
		log_lines.append(message)

	func _update_ui() -> void:
		pass

	func _on_enemy_hp_changed(_o, _n, _i) -> void:
		pass

	func _on_enemy_died(_i) -> void:
		pass

	func _on_status_added(_s, _c) -> void:
		pass

	func _on_status_removed(_s, _c) -> void:
		pass

	func _on_status_tick_damage(_a, _s, _t) -> void:
		pass

	func _on_status_tick_heal(_a, _s, _t) -> void:
		pass


func _host() -> SpawnHost:
	var h := SpawnHost.new()
	add_child_autofree(h)
	return h


func _catalog() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS))
	assert_true(parsed is Dictionary, "SCOPE control: monsters.json did not parse")
	var d: Dictionary = parsed as Dictionary
	return d.get("monsters", d)


## The exact predicate BattleScene:885 branches on. Not a proxy for it.
func _would_block_start_battle(data: Dictionary) -> bool:
	return data.has("intro") and data["intro"].size() > 0


func _spawn(route: String, id: String) -> SpawnHost:
	var h := _host()
	var s := BattleEnemySpawner.new(h)
	if route == "encounter":
		h.encounter_enemies = [id]
		s.spawn_encounter_enemies()
	else:
		h.forced_enemies = [id]
		s.spawn_forced_enemies()
	return h


func test_the_symbols_this_file_drives_exist() -> void:
	## FLOOR, own frame. Every arm reaches these; a rename aborts the arm, and an
	## arm with a prior assert scores PASSING through the abort.
	var h := _host()
	var s := BattleEnemySpawner.new(h)
	for m in ["spawn_encounter_enemies", "spawn_forced_enemies"]:
		assert_true(s.has_method(str(m)),
			"BattleEnemySpawner.%s is gone — the arms below abort on it and score PASSING" % m)
	var script: Script = load("res://src/battle/BattleScene.gd")
	assert_not_null(script, "BattleScene.gd did not load")
	var sc: Node = script.new()
	assert_true("_boss_dialogue_data" in sc,
		"BattleScene._boss_dialogue_data is gone — this whole file is about what gets written there")
	assert_true(sc.has_method("_show_boss_intro_dialogue"),
		"_show_boss_intro_dialogue is gone — the branch this file defends no longer exists")
	sc.free()


func test_a_dungeon_boss_from_exploration_does_not_block_start_battle() -> void:
	## THE DEFECT. fire_dragon is reached only from FireDragonCave, which plays
	## world1_pyrroth_intro first, so its 7 in-battle intro lines are a second
	## intro AND they skip start_battle.
	var h := _spawn("encounter", "fire_dragon")
	assert_gt(h.test_enemies.size(), 0, "SCOPE control: fire_dragon did not spawn, so nothing below is measured")
	assert_false(_would_block_start_battle(h._boss_dialogue_data),
		"the exploration path armed a blocking intro (%d lines). BattleScene:885 then skips BattleManager.start_battle, leaving the PREVIOUS battle active — 15k freed-instance errors in cowir-deploy's render smoke on .654" % [h._boss_dialogue_data.get("intro", []).size()])


func test_the_dialogue_that_does_not_gate_anything_is_still_carried() -> void:
	## The fix must not be "drop the dialogue". defeat and low_hp were genuinely
	## dark on this path before .654 and neither gates start_battle, so both stay.
	var h := _spawn("encounter", "fire_dragon")
	var d: Dictionary = h._boss_dialogue_data
	assert_gt(d.get("defeat", []).size(), 0,
		"defeat dialogue was dropped along with the intro; it does not gate start_battle and Pyrroth has 4 lines")
	assert_gt(d.get("low_hp", []).size(), 0,
		"low_hp dialogue was dropped along with the intro; it does not gate start_battle")


func test_CONTROL_the_forced_path_keeps_its_intro() -> void:
	## Without this the fix could be "never carry an intro anywhere", which would
	## silence the intro for a scripted battle that has no cutscene in front of
	## it — the one case where the panel IS the first intro.
	var h := _spawn("forced", "fire_dragon")
	assert_gt(h.test_enemies.size(), 0, "CONTROL: the forced path spawned nothing")
	assert_true(_would_block_start_battle(h._boss_dialogue_data),
		"CONTROL FAILED: the forced path lost its intro too. The fix is too broad — a scripted boss battle with no preceding cutscene now has no intro at all")


func test_every_dungeon_that_plays_a_cutscene_is_covered() -> void:
	## Corpus derived from the DUNGEON SCRIPTS, not from the spawner, so a boss
	## whose double intro I did not think of is still a case. Measured 12 of 12
	## at authoring time; the assert is that none of them blocks.
	var pairs: Array = []
	var dir := DirAccess.open(DUNGEON_DIR)
	assert_not_null(dir, "SCOPE control: could not open %s, so this sweep walks nothing" % DUNGEON_DIR)
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var src: String = FileAccess.get_file_as_string("%s/%s" % [DUNGEON_DIR, f])
		if not src.contains("boss_cutscene_id = \""):
			continue
		var bid := src.get_slice("boss_id = \"", 1).get_slice("\"", 0) if src.contains("boss_id = \"") else ""
		if bid != "":
			pairs.append(bid)
	assert_gt(pairs.size(), 5,
		"SCOPE control: only %d dungeons found declaring a boss_cutscene_id — the walk is not reaching them" % pairs.size())

	var cat: Dictionary = _catalog()
	var blocking: Array[String] = []
	var had_intro: int = 0
	for bid in pairs:
		var rec: Dictionary = cat.get(str(bid), {}) as Dictionary
		var dlg: Variant = rec.get("dialogue", {})
		if dlg is Dictionary and (dlg as Dictionary).get("intro", []).size() > 0:
			had_intro += 1
		var h := _spawn("encounter", str(bid))
		if h.test_enemies.is_empty():
			continue
		if _would_block_start_battle(h._boss_dialogue_data):
			blocking.append(str(bid))

	assert_gt(had_intro, 5,
		"PREMISE moved: only %d of %d cutscene dungeons still have intro lines in the catalog. If that is now 0 the double intro is gone from the data and this guard is about nothing — re-derive it." % [had_intro, pairs.size()])
	assert_eq(blocking.size(), 0,
		"%d of %d dungeon bosses still arm a blocking intro from the exploration path: %s" % [blocking.size(), pairs.size(), blocking])


func test_the_fix_does_not_erase_the_intro_from_the_shared_catalog() -> void:
	## ⛔ THE TRAP IN THE OBVIOUS IMPLEMENTATION. load_monsters_data() returns
	## EncounterSystem.monster_database — the CACHED catalog, shared for the whole
	## session. Erasing "intro" from the dictionary it handed back would delete
	## those lines for every later consumer, including the forced path and the
	## bestiary, and the damage would outlive the battle that caused it.
	##
	## So the fix duplicates before erasing, and this arm is what proves it: the
	## CONTROL above spawns forced on a fresh host and would pass either way,
	## because it never runs an encounter spawn first. This one does both, in
	## order, in one process.
	var enc := _spawn("encounter", "fire_dragon")
	assert_false(_would_block_start_battle(enc._boss_dialogue_data),
		"PREMISE: the encounter spawn did not strip the intro, so the mutation question below is moot")

	var forced := _spawn("forced", "fire_dragon")
	assert_true(_would_block_start_battle(forced._boss_dialogue_data),
		"the forced path lost its intro AFTER an encounter spawn ran in the same process — the fix erased 'intro' from the cached catalog instead of from a copy, so it is gone session-wide")

	## And the catalog itself, read directly rather than through a spawn.
	var cat: Dictionary = _catalog()
	assert_gt((cat.get("fire_dragon", {}) as Dictionary).get("dialogue", {}).get("intro", []).size(), 0,
		"monsters.json on disk no longer has fire_dragon's intro — if this fails the data was edited, not the code")
