extends GutTest

## Every route BattleScene can take must land on a real bed (2026-09-10).
##
## Verified by hand this session across four routing paths; that took most of an
## hour and produced no defect. This file is that map, made cheap to re-check —
## because the expensive part was never the fix, it was establishing that all
## four paths are covered, and nothing currently notices when one stops being.
##
## THE FOUR PATHS, from BattleScene:2889-2936:
##     declared      monsters.json `music_track` outranks everything
##     masterite     "boss_<archetype>_<world_suffix>"
##     monster       "battle_<id>", rewritten to "battle_<world>" on a miss
##     terrain       _get_terrain_battle_track()
##
## ⚠️ WHY THE WORLD-SUFFIX ARM IS THE ONE WORTH PINNING: it has already failed
## silently and world-wide. Tick 359 — GameLoop began passing the canonical
## `<world>_overworld` map_id while the match arms only listed the legacy
## `overworld_<world>` form, so every arm fell through to `_:` and returned the
## cached default. **Every battle in suburban / steampunk / industrial /
## futuristic / abstract played MEDIEVAL battle music**, and nothing failed.
##
## 🔑 THE SUFFIX LIST IS DERIVED FROM SoundManager, NOT RESTATED HERE. A
## hardcoded ["medieval", ...] would be a coincidental pin: it passes while
## agreeing with a stale copy of the vocabulary, and the tick-359 defect was
## exactly a vocabulary disagreement between two files. Deriving it means adding
## a seventh world makes this test demand that world's beds on its own.
##
## ⚠️ AND THE MONSTER ARM IS DELIBERATELY *NOT* REQUIRED TO BE COMPLETE. 56 of
## 84 pool-reachable monsters have no bed of their own and correctly fall to
## their world's battle bed — that is the design, not a gap. Asserting per
## monster would demand ~56 tracks nobody wants. What must hold is that the
## thing they fall TO exists, which is the WORLD_KEYS arm below.

const MANIFEST := "res://data/music_manifest.json"
const SOUNDMANAGER := "res://src/audio/SoundManager.gd"

## Every generic key that gets rewritten to "<key>_<world>" in play_music's
## `match track:` block, plus the area beds a world needs to not be silent.
const WORLD_KEYS := ["battle", "boss", "overworld", "dungeon", "village", "victory"]

const MASTERITE_ARCHETYPES := ["warden", "arbiter", "tempo", "curator"]

## Beds that do not exist yet and cannot be authored: Suno has been behind a
## ToS modal since 2026-09-03 that only struktured can clear. Named with the
## reason and the unblock, NOT a bare allowlist — and the test goes RED when
## one ARRIVES, so this list cannot quietly outlive its cause.
const PENDING_AUTHORING := {
	"boss_arbiter_steampunk": "staged prompt, blocked on the Suno ToS login",
	"boss_curator_steampunk": "staged prompt, blocked on the Suno ToS login",
}


func _tracks() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	return (JSON.parse_string(raw) as Dictionary).get("tracks", {})


func _has_bed(tracks: Dictionary, key: String) -> bool:
	var e: Variant = tracks.get(key, null)
	return e is Dictionary and str((e as Dictionary).get("file", "")) != ""


func _world_suffixes() -> Array[String]:
	## Derived from the body of _get_current_world_suffix, so this test cannot
	## disagree with the runtime about which worlds exist.
	var src: String = FileAccess.get_file_as_string(SOUNDMANAGER)
	assert_gt(src.length(), 5000, "SCOPE control: SoundManager.gd read back %d chars" % src.length())
	var start: int = src.find("func _get_current_world_suffix")
	assert_gt(start, 0, "SCOPE control: _get_current_world_suffix not found — this probe reads nothing")
	var body: String = src.substr(start, 3000)

	var found: Array[String] = []
	var re := RegEx.new()
	re.compile("return \"([a-z_]+)\"")
	for m in re.search_all(body):
		var s: String = m.get_string(1)
		if s != "" and not found.has(s):
			found.append(s)
	found.sort()
	return found


func test_the_world_suffix_vocabulary_is_readable() -> void:
	## Control for every arm below: if the derivation breaks, the other tests
	## would walk an empty list and pass having checked nothing.
	var worlds: Array[String] = _world_suffixes()
	assert_gt(worlds.size(), 3,
		"SCOPE control: derived only %s from _get_current_world_suffix — the parse is broken and a green elsewhere would be vacuous" % [worlds])
	assert_true(worlds.has("medieval"),
		"CONTROL FAILED: 'medieval' is not in the derived vocabulary %s — the parse found something, but not the suffixes" % [worlds])


