extends GutTest

## A dungeon boss reached from exploration never announced itself as one.
##
## Measured in struktured's 2026-10-05 session log, not argued. Every boss he
## fought routed through `[ENCOUNTER] Spawning encounter enemies`, because
## GameLoop._on_exploration_battle_triggered passes `is_encounter = true` for
## EVERY battle an exploration scene emits — and the dragons, the Warden and
## Mordaine are all emitted that way (DragonCave:872, CastleHarmonia:281,
## WhisperingCave:726). That lands them in spawn_encounter_enemies, which was
## the one spawn path that never translated the catalog's `boss` flag into the
## `is_boss` / `is_miniboss` meta. spawn_forced_enemies does it at :481.
##
## What he actually got, from that log:
##     [MUSIC] Playing from manifest: battle_medieval        <- the generic bed
##     [MUSIC] Playing chancellor_mordaine battle theme (battle_chancellor_mordaine)
##     [color=gray]1 Chancellor Mordaine appeared![/color]
## and `grep -c 'BOSS BATTLE' godot.log` -> 0 for the whole session. The World 1
## final boss was announced in gray, in the same shape as "1 Imp appeared!",
## over the random-encounter music, while her own authored track
## ("boss_mordaine" — A Sound Like a Verdict) sat unplayed on disk.
##
## The meta is the mechanism, so this file asserts the meta AND the predicate
## that consumes it. `is_boss` has nine other readers (boss music selection,
## the BOSS BATTLE banner, VictoryOverlay's grade and headline, the boss damage
## passive, show_boss_hp, boss defeat dialogue, the gloat name, and the LLM
## boss-strategy loop in BattleManager:951) — every one of them was dark for
## these fights. Fixing the flag is what turns them all back on, which is why
## this guard sits on the flag and not on the music.

const MONSTERS := "res://data/monsters.json"
const BATTLE_SCENE_SCRIPT := "res://src/battle/BattleScene.gd"

## Named in the log above. Pinned by NAME so a rename reds here rather than
## quietly shrinking the corpus the derived arm walks.
const WITNESSES := ["chancellor_mordaine", "lightning_dragon", "fire_dragon", "castle_warden"]


class SpawnHost:
	extends Node
	var encounter_enemies: Array = []
	var forced_enemies: Array = []
	var autogrind_enemy_data: Array = []
	var force_miniboss: bool = false
	var enemy_positions: Array = [0, 0, 0]
	var test_enemies: Array = []
	var _boss_dialogue_data = null
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
	var host := SpawnHost.new()
	add_child_autofree(host)
	return host


func _catalog() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS))
	assert_true(parsed is Dictionary, "SCOPE control: monsters.json did not parse as a Dictionary")
	var d: Dictionary = parsed as Dictionary
	return d.get("monsters", d)


## Spawn `ids` down the exploration path and report each enemy's boss meta.
func _spawn_as_encounter(ids: Array) -> Array:
	var host := _host()
	var spawner := BattleEnemySpawner.new(host)
	host.encounter_enemies = ids.duplicate()
	spawner.spawn_encounter_enemies()
	var out: Array = []
	for e in host.test_enemies:
		if is_instance_valid(e):
			out.append({
				"monster_type": str(e.get_meta("monster_type", "")),
				"is_boss": bool(e.get_meta("is_boss", false)),
				"is_miniboss": bool(e.get_meta("is_miniboss", false)),
			})
	return out


func test_the_symbols_this_file_drives_exist() -> void:
	## FLOOR. Every arm below reaches these on a live instance, so a rename
	## aborts the enclosing arm — and an arm that already asserted once scores
	## PASSING through that abort (CLAUDE.md's rung 3). This arm asserts
	## nothing else, so it is the one place a missing symbol is named.
	var host := _host()
	var spawner := BattleEnemySpawner.new(host)
	for m in ["spawn_encounter_enemies", "spawn_forced_enemies", "load_monsters_data"]:
		assert_true(spawner.has_method(str(m)),
			"BattleEnemySpawner.%s is gone — every arm below aborts on it and the ones with a prior assert score PASSING" % m)

	var script: Script = load(BATTLE_SCENE_SCRIPT)
	assert_not_null(script, "BattleScene.gd did not load; the consequence arm would measure nothing")
	var scene: Node = script.new()
	for m in ["_check_for_boss", "_get_boss_type"]:
		assert_true(scene.has_method(str(m)),
			"BattleScene.%s is gone — the consequence arm aborts and cannot red" % m)
	scene.free()


