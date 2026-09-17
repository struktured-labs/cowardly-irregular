extends GutTest

## `pinned` on a music manifest entry is the ONLY thing standing between an authored bed and
## `suno_api.py`'s regeneration queue, and regeneration OVERWRITES the .ogg. Nothing tested it.
##
## Found by asking which FIELDS of the manifest any guard reads (@cowir-autogrind's column lesson,
## 2026-09-17): 11 of 17 fields are named by some test; `pinned` was not, on 48 entries.
##
## 📌 SCOPE: this covers the REGENERATION route only. The other way a master can be overwritten is
## a build transcoding it in place, and `tools/check_masters_untouched.sh` already proves that one.
##
## ⛔ NOT A "THESE 48 MUST STAY PINNED" RATCHET — `suno_api.py` has a deliberate `unpin_tracks()`
## command and a hard ratchet would fight it. This reds in BOTH directions and says what to do, so
## an intentional unpin is one list edit and an ACCIDENTAL one cannot pass.

const MANIFEST := "res://data/music_manifest.json"
const SUNO := "res://tools/suno_api.py"

const PROTECTED: Array[String] = [
	"autogrind",
	"battle_abstract",
	"battle_barbarian",
	"battle_bat",
	"battle_brute",
	"battle_cave_troll",
	"battle_digital",
	"battle_ghost",
	"battle_imp",
	"battle_industrial",
	"battle_medieval",
	"battle_mushroom",
	"battle_ogre",
	"battle_skeleton",
	"battle_slime",
	"battle_snake",
	"battle_steampunk",
	"battle_suburban",
	"battle_troll",
	"battle_wolf",
	"danger",
	"danger_abstract",
	"danger_digital",
	"danger_industrial",
	"danger_medieval",
	"danger_steampunk",
	"danger_suburban",
	"dungeon_medieval",
	"game_over",
	"overworld_abstract",
	"overworld_digital",
	"overworld_industrial",
	"overworld_medieval",
	"overworld_steampunk",
	"overworld_suburban",
	"title",
	"victory",
	"victory_digital",
	"victory_industrial",
	"victory_medieval",
	"victory_steampunk",
	"victory_suburban",
	"village_abstract",
	"village_digital",
	"village_industrial",
	"village_medieval",
	"village_steampunk",
	"village_suburban",
]


func _tracks() -> Dictionary:
	var txt: String = FileAccess.get_file_as_string(MANIFEST)
	assert_ne(txt, "", "CONTROL: the manifest must be readable")
	var parsed = JSON.parse_string(txt)
	assert_true(parsed is Dictionary, "CONTROL: the manifest must parse")
	return (parsed as Dictionary).get("tracks", {})


func test_the_protected_set_is_not_empty() -> void:
	## Without this the two arms below pass on an empty list and guard nothing.
	assert_gt(PROTECTED.size(), 0, "CONTROL: the protected list must name tracks")


func test_no_bed_has_quietly_lost_its_pin() -> void:
	var tracks := _tracks()
	var lost: Array[String] = []
	for id in PROTECTED:
		var e = tracks.get(id, null)
		if e == null or not (e is Dictionary) or not bool((e as Dictionary).get("pinned", false)):
			lost.append(id)
	assert_eq(lost, [] as Array[String],
		"these beds lost their pin and are now REGENERABLE (%s) — suno_api.py skips only pinned entries, and a regeneration overwrites the .ogg. If the unpin was deliberate, remove them from PROTECTED in this file" % [lost])


func test_a_new_pin_is_recorded_here() -> void:
	## The other direction, so the list cannot rot into a stale claim about what is protected.
	var tracks := _tracks()
	var unrecorded: Array[String] = []
	for id in tracks:
		var e = tracks[id]
		if e is Dictionary and bool((e as Dictionary).get("pinned", false)) and not PROTECTED.has(id):
			unrecorded.append(str(id))
	assert_eq(unrecorded, [] as Array[String],
		"newly pinned beds are not recorded in PROTECTED (%s) — add them, or this list stops describing what is actually protected" % [unrecorded])


func test_the_pin_still_has_a_consumer() -> void:
	## ⛔ THE ARM THAT KEEPS THE OTHERS HONEST. If suno_api.py stops SKIPPING pinned entries, the
	## flag becomes decorative and every arm above still passes while nothing is protected.
	var src: String = FileAccess.get_file_as_string(SUNO)
	assert_ne(src, "", "CONTROL: suno_api.py must be readable — it is the consumer this guard assumes")
	## ⛔ NOT `entry.get("pinned")` — that also appears in the LISTING code, so deleting the
	## enforcement branch leaves the pattern intact and this arm green. Measured, 2026-09-17.
	assert_true(src.contains('if entry.get("pinned"):'),
		"suno_api.py no longer BRANCHES on the pin when building its queue — the flag is decorative and these %d beds are regenerable" % PROTECTED.size())
	assert_true(src.contains("pinned_skipped += 1"),
		"suno_api.py no longer counts a pinned skip — reading the flag is not the same as honouring it")
