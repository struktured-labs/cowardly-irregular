extends GutTest

## Two of the 24 Masterite fights have no bed of their own, and nothing in the repo says so.
##
## BattleScene composes `"boss_%s_%s" % [masterite_type, world_suffix]` and hands it to
## play_music. 22 of those 24 keys name a shipped bed. `boss_arbiter_steampunk` and
## `boss_curator_steampunk` name nothing — their prompts are staged in tools/music_prompts.json
## and blocked on the Suno login, not on anything here. The existing routing guard checks
## DECLARED music_track keys; the composed space was unchecked in both directions.
##
## 🔑 The product is derived, never listed: roles come from monsters.json's own masterite_type
## values and suffixes from WeatherSystem.world_id_for(). A hand-written 4x6 table would keep
## passing after a seventh world or a fifth role arrived with no theme — the exact silence
## this file exists to make loud.
##
## ⚠️ The suffix is NOT the world's design name. CLAUDE.md's fifth world is "futuristic" and
## its monsters are named for it, while world_id_for(5) is "digital" and every bed is keyed
## that way. Deriving the suffix from the monster id would look right and check nothing.
##
## The second half is what the player actually gets today: a themeless fight still SOUNDS
## like a boss, because play_music's `begins_with("boss")` arm falls back to boss_<world>.
## Nothing pinned that arm. Without it those two fights would keep playing the corridor bed
## you walked in from — audible, and far worse than a shared theme.

const MANIFEST := "res://data/music_manifest.json"
const MONSTERS := "res://data/monsters.json"

## Composed keys no bed answers. This fails if the set GROWS (a fight went themeless) or
## SHRINKS (the bed landed — delete the entry, the fallback is no longer its story).
const THEMELESS := {
	"boss_arbiter_steampunk": "staged in tools/music_prompts.json, awaiting the Suno login",
	"boss_curator_steampunk": "staged in tools/music_prompts.json, awaiting the Suno login",
}

var _world_before: int = 1


func before_each() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs:
		_world_before = int(gs.get("current_world"))


func after_each() -> void:
	SoundManager.stop_music()
	var gs: Node = get_node_or_null("/root/GameState")
	if gs:
		gs.set("current_world", _world_before)


func _json(p: String) -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(p)
	assert_gt(raw.length(), 1000, "SCOPE control: %s read back %d chars" % [p, raw.length()])
	var parsed: Variant = JSON.parse_string(raw)
	return parsed as Dictionary if parsed is Dictionary else {}


func _roles() -> Array[String]:
	var out: Array[String] = []
	for rec in _json(MONSTERS).values():
		if not (rec is Dictionary):
			continue
		var role: String = str((rec as Dictionary).get("masterite_type", ""))
		if role != "" and not out.has(role):
			out.append(role)
	out.sort()
	return out


func _suffixes() -> Array[String]:
	var out: Array[String] = []
	for w in range(1, 7):
		var s: String = WeatherSystem.world_id_for(w)
		if s != "" and not out.has(s):
			out.append(s)
	return out


func _bed_file() -> String:
	var s: AudioStream = SoundManager._music_player.stream if SoundManager._music_player else null
	return s.resource_path.get_file() if s != null else ""


func test_every_masterite_fight_composes_a_key_a_bed_answers() -> void:
	var roles: Array[String] = _roles()
	var suffixes: Array[String] = _suffixes()
	assert_gte(roles.size(), 4, "CONTROL: monsters.json declares %d masterite roles %s" % [roles.size(), roles])
	assert_eq(suffixes.size(), 6, "CONTROL: world_id_for(1..6) gave %s" % [suffixes])

	var tracks: Dictionary = _json(MANIFEST).get("tracks", {})
	assert_gt(tracks.size(), 100, "SCOPE control: manifest carries %d tracks" % tracks.size())

	var missing: Array[String] = []
	for role in roles:
		for suffix in suffixes:
			var key: String = "boss_%s_%s" % [role, suffix]
			if not tracks.has(key):
				missing.append(key)
	missing.sort()

	var expected: Array[String] = []
	for k in THEMELESS.keys():
		expected.append(str(k))
	expected.sort()
	assert_eq(missing, expected,
		"masterite fights with no bed changed. New entries went themeless; a vanished one means the bed landed — delete it from THEMELESS. Reasons on record: %s" % [THEMELESS])


func test_a_themeless_masterite_still_sounds_like_a_boss() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	gs.set("current_world", 3)
	SoundManager.play_area_music("steampunk_dungeon")
	for i in range(3):
		await get_tree().process_frame
	assert_eq(_bed_file(), "dungeon_steampunk.ogg", "CONTROL: the corridor bed is what's playing when the fight starts")

	SoundManager.play_music("boss_curator_steampunk")
	for i in range(3):
		await get_tree().process_frame
	assert_eq(_bed_file(), "boss_steampunk.ogg",
		"a fight whose own theme does not exist must fall back to the world's boss bed, not keep the corridor playing")


func test_control_a_masterite_with_a_theme_plays_its_own() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	gs.set("current_world", 3)
	SoundManager.play_area_music("steampunk_dungeon")
	for i in range(3):
		await get_tree().process_frame
	SoundManager.play_music("boss_warden_steampunk")
	for i in range(3):
		await get_tree().process_frame
	assert_eq(_bed_file(), "boss_warden_steampunk.ogg",
		"CONTROL: a role that HAS a bed still gets its own — otherwise the arm above is measuring a constant")
