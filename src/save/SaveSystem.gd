extends Node

## SaveSystem - Manages game saves with quick save and save points
## Supports saving anywhere on overworld, at save points in dungeons/villages

signal save_started()
signal save_completed(save_slot: int)
signal save_failed(reason: String)
signal load_started()
signal load_completed(save_slot: int)
signal load_failed(reason: String)

## Fired by save_game/quick_save/auto_save BEFORE _create_save_data
## reads GameState. Listeners flush their runtime state into the
## serializable buckets — e.g. GameLoop._sync_party_to_game_state
## copies the live Combatant array into GameState.player_party so
## post-battle XP / HP / items aren't lost.
##
## Without this, the sync only happened when the overworld menu was
## opened — auto-saves from zone-transitions / boss-defeat / the
## 5-min timer wrote stale party state, losing any progress since
## the last menu open.
signal pre_save_sync()

## Save configuration
const SAVE_DIR = "user://saves/"
const MAX_SAVE_SLOTS = 3
const QUICK_SAVE_SLOT = 99  # Special slot for quick save
# Dedicated auto-save slot — kept OUT of the user slot range
# (0..MAX_SAVE_SLOTS-1) so the periodic / zone-transition auto-save never
# overwrites a manual save. (Bug fix: auto_save() used to write slot 0, which
# SaveScreen presents as "Slot 1", silently clobbering the player's manual save.)
const AUTO_SAVE_SLOT = 98

## Preloaded for the settings save/load path. Promoted from two runtime
## load("res://src/battle/BattleScene.gd") calls so we don't hit the
## resource cache twice per session (and so a partial-import race during
## launch can't silently degrade settings to defaults).
const BATTLE_SCENE_SCRIPT := preload("res://src/battle/BattleScene.gd")

## Save data
var current_save_slot: int = -1
var auto_save_enabled: bool = true
var auto_save_interval: float = 300.0  # 5 minutes

## Auto-save timer
var time_since_last_auto_save: float = 0.0

## One-shot tracking records
var one_shot_records: Dictionary = {}  # {monster_id: {count: int, best_rank: String, best_setup: int}}

## Autobattle victory tracking records
var autobattle_records: Dictionary = {}  # {monster_key: {count: int, best_turns: int, best_multiplier: float}}

## Tick 309: pending player position from a load — populated by
## _apply_save_data and consumed by GameLoop after _start_exploration
## creates the saved map's scene. Vector2.INF is the "no pending" sentinel
## so the consumer can distinguish "load wasn't called" from "load placed
## the player at (0, 0)". GameLoop must reset this back to INF after
## consuming it so subsequent _start_exploration calls don't snap the
## player back to a stale position.
var pending_player_position: Vector2 = Vector2.INF


func _ready() -> void:
	# Create save directory if it doesn't exist
	_ensure_save_directory()
	# Load persisted settings
	load_settings()


## Tick 329: how long to delay the next retry when the auto-save attempt
## was refused (e.g., player in battle / inside an interior). Pre-fix the
## timer reset to 0 regardless of success, so a refused auto-save meant
## the player waited another full auto_save_interval (default 5 min) for
## the next retry — during which any progress could be lost to a wipe.
## 30s is short enough that a quick boss battle yields a near-immediate
## retry post-victory, long enough not to spam can_quick_save() every
## frame.
const AUTO_SAVE_RETRY_BACKOFF: float = 30.0


func _process(delta: float) -> void:
	# Auto-save timer
	if auto_save_enabled:
		time_since_last_auto_save += delta
		if time_since_last_auto_save >= auto_save_interval:
			if auto_save():
				time_since_last_auto_save = 0.0
			else:
				# Refused (battle / interior / no SaveSystem state). Back the
				# timer off by the backoff window so we retry soon instead
				# of waiting another full interval. Clamp at 0.0 so a
				# pathologically small auto_save_interval can't underflow.
				time_since_last_auto_save = maxf(0.0, auto_save_interval - AUTO_SAVE_RETRY_BACKOFF)


## Save functions
## Tick 397: Time Mage meta-ability quicksave override flag. Set by
## force_quick_save() to bypass the can_quick_save battle/interior
## gate. Self-clearing after a single save_game call so it can't
## accidentally leak across other save paths.
var _meta_save_bypass: bool = false


func force_quick_save(slot: int = -1) -> bool:
	"""Bypass the battle/interior gate for meta-job quicksave abilities."""
	_meta_save_bypass = true
	# Default to QUICK_SAVE_SLOT when no slot specified — matches quick_save's
	# slot choice and keeps the meta save out of the manual user slots.
	if slot == -1:
		slot = QUICK_SAVE_SLOT
	return save_game(slot)