func test_a_plain_encounter_monster_is_not_promoted_to_a_boss() -> void:
	## CONTROL, and it runs first on purpose: if the fix tagged everything, the
	## defect arm below would pass for the wrong reason and read as a repair.
	var rows: Array = _spawn_as_encounter(["slime", "slime"])
	assert_gt(rows.size(), 0, "CONTROL: the encounter path spawned nothing, so nothing below is measured")
	var cat: Dictionary = _catalog()
	assert_false(bool((cat.get("slime", {}) as Dictionary).get("boss", false)),
		"CONTROL PREMISE: slime is flagged boss in the catalog, so it is the wrong control — pick another")
	for r in rows:
		assert_false(bool(r["is_boss"]),
			"a slime came back is_boss — the tagging is unconditional, so the boss arms below prove nothing")
		assert_false(bool(r["is_miniboss"]), "a slime came back is_miniboss")


func test_the_bosses_he_fought_are_tagged_as_bosses() -> void:
	## The four from the log, each spawned exactly as exploration spawns it.
	var cat: Dictionary = _catalog()
	var missing: Array[String] = []
	var absent: Array[String] = []
	for wid in WITNESSES:
		var id: String = str(wid)
		var rec: Dictionary = cat.get(id, {}) as Dictionary
		if rec.is_empty():
			absent.append(id)
			continue
		if not (rec.get("boss", false) or rec.get("miniboss", false)):
			absent.append("%s (no longer flagged boss in the catalog)" % id)
			continue
		var rows: Array = _spawn_as_encounter([id])
		if rows.is_empty():
			missing.append("%s spawned nothing" % id)
			continue
		if not bool(rows[0]["is_boss"]):
			missing.append(id)

	assert_eq(absent.size(), 0,
		"PREMISE moved (%d): %s — these ids drove the measurement in the log; re-derive the witnesses" % [absent.size(), absent])
	assert_eq(missing.size(), 0,
		"a boss reached from exploration came back untagged (%d): %s — this is the gray \"1 Chancellor Mordaine appeared!\" over battle_medieval that struktured heard on 2026-10-05" % [missing.size(), missing])


func test_every_catalog_boss_is_tagged_on_the_exploration_path() -> void:
	## Corpus derived from the CATALOG, not from the spawner's own handled set —
	## deriving it from the code under test would make an untagged boss no case
	## at all. Masterites are excluded only from the per-id spawn (they carry
	## their own `masterite` arm and the roster is 24 of the 53); every other
	## boss-flagged id is walked.
	var cat: Dictionary = _catalog()
	var bosses: Array[String] = []
	for k in cat.keys():
		var rec: Variant = cat[k]
		if rec is Dictionary and ((rec as Dictionary).get("boss", false) or (rec as Dictionary).get("miniboss", false)):
			bosses.append(str(k))
	bosses.sort()
	assert_gt(bosses.size(), 10,
		"SCOPE control: only %d boss-flagged monsters found, so this sweep is not walking the catalog" % bosses.size())

	var untagged: Array[String] = []
	for id in bosses:
		var rows: Array = _spawn_as_encounter([id])
		if rows.is_empty():
			continue  # unspawnable ids are a different defect; the arms above pin the live ones
		if not bool(rows[0]["is_boss"]):
			untagged.append(id)

	assert_eq(untagged.size(), 0,
		"%d of %d catalog bosses are untagged when reached from exploration: %s" % [untagged.size(), bosses.size(), untagged])


