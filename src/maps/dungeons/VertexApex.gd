extends DragonCave
class_name VertexApexScene

## The Vertex Apex — the Calibrant's arena, and the last room in the game.
##
## Until now the Calibrant "battle" was elided as narrative (GameLoop's W6 closer went
## chapter3 -> calibrant_defeat -> ending) because no arena existed. The confrontation's
## 86-step setpiece, world6_calibrant_intro, was authored and never played. This is the
## room that lets it play.
##
## One floor by design. The dragon caves and Castle Harmonia earn their length by
## ascending; there is nothing to ascend to here. The player arrives having already been
## everywhere. Encounters are off — nothing random happens in a room that is only ever
## about one thing.

func _init() -> void:
	cave_name = "The Vertex Apex"
	cave_id = "vertex_apex"
	boss_id = "the_calibrant"
	boss_llm_persona_id = "the_calibrant"
	boss_cutscene_id = "world6_calibrant_intro"
	boss_flag_key = "world6_calibrant_defeated"
	total_floors = 1
	overworld_exit_spawn = "apex"
	overworld_exit_map = "abstract_overworld"

	defeat_cutscene_flags = ["cutscene_flag_world6_calibrant_defeated"]
	unlock_story_flag = "w6_calibrant_defeated"

	# A single chamber. The walk from D to B is deliberately long and quiet — one chest by
	# the door (the game's last kindness), then nothing but floor. Legend: M=wall, .=floor,
	# B=boss, T=treasure, D=exit.
	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMM......MMMMMMM",
			"MMMM............MMMM",
			"MM................MM",
			"M..................M",
			"M........B.........M",
			"M..................M",
			"M..................M",
			"MM................MM",
			"MM................MM",
			"M..................M",
			"M..................M",
			"MM................MM",
			"MMMM....T.......MMMM",
			"MMMMMMM..D...MMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}


## Every non-medieval dungeon overrides this; without it DragonCave's "cave" maps to the
## MEDIEVAL suffix and the finale scores to World 1 cave + boss music. Sibling key on
## purpose: an unmatched new key falls through play_area_music to OVERWORLD music, worse.
func _get_music_area_id() -> String:
	return "abstract_dungeon"


## ⛔ HANDS BACK ONLY WHAT IT TOOK. `_exit_tree` used to write `true` unconditionally, so leaving
## this room re-enabled encounters for a caller that had asked for them OFF — the render smoke
## disables them at startup and this handed them back mid-run (cowir-deploy/cowir-main, 2026-09-18).
## `_exit_tree` has no knowledge of who disabled them, so it must not answer for them.
##
## 🔑 THE CLAIM IS GATED ON "THEY ARE CURRENTLY ON", WHICH MAKES THE LITERAL CORRECT BY
## CONSTRUCTION AND NEEDS NO SNAPSHOT: `_suppressed_encounters` can only be true if they WERE on,
## so `true` is the right value for every state that can reach the restore. cowir-music's
## `_hidden_by_submenu` shape — membership IS the capture — simplified from my own two-member
## version by cowir-battle.
##
## ⚠️ IT ALSO COVERS RE-ENTRY FOR FREE, WHICH A NAIVE SAVE/RESTORE GETS WRONG IN THE OPPOSITE
## DIRECTION: a second `_ready` without an intervening `_exit_tree` finds them already false, does
## not claim, and cannot overwrite anything. An ungated `_prev = encounters_enabled` would store
## the ALREADY-FALSE value and disable encounters permanently — silent, and worse than this bug.
##
## 📌 LATENT TODAY, STATED SO IT IS NOT READ AS LIVE: the smoke is the only other writer, so
## nothing in normal play disables encounters for this room to re-enable. It goes live the day a
## cutscene, a scripted sequence, or another smoke leg does.
var _suppressed_encounters: bool = false


func _ready() -> void:
	super._ready()
	# Nothing random happens in this room.
	if EncounterSystem and EncounterSystem.encounters_enabled:
		EncounterSystem.encounters_enabled = false
		_suppressed_encounters = true


## ⚠️ NO "DID SOMEBODY RE-ENABLE THEM WHILE WE WERE HERE" CHECK, AND THAT IS MEASURED. I wrote one
## — `and not EncounterSystem.encounters_enabled` — and mutating it away red NOTHING: if they were
## re-enabled inside, they are already `true`, so the write is a no-op. The clause could not change
## an outcome, and the arm I wrote for it could not fail.
func _exit_tree() -> void:
	## Only hand them back if we took them.
	if EncounterSystem and _suppressed_encounters:
		EncounterSystem.encounters_enabled = true
	_suppressed_encounters = false