func save_game(slot: int = -1) -> bool:
	"""Save the current game state to a slot"""
	if slot == -1:
		slot = current_save_slot

	if slot < 0:
		save_failed.emit("No save slot selected")
		return false

	# Gate on battle state — same as can_quick_save. Pre-fix (2026-04-30),
	# only quick_save() and auto_save() checked this; save_game(slot)
	# called from SaveScreen could write transient battle state (queued
	# actions, mid-animation HP, party still mid-revive) into the save.
	# Tick 75: pick the specific reason so SaveScreen can surface the
	# real blocker (interior, battle) instead of a misleading 'battle'
	# message when the player is actually inside a chapel.
	## Tick 397: meta-ability quicksave bypasses the gate. Consume the
	## flag on entry so it can't leak.
	var bypass_gate: bool = _meta_save_bypass
	_meta_save_bypass = false
	if not bypass_gate and not can_quick_save():
		var reason: String = _save_block_reason()
		save_failed.emit(reason)
		print("[SAVE] save_game refused: %s" % reason)
		return false

	# Flush runtime state into the serializable GameState buckets
	# BEFORE reading them. Listeners (currently GameLoop) sync live
	# Combatant array → GameState.player_party so post-battle gains
	# don't disappear on save.
	pre_save_sync.emit()

	save_started.emit()

	# Gather save data
	var save_data = _create_save_data()

	# Derive chapter + world from story flags (source of truth is
	# GameState.game_constants — see src/save/ChapterTitles.gd).
	var story := ChapterTitles.derive(GameState.game_constants if GameState else {})

	save_data["metadata"] = {
		"save_slot": slot,
		"save_time": Time.get_unix_time_from_system(),
		"save_date": Time.get_datetime_string_from_system(),
		"play_time": GameState.get_play_time() if GameState else 0.0,
		"play_time_formatted": GameState.get_playtime_formatted() if GameState else "00:00:00",
		"game_version": Version.semver(),
		"chapter": story.chapter,
		"chapter_title": story.title,
		"world": story.world,
		"world_name": story.world_name,
		"location_name": _current_location_display_name(),
		"party_summary": _get_party_summary()
	}

	# Write to file
	var success = _write_save_file(slot, save_data)

	if success:
		current_save_slot = slot
		save_settings()  # Persist settings alongside save
		## Tick 414: feed the rewind ring buffer on every save success.
		## record_history_checkpoint without force respects the
		## rewind_enabled gate, so pre-Time-Mage saves are cheap
		## (early return, no deep-duplicate). Documented contract from
		## the helper's docstring ("Public checkpoint hook: callers
		## SaveSystem on save success, BattleManager at battle start").
		if GameState and GameState.has_method("record_history_checkpoint"):
			GameState.record_history_checkpoint(false)
		save_completed.emit(slot)
		print("Game saved to slot %d" % slot)
		return true
	else:
		save_failed.emit("Failed to write save file")
		return false


func quick_save() -> bool:
	"""Quick save to dedicated slot"""
	# Check if quick save is allowed in current location
	if not can_quick_save():
		var reason: String = _save_block_reason()
		save_failed.emit(reason)
		print("Quick save not allowed: %s" % reason)
		return false

	print("Quick saving...")
	return save_game(QUICK_SAVE_SLOT)


func auto_save() -> bool:
	"""Auto-save to the dedicated AUTO_SAVE_SLOT.

	Writes to AUTO_SAVE_SLOT (NOT a manual user slot). Earlier versions
	wrote to slot 0, which SaveScreen renders as "Slot 1" — so the timed
	/ zone-transition auto-save silently overwrote whatever the player had
	manually saved there. Routing to the reserved slot keeps manual saves
	(0..MAX_SAVE_SLOTS-1) untouched."""
	if not can_quick_save():
		return false

	print("Auto-saving...")
	return save_game(AUTO_SAVE_SLOT)


func can_quick_save() -> bool:
	"""Check if quick save is allowed in the current game state.

	Previous versions gated this on MapSystem.get_current_map_type(), but
	that API relied on an `enter_location`/`current_location_id` system
	that was never wired up (so it always returned OVERWORLD). Dungeon
	save points instead call quick_save() directly, meaning the only
	real gate is "not in a battle".

	Tick 74: also block while inside an interior. Interiors bypass
	MapSystem entirely (GameLoop loads them via direct scene-routing),
	so MapSystem.current_map_id is stale when the player is in one.
	Saving would record the wrong map and the resume path would either
	spawn in the wrong location or fail to load any map. Quick + auto
	saves both share this gate, so neither corrupts state."""
	if not BattleManager:
		return false
	if BattleManager.is_battle_active():
		return false
	if _is_player_inside_interior():
		return false
	if _is_cutscene_active():
		return false
	return true


## Specific reason save was blocked. Returns "" when save is allowed.
## Mirrors the can_quick_save check order so the surfaced message
## matches the actual blocker.
func _save_block_reason() -> String:
	if not BattleManager:
		return "Save system not ready"
	if BattleManager.is_battle_active():
		return "Cannot save during battle"
	if _is_player_inside_interior():
		return "Cannot save inside this room — leave to a village or overworld first"
	if _is_cutscene_active():
		return "Cannot save mid-cutscene — wait for the scene to finish"
	return ""


func _is_player_inside_interior() -> bool:
	"""Returns true when GameLoop is currently showing an interior scene.
	Falls back to false when GameLoop isn't reachable (e.g. unit tests
	with no scene tree) — keeps the gate permissive in non-game contexts."""
	var root := get_tree().current_scene
	if root != null and root.has_method("is_inside_interior"):
		return root.is_inside_interior()
	return false


func _is_cutscene_active() -> bool:
	"""Returns true when GameLoop.current_state == LoopState.CUTSCENE.
	Introduced with the Spotlight Duels spec (cowir-main msg 1964
	fallback path): saving mid-cutscene captures an ambiguous state
	(intro dialogue partially played, battle step not entered, etc.).
	The Spotlight Duel embeds a battle step inside the cutscene, so
	mid-cutscene = mid-narration OR mid-duel; neither is a clean save
	point. Falls back to false when GameLoop isn't reachable (unit
	tests, boot edge) — keeps the gate permissive in non-game contexts,
	same shape as _is_player_inside_interior."""
	var gl := get_tree().root.get_node_or_null("GameLoop")
	if gl == null:
		# GameLoop is the main scene root in production, so also try
		# current_scene for headless tests that load it that way.
		gl = get_tree().current_scene
	if gl == null or not "current_state" in gl:
		return false
	# LoopState.CUTSCENE == 4 per GameLoop's enum ordering
	# (TITLE=0, BATTLE=1, EXPLORATION=2, AUTOGRIND=3, CUTSCENE=4).
	# Comparing by ordinal avoids importing the enum type.
	return int(gl.current_state) == 4


