extends GutTest

## W2's Arbiter and Curator had their defeat flags AUTO-SET the instant the preceding cutscene
## ended — GameLoop's own comment called the fights "off-screen narrative beats" because nothing
## triggered them. Two authored Masterites, their intros and their defeat scenes were unreachable
## while the campaign spine still walked to the ending, because the spine injects those flags.
##
## The repair is a real MasteriteEncounter per boss, naming the cutscene_flag_* its world's gates
## already read. These arms defend the mechanism (an encounter may name its own flag) and the
## defect class (no defeat flag is granted without a battle).

const ENCOUNTER := "res://src/exploration/MasteriteEncounter.gd"
const GAMELOOP := "res://src/GameLoop.gd"
const MAPLE := "res://src/maps/villages/MapleHeightsVillage.gd"

## The two the auto-sets used to grant, and what a real fight must name for each.
const W2_FIGHTS := {
	"masterite_arbiter_suburban": "cutscene_flag_arbiter_suburban_defeated",
	"masterite_curator_suburban": "cutscene_flag_curator_suburban_defeated",
}


func _source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "FLOOR: %s must be readable — every arm below reads it" % path)
	return f.get_as_text() if f else ""


func test_an_encounter_may_name_its_own_defeat_flag() -> void:
	var script = load(ENCOUNTER)
	assert_not_null(script, "FLOOR: MasteriteEncounter.gd must load")
	var w1 = script.new()
	w1.archetype = "warden"
	## CONTROL FIRST: W1's four compose their flag and must be untouched by the override.
	assert_eq(w1.defeat_flag(), "w1_warden_defeated",
		"an encounter with no explicit flag keeps W1's composed name")
	var w2 = script.new()
	w2.archetype = "arbiter"
	w2.defeat_flag_name = "cutscene_flag_arbiter_suburban_defeated"
	assert_eq(w2.defeat_flag(), "cutscene_flag_arbiter_suburban_defeated",
		"an explicit flag wins, so W2-W6 can name the gate's own flag")
	w1.free()
	w2.free()


func test_a_defeated_masterite_does_not_re_fire() -> void:
	## The guard that keeps a beaten boss beaten reads through the four-namespace reader, so a
	## cutscene_flag_* name set in game_constants must satisfy it. Without this the encounter
	## would re-arm on every entry after its own victory.
	var script = load(ENCOUNTER)
	var e = script.new()
	e.archetype = "curator"
	e.defeat_flag_name = "cutscene_flag_curator_suburban_defeated"
	var had: bool = bool(GameState.game_constants.get(e.defeat_flag_name, false))
	GameState.game_constants.erase(e.defeat_flag_name)
	assert_false(e._defeat_flag_set(), "CONTROL: undefeated before the flag is written")
	GameState.game_constants[e.defeat_flag_name] = true
	assert_true(e._defeat_flag_set(), "a game_constants cutscene_flag_* defeat must read as defeated")
	if not had:
		GameState.game_constants.erase(e.defeat_flag_name)
	e.free()


func test_no_defeat_flag_is_granted_without_a_battle() -> void:
	## The defect itself. A `_set_cutscene_flag_and_mirror("cutscene_flag_<x>_defeated")` call in
	## the story-gate chain hands the player a victory they never fought.
	var src := _source(GAMELOOP)
	var rx := RegEx.new()
	rx.compile('_set_cutscene_flag_and_mirror\\("cutscene_flag_[a-z0-9_]+_defeated"\\)')
	var hits := rx.search_all(src)
	var names: Array[String] = []
	for h in hits:
		names.append(h.get_string())
	assert_eq(names.size(), 0,
		"a defeat flag set without a battle grants an unfought victory: %s" % str(names))
	## CONTROL: the pattern DOES match that shape, so the zero above is a measurement.
	var planted := rx.search('\t_set_cutscene_flag_and_mirror("cutscene_flag_planted_defeated")')
	assert_not_null(planted, "CONTROL: the pattern must match an auto-set when one is present")


func test_the_w2_masterites_are_placed_as_real_fights() -> void:
	## Derived from the village's own source: each fight names its monster, the flag its world's
	## gates wait on, and an authored lead-in scene.
	var src := _source(MAPLE)
	for monster in W2_FIGHTS:
		assert_true(src.contains('monster_id = "%s"' % monster),
			"%s must be placed in Maple Heights" % monster)
		assert_true(src.contains('defeat_flag_name = "%s"' % W2_FIGHTS[monster]),
			"%s must write %s on victory" % [monster, W2_FIGHTS[monster]])
	## Only the Curator's intro is wired. The Arbiter's writes the very flag world2_chapter4 is
	## gated on NOT having, so playing it would cancel chapter4 for good; chapter4 is already
	## titled "Arbiter's Appeal" and serves as that intro.
	assert_true(src.contains('cutscene_id = "world2_curator_intro"'),
		"world2_curator_intro was authored with no dispatcher — the fight is its first caller")
	assert_false(src.contains('cutscene_id = "world2_arbiter_intro"'),
		"world2_arbiter_intro must stay unwired: it cancels world2_chapter4's gate")


func test_each_placed_fight_names_a_real_monster_and_scene() -> void:
	## The ids must resolve, or the encounter warns and skips at runtime and the world stalls.
	var mons: Dictionary = _json("res://data/monsters.json")
	for monster in W2_FIGHTS:
		assert_true(mons.has(monster), "%s must exist in monsters.json" % monster)
	for scene in ["world2_arbiter_intro", "world2_curator_intro",
			"world2_arbiter_defeat", "world2_curator_defeat"]:
		assert_true(FileAccess.file_exists("res://data/cutscenes/%s.json" % scene),
			"%s.json must exist on disk" % scene)


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