func test_every_world_has_the_beds_its_fallbacks_name() -> void:
	## The load-bearing arm. A missing entry here is not one quiet monster, it
	## is a whole world with no music for a whole category.
	var tracks: Dictionary = _tracks()
	var worlds: Array[String] = _world_suffixes()
	var missing: Array[String] = []
	var checked: int = 0
	for w in worlds:
		for k in WORLD_KEYS:
			checked += 1
			if not _has_bed(tracks, "%s_%s" % [k, w]):
				missing.append("%s_%s" % [k, w])
	assert_gt(checked, 20,
		"SCOPE control: only %d world/key pairs walked" % checked)
	assert_eq(missing.size(), 0,
		"worlds missing a fallback bed (%d of %d): %s — play_music rewrites the generic key to this one, so a miss is silence or a procedural buzz for every battle in that world" % [missing.size(), checked, missing])


func test_every_masterite_archetype_has_a_bed_in_every_world() -> void:
	## BattleScene:2898 builds "boss_<archetype>_<world_suffix>" with no fallback
	## of its own — a miss drops straight through play_music to _start_boss_music.
	var tracks: Dictionary = _tracks()
	var worlds: Array[String] = _world_suffixes()
	var missing: Array[String] = []
	var arrived: Array[String] = []
	var checked: int = 0
	for a in MASTERITE_ARCHETYPES:
		for w in worlds:
			var key: String = "boss_%s_%s" % [a, w]
			checked += 1
			if _has_bed(tracks, key):
				if PENDING_AUTHORING.has(key):
					arrived.append(key)
			elif not PENDING_AUTHORING.has(key):
				missing.append(key)
	assert_gt(checked, 12,
		"SCOPE control: only %d archetype/world pairs walked" % checked)
	assert_eq(missing.size(), 0,
		"Masterite themes with no bed (%d of %d): %s — this arm has no fallback, so the fight gets generic boss music" % [missing.size(), checked, missing])
	## The pin must expire on its own. Without this the two entries survive the
	## day the tracks land and start suppressing a real regression instead.
	assert_eq(arrived.size(), 0,
		"PENDING_AUTHORING names beds that now EXIST (%s) — the Suno block is cleared for these; delete them from the dict so they are covered like the rest" % [arrived])


func test_no_track_is_exempted_from_the_fallback_with_nowhere_to_land() -> void:
	## PROCEDURAL_BATTLE_TRACKS opts a key OUT of the "battle_<world>" rewrite,
	## on the promise that it has its own generator. struktured 2026-08-29 —
	## "The goblin music is gone and defaults to something else. I wanted it
	## replaced not removed entirely." A member with neither a bed NOR a match
	## arm is exempted from the safety net with no substitute: it reaches
	## nothing at all, which is worse than the fallback it was excused from.
	var src: String = FileAccess.get_file_as_string(SOUNDMANAGER)
	var start: int = src.find("PROCEDURAL_BATTLE_TRACKS")
	assert_gt(start, 0, "SCOPE control: PROCEDURAL_BATTLE_TRACKS not found")
	var decl: String = src.substr(start, 900)

	var re := RegEx.new()
	re.compile("\"(battle_[a-z_]+)\"")
	var members: Array[String] = []
	for m in re.search_all(decl):
		var s: String = m.get_string(1)
		if not members.has(s):
			members.append(s)
	assert_gt(members.size(), 8,
		"SCOPE control: parsed only %d members from the declaration" % members.size())

	var tracks: Dictionary = _tracks()
	var stranded: Array[String] = []
	for t in members:
		## ⚠️ Arms are GROUPED — `"battle_troll", "battle_ogre":` — so a probe
		## anchored on a line START finds 9 of 14 and calls the other 5 broken.
		## Measured: that exact false negative, this session. Look for the
		## quoted key anywhere after the declaration instead.
		var has_arm: bool = src.find("\"%s\"" % t, start + decl.length()) > 0
		if not _has_bed(tracks, t) and not has_arm:
			stranded.append(t)
	assert_eq(stranded.size(), 0,
		"tracks exempted from the world-bed rewrite with no bed and no procedural arm (%d of %d): %s" % [stranded.size(), members.size(), stranded])


func test_a_declared_music_track_always_names_a_real_bed() -> void:
	## `music_track` in monsters.json outranks every derived key (BattleScene
	## :2999), so a typo there is not a fallback, it is a dead end that beats
	## the working default. 12 of these were added 2026-09-09.
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	assert_gt(raw.length(), 1000, "SCOPE control: monsters.json read back %d chars" % raw.length())
	var mons: Dictionary = JSON.parse_string(raw) as Dictionary
	var tracks: Dictionary = _tracks()

	var declared: int = 0
	var broken: Array[String] = []
	for id in mons.keys():
		var rec: Variant = mons[id]
		if not (rec is Dictionary):
			continue
		var t: String = str((rec as Dictionary).get("music_track", ""))
		if t == "":
			continue
		declared += 1
		if not _has_bed(tracks, t):
			broken.append("%s -> %s" % [id, t])
	assert_gt(declared, 5,
		"SCOPE control: only %d monsters declare a music_track — the walk found almost none and a green would be vacuous" % declared)
	assert_eq(broken.size(), 0,
		"monsters.json declares a music_track with no bed (%d of %d): %s — a declared key outranks the derived one, so this is silence where the default would have worked" % [broken.size(), declared, broken])
