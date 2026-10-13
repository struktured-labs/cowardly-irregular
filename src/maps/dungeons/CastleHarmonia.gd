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

## struktured 2026-08-22: "u shouldnt be able to fight mordain until u take out her warden".
const WARDEN_ID: String = "castle_warden"
const WARDEN_FLAG: String = "castle_warden_defeated"
var _warden_triggered: bool = false


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
			"M........L.........M",
			"M....MMMMMMMMMM....M",
			"M....M........M....M",
			"M....M....U...M....M",
			"M....M........M....M",
			"M....MMMM..MMMM..e.M",
			"M.T................M",
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
			"M........S.........M",
			"M.....MM....MM.....M",
			"M.....MM....MM.....M",
			"M..................M",
			"M..T............T..M",
			"M..................M",
			"M.....MM..U.MM.....M",
			"M.....MM....MM.....M",
			"M................T.M",
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
			"M...T..........T.e.M",
			"M..................M",
			"M.MMM..........MMM.M",
			"M.M..............M.M",
			"M.M....MMMMMM....M.M",
			"M.M....M....M....M.M",
			"M.M....M....M....M.M",
			"M.M....MMMMMM....M.M",
			"M.T..............M.M",
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
			"M........T.........M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	# Down-direction spawn on F1 uses the "entrance" key (see
	# DragonCave._transition_to_floor); the "castle_entrance" alias
	# preserves compatibility with any previous save that stored the
	# original single-floor spawn name.
	# 2026-07-26 playtest ("got stuck in castle harmonia... cant go up or down"): the entrance
	# sat on tile (10,14) — the SAME tile as every floor's 'D' marker. Spawning inside a 48x48
	# walk-on stair sensor fires it on the first physics frame: on F1 that is the overworld
	# AreaTransition (latch spent, exit dead), on F2-F4 the descend sensor (instant cascade down).
	# (10,12) is walkable on all four floors and clears every U and D trigger by >=48px.
	floor_spawn_points = {
		1: {"entrance": Vector2(10, 12), "castle_entrance": Vector2(10, 12)},
		2: {"entrance": Vector2(10, 12)},
		3: {"entrance": Vector2(10, 12)},
		4: {"entrance": Vector2(10, 12)},
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

	# struktured 2026-09-06 depth pass: a lever shortcut (F1), an ambush plate
	# in the Antechamber (F2), and a portal pair linking the Great Hall to the
	# archives wing on F3 -- additive only, none of the original geometry moved.
	switch_effects = {
		"sw0": {"flip": [[9, 7]]},
		"sw1": {"trap": "encounter"},
	}
	forced_item_chests = {
		"castle_harmonia_f1_c2": "hi_ether",
		"castle_harmonia_f2_c4": "gold_needle",
		"castle_harmonia_f3_c2": "elixir",
		"castle_harmonia_f4_c2": "equipment:dragon_mail",
	}


const _LORE := {
	1: [
		{"pos": Vector2(9, 5), "text": "A lever behind the colonnade. The staff swore they never installed one."},
		{"pos": Vector2(17, 10), "text": "The floor grate hums faintly. Somewhere below, the archives are listening."},
	],
	2: [
		{"pos": Vector2(9, 3), "text": "The Petrified Court. Do not touch the plaques. Do not touch the plate either."},
	],
	3: [
		{"pos": Vector2(17, 1), "text": "The grate on the other end. The archives were never on the tour."},
	],
	4: [
		{"pos": Vector2(9, 1), "text": "The Chancellor's Warden is dealt with. Whatever waits past this hall is not."},
	],
}


## Where each authored castle NPC stands. The LINES are not here — they live in
## `data/castle_harmonia_narrative.json`, which has been authored and unreachable since 2026-07-13
## (cowir-story's census: 510 words, no `src` consumer). Floor and role come from the pack too; this
## table carries only what the pack cannot know, which is the cell.
const _NPC_MARKS := {
	"castle_guard_young": Vector2(6, 8),
	"castle_guard_captain": Vector2(14, 6),
	"castle_guard_bureaucrat": Vector2(7, 5),
	"castle_servant_witness": Vector2(13, 4),
	"castle_guard_husk": Vector2(8, 2),
}
const _NARRATIVE_PACK := "res://data/castle_harmonia_narrative.json"
const _EXAMINE_PACK := "res://data/examine_texts.json"
const _ROOM_BEAT := "room_beat"

## Where each authored castle examine is READ FROM. The TEXT is not here — it lives in
## `data/examine_texts.json`, authored 2026-04-21 and reachable by nobody since.
##
## ⛔ THE FLOOR IS MINE, NOT THE PACK'S, recorded rather than implied: the pack carries
## `world / scene / prop / name / text` and NO floor, so these are my inference, anchored to the
## castle's own `_LORE` rooms — floor 1 the entrance hall, floor 2 "The Petrified Court", floor 3
## the archives and apartments, floor 4 the Mordaine approach left deliberately bare.
## @cowir-story flagged four of their fifteen re-keys as inferences; these eleven floors are eleven
## more, and a reader should be able to tell which facts came from the author.
##
## 🔑 THE CELL IS THE TILE THE PLAYER STANDS ON, NOT THE OBJECT'S OWN — @cowir-story's design and
## the flat geometry agreeing. Every text is written in second person doing the looking, and
## `DragonCave` sets `Mode7Overlay.is_active = false`, so `READABLE_BOX_FLAT` (28px) means a
## readable here is pressable only by STANDING ON IT. Keying to the looking-tile makes that the
## correct behaviour rather than a compromise.
const _EXAMINE_MARKS := {
	1: {
		"castle_harmonia_foyer_narration": Vector2(10, 7),
		"castle_harmonia_overpainted_tapestry": Vector2(5, 6),
		"castle_harmonia_frozen_captain": Vector2(15, 8),
	},
	2: {
		"castle_harmonia_council_narration": Vector2(11, 6),
		"castle_harmonia_petrified_courtier": Vector2(7, 4),
		"castle_harmonia_broken_seal": Vector2(16, 7),
		"castle_harmonia_abandoned_desk": Vector2(5, 9),
	},
	3: {
		"castle_harmonia_apartments_narration": Vector2(12, 5),
		"castle_harmonia_relocked_door": Vector2(8, 3),
		"castle_harmonia_worn_wax": Vector2(14, 9),
		"castle_harmonia_glyphs": Vector2(6, 7),
	},
}


func _setup_transitions_for_floor(floor_num: int) -> void:
	super._setup_transitions_for_floor(floor_num)
	for entry in (_LORE.get(floor_num, []) as Array):
		var sign := Signpost.new()
		sign.sign_text = str(entry["text"])
		sign.position = _sign_position(Vector2i(entry["pos"] as Vector2), floor_num)
		transitions.add_child(sign)
	_place_castle_npcs(floor_num)
	_place_castle_examines(floor_num)


## Place this floor's authored examines. A `room_beat` is the ROOM speaking, so it reads from
## anywhere sensible in it — which is what a Signpost does (proximity, no press) and what the castle
## already uses for `_LORE`. Everything else is a thing you stop at, so it is a ReadableProp you
## stand on.
##
## Same allocator as the signposts and the NPCs: `_sign_position` consumes `_sign_taken`, so an
## examine cannot land on a sign's cell, an NPC's, or another examine's. Interaction is nearest-wins,
## which is how two Harmonia librarians made one of them unreachable (.344).
func _place_castle_examines(floor_num: int) -> void:
	var authored: Dictionary = _load_examine_pack()
	var marks: Dictionary = _EXAMINE_MARKS.get(floor_num, {})
	for examine_id in marks.keys():
		var entry: Dictionary = authored.get(examine_id, {}) if authored.get(examine_id, {}) is Dictionary else {}
		if entry.is_empty():
			push_warning("[castle_harmonia] examine '%s' has a cell but no authored entry — placing nothing rather than an empty panel" % examine_id)
			continue
		var text: String = str(entry.get("text", ""))
		if text == "":
			push_warning("[castle_harmonia] examine '%s' is authored with no text" % examine_id)
			continue
		var at: Vector2 = _sign_position(Vector2i(marks[examine_id] as Vector2), floor_num)
		if str(entry.get("prop", "")) == _ROOM_BEAT:
			var sign := Signpost.new()
			sign.sign_text = text
			sign.position = at
			transitions.add_child(sign)
			continue
		var prop := ReadableProp.new()
		prop.name = "Examine_" + str(examine_id)
		prop.position = at
		prop.setup(str(entry.get("name", "Examine")), func(): return [text])
		transitions.add_child(prop)


## Only this castle's entries, so a pack-wide key change cannot quietly pull another scene's text in.
func _load_examine_pack() -> Dictionary:
	if not FileAccess.file_exists(_EXAMINE_PACK):
		push_warning("[castle_harmonia] %s is missing — the castle keeps its signposts" % _EXAMINE_PACK)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_EXAMINE_PACK))
	if not (parsed is Dictionary):
		push_warning("[castle_harmonia] %s did not parse as a dictionary" % _EXAMINE_PACK)
		return {}
	var all: Dictionary = (parsed as Dictionary).get("examines", {})
	var mine: Dictionary = {}
	for k in all.keys():
		var e = all[k]
		if e is Dictionary and str((e as Dictionary).get("scene", "")) == "castle_harmonia":
			mine[str(k)] = e
	return mine