func test_both_spawn_paths_agree_about_who_is_a_boss() -> void:
	## The defect stated structurally: one spawn path translated the flag and
	## the other did not, so WHICH ROUTE a fight took decided whether it was a
	## boss. Two sources that must AGREE — so assert agreement rather than
	## modelling a precedence (CLAUDE.md's case (a)).
	var disagree: Array[String] = []
	for wid in WITNESSES + ["slime"]:
		var id: String = str(wid)

		var enc: Array = _spawn_as_encounter([id])

		var fhost := _host()
		var fspawner := BattleEnemySpawner.new(fhost)
		fhost.forced_enemies = [id]
		fspawner.spawn_forced_enemies()
		var forced_boss: bool = false
		for e in fhost.test_enemies:
			if is_instance_valid(e) and bool(e.get_meta("is_boss", false)):
				forced_boss = true

		if enc.is_empty():
			continue
		if bool(enc[0]["is_boss"]) != forced_boss:
			disagree.append("%s: encounter=%s forced=%s" % [id, enc[0]["is_boss"], forced_boss])

	assert_eq(disagree.size(), 0,
		"the two spawn paths disagree about who is a boss (%d): %s — the same monster is a boss or not depending on which route the battle took" % [disagree.size(), disagree])


func test_the_predicate_that_picks_the_music_sees_the_boss() -> void:
	## CONSEQUENCE, not bookkeeping. The meta is only worth anything because
	## BattleScene._check_for_boss() gates the whole boss-music block —
	## including the `boss_type == "chancellor_mordaine"` arm that plays her own
	## track. So hand the real spawned enemy to the real predicate.
	var host := _host()
	var spawner := BattleEnemySpawner.new(host)
	host.encounter_enemies = ["chancellor_mordaine"]
	spawner.spawn_encounter_enemies()
	assert_gt(host.test_enemies.size(), 0, "SCOPE control: Mordaine did not spawn, so the predicate reads an empty pack")

	var script: Script = load(BATTLE_SCENE_SCRIPT)
	var scene: Node = script.new()
	## BattleScene.test_enemies is Array[Combatant]. Assigning the host's
	## untyped Array is a SCRIPT ERROR that ABORTS this function — and with the
	## assert above already banked, the arm scored PASSING through it on the
	## first run of this file. Coerce element by element.
	var typed: Array[Combatant] = []
	for e in host.test_enemies:
		if e is Combatant:
			typed.append(e as Combatant)
	assert_eq(typed.size(), host.test_enemies.size(),
		"SCOPE control: %d of %d spawned enemies are not Combatants, so the predicate reads a short pack" % [typed.size(), host.test_enemies.size()])
	scene.test_enemies = typed

	var sees_boss: bool = scene._check_for_boss()
	var boss_type: String = scene._get_boss_type()
	var dominant: String = scene._get_dominant_monster_type()
	scene.free()

	assert_eq(dominant, "chancellor_mordaine",
		"CONTROL: the pack reads as '%s', so the fixture is not driving Mordaine at all" % dominant)
	assert_true(sees_boss,
		"_check_for_boss() is FALSE for Chancellor Mordaine, so BattleScene skips the entire boss-music block and falls through to \"battle_\" + dominant monster — battle_chancellor_mordaine, which is not a track, so the generic world bed plays")
	assert_eq(boss_type, "chancellor_mordaine",
		"_get_boss_type() returned '%s'; her boss_mordaine arm is selected by that exact string" % boss_type)


