extends GutTest

## Each W1 masterite trigger plays its authored pre-fight beat. Three were placed with no route at all.

const ENCOUNTER_SCRIPT := "res://src/exploration/MasteriteEncounter.gd"
const TALLY_WALL := "res://src/exploration/TallyWall.gd"
const CUTSCENE_DIR := "res://data/cutscenes"

## village script -> the beat its masterite must play. Warden is absent BY DESIGN, see below.
const WIRED := {
	"EldertreeVillage.gd": "world1_tempo_encounter",
	"GrimhollowVillage.gd": "world1_arbiter_encounter",
	"IronhavenVillage.gd": "world1_curator_encounter",
}

## Sandrift places the Warden but must NOT set a beat — TallyWall already plays it.
const OWNED_ELSEWHERE := {
	"SandriftVillage.gd": "world1_warden_encounter",
}


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _village(name: String) -> String:
	return _read("res://src/maps/villages/%s" % name)


func test_the_scan_can_see_the_villages_at_all() -> void:
	var total := WIRED.size() + OWNED_ELSEWHERE.size()
	assert_eq(total, 4, "W1 places exactly four masterite triggers")
	for name in WIRED:
		assert_gt(_village(name).length(), 0, "CONTROL: %s must load" % name)
		assert_true(_village(name).contains("MasteriteEncounter.gd"),
			"CONTROL: %s must still place a MasteriteEncounter, or this file is pinning a dead placement" % name)
	assert_false(_village("EldertreeVillage.gd").contains("zzz_not_a_real_symbol"),
		"CONTROL: a fabricated symbol must not be found")


func test_the_trigger_can_play_a_beat_at_all() -> void:
	var src := _read(ENCOUNTER_SCRIPT)
	assert_gt(src.length(), 0, "CONTROL: MasteriteEncounter must load")
	assert_true(src.contains("@export var cutscene_id"),
		"MasteriteEncounter lost its cutscene_id export — the three W1 beats it routes have no other dispatch, so they go dark. Restore the export and the await in _on_body_entered.")
	assert_true(src.contains("await _play_encounter_beat()"),
		"MasteriteEncounter declares cutscene_id but no longer awaits the beat before _fire_battle — the scene is configured and never plays. Restore the await between monitoring = false and _fire_battle().")
	assert_true(src.contains("get_cutscene_director"),
		"the beat must resolve through GameLoop.get_cutscene_director — CutsceneDirector is GameLoop-owned, and a /root/ lookup silently falls through to no cutscene (DragonCave:676)")


func test_every_wired_beat_names_a_scene_on_disk() -> void:
	var broken: Array = []
	for name in WIRED:
		var want: String = str(WIRED[name])
		var body := _village(name)
		if not body.contains("cutscene_id = \"%s\"" % want):
			broken.append("%s does not set cutscene_id to %s" % [name, want])
		elif not FileAccess.file_exists("%s/%s.json" % [CUTSCENE_DIR, want]):
			broken.append("%s names %s but no such scene is on disk" % [name, want])
	broken.sort()
	assert_eq(broken.size(), 0,
		("a W1 masterite trigger stopped naming its authored pre-fight beat. These three scenes have NO "
		+ "other dispatch route — no gate, no boss_cutscene_id, no quest — so an unset cutscene_id is the "
		+ "difference between the beat playing and 18 authored steps being unreachable. Restore the "
		+ "assignment, or delete the scene and say why here: " + ", ".join(broken)) % [])


func test_the_warden_beat_is_owned_by_the_tally_wall_not_the_trigger() -> void:
	var wrong: Array = []
	for name in OWNED_ELSEWHERE:
		var beat: String = str(OWNED_ELSEWHERE[name])
		if _village(name).contains("cutscene_id = \"%s\"" % beat):
			wrong.append("%s sets cutscene_id to %s, which TallyWall already plays" % [name, beat])
	assert_eq(wrong.size(), 0,
		("the Warden beat would play twice. TallyWall is its owner; Sandrift must leave cutscene_id unset. "
		+ "If the TallyWall route is being retired, move the beat here in the same change rather than "
		+ "setting both: " + ", ".join(wrong)) % [])
	var tally := _read(TALLY_WALL)
	assert_true(tally.contains("world1_warden_encounter"),
		"TallyWall stopped playing world1_warden_encounter, so Sandrift is now the only possible route for it — set cutscene_id on the Warden placement in the same change that removed this")