## Best-effort human-readable name for the currently loaded map, used
## in the save slot summary. Defaults to "Unknown" when no map is loaded.
func _current_location_display_name() -> String:
	if MapSystem and MapSystem.current_map_id:
		# Convert snake_case map id to Title Case ("harmonia_village" -> "Harmonia Village").
		return MapSystem.current_map_id.capitalize()
	return "Unknown"


func save_at_save_point(save_point_id: String) -> bool:
	"""Save at a designated save point (works anywhere)"""
	print("Saving at save point: %s" % save_point_id)

	# Save points work even in dungeons
	var result = save_game(current_save_slot if current_save_slot >= 0 else 1)
	if result:
		SoundManager.play_music("stinger_save_point")
	return result


## Load functions
func load_game(slot: int) -> bool:
	"""Load a saved game"""
	if not save_exists(slot):
		load_failed.emit("Save file not found")
		return false

	load_started.emit()

	var save_data = _read_save_file(slot)
	if save_data.is_empty():
		load_failed.emit("Failed to read save file")
		return false

	# Apply save data
	_apply_save_data(save_data)

	current_save_slot = slot
	load_completed.emit(slot)
	print("Game loaded from slot %d" % slot)
	return true


func save_exists(slot: int) -> bool:
	"""Check if a save file exists"""
	var file_path = _get_save_path(slot)
	return FileAccess.file_exists(file_path)


func has_save() -> bool:
	"""Check if any save file exists (for title screen Continue button)"""
	for slot in range(MAX_SAVE_SLOTS):
		if save_exists(slot):
			return true
	if save_exists(QUICK_SAVE_SLOT):
		return true
	if save_exists(AUTO_SAVE_SLOT):
		return true
	return false


func get_most_recent_slot() -> int:
	"""Find the most recently saved slot. Returns -1 if no saves exist."""
	var best_slot = -1
	var best_time = 0.0
	for slot in range(MAX_SAVE_SLOTS):
		var info = get_save_info(slot)
		if not info.is_empty():
			var save_time = info.get("save_time", 0.0)
			if save_time > best_time:
				best_time = save_time
				best_slot = slot
	# Also check quick save
	var qs_info = get_save_info(QUICK_SAVE_SLOT)
	if not qs_info.is_empty():
		var qs_time = qs_info.get("save_time", 0.0)
		if qs_time > best_time:
			best_time = qs_time
			best_slot = QUICK_SAVE_SLOT
	# Also check the dedicated auto-save slot — a fresh launch's "Continue"
	# should be able to resume from the latest auto-save too.
	var as_info = get_save_info(AUTO_SAVE_SLOT)
	if not as_info.is_empty():
		var as_time = as_info.get("save_time", 0.0)
		if as_time > best_time:
			best_time = as_time
			best_slot = AUTO_SAVE_SLOT
	return best_slot


func get_save_info(slot: int) -> Dictionary:
	"""Get save file metadata without loading the full save"""
	if not save_exists(slot):
		return {}

	var save_data = _read_save_file(slot)
	return save_data.get("metadata", {})


func delete_save(slot: int) -> bool:
	"""Delete a save file"""
	if not save_exists(slot):
		return false

	var file_path = _get_save_path(slot)
	var dir = DirAccess.open("user://")
	if dir:
		dir.remove(file_path)
		print("Deleted save slot %d" % slot)
		return true

	return false


## One-shot record management
func record_one_shot(monster_ids: Array, rank: String, setup_turns: int) -> void:
	"""Record a one-shot achievement for the given monster types"""
	for id in monster_ids:
		if not one_shot_records.has(id):
			one_shot_records[id] = {"count": 0, "best_rank": "C", "best_setup": 999}
		one_shot_records[id]["count"] += 1
		if _rank_value(rank) > _rank_value(one_shot_records[id]["best_rank"]):
			one_shot_records[id]["best_rank"] = rank
		if setup_turns < one_shot_records[id]["best_setup"]:
			one_shot_records[id]["best_setup"] = setup_turns
	print("[SAVE] One-shot recorded for monsters: %s (rank: %s, setup: %d)" % [monster_ids, rank, setup_turns])


func _rank_value(rank: String) -> int:
	"""Convert rank letter to numeric value for comparison"""
	match rank:
		"S":
			return 4
		"A":
			return 3
		"B":
			return 2
		"C":
			return 1
		_:
			return 0


func _get_one_shot_records() -> Dictionary:
	"""Get all one-shot records"""
	return one_shot_records


func get_one_shot_record(monster_id: String) -> Dictionary:
	"""Get one-shot record for a specific monster"""
	return one_shot_records.get(monster_id, {})


## Autobattle record management
func record_autobattle_victory(monster_ids: Array, turns: int, multiplier: float) -> void:
	"""Record an autobattle victory for the given monster types"""
	var monster_key = "_".join(monster_ids) if monster_ids.size() > 0 else "unknown"
	if not autobattle_records.has(monster_key):
		autobattle_records[monster_key] = {"count": 0, "best_turns": 999, "best_multiplier": 0.0}
	autobattle_records[monster_key]["count"] += 1
	if turns < autobattle_records[monster_key]["best_turns"]:
		autobattle_records[monster_key]["best_turns"] = turns
	if multiplier > autobattle_records[monster_key]["best_multiplier"]:
		autobattle_records[monster_key]["best_multiplier"] = multiplier
	print("[SAVE] Autobattle victory recorded for monsters: %s (turns: %d, multiplier: %.1fx)" % [monster_key, turns, multiplier])


