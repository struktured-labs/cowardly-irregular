extends GutTest

## A generic per-world bed must not carry a named character's epithet.
##
## `boss_medieval` was titled "The Usurper's Shadow" — which is Chancellor
## Mordaine's epithet, `boss_dialogue.json` display_name "Chancellor Mordaine,
## the Usurper's Shadow". It was authored AS her theme. She was later moved to
## her own `boss_mordaine` ("A Sound Like a Verdict") and boss_medieval reverted
## to the generic W1 boss bed it was written as — BattleScene:2906-2918 records
## that decision — but the title never followed, and neither did the prompt
## template nor CLAUDE.md's boss table.
##
## 🔑 THE PLAYER-FACING HALF. The Jukebox lists `title`, so this was not a
## bookkeeping slip: every dragon fight played a track named after Mordaine, and
## her actual theme sat under a name nothing connects to her. A player who
## wanted to replay the Mordaine fight picked the wrong row, and the right row
## looked like something else entirely.
##
## ⚠️ AND THE AUTHORED BRIEF ALREADY SAID SO. tools/music_prompts.json's `boss`
## entry reads "Epic boss confrontation, towering enemy, high stakes battle" —
## entirely generic, no Mordaine in it. The BRIEF was generic and only the TITLE
## was specific, which is what identified the title as the anomaly rather than
## the routing. When two authored artifacts disagree, the one that describes the
## WORK is usually right and the one that describes the NAME has drifted.
##
## The convention this restores, read off the siblings rather than invented:
## every generic boss bed names its world's ARCHETYPE OF AUTHORITY, never a
## person — The Foreman (industrial) · HOA President (suburban) · The Grand
## Automaton (steampunk) · Root Access (digital) · The Final Question (abstract).
## boss_medieval is now The High Seat.
##
## ⚠️ THE NAME IS MINE AND IS struktured's TO OVERRIDE. The defect is that her
## epithet sat on a shared bed; what it becomes instead is a creative call and he
## named the other five. This test does NOT pin "The High Seat" — it pins that
## the title is not a character's epithet, so any replacement passes.

const MANIFEST := "res://data/music_manifest.json"
const BOSS_DIALOGUE := "res://data/boss_dialogue.json"

## Beds that serve a whole world rather than one encounter.
const GENERIC_PREFIXES := ["boss_", "battle_", "danger_", "victory_", "village_",
	"overworld_", "dungeon_", "credits_", "ambient_"]
const WORLDS := ["medieval", "suburban", "steampunk", "industrial", "digital", "abstract"]


func _tracks() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	return (JSON.parse_string(raw) as Dictionary).get("tracks", {})


## "Chancellor Mordaine, the Usurper's Shadow" -> "The Usurper's Shadow"
func _epithets() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(BOSS_DIALOGUE)
	assert_gt(raw.length(), 500, "SCOPE control: boss_dialogue.json read back %d chars" % raw.length())
	var root: Dictionary = JSON.parse_string(raw) as Dictionary
	var out: Dictionary = {}
	for boss_id in root.keys():
		var rec: Variant = root[boss_id]
		if not (rec is Dictionary):
			continue
		var name: String = str((rec as Dictionary).get("display_name", ""))
		var comma: int = name.find(",")
		if comma < 0:
			continue
		var ep: String = name.substr(comma + 1).strip_edges()
		## "the Usurper's Shadow" and "The Usurper's Shadow" are the same name.
		if ep.begins_with("the "):
			ep = "The " + ep.substr(4)
		if ep != "":
			out[ep.to_lower()] = str(boss_id)
	return out


func test_control_the_epithets_parse() -> void:
	## Every arm below is vacuous if this returns nothing, and a green would then
	## mean "no epithets to collide with" rather than "no collisions".
	var eps: Dictionary = _epithets()
	assert_gt(eps.size(), 2,
		"SCOPE control: parsed only %d boss epithets from boss_dialogue.json — the split is broken and a clean result below would be vacuous" % eps.size())
	assert_true(eps.has("the usurper's shadow"),
		"CONTROL FAILED: Mordaine's epithet is not among the parsed set %s — this test cannot detect the defect it was written for" % [eps.keys()])


func test_no_generic_bed_is_titled_with_a_boss_epithet() -> void:
	var tracks: Dictionary = _tracks()
	var eps: Dictionary = _epithets()
	var checked: int = 0
	var bad: Array[String] = []
	for key in tracks.keys():
		var k: String = str(key)
		var is_generic: bool = false
		for p in GENERIC_PREFIXES:
			if k.begins_with(p) and WORLDS.has(k.substr(p.length())):
				is_generic = true
				break
		if not is_generic:
			continue
		checked += 1
		var title: String = str((tracks[k] as Dictionary).get("title", "")).strip_edges()
		if title == "":
			continue
		if eps.has(title.to_lower()):
			bad.append("%s titled %s — that is %s's epithet" % [k, title, eps[title.to_lower()]])
	assert_gt(checked, 20,
		"SCOPE control: only %d generic per-world beds walked — the prefix/world match is broken" % checked)
	assert_eq(bad.size(), 0,
		"generic beds carrying a named character's epithet (%d of %d): %s — the Jukebox lists `title`, so every encounter using this shared bed is announced under one boss's name, and that boss's own theme is listed as something else" % [bad.size(), checked, bad])