func test_the_boss_banner_reaches_the_battle_log() -> void:
	## The other half of what he saw: no 👑 BOSS BATTLE 👑 banner in the whole
	## session (`grep -c` = 0). The banner is written by spawn_forced_enemies
	## off its own `is_boss_battle` local, so this arm pins the route that still
	## has one — a regression there would silence the banner everywhere.
	var host := _host()
	var spawner := BattleEnemySpawner.new(host)
	host.forced_enemies = ["chancellor_mordaine"]
	spawner.spawn_forced_enemies()

	var joined: String = "\n".join(host.log_lines)
	assert_true(joined.contains("BOSS BATTLE"),
		"a forced Mordaine fight printed no BOSS BATTLE banner; the battle log said only \"appeared!\". Lines: %s" % [host.log_lines])

	var plain := _host()
	var pspawner := BattleEnemySpawner.new(plain)
	plain.forced_enemies = ["slime"]
	pspawner.spawn_forced_enemies()
	assert_false("\n".join(plain.log_lines).contains("BOSS BATTLE"),
		"CONTROL: a slime got the BOSS BATTLE banner, so the assert above passes for everything")


func test_the_track_each_boss_now_reaches_is_real_audio() -> void:
	## The audible half, measured through the real resolver rather than derived.
	##
	## The fix only moves these fights INTO the boss-music block; what they then
	## hear is that block's ladder, whose final else asks for the GENERIC id
	## "boss" — and "boss" is not a manifest key. So this arm exists to answer
	## one question: does the fix land these fights on real audio, or on a
	## second dead key? Measured: play_music("boss") loads boss_medieval.ogg.
	##
	## ⚠️ THIS IS AN OUTCOME PIN, NOT A MUTATION-VERIFIED GUARD, and the two
	## mutations I expected to red it both stayed GREEN at 8/8:
	##   - "boss" removed from has_music_track's allowlist -> still green, because
	##     that function ends in `track.begins_with("boss")`, which catches it.
	##   - play_music's `"boss": manifest_track_id = "boss_" + suffix` arm deleted
	##     -> still green, because the id then falls through to `match track:
	##     "boss": _start_boss_music()`, which does its OWN
	##     _try_play_from_manifest("boss_" + suffix) and lands on the same bed.
	## Three independent routes reach boss_medieval, so no single edit can break
	## it. That is CLAUDE.md's redundant case (a): assert the OUTCOME the player
	## gets, never model which route won. The mutation-verified half of this file
	## is the meta/predicate arms above — those red twice with distinct
	## signatures. Do not read this arm as covering the ladder.
	var cases := {
		"boss": "boss_medieval",          # the four dragons + the Warden, via the generic arm
		"boss_mordaine": "boss_mordaine",  # her own authored track
		"boss_rat_king": "boss_rat_king",
		"boss_curator_medieval": "boss_curator_medieval",
	}
	var wrong: Array[String] = []
	for key in cases.keys():
		var want: String = str(cases[key])
		assert_true(SoundManager.has_music_track(str(key)),
			"has_music_track(\"%s\") is false, so play_music returns early and keeps the previous bed" % key)
		SoundManager.play_music(str(key))
		await get_tree().process_frame
		var stream: Variant = SoundManager._music_player.stream
		var got: String = stream.resource_path.get_file().get_basename() if stream != null else "<silence>"
		if got != want:
			wrong.append("%s -> %s (expected %s)" % [key, got, want])

	## CONTROL: the generic rewrite must be a rewrite, not a coincidence. If
	## "boss" and "battle" landed on the same stream the arm above is inert.
	SoundManager.play_music("battle")
	await get_tree().process_frame
	var battle_stream: Variant = SoundManager._music_player.stream
	var battle_file: String = battle_stream.resource_path.get_file().get_basename() if battle_stream != null else "<silence>"
	assert_eq(battle_file, "battle_medieval",
		"CONTROL: the generic \"battle\" alias resolved to '%s'; the world rewrite is not working, so the \"boss\" arm proves nothing" % battle_file)
	assert_ne(battle_file, "boss_medieval",
		"CONTROL: \"battle\" and \"boss\" land on the same stream, so this file cannot tell a boss bed from an encounter bed")

	assert_eq(wrong.size(), 0,
		"a boss key did not load its own audio (%d): %s — struktured heard battle_medieval.ogg for all four of these on 2026-10-05" % [wrong.size(), wrong])