func get_autobattle_record(monster_key: String) -> Dictionary:
	"""Get autobattle record for a specific monster combination"""
	return autobattle_records.get(monster_key, {})


func _get_autobattle_records() -> Dictionary:
	"""Get all autobattle records"""
	return autobattle_records


## Save data creation
func _create_save_data() -> Dictionary:
	"""Create a dictionary of all save data"""
	var data = {}

	# Player data — find via group first (OverworldPlayer), fall back to
	# MapSystem.get_player() for other map types.
	var player = _find_active_player()
	if player:
		var step_count = player.step_count if "step_count" in player else 0
		data["player"] = {
			"position": {
				"x": player.position.x,
				"y": player.position.y
			},
			"step_count": step_count
		}

	# Party data (combatants)
	data["party"] = _serialize_party()

	# Map data (current_location_id was dropped along with the dead
	# MapSystem.enter_location() subsystem — it was always "").
	data["map"] = {
		"current_map_id": MapSystem.current_map_id,
	}

	# Tick 265: removed dead "inventory" field. Per-character inventories
	# already roundtrip via Combatant.to_dict / from_dict (lines 819-840).
	# The original intent — party-wide shared item pouch — was never
	# implemented; the field was a {} placeholder that took space in the
	# save file for nothing. _apply_save_data still tolerates legacy
	# saves that have an "inventory" key (silently ignored).

	# Game state flags/variables
	if GameState:
		data["game_state"] = GameState.to_dict()

	# Autogrind/autobattle stats
	data["automation"] = {
		"region_crack_levels": AutogrindSystem.region_crack_levels if AutogrindSystem else {},
		## Tick 418: read GameState.battles_won (the canonical
		## persistent counter) instead of the dead BattleManager
		## reference that never existed — the old read always took
		## the `else 0` fallback, silently saving 0 on every save
		## regardless of actual battle count.
		"total_battles": GameState.battles_won if GameState and "battles_won" in GameState else 0,
		"learned_patterns": AutogrindSystem.learned_patterns if AutogrindSystem else {}
	}

	# One-shot records
	data["one_shot_records"] = _get_one_shot_records()

	# Autobattle records
	data["autobattle_records"] = _get_autobattle_records()

	## Tick 417: persist encounter state so a Repel mid-use survives
	## save+quit. Pre-fix repel_steps_remaining = 0 on every game
	## restart — a player who used a 30-gold Repel, walked 3 steps,
	## then saved and quit lost the remaining 47 protected steps.
	## Same applies to steps_since_last_encounter (the minimum-steps
	## gate would reset, briefly allowing back-to-back encounters
	## right after a load).
	if EncounterSystem:
		data["encounter_state"] = {
			"repel_steps_remaining": EncounterSystem.repel_steps_remaining,
			"steps_since_last_encounter": EncounterSystem.steps_since_last_encounter,
		}

	return data


func _serialize_party() -> Array:
	"""Serialize party members"""
	if GameState and "player_party" in GameState:
		return GameState.player_party.duplicate(true)
	return []


func _get_party_summary() -> Array:
	"""Get summary of party members for save slot display"""
	var summary = []

	# Get party from GameState if available
	if GameState and "player_party" in GameState:
		for member in GameState.player_party:
			if member is Dictionary:
				## Tick 415: dropped the "customization" field. The
				## player_party member dict only ever holds the live
				## CharacterCustomization RefCounted reference (set by
				## GameLoop _save_customizations on creation); JSON
				## stringification turns RefCounted instances into null,
				## so the field landed in saves as "customization":
				## null. SaveScreen reads name/job_id/hp/max_hp only —
				## never customization — so the null entry was pure
				## bloat. Persistence of actual customization data
				## happens through GameLoop._save_customizations writing
				## to user://save_data.json (the global customization
				## file). No consumer is impacted by removing this.
				summary.append({
					"name": member.get("name", "Unknown"),
					"level": member.get("job_level", 1),
					"job": member.get("job", {}).get("name", "Fighter") if member.get("job") is Dictionary else "Fighter",
					"job_id": member.get("job", {}).get("id", "fighter") if member.get("job") is Dictionary else "fighter",
					"secondary_job_id": member.get("secondary_job_id", ""),
					"hp": member.get("current_hp", 0),
					"max_hp": member.get("max_hp", 1),
				})

	return summary


# Tick 265: _serialize_inventory removed (was a {} stub since 2025
# with a stale "TODO: when InventorySystem is implemented" comment).
# Per-character inventory IS implemented via Combatant.to_dict —
# this stub was confusing future readers into thinking a separate
# party-wide system existed somewhere. If a party-shared item pouch
# is ever introduced, add it as a top-level save field with its own
# serializer/deserializer — don't resurrect this dead method.


## Find the active player node. Prefers the "player" group (OverworldPlayer),
## falls back to MapSystem.get_player() for dungeon/village scenes that
## register players through that API instead.
func _find_active_player() -> Node2D:
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		var in_group = tree.get_nodes_in_group("player")
		if in_group.size() > 0:
			return in_group[0] as Node2D
	if MapSystem:
		return MapSystem.get_player()
	return null