## The castle had ZERO NPCs — success criterion 4 of `docs/design/w1-progression-expansion.md` is
## "fighting corrupt guards, reading environmental storytelling, then face Mordaine", and only the
## fighting and the signposts had landed.
##
## ⛔ PLACED THROUGH `_sign_position`, NOT BY RAW CELL, and that is the whole reason this cannot
## stack. It resolves a mark to a walkable floor spot and consumes `_sign_taken`, the same set the
## signposts draw from — so an NPC can never land on a sign's cell or another NPC's, and interaction
## is nearest-wins, which is exactly how two Harmonia librarians made one of them unreachable
## (`InteriorPlacementSweep`, .344). Reusing the signs' allocator gets that for free rather than
## reserving cells a second way.
##
## Same container as the signposts on purpose: the castle rebuilds per floor, and anything parented
## elsewhere would survive a floor change and show up on the wrong one.
func _place_castle_npcs(floor_num: int) -> void:
	var pack: Dictionary = _load_narrative_pack()
	var npcs: Dictionary = pack.get("npcs", {}) if pack.get("npcs", {}) is Dictionary else {}
	for npc_id in _NPC_MARKS.keys():
		var authored: Dictionary = npcs.get(npc_id, {}) if npcs.get(npc_id, {}) is Dictionary else {}
		if authored.is_empty():
			push_warning("[castle_harmonia] no authored entry for '%s' — placing nothing rather than an NPC with no lines" % npc_id)
			continue
		if int(authored.get("floor", 0)) != floor_num:
			continue
		var lines: Array = authored.get("lines", []) if authored.get("lines", []) is Array else []
		if lines.is_empty():
			push_warning("[castle_harmonia] '%s' is authored with no lines — a silent NPC advertises a talk it cannot have" % npc_id)
			continue
		var npc := OverworldNPC.new()
		npc.name = "CastleNPC_" + str(npc_id)
		npc.npc_id = str(npc_id)
		npc.npc_name = str(authored.get("display_name", _display_name_for(str(npc_id))))
		npc.npc_type = "guard" if str(authored.get("role", "")) == "corrupt_guard" else "villager"
		var typed: Array = []
		for l in lines:
			typed.append(str(l))
		npc.dialogue_lines = typed
		npc.position = _sign_position(Vector2i(_NPC_MARKS[npc_id] as Vector2), floor_num)
		transitions.add_child(npc)


