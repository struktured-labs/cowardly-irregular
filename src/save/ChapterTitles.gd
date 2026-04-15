extends Node
class_name ChapterTitles

## Maps story-flag state to a friendly "World N — Chapter K: Title" string for
## the save/load screen and any other metadata surface that needs it.
##
## The source of truth for story progression is still the cutscene_flag_*
## entries in GameState.game_constants. This is a read-only derivation —
## writing here would split state and cause drift.

## Ordered progression of story beats. The LAST entry whose flag is set
## is the player's current chapter.
const CHAPTERS := [
	{"flag": "cutscene_flag_prologue_complete",         "world": 1, "chapter": 0, "title": "Prologue"},
	{"flag": "cutscene_flag_chapter1_complete",         "world": 1, "chapter": 1, "title": "The Summons"},
	{"flag": "cutscene_flag_chapter2_complete",         "world": 1, "chapter": 2, "title": "The Road North"},
	{"flag": "cutscene_flag_chapter3_complete",         "world": 1, "chapter": 3, "title": "The Whispering Cave"},
	{"flag": "cutscene_flag_chapter4_complete",         "world": 1, "chapter": 4, "title": "The Warden's Chain"},
	{"flag": "cutscene_flag_chapter5_complete",         "world": 1, "chapter": 5, "title": "Into the Forest"},
	{"flag": "cutscene_flag_chapter5_forest_entered",   "world": 1, "chapter": 5, "title": "Tempo's Chase"},
	{"flag": "cutscene_flag_chapter7_complete",         "world": 1, "chapter": 7, "title": "The Capital"},
	{"flag": "cutscene_flag_chapter8_complete",         "world": 1, "chapter": 8, "title": "Scholar's Reckoning"},
	{"flag": "cutscene_flag_chapter9_complete",         "world": 1, "chapter": 9, "title": "The Throne"},
	{"flag": "cutscene_flag_world1_mordaine_defeated",  "world": 1, "chapter": 10, "title": "Mordaine Falls"},
	{"flag": "cutscene_flag_world2_prologue_complete",  "world": 2, "chapter": 0, "title": "Suburban Arrival"},
	{"flag": "cutscene_flag_world2_chapter1_complete",  "world": 2, "chapter": 1, "title": "Maple Heights"},
	{"flag": "cutscene_flag_world2_chapter2_complete",  "world": 2, "chapter": 2, "title": "Mail & Malice"},
	{"flag": "cutscene_flag_world2_chapter3_complete",  "world": 2, "chapter": 3, "title": "Warden of Routine"},
	{"flag": "cutscene_flag_chapter4_garage_complete",  "world": 2, "chapter": 4, "title": "The Garage Sale"},
	{"flag": "cutscene_flag_arbiter_suburban_intro_complete", "world": 2, "chapter": 4, "title": "Arbiter's Appeal"},
	{"flag": "cutscene_flag_arbiter_suburban_defeated", "world": 2, "chapter": 5, "title": "The Community Center"},
	{"flag": "cutscene_flag_world2_chapter5_complete",  "world": 2, "chapter": 5, "title": "The Coordinator's Reveal"},
	{"flag": "cutscene_flag_curator_suburban_defeated", "world": 2, "chapter": 7, "title": "Feral Infrastructure"},
	{"flag": "cutscene_flag_chapter7_infrastructure_complete", "world": 2, "chapter": 7, "title": "The Shopping Cart"},
	{"flag": "cutscene_flag_chapter8_memos_found",      "world": 2, "chapter": 8, "title": "The Memos"},
	{"flag": "cutscene_flag_chapter11_complete",        "world": 2, "chapter": 11, "title": "Crossing Over"},
	{"flag": "cutscene_flag_world2_complete",           "world": 2, "chapter": 12, "title": "Suburban Sprawl Falls"},
	{"flag": "cutscene_flag_world3_prologue_complete",  "world": 3, "chapter": 0, "title": "Steam & Steel"},
	{"flag": "cutscene_flag_world3_chapter1_complete",  "world": 3, "chapter": 1, "title": "Brasston Village"},
	{"flag": "cutscene_flag_world3_chapter2_complete",  "world": 3, "chapter": 2, "title": "The Mechanism"},
	{"flag": "cutscene_flag_world3_chapter3_complete",  "world": 3, "chapter": 3, "title": "Industrial Dissent"},
	{"flag": "cutscene_flag_warden_industrial_defeated", "world": 3, "chapter": 4, "title": "Warden of Steam"},
	{"flag": "cutscene_flag_world3_chapter4_complete",  "world": 3, "chapter": 4, "title": "The Steam Core"},
	{"flag": "cutscene_flag_world3_chapter5_complete",  "world": 3, "chapter": 5, "title": "Airship Departure"},
	{"flag": "cutscene_flag_world3_complete",           "world": 3, "chapter": 6, "title": "Steampunk Falls"},
	{"flag": "cutscene_flag_world4_prologue_complete",  "world": 4, "chapter": 0, "title": "The Factory Floor"},
	{"flag": "cutscene_flag_world4_chapter1_complete",  "world": 4, "chapter": 1, "title": "Rivet Row"},
	{"flag": "cutscene_flag_world4_chapter2_complete",  "world": 4, "chapter": 2, "title": "Assembly Lines"},
	{"flag": "cutscene_flag_world4_chapter3_complete",  "world": 4, "chapter": 3, "title": "The Director"},
	{"flag": "cutscene_flag_world4_chapter4_complete",  "world": 4, "chapter": 4, "title": "Logic Gates"},
	{"flag": "cutscene_flag_world4_chapter5_complete",  "world": 4, "chapter": 5, "title": "Industrial Collapse"},
	{"flag": "cutscene_flag_world4_complete",           "world": 4, "chapter": 6, "title": "The Factory Falls"},
	{"flag": "cutscene_flag_world5_prologue_complete",  "world": 5, "chapter": 0, "title": "The Network"},
	{"flag": "cutscene_flag_world5_chapter1_complete",  "world": 5, "chapter": 1, "title": "Node Prime"},
	{"flag": "cutscene_flag_world5_chapter2_complete",  "world": 5, "chapter": 2, "title": "Packet Storms"},
	{"flag": "cutscene_flag_world5_chapter3_complete",  "world": 5, "chapter": 3, "title": "The Core"},
	{"flag": "cutscene_flag_world5_chapter4_complete",  "world": 5, "chapter": 4, "title": "Digital Reformation"},
	{"flag": "cutscene_flag_world5_chapter5_complete",  "world": 5, "chapter": 5, "title": "System Collapse"},
	{"flag": "cutscene_flag_world5_complete",           "world": 5, "chapter": 6, "title": "The Network Falls"},
	{"flag": "cutscene_flag_world6_prologue_complete",  "world": 6, "chapter": 0, "title": "The Vertex"},
	{"flag": "cutscene_flag_world6_chapter1_complete",  "world": 6, "chapter": 1, "title": "Abstract Seas"},
	{"flag": "cutscene_flag_world6_chapter2_complete",  "world": 6, "chapter": 2, "title": "The Question"},
	{"flag": "cutscene_flag_world6_chapter3_complete",  "world": 6, "chapter": 3, "title": "The Answer"},
]

const WORLD_NAMES := {
	1: "Medieval", 2: "Suburban", 3: "Steampunk",
	4: "Industrial", 5: "Digital", 6: "Abstract",
}


## Returns {world, chapter, title, world_name}. If no flags are set, returns
## the opening state (World 1 / "The Beginning").
static func derive(game_constants: Dictionary) -> Dictionary:
	var current := {
		"world": 1,
		"chapter": 0,
		"title": "The Beginning",
		"world_name": WORLD_NAMES.get(1, ""),
	}
	for entry in CHAPTERS:
		if game_constants.get(entry.flag, false):
			current = {
				"world": entry.world,
				"chapter": entry.chapter,
				"title": entry.title,
				"world_name": WORLD_NAMES.get(entry.world, ""),
			}
	return current


static func world_name(world: int) -> String:
	return WORLD_NAMES.get(world, "")
