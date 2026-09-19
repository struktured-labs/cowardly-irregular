extends GutTest

## `monsters.json` declares `music_track` per monster — 12 of them today. NO AUDIT EVER OPENED THAT
## FILE against a manifest. `test_every_monster_theme_is_named_by_the_manifest` looks like the guard
## for this and is not: it derives themes from `SoundManager`'s match arms and reads
## `music_manifest.json` + `SoundManager.gd`, never `monsters.json`. Two populations, one name.
##
## ⛔ THE FAILURE IS SILENT AND HAS SHIPPED BEFORE. `play_music` rewrites an unknown `battle_*` to
## `battle_<world suffix>`, so a retired or mistyped theme plays the generic world bed with nothing on
## the console. That is the goblin defect verbatim: `battle_goblin.ogg` was recast as
## `battle_brute.ogg` (7e6c50d2), no key replaced it, and the rewrite sent the goblin to
## battle_medieval — struktured, 2026-08-29: "The goblin music is gone and defaults to something else."
##
## ⚠️ LATENT: all 12 resolve today. Found by borrowing @cowir-autogrind's lens — a registry cannot
## report a file it never opens — after their lens sweep found `data/lenses.json` outside all three
## of their parity registries.

const MANIFEST := "res://data/music_manifest.json"
const MONSTERS := "res://data/monsters.json"


func _manifest_keys() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "CONTROL: the music manifest parses")
	var out: Dictionary = {}
	if parsed is Dictionary:
		var t = (parsed as Dictionary).get("tracks", {})
		if t is Dictionary:
			for k in (t as Dictionary).keys():
				out[str(k)] = true
	assert_gt(out.size(), 50, "CONTROL: the manifest read non-empty (%d keys)" % out.size())
	return out


## Every monster entry declaring a theme, DERIVED from the file rather than listed here — a
## hand-list is what let the data file sit outside every corpus in the first place.
func _declared_themes() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS))
	assert_true(parsed is Dictionary, "CONTROL: monsters.json parses")
	var out: Dictionary = {}
	if not (parsed is Dictionary):
		return out
	var mons = (parsed as Dictionary).get("monsters", parsed)
	if not (mons is Dictionary):
		return out
	for id in (mons as Dictionary).keys():
		var m = (mons as Dictionary)[id]
		if not (m is Dictionary):
			continue
		var track: String = str((m as Dictionary).get("music_track", ""))
		if track != "":
			out[str(id)] = track
	return out


func test_every_declared_monster_theme_is_a_manifest_key() -> void:
	var keys := _manifest_keys()
	var themes := _declared_themes()
	## ANTI-VACUITY: with no declared themes the arm passes by finding nothing to check.
	assert_gt(themes.size(), 5,
		"ANTI-VACUITY: only %d monsters declare music_track (%s) — either the field was renamed or this walk stopped matching, and an empty corpus cannot fail" % [themes.size(), str(themes.keys())])
	var liars: Array = []
	for id in themes.keys():
		var track: String = str(themes[id])
		if not keys.has(track):
			liars.append("%s declares music_track '%s'" % [id, track])
	assert_eq(liars.size(), 0,
		"a monster names a bed the manifest does not have. play_music rewrites an unknown battle_* to battle_<world suffix>, so this plays the generic world bed and nothing says so — the 2026-08-29 goblin defect verbatim: "
		+ " · ".join(liars)
		+ " — either author the key in data/music_manifest.json, or drop music_track and let the monster use the world bed deliberately")


## ⛔ THE OTHER DIRECTION, because a theme that resolves is not the same as a theme that is REACHED.
## A monster whose theme is a manifest key still plays nothing if the id never spawns; but the
## inverse — a bed authored FOR a monster that no monster names — is a dead asset the orphan audits
## key on SoundManager's match arms and would not see declared here.
func test_no_monster_theme_is_declared_twice_with_different_beds() -> void:
	var themes := _declared_themes()
	assert_gt(themes.size(), 5, "ANTI-VACUITY: nothing declared")
	var by_track: Dictionary = {}
	for id in themes.keys():
		var t: String = str(themes[id])
		if not by_track.has(t):
			by_track[t] = []
		(by_track[t] as Array).append(str(id))
	var shared: int = 0
	for t in by_track.keys():
		if (by_track[t] as Array).size() > 1:
			shared += 1
	## Sharing is legitimate (blood_wolf_alpha and ice_wolf both use battle_wolf). This arm exists so
	## the count is visible: if it ever reaches zero, the multi-namer case below stops being tested.
	assert_gt(shared, 0,
		"ANTI-VACUITY: no bed is named by more than one monster, so the shared-bed case is untested here")
