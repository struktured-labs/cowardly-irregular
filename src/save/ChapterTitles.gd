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
	# Tick 240: bridge the W1 ch3 boss → ch4 gap. Pre-fix the title stayed "The Whispering Cave" after defeating Rat King until the chapter4 cutscene fired, leaving a stale "in cave" feeling on save slots.
	{"flag": "cutscene_flag_world1_rat_king_defeat_complete", "world": 1, "chapter": 3, "title": "Rat King Falls"},
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
	# Tick 241: missing boss-defeat title for W2 Warden. Mirrors W1 mordaine_defeated and W3 tempo_steampunk_defeated entries — fires immediately on boss KO via defeat_cutscene_flags (set by SuburbanUnderground subclass).
	{"flag": "cutscene_flag_warden_suburban_defeated",  "world": 2, "chapter": 3, "title": "Warden of Routine Falls"},
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
	# Tick 241: BUG FIX. Pre-fix this entry used the W4 industrial-warden flag (cutscene_flag_warden_industrial_defeated) — likely a copy-paste error since W3's actual boss is Tempo. A player defeating the W4 Industrial Warden before completing W4 chapter4 would see their chapter title silently rewind to W3 ch4 "Warden of Steam". W3's actual boss-defeat flag is cutscene_flag_tempo_steampunk_defeated.
	{"flag": "cutscene_flag_tempo_steampunk_defeated",  "world": 3, "chapter": 4, "title": "Tempo Falls"},
	{"flag": "cutscene_flag_world3_chapter4_complete",  "world": 3, "chapter": 4, "title": "The Steam Core"},
	{"flag": "cutscene_flag_world3_chapter5_complete",  "world": 3, "chapter": 5, "title": "Airship Departure"},
	{"flag": "cutscene_flag_world3_complete",           "world": 3, "chapter": 6, "title": "Steampunk Falls"},
	{"flag": "cutscene_flag_world4_prologue_complete",  "world": 4, "chapter": 0, "title": "The Factory Floor"},
	{"flag": "cutscene_flag_world4_chapter1_complete",  "world": 4, "chapter": 1, "title": "Rivet Row"},
	{"flag": "cutscene_flag_world4_chapter2_complete",  "world": 4, "chapter": 2, "title": "Assembly Lines"},
	{"flag": "cutscene_flag_world4_chapter3_complete",  "world": 4, "chapter": 3, "title": "The Director"},
	# Tick 241: missing boss-defeat title for W4 Industrial Warden. Set by AssemblyCore subclass's defeat_cutscene_flags. Pre-fix the title silently rewound to W3 "Warden of Steam" because the SAME flag was misplaced there (now fixed).
	{"flag": "cutscene_flag_warden_industrial_defeated", "world": 4, "chapter": 3, "title": "Warden of Industrial Falls"},
	{"flag": "cutscene_flag_world4_chapter4_complete",  "world": 4, "chapter": 4, "title": "Logic Gates"},
	{"flag": "cutscene_flag_world4_chapter5_complete",  "world": 4, "chapter": 5, "title": "Industrial Collapse"},
	{"flag": "cutscene_flag_world4_complete",           "world": 4, "chapter": 6, "title": "The Factory Falls"},
	{"flag": "cutscene_flag_world5_prologue_complete",  "world": 5, "chapter": 0, "title": "The Network"},
	{"flag": "cutscene_flag_world5_chapter1_complete",  "world": 5, "chapter": 1, "title": "Node Prime"},
	{"flag": "cutscene_flag_world5_chapter2_complete",  "world": 5, "chapter": 2, "title": "Packet Storms"},
	{"flag": "cutscene_flag_world5_chapter3_complete",  "world": 5, "chapter": 3, "title": "The Core"},
	# Tick 241: missing boss-defeat title for W5 Arbiter. Set by RootProcess subclass's defeat_cutscene_flags.
	{"flag": "cutscene_flag_arbiter_futuristic_defeated", "world": 5, "chapter": 3, "title": "Arbiter Falls"},
	{"flag": "cutscene_flag_world5_chapter4_complete",  "world": 5, "chapter": 4, "title": "Digital Reformation"},
	{"flag": "cutscene_flag_world5_chapter5_complete",  "world": 5, "chapter": 5, "title": "System Collapse"},
	{"flag": "cutscene_flag_world5_complete",           "world": 5, "chapter": 6, "title": "The Network Falls"},
	{"flag": "cutscene_flag_world6_prologue_complete",  "world": 6, "chapter": 0, "title": "The Vertex"},
	{"flag": "cutscene_flag_world6_chapter1_complete",  "world": 6, "chapter": 1, "title": "Abstract Seas"},
	{"flag": "cutscene_flag_world6_chapter2_complete",  "world": 6, "chapter": 2, "title": "The Question"},
	{"flag": "cutscene_flag_world6_chapter3_complete",  "world": 6, "chapter": 3, "title": "The Answer"},
	# Tick 240: post-game progression. Pre-fix a player who beat the Calibrant or finished the game still saw "Chapter 3: The Answer" on their save slot — incomplete-feeling end state. The completion flags are durable (set by _play_story_cutscene's post-cutscene hook) so they persist across saves/sessions.
	{"flag": "cutscene_flag_world6_calibrant_defeat_complete", "world": 6, "chapter": 4, "title": "Calibrant Falls"},
	{"flag": "cutscene_flag_world6_ending_complete",    "world": 6, "chapter": 5, "title": "The End"},
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
