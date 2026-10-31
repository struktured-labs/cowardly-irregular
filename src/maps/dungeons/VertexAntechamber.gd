extends DragonCave
class_name VertexAntechamberScene

## The Vertex Antechamber — the room before the last room, and the only one whose occupant is
## chosen by how you played.
##
## struktured 2026-10-26: "three sub final bosses, one for automated gamers, one for classic
## gmaes, one for one shottesr". TrialRouting shipped in v3.33.728 deciding WHICH, with its routing
## guarded and no arena to decide it in. This is that arena.
##
## One floor, like the Apex it opens onto. Encounters off — nothing random happens in a room that
## is only ever about one thing.

## Resolved in _ready BEFORE super._ready(), because DragonCave reads boss_id while generating the
## floor: _maybe_warn_out_of_league, the boss marker sprite and the BossTrigger all consult it.
## Setting it in _init would be too early — SaveSystem and GameState are not yet readable there.
var _trial: String = ""


func _init() -> void:
	cave_name = "The Vertex Antechamber"
	cave_id = "vertex_antechamber"
	## A placeholder until _ready routes it. Never fought: the classic occupant is also the
	## documented fallback, so if routing somehow fails the player still gets a real fight.
	boss_id = TrialRouting.monster_for(TrialRouting.TRIAL_CLASSIC)
	boss_flag_key = "vertex_antechamber_cleared"
	total_floors = 1
	overworld_exit_spawn = "antechamber"
	overworld_exit_map = "abstract_overworld"
	unlock_story_flag = "w6_trial_passed"

	## ⛔ NO defeat_cutscene_flags, DELIBERATELY. GameLoop._KNOWN_DEFEAT_CUTSCENE_FLAGS' own comment is
	## the reason: "when a subclass declares defeat_cutscene_flags and X isn't here, the flag gets set
	## but no gate fires — silent narrative drop", and it requires updating the set AND the gate. There
	## is no trial cutscene for a gate to return yet, so declaring the flag would set something nothing
	## reads — the authored-but-unread class. It lands with cowir-story's scene, not before it.
	##
	## The MECHANICAL gates are already here and do not need a cutscene: boss_flag_key marks the room
	## cleared and unlock_story_flag is what a future Apex gate would read.

	## No boss_cutscene_id. DragonCave falls back to the console announce when it is empty, and the
	## three intros are cowir-story's to author — an id pointing at missing JSON would red
	## test_orphan_boss_cutscene_registry, and inventing one to look finished is worse than absent.

	# A single chamber, narrower than the Apex. One chest by the door, like the Apex's own "last
	# kindness" — every layout-driven dungeon keeps at least one T, which
	# test_the_dungeon_layouts_are_walkable enforces and which my first draft broke by giving the room
	# no treasure for flavour reasons. Legend: M=wall, .=floor, B=boss, T=treasure, D=exit.
	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMM........MMMMMM",
			"MMMM............MMMM",
			"MMM..............MMM",
			"MM................MM",
			"MM.......B........MM",
			"MM................MM",
			"MM................MM",
			"MMM..............MMM",
			"MMM..............MMM",
			"MM................MM",
			"MMMM............MMMM",
			"MMMMMM.T.D....MMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}


func _ready() -> void:
	_trial = _resolve_trial()
	boss_id = TrialRouting.monster_for(_trial)
	super._ready()
	print("[ANTECHAMBER] trial=%s occupant=%s" % [_trial, boss_id])
	# Nothing random happens in this room.
	if EncounterSystem and EncounterSystem.encounters_enabled:
		EncounterSystem.encounters_enabled = false
		_suppressed_encounters = true


## Every reach is guarded because this scene is instantiable with no GameLoop — the tileset and
## exit-spawn guards do exactly that. A null director yields "balanced", which TrialRouting
## documents as landing on the classic trial.
func _resolve_trial() -> String:
	var director: Node = null
	var gl: Node = get_tree().root.get_node_or_null("GameLoop") if is_inside_tree() else null
	if gl != null and gl.has_method("get_cutscene_director"):
		director = gl.get_cutscene_director()
	return TrialRouting.trial_from_game(director, SaveSystem, GameState)


func _get_music_area_id() -> String:
	return "abstract_dungeon"


func _char_to_tile_type(char: String) -> int:
	return _remap_wall_floor(char, TileGeneratorScript.TileType.ABSTRACT_WALL, TileGeneratorScript.TileType.ABSTRACT_FLOOR)


func _get_dungeon_ambient() -> Color:
	return Color(0.19, 0.17, 0.28)


## Hands back only what it took — the same shape VertexApex uses, and for the reason recorded there:
## _exit_tree has no knowledge of who disabled encounters, so it must not answer for them.
var _suppressed_encounters: bool = false


func _exit_tree() -> void:
	if EncounterSystem and _suppressed_encounters:
		EncounterSystem.encounters_enabled = true
	_suppressed_encounters = false