## Save data application
func _apply_save_data(data: Dictionary) -> void:
	"""Apply loaded save data to game state.

	Apply order matters:
	  1. Map FIRST — load_map unloads the prior map and re-spawns the player
	     at its default spawn point. If player position were applied before
	     load_map, the saved coordinates would be lost on the spawn re-pos.
	     (Bug fix 2026-04-30 — saved positions never restored when map_id
	     differed from current.)
	  2. Player position SECOND — overrides the spawn point with saved coords.
	  3. Party — rehydrate Combatants from serialized state.
	  4. Inventory — items, gold.
	"""
	# Apply map/location FIRST so player respawn happens cleanly, then teleport.
	# Tick 308: write MapSystem.current_map_id UNCONDITIONALLY before the
	# load_map call so dungeon/interior/village saves survive the round-trip.
	# MapSystem._get_map_path only handles 3 ids (overworld / harmonia_village
	# / whispering_cave); load_map push_errors + early-returns for everything
	# else, leaving MapSystem.current_map_id at the pre-load value. GameLoop's
	# Continue / quick_load path reads MapSystem.current_map_id to sync its
	# private _current_map_id (tick 307), so we need it pre-populated. The
	# subsequent load_map() call is best-effort — its success path overwrites
	# current_map_id with the same value (harmless), its failure path leaves
	# our pre-set value intact.
	if data.has("map"):
		var map_data = data["map"]
		if map_data.has("current_map_id"):
			var saved_map_id: String = str(map_data["current_map_id"])
			if MapSystem and "current_map_id" in MapSystem:
				MapSystem.current_map_id = saved_map_id
			MapSystem.load_map(saved_map_id)

	# Apply player position AFTER map load.
	# Tick 309: stash the saved position into pending_player_position so
	# GameLoop's Continue / quick_load flow can re-apply it AFTER it tears
	# down the current scene and instantiates the saved map's scene. Pre-
	# fix player.teleport() was applied to whatever player happened to be
	# in the tree NOW (typically the title-screen-residual or a stale
	# scene's player), which gets queue_free()'d a moment later when
	# GameLoop._start_exploration swaps to the saved scene — so the new
	# scene's player spawned at its default marker and the saved position
	# was silently lost. The in-place teleport is preserved as a best-effort
	# (live-scene saves like the in-overworld autosave still benefit), but
	# the stash is the canonical path Continue/quick_load now consume.
	## Tick 362: validate pos shape before reading x/y. Pre-fix a
	## hand-edited / partially-corrupt save with position=null or
	## position={} crashed with `Invalid get index 'x' on base: 'Nil'`
	## at pos["x"], leaving the player no recovery path. Now we
	## push_warning and skip the position restore — the player keeps
	## the scene's default spawn marker instead of crashing.
	if data.has("player") and data["player"].has("position"):
		var pos: Variant = data["player"]["position"]
		if pos is Dictionary and pos.has("x") and pos.has("y"):
			pending_player_position = Vector2(float(pos["x"]), float(pos["y"]))
			var player = _find_active_player()
			if player:
				if player.has_method("teleport"):
					player.teleport(pending_player_position)
				else:
					player.position = pending_player_position
		else:
			push_warning("[SaveSystem] _apply_save_data: player.position malformed (type=%s, value=%s) — keeping default spawn, no crash" % [typeof(pos), pos])

	# Apply party data
	if data.has("party"):
		_deserialize_party(data["party"])

	# Tick 265: legacy "inventory" field tolerated for backward compat
	# with pre-v3.x saves (carried a {} placeholder for an unimplemented
	# party-wide pouch). Per-character inventories live on Combatant
	# and load via the party path above — nothing to do here.

	# Apply game state
	if data.has("game_state") and GameState:
		GameState.from_dict(data["game_state"])

	## Tick 364: type-guard automation/records reads. Pre-fix a save
	## with automation=null/int/string crashed at automation_data.has()
	## with `Invalid call .has on Nil`, and the direct typed-Dictionary
	## assignments below crashed with `Trying to assign value of type
	## 'X' to a variable of type 'Dictionary'`. Same defensive shape as
	## tick 362/363's other save-load guards.
	# Apply automation stats
	if data.has("automation"):
		var automation_data: Variant = data["automation"]
		if automation_data is Dictionary:
			# Restore region crack levels
			if automation_data.has("region_crack_levels") and AutogrindSystem:
				var rcl: Variant = automation_data["region_crack_levels"]
				if rcl is Dictionary:
					AutogrindSystem.region_crack_levels = rcl
				else:
					push_warning("[SaveSystem] _apply_save_data: automation.region_crack_levels malformed (type=%s) — keeping current" % typeof(rcl))
			# Restore learned patterns for adaptive AI
			if automation_data.has("learned_patterns") and AutogrindSystem:
				var lp: Variant = automation_data["learned_patterns"]
				if lp is Dictionary:
					AutogrindSystem.learned_patterns = lp
				else:
					push_warning("[SaveSystem] _apply_save_data: automation.learned_patterns malformed (type=%s) — keeping current" % typeof(lp))
		else:
			push_warning("[SaveSystem] _apply_save_data: automation block malformed (type=%s) — skipping automation restore" % typeof(automation_data))

	# Restore one-shot records
	if data.has("one_shot_records"):
		var osr: Variant = data["one_shot_records"]
		if osr is Dictionary:
			one_shot_records = osr
		else:
			push_warning("[SaveSystem] _apply_save_data: one_shot_records malformed (type=%s) — keeping current" % typeof(osr))

	# Restore autobattle records
	if data.has("autobattle_records"):
		var ar: Variant = data["autobattle_records"]
		if ar is Dictionary:
			autobattle_records = ar
		else:
			push_warning("[SaveSystem] _apply_save_data: autobattle_records malformed (type=%s) — keeping current" % typeof(ar))

	## Tick 417: restore encounter state — pairs with the save-side
	## persistence in _create_save_data so a mid-Repel save+quit
	## doesn't lose the remaining protection.
	if data.has("encounter_state") and EncounterSystem:
		var raw_es: Variant = data["encounter_state"]
		if raw_es is Dictionary:
			# Per-field type-guarded reads so a partial save (missing
			# one of the two fields) doesn't reset the other to default.
			if raw_es.has("repel_steps_remaining"):
				EncounterSystem.repel_steps_remaining = max(0, int(raw_es["repel_steps_remaining"]))
			if raw_es.has("steps_since_last_encounter"):
				EncounterSystem.steps_since_last_encounter = max(0, int(raw_es["steps_since_last_encounter"]))
		else:
			push_warning("[SaveSystem] _apply_save_data: encounter_state malformed (type=%s) — keeping current" % typeof(raw_es))