func test_every_generic_boss_bed_still_has_a_title() -> void:
	## Removing a bad title is not a fix — the Jukebox falls back to a
	## title-cased id ("Boss Medieval") and the row stops matching the five
	## siblings that read as names. Deleting must not be the easy way out.
	var tracks: Dictionary = _tracks()
	var missing: Array[String] = []
	for w in WORLDS:
		var k: String = "boss_" + w
		if not tracks.has(k):
			continue
		if str((tracks[k] as Dictionary).get("title", "")).strip_edges() == "":
			missing.append(k)
	assert_eq(missing.size(), 0,
		"generic boss beds with no title (%d): %s — five of six read as names; an untitled one shows as a title-cased id" % [missing.size(), missing])


func test_mordaine_is_routed_to_her_own_track_not_the_generic_bed() -> void:
	## The premise. If she were still on boss_medieval, its title would be
	## correct and this whole file would be wrong.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_gt(src.length(), 10000, "SCOPE control: BattleScene.gd read back %d chars" % src.length())
	assert_gt(src.find("play_music(\"boss_mordaine\")"), 0,
		"BattleScene no longer routes Mordaine to boss_mordaine — if she is back on the generic bed, the retitle in this commit is wrong and should be reverted, not patched")
	var tracks: Dictionary = _tracks()
	assert_true(tracks.has("boss_mordaine"),
		"boss_mordaine is missing from the manifest but BattleScene plays it")


## One real collision, pinned with its reason rather than renamed: both are
## legitimately W6 pieces and the name fits each, so which keeps it is a
## creative call and not mine. Goes RED if it is FIXED, so the pin cannot
## outlive its cause.
const KNOWN_TITLE_COLLISIONS := {
	"the answered absence": "overworld_abstract + cutscene_w6_entering_nothing — both W6, name fits both, @struktured picks",
}


func test_no_two_DIFFERENT_tracks_share_a_title() -> void:
	## ⚠️ THE FIRST VERSION OF THIS ARM WAS WRONG AND ITS NOISE TAUGHT ME THE
	## PREDICATE. It flagged 5 collisions; 4 were battle_brute/troll/cave_troll/
	## ogre/barbarian, which all point at the SAME FILE — the deliberate "a
	## monster family shares one theme" ruling (struktured 2026-08-17). Five rows
	## naming one piece of music is CORRECT and identical titles are the honest
	## rendering of it. A title collision is only a defect when the FILES DIFFER,
	## because only then do two distinct pieces answer to one name.
	var tracks: Dictionary = _tracks()
	var by_title: Dictionary = {}
	var counted: int = 0
	for key in tracks.keys():
		var e: Dictionary = tracks[key] as Dictionary
		var title: String = str(e.get("title", "")).strip_edges()
		if title == "":
			continue
		counted += 1
		var lc: String = title.to_lower()
		if not by_title.has(lc):
			by_title[lc] = []
		(by_title[lc] as Array).append([str(key), str(e.get("file", ""))])

	var dupes: Array[String] = []
	var stale: Array[String] = []
	for lc in by_title.keys():
		var rows: Array = by_title[lc]
		var files: Dictionary = {}
		for r in rows:
			files[r[1]] = true
		var collides: bool = files.size() > 1
		if collides and not KNOWN_TITLE_COLLISIONS.has(lc):
			var names: Array[String] = []
			for r in rows:
				names.append(str(r[0]))
			dupes.append("%s <- %s (%d distinct files)" % [rows[0][0] + "/" + rows[1][0], names, files.size()])
		elif not collides and KNOWN_TITLE_COLLISIONS.has(lc):
			stale.append(str(lc))

	assert_gt(counted, 100,
		"SCOPE control: only %d titled tracks walked" % counted)
	assert_eq(dupes.size(), 0,
		"DIFFERENT tracks sharing a title (%d): %s — two distinct pieces answer to one name in the Jukebox" % [dupes.size(), dupes])
	## The pin must expire on its own or it starts suppressing a real regression.
	assert_eq(stale.size(), 0,
		"KNOWN_TITLE_COLLISIONS names a collision that no longer exists (%s) — it was resolved; delete the entry so the pair is covered like everything else" % [stale])
