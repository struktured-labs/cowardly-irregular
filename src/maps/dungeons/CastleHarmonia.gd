extends DragonCave
class_name CastleHarmoniaScene

## Castle Harmonia — Chancellor Mordaine's four-floor W1 climax.
##
## Ascending arc: Great Hall (F1) → Antechamber of the Petrified Court (F2)
## → Corrupted Throne Room (F3) → Mordaine's Inner Sanctum (F4). Reuses the
## DragonCave engine (stair markers U/D/B, letter parser, boss trigger,
## save-crystal auto-placement on F1 + F3). Encounter density scales F1→F3;
## F4 is the boss floor (no random encounters, boss trigger on the B tile).
##
## Story wiring (playtest v3.33.147 redesign, msg 2525):
##  - `world1_throne_room_approach` plays as a threshold cutscene the first
##    time the player arrives on F4 (letterboxed narration, sets its own
##    completion flag). Uses GameLoop.get_cutscene_director() — the correct
##    path (CutsceneDirector is GameLoop-owned, not autoloaded; the /root/
##    lookup silently falls back, same class as the TallyWall bug fixed
##    2026-07-08).
##  - `world1_mordaine_intro` still fires from the DragonCave boss trigger
##    once the player steps into the B marker's zone on F4.
##  - Defeating Mordaine sets `cutscene_flag_world1_mordaine_defeated` and
##    `w1_boss_defeated`, unlocks W2 via GameLoop's pending_boss_defeat.

const THRONE_APPROACH_ID: String = "world1_throne_room_approach"
const THRONE_APPROACH_FLAG: String = "cutscene_flag_world1_throne_room_approach_complete"


func _init() -> void:
	cave_name = "Castle Harmonia"
	cave_id = "castle_harmonia"
	boss_id = "chancellor_mordaine"
	# BossDialogue persona (matches data/boss_dialogue.json entry key so
	# BattleManager._update_boss_dialogue_phase finds Mordaine's intents).
	boss_llm_persona_id = "chancellor_mordaine"
	boss_cutscene_id = "world1_mordaine_intro"
	boss_flag_key = "world1_mordaine_defeated"
	total_floors = 4
	overworld_exit_spawn = "castle_entrance"

	unlock_world = 2
	defeat_cutscene_flags = ["cutscene_flag_world1_mordaine_defeated"]
	unlock_story_flag = "w1_boss_defeated"

	# Four-floor arc. Legend: M=stone wall, .=floor, T=treasure chest,
	# U=up stairs (to floor N+1), D=down stairs (to N-1 or overworld
	# on F1), B=boss marker. Each row is 20 chars; grid is 20×16.
	floor_layouts = {
		# F1 — the Great Hall. Grand entrance colonnade flanked by side
		# alcoves (treasure), inner sanctum at the north with a raised
		# throne dais (U stairs sit where the old throne was hauled off).
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..MMMM......MMMM..M",
			"M..M..T......T..M..M",
			"M..M............M..M",
			"M..MMMM......MMMM..M",
			"M..................M",
			"M....MMMMMMMMMM....M",
			"M....M........M....M",
			"M....M....U...M....M",
			"M....M........M....M",
			"M....MMMM..MMMM....M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		# F2 — Antechamber of the Petrified Court. Courtiers frozen
		# mid-objection stand as pillar pairs; the party threads through
		# the pauses between arguments to reach the north stairs.
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..MM..T....T..MM..M",
			"M..MM..........MM..M",
			"M..................M",
			"M.....MM....MM.....M",
			"M.....MM....MM.....M",
			"M..................M",
			"M..T............T..M",
			"M..................M",
			"M.....MM..U.MM.....M",
			"M.....MM....MM.....M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		# F3 — Corrupted Throne Room. The rightful monarch's overturned
		# throne dominates the center (the inner MMMMMM alcove); banners
		# in shreds along the walls (outer pillar columns). Save crystal
		# auto-places here (penultimate floor before the boss).
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M...T..........T...M",
			"M..................M",
			"M.MMM..........MMM.M",
			"M.M..............M.M",
			"M.M....MMMMMM....M.M",
			"M.M....M....M....M.M",
			"M.M....M....M....M.M",
			"M.M....MMMMMM....M.M",
			"M.M..............M.M",
			"M.MMM..........MMM.M",
			"M..........U.......M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		# F4 — Mordaine's Inner Sanctum. She waits at B, seated in the
		# plain chair beside where the throne used to be — the approach
		# cutscene sells the reveal on the threshold, then the boss
		# trigger fires the full Mordaine intro.
		4: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..T............T..M",
			"M..................M",
			"M....MMMM..MMMM....M",
			"M....M........M....M",
			"M....M........M....M",
			"M....M...B....M....M",
			"M....M........M....M",
			"M....M........M....M",
			"M....MMMM..MMMM....M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	# Down-direction spawn on F1 uses the "entrance" key (see
	# DragonCave._transition_to_floor); the "castle_entrance" alias
	# preserves compatibility with any previous save that stored the
	# original single-floor spawn name.
	floor_spawn_points = {
		1: {"entrance": Vector2(10, 14), "castle_entrance": Vector2(10, 14)},
		2: {"entrance": Vector2(10, 14)},
		3: {"entrance": Vector2(10, 14)},
		4: {"entrance": Vector2(10, 14)},
	}

	# Encounter pool + rate (base 6% at F1, +2% per floor). Palette
	# escalates from residual undead (courtyard aftermath) → shadow
	# knights (Mordaine's real guard) → meta-knight ("the corruption
	# knows who you are" — matches Mordaine's Calibrant facet). F4 is
	# a boss floor (rate forced to 0 by DragonCave).
	floor_encounter_pools = {
		1: ["skeleton", "specter"],
		2: ["shadow_knight", "skeleton"],
		3: ["shadow_knight", "meta_knight"],
		4: [],
	}


func _ready() -> void:
	super._ready()
	# Cover both entry paths for the threshold cutscene: (a) fresh scene
	# load already on F4 (save restore, dungeon_skip warp) — handled
	# right here; (b) arriving via stair transition — handled by the
	# floor_changed hook. The flag gate makes both paths idempotent.
	floor_changed.connect(_on_floor_changed)
	if current_floor == total_floors:
		_maybe_play_throne_approach()


func _on_floor_changed(new_floor: int) -> void:
	if new_floor == total_floors:
		_maybe_play_throne_approach()


## Fires world1_throne_room_approach once — the "the doors open onto a
## room that has forgotten which end is the top" beat. The cutscene sets
## its own completion flag; we gate on it so re-entering F4 doesn't
## replay. Missing JSON = graceful no-op (writes the flag so the boss
## trigger still fires cleanly on the next tick).
func _maybe_play_throne_approach() -> void:
	if GameState == null or GameState.get_story_flag(THRONE_APPROACH_FLAG):
		return
	var game_loop = get_node_or_null("/root/GameLoop")
	if game_loop == null or not game_loop.has_method("get_cutscene_director"):
		return
	var director = game_loop.get_cutscene_director()
	if director == null or not director.has_method("play_cutscene"):
		return
	var cutscene_path := "res://data/cutscenes/%s.json" % THRONE_APPROACH_ID
	if not FileAccess.file_exists(cutscene_path):
		# Belt-and-suspenders: cutscene missing on disk shouldn't strand
		# a repeat playtester on the threshold — mark seen and continue.
		GameState.set_story_flag(THRONE_APPROACH_FLAG)
		return
	await director.play_cutscene(THRONE_APPROACH_ID)