func _deserialize_party(party_data: Array) -> void:
	"""Deserialize party members.

	Bug fix (2026-04-30): old saves with `white_mage`/`black_mage`/`thief`
	job IDs were stuffed into player_party verbatim. Combatant.from_dict
	resolves aliases at the live-Combatant level, but this dict array is
	consumed by menus / shops / load-time UI before Combatants are
	constructed — those readers saw the legacy IDs and rendered wrong
	job sprites/labels. Now we resolve aliases here too so player_party
	contains canonical IDs.
	"""
	if not (GameState and "player_party" in GameState):
		return
	var resolved: Array[Dictionary] = []
	var job_system = get_node_or_null("/root/JobSystem")
	for entry in party_data:
		if not (entry is Dictionary):
			continue
		var copy = entry.duplicate(true)
		if job_system:
			# Top-level job_id (used by both legacy synth and new to_dict).
			if copy.has("job_id") and copy["job_id"] is String:
				copy["job_id"] = job_system.resolve_job_id(copy["job_id"])
			# Legacy "job" string field used by old save metadata.
			if copy.has("job") and copy["job"] is String:
				copy["job"] = job_system.resolve_job_id(copy["job"])
			# Secondary job ID.
			if copy.has("secondary_job_id") and copy["secondary_job_id"] is String:
				copy["secondary_job_id"] = job_system.resolve_job_id(copy["secondary_job_id"])
			# job_profiles keys are "primary:secondary" tuples — re-key under
			# resolved IDs so per-job memory survives the rename.
			if copy.has("job_profiles") and copy["job_profiles"] is Dictionary:
				var resolved_profiles := {}
				for key in copy["job_profiles"]:
					var parts = key.split(":")
					var rk = job_system.resolve_job_id(parts[0])
					if parts.size() > 1 and parts[1] != "":
						rk += ":" + job_system.resolve_job_id(parts[1])
					else:
						rk += ":"
					resolved_profiles[rk] = copy["job_profiles"][key]
				copy["job_profiles"] = resolved_profiles
		resolved.append(copy)
	GameState.player_party = resolved


# Tick 265: _deserialize_inventory removed alongside its sibling.
# Was an empty `pass` since 2025. Per-character inventory comes back
# via Combatant.from_dict on the party path.


## File I/O
func _write_save_file(slot: int, data: Dictionary) -> bool:
	"""Write save data to file"""
	var file_path = _get_save_path(slot)

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		## Tick 181: surface save-write failures via push_warning.
		## Pre-fix print() only — silent failure. SaveSystem returned
		## false, the save UI sometimes still showed "Saved!" toast
		## depending on caller. push_warning + FileAccess error code
		## gives diagnostic surface (perms / disk full / RO FS).
		push_warning("[SaveSystem] _write_save_file: could not open '%s' for write (error: %s)" % [file_path, FileAccess.get_open_error()])
		return false

	var json_string = JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()

	return true


func _read_save_file(slot: int) -> Dictionary:
	"""Read save data from file"""
	var file_path = _get_save_path(slot)

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		## Tick 181: surface save-read failures. Pre-fix print()
		## only — load silently returned {} which the title-screen
		## CONTINUE button treated as "no save"; player saw their
		## save disappear with no hint why.
		push_warning("[SaveSystem] _read_save_file: could not open '%s' for read (error: %s)" % [file_path, FileAccess.get_open_error()])
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) != OK:
		push_warning("[SaveSystem] _read_save_file: failed to parse '%s' as JSON: %s" % [file_path, json.get_error_message()])
		return {}

	# Validate that parsed data is a Dictionary
	if not json.data is Dictionary:
		push_warning("[SaveSystem] _read_save_file: '%s' parsed but root is not a Dictionary (type=%s) — invalid save" % [file_path, typeof(json.data)])
		return {}

	return json.data


func _get_save_path(slot: int) -> String:
	"""Get file path for a save slot"""
	return SAVE_DIR + "save_%02d.json" % slot


func _ensure_save_directory() -> void:
	"""Create save directory if it doesn't exist"""
	var dir = DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("saves"):
			dir.make_dir("saves")
			print("Created save directory: user://saves/")


## Utility
func get_all_saves() -> Array:
	"""Get info for all save slots"""
	var saves = []
	for slot in range(MAX_SAVE_SLOTS):
		var info = get_save_info(slot)
		if not info.is_empty():
			saves.append(info)
	return saves