## The pack carries no display names, so they are derived from the id rather than duplicated:
## a second copy of a name is a second thing to keep in step.
func _display_name_for(npc_id: String) -> String:
	var trimmed: String = npc_id.trim_prefix("castle_")
	var words: PackedStringArray = trimmed.split("_")
	var out: Array = []
	for w in words:
		out.append(str(w).capitalize())
	return " ".join(out)


func _load_narrative_pack() -> Dictionary:
	if not FileAccess.file_exists(_NARRATIVE_PACK):
		push_warning("[castle_harmonia] %s is missing — the castle falls back to signposts only" % _NARRATIVE_PACK)
		return {}
	var raw: String = FileAccess.get_file_as_string(_NARRATIVE_PACK)
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_warning("[castle_harmonia] %s did not parse as a dictionary" % _NARRATIVE_PACK)
		return {}
	return parsed as Dictionary


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


## Fires world1_throne_room_approach once. The cutscene's set_flag stores
## game_constants["cutscene_flag_<bare>"] and story_flags["<bare>"]; the
## missing-JSON fallback stores story_flags[THRONE_APPROACH_FLAG]. A
## get_story_flag on that prefixed const sees neither of the cutscene's
## writes, so F4 replayed the scene on every entry and on load.
## is_story_flag_set reads both stores, and the fallback key too.
## Missing JSON = graceful no-op (writes the flag so the boss trigger
## still fires cleanly on the next tick).
func _maybe_play_throne_approach() -> void:
	if GameState == null or GameState.is_story_flag_set(THRONE_APPROACH_FLAG):
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


## Grandfathered two ways: a save past Mordaine skips it, and a save already ON F4 never
## crosses this stair. Only the F3 ascent is audited.
func _warden_defeated() -> bool:
	if GameState == null:
		return true
	if GameState.is_story_flag_set("world1_mordaine_defeated"):
		return true
	return GameState.is_story_flag_set(WARDEN_FLAG)


func _on_stairs_up_entered(body: Node2D) -> void:
	if current_floor == total_floors - 1 and not _transitioning \
			and not _warden_triggered and not _warden_defeated():
		if body.has_method("set_can_move"):
			_trigger_warden_battle()
		return
	super._on_stairs_up_entered(body)


## Mirrors _trigger_boss_battle's pending_boss_defeat shape — the scene is freed during the
## battle transition, so victory flags must ride the central spec, never a local handler.
func _trigger_warden_battle() -> void:
	_warden_triggered = true
	controller.pause_exploration()
	GameState.pending_boss_defeat = {
		"story_flags": [WARDEN_FLAG],
		"constants": [],
		"dungeon_flag": WARDEN_FLAG,
	}
	battle_triggered.emit([WARDEN_ID])


## Ambient FX: castle halls: dust motes, not cave crystals.
func _get_ambient_fx_theme() -> String:
	return "castle"
