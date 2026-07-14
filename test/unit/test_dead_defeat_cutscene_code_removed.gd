extends GutTest

## tick 105 cleanup: the legacy `defeat_cutscene` field and
## DragonCave._on_boss_defeated function had NO callers — pure dead
## code. Ticks 102-104 wired the actual mechanism (GameLoop gates).
## This tick removes the misleading dead code so future maintainers
## don't keep adding to it.
##
## Negative pin: anything that re-introduces the field or function
## fails this test, prompting a check that the new code path is
## actually wired through (via GameLoop._get_pending_story_cutscene
## gates, not a dungeon-side handler).

const DRAGON_CAVE := "res://src/maps/dungeons/DragonCave.gd"
const SUBCLASSES_WITH_REMOVED_FIELD: Array[String] = [
	"res://src/maps/dungeons/SuburbanUnderground.gd",
	"res://src/maps/dungeons/SteampunkMechanism.gd",
	"res://src/maps/dungeons/AssemblyCore.gd",
	"res://src/maps/dungeons/RootProcess.gd",
	"res://src/maps/dungeons/CastleHarmonia.gd",
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_dragon_cave_no_longer_declares_defeat_cutscene_field() -> void:
	var src := _read(DRAGON_CAVE)
	assert_false(src.contains("var defeat_cutscene: String"),
		"DragonCave must NOT declare `var defeat_cutscene: String` — that field had no read path (dead code)")


func test_dragon_cave_no_longer_has_on_boss_defeated_function() -> void:
	var src := _read(DRAGON_CAVE)
	assert_false(src.contains("func _on_boss_defeated()"),
		"DragonCave must NOT define _on_boss_defeated — it had no caller anywhere in the codebase")


func test_subclasses_no_longer_assign_defeat_cutscene() -> void:
	for path in SUBCLASSES_WITH_REMOVED_FIELD:
		var src := _read(path)
		assert_false(src.contains("defeat_cutscene = \""),
			"%s must NOT assign defeat_cutscene = '<id>' — the field was removed in tick 105" % path)


func test_defeat_cutscene_flags_field_still_present() -> void:
	# This field IS used — _trigger_boss packs it into
	# GameState.pending_boss_defeat spec, which GameLoop applies on
	# victory. Cleanup must NOT touch it.
	var src := _read(DRAGON_CAVE)
	assert_true(src.contains("var defeat_cutscene_flags: Array[String] = []"),
		"DragonCave must still declare defeat_cutscene_flags — used by pending_boss_defeat to push flags into game_constants")


func test_defeat_cutscene_flags_still_set_in_subclasses() -> void:
	# Negative pin: subclasses that previously declared
	# defeat_cutscene_flags must keep their declarations.
	for path in [
		"res://src/maps/dungeons/SuburbanUnderground.gd",
		"res://src/maps/dungeons/SteampunkMechanism.gd",
		"res://src/maps/dungeons/AssemblyCore.gd",
		"res://src/maps/dungeons/RootProcess.gd",
		"res://src/maps/dungeons/CastleHarmonia.gd",
	]:
		var src := _read(path)
		assert_true(src.contains("defeat_cutscene_flags = ["),
			"%s must still declare defeat_cutscene_flags — that's the LIVE bridge, not the removed defeat_cutscene field" % path)


func test_defeat_cutscene_gates_in_game_loop_still_present() -> void:
	# Sanity: the actual mechanism (GameLoop gates) is intact. If a
	# future revert restores the dead code AND breaks the gates, the
	# defeat cutscenes silently stop playing.
	var src := _read("res://src/GameLoop.gd")
	for cutscene_id in [
		"world1_rat_king_defeat",
		"world1_mordaine_defeat",
		"world2_warden_defeat",
		"world3_tempo_defeat",
		"world4_warden_defeat",
		"world5_arbiter_defeat",
	]:
		assert_true(src.contains("return \"" + cutscene_id + "\""),
			"GameLoop must still gate %s — the live mechanism replacing the removed defeat_cutscene field" % cutscene_id)


func test_dragon_cave_still_compiles_via_pending_boss_defeat_path() -> void:
	# The boss-defeat side effects (boss_defeated, unlock_story_flag,
	# unlock_world, dungeon_flag) are now ALL applied via
	# GameLoop._apply_pending_boss_defeat. Pin that path stays.
	var gl_src := _read("res://src/GameLoop.gd")
	assert_true(gl_src.contains("func _apply_pending_boss_defeat"),
		"_apply_pending_boss_defeat must still exist — replaces _on_boss_defeated for the side-effect work")
	assert_true(gl_src.contains("GameState.pending_boss_defeat"),
		"GameState.pending_boss_defeat must still be the channel — set by _trigger_boss, read by _apply_pending_boss_defeat")