func set_current_save_slot(slot: int) -> void:
	"""Set the active save slot"""
	current_save_slot = slot


## ═══════════════════════════════════════════════════════════════════════
## SETTINGS PERSISTENCE (global, not per-slot)
## ═══════════════════════════════════════════════════════════════════════

const SETTINGS_PATH = "user://settings.json"


func save_settings() -> void:
	"""Save global game settings (battle speed, audio, display options)."""
	var settings = {
		"version": 2,
		"speed_scale_v2": true,
		"battle_speed_index": BATTLE_SCENE_SCRIPT._battle_speed_index,
		"show_controller_overlay": GameState.show_controller_overlay if GameState else true,
		"master_volume": AudioServer.get_bus_volume_db(0),
	}
	if GameState:
		settings["music_volume"] = GameState.music_volume
		settings["sfx_volume"] = GameState.sfx_volume
		settings["text_speed"] = GameState.text_speed
		# Tick 222: accessibility text scale.
		if "text_size_scale" in GameState:
			settings["text_size_scale"] = GameState.text_size_scale
		# Tick 226: color-blind palette.
		if "color_blind_mode" in GameState:
			settings["color_blind_mode"] = GameState.color_blind_mode
		settings["encounter_rate_multiplier"] = GameState.encounter_rate_multiplier
		settings["screen_shake_enabled"] = GameState.screen_shake_enabled
		settings["default_battle_speed"] = GameState.default_battle_speed
		settings["debug_log_enabled"] = GameState.debug_log_enabled
		settings["debug_all_pcs_unlocked"] = GameState.debug_all_pcs_unlocked
		# Wave C: persist the dynamic-dialogue master switch alongside other
		# UX preferences so the SettingsMenu toggle survives a relaunch.
		if "llm_enabled" in GameState:
			settings["llm_enabled"] = GameState.llm_enabled
		# Phase 1: persist the LLM-strategic-boss flag (opt-in).
		if "boss_llm_strategy_enabled" in GameState:
			settings["boss_llm_strategy_enabled"] = GameState.boss_llm_strategy_enabled
		# Party LLM dialogue flag (opt-in).
		if "party_llm_dialogue_enabled" in GameState:
			settings["party_llm_dialogue_enabled"] = GameState.party_llm_dialogue_enabled
		# tick 42: LLM-guided rebalance daemon flag (opt-in).
		if "llm_rebalance_enabled" in GameState:
			settings["llm_rebalance_enabled"] = GameState.llm_rebalance_enabled
		# Item 9: dash always-on toggle (testing/accessibility).
		if "dash_always_on" in GameState:
			settings["dash_always_on"] = GameState.dash_always_on
		# BYOK (Bring Your Own Key) — user-provided cloud LLM config.
		# Gated off in web builds (browser sandbox can't hold secrets
		# safely). Same gate as llm_enabled. The API key is sensitive;
		# treat the settings.json file as containing a secret. Per-
		# machine, NOT per-save.
		if not OS.has_feature("web"):
			if "llm_custom_backend_enabled" in GameState:
				settings["llm_custom_backend_enabled"] = GameState.llm_custom_backend_enabled
			if "llm_custom_base_url" in GameState:
				settings["llm_custom_base_url"] = GameState.llm_custom_base_url
			if "llm_custom_api_format" in GameState:
				settings["llm_custom_api_format"] = GameState.llm_custom_api_format
			if "llm_custom_model" in GameState:
				settings["llm_custom_model"] = GameState.llm_custom_model
			if "llm_custom_api_key" in GameState:
				settings["llm_custom_api_key"] = GameState.llm_custom_api_key
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))
		file.close()


