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


func _ready() -> void:
	super._ready()
	# Nothing random happens in this room.
	if EncounterSystem:
		EncounterSystem.encounters_enabled = false


func _exit_tree() -> void:
	if EncounterSystem:
		EncounterSystem.encounters_enabled = true