func load_settings() -> void:
	"""Load and apply global game settings.

	Tick 347: 3-stage loud-fail on the post-existence failure paths
	(open / parse / non-Dict root). Pre-fix every failure mode silently
	returned and the player lost ALL their settings (volume, text speed,
	controller overlay, etc.) with zero diagnostic. Common cause: game
	crashed mid-write, leaving an empty / truncated settings.json.

	The file-missing case stays silent — first-launch players don't
	have a settings file.
	"""
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		push_warning("[SaveSystem] settings.json exists but FileAccess.open failed (error %d) — settings reset to defaults this session" % FileAccess.get_open_error())
		return
	var json = JSON.new()
	var parse_result: int = json.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		push_warning("[SaveSystem] settings.json parse error: %s — likely corrupted by interrupted write; settings reset to defaults" % json.get_error_message())
		return
	if not (json.data is Dictionary):
		push_warning("[SaveSystem] settings.json parsed but root is not a Dictionary (got %s) — file shape changed; settings reset to defaults" % typeof(json.data))
		return

	var settings = json.data
	# Battle speed — speed_scale_v2 migration: pre-recalibration files
	# persisted indexes chosen under raw-engine labels (user's file sat
	# at engine 4.0 shown as "4x"; the battle scale calls that "8x").
	# One-time reset to the true default; users re-pick if they want fast.
	if not settings.get("speed_scale_v2", false):
		BATTLE_SCENE_SCRIPT._battle_speed_index = 1
		if GameState:
			GameState.default_battle_speed = 0.5
	elif settings.has("battle_speed_index"):
		var idx = int(settings["battle_speed_index"])
		if idx >= 0 and idx < BATTLE_SCENE_SCRIPT.BATTLE_SPEEDS.size():
			BATTLE_SCENE_SCRIPT._battle_speed_index = idx

	# Controller overlay
	if GameState and settings.has("show_controller_overlay"):
		GameState.show_controller_overlay = settings["show_controller_overlay"]

	# Master volume — clamp to safe range. Pre-fix (2026-04-30) a corrupt
	# or hand-edited settings.json could push the bus to +60 dB, instant
	# ear damage. Godot's documented audio bus range is -80..+24 dB; we
	# cap at +6 dB to leave 18 dB of headroom against clipping.
	if settings.has("master_volume"):
		var mv = clampf(float(settings["master_volume"]), -80.0, 6.0)
		AudioServer.set_bus_volume_db(0, mv)

	# Extended settings — every numeric field clamped to its sane range.
	const VALID_TEXT_SPEEDS = ["slow", "normal", "fast", "instant"]
	if GameState:
		if settings.has("music_volume"):
			GameState.music_volume = clampi(int(settings["music_volume"]), 0, 100)
			if SoundManager and SoundManager.has_method("set_music_volume"):
				SoundManager.set_music_volume(GameState.music_volume / 100.0)
		if settings.has("sfx_volume"):
			GameState.sfx_volume = clampi(int(settings["sfx_volume"]), 0, 100)
			if SoundManager and SoundManager.has_method("set_sfx_volume"):
				SoundManager.set_sfx_volume(GameState.sfx_volume / 100.0)
		if settings.has("text_speed"):
			var ts = str(settings["text_speed"])
			GameState.text_speed = ts if ts in VALID_TEXT_SPEEDS else "normal"
		if settings.has("text_size_scale"):
			# Tick 222: clamp to the valid preset range [0.8, 2.0] — defends against legacy/corrupt saves.
			GameState.text_size_scale = clampf(float(settings["text_size_scale"]), 0.8, 2.0)
		if settings.has("color_blind_mode"):
			# Tick 226: bool flag, no clamping needed but coerce to bool defensively.
			GameState.color_blind_mode = bool(settings["color_blind_mode"])
		if settings.has("encounter_rate_multiplier"):
			# UI exposes 0.0 (off) to 2.0 (double rate); clamp accordingly.
			GameState.encounter_rate_multiplier = clampf(float(settings["encounter_rate_multiplier"]), 0.0, 2.0)
		if settings.has("screen_shake_enabled"):
			GameState.screen_shake_enabled = bool(settings["screen_shake_enabled"])
		if settings.has("default_battle_speed"):
			# Validate against actual BATTLE_SPEEDS — fall back to 1.0 if drift.
			var raw_speed = float(settings["default_battle_speed"])
			GameState.default_battle_speed = raw_speed if (raw_speed in BATTLE_SCENE_SCRIPT.BATTLE_SPEEDS) else 1.0
		if settings.has("debug_log_enabled"):
			GameState.debug_log_enabled = bool(settings["debug_log_enabled"])
			if DebugLogOverlay and DebugLogOverlay.has_method("set_enabled"):
				DebugLogOverlay.set_enabled(GameState.debug_log_enabled)
		if settings.has("debug_all_pcs_unlocked"):
			GameState.debug_all_pcs_unlocked = bool(settings["debug_all_pcs_unlocked"])
		# Wave C: dynamic-dialogue preference. Push to LLMService so the
		# autoload's runtime gate matches the persisted choice.
		if settings.has("llm_enabled") and "llm_enabled" in GameState:
			GameState.llm_enabled = bool(settings["llm_enabled"])
			var svc: Node = get_node_or_null("/root/LLMService")
			if svc and "llm_enabled" in svc:
				svc.llm_enabled = GameState.llm_enabled
		# Phase 1: load the LLM-strategic-boss flag if present.
		if settings.has("boss_llm_strategy_enabled") and "boss_llm_strategy_enabled" in GameState:
			GameState.boss_llm_strategy_enabled = bool(settings["boss_llm_strategy_enabled"])
		if settings.has("party_llm_dialogue_enabled") and "party_llm_dialogue_enabled" in GameState:
			GameState.party_llm_dialogue_enabled = bool(settings["party_llm_dialogue_enabled"])
		if settings.has("llm_rebalance_enabled") and "llm_rebalance_enabled" in GameState:
			GameState.llm_rebalance_enabled = bool(settings["llm_rebalance_enabled"])
		if settings.has("dash_always_on") and "dash_always_on" in GameState:
			GameState.dash_always_on = bool(settings["dash_always_on"])
		# BYOK load. Web build skips this — the fields stay at their
		# struct-default empty strings, so even a settings.json
		# transplanted FROM a desktop save into a web export can't
		# leak the key into web logic. Belt-and-suspenders.
		if not OS.has_feature("web"):
			if settings.has("llm_custom_backend_enabled") and "llm_custom_backend_enabled" in GameState:
				GameState.llm_custom_backend_enabled = bool(settings["llm_custom_backend_enabled"])
			if settings.has("llm_custom_base_url") and "llm_custom_base_url" in GameState:
				GameState.llm_custom_base_url = str(settings["llm_custom_base_url"])
			if settings.has("llm_custom_api_format") and "llm_custom_api_format" in GameState:
				var fmt: String = str(settings["llm_custom_api_format"])
				GameState.llm_custom_api_format = fmt if fmt in ["openai", "ollama"] else "openai"
			if settings.has("llm_custom_model") and "llm_custom_model" in GameState:
				GameState.llm_custom_model = str(settings["llm_custom_model"])
			if settings.has("llm_custom_api_key") and "llm_custom_api_key" in GameState:
				GameState.llm_custom_api_key = str(settings["llm_custom_api_key"])

	print("[SAVE] Settings loaded")
