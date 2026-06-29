extends Node

## GameState - Manages save/load, game state, and meta-manipulation
## Handles save corruption, time manipulation, and game constant editing

signal save_corrupted(corruption_level: float)
## Tick 178: emitted when a NEW corruption effect lands (added to
## corruption_effects). Distinct from save_corrupted which fires
## on every level increase regardless of whether a new effect was
## applied. UI uses this for the "Reality glitches: VISUAL_GLITCH"
## toast — without it the player has no surface for WHICH effect
## just got applied.
signal corruption_effect_added(effect: String)
signal game_constant_modified(constant_name: String, old_value, new_value)
## Tick 264: fired by BestiarySystem.mark_defeated when the per-monster
## kill count crosses a defined milestone (10/50/100/500). UI shows a
## Toast so the grinding loop gets visible reward feedback. BestiarySystem
## itself can't emit (static class, no instance), so the signal hangs off
## GameState — same pattern as save_corrupted / corruption_effect_added.
signal bestiary_kill_milestone(monster_id: String, monster_name: String, count: int)

const SAVE_DIR = "user://saves/"
const SAVE_EXTENSION = ".cowirsave"

## Current game state
var current_save_name: String = ""
var playtime_seconds: float = 0.0
var corruption_level: float = 0.0  # 0.0 to 1.0, affects save stability

## Macro volatility - persistent across battles, drifts up with Speculator use
var macro_volatility: float = 0.0  # 0.0-1.0, soft cap

## Player party state (references to Combatant nodes)
var player_party: Array[Dictionary] = []

## Party leader index (which party member leads the overworld sprite)
var party_leader_index: int = 0

## Economy
var party_gold: int = 500  # Starting gold

## Settings (exposed to UI)
var encounter_rate_multiplier: float = 1.0  # 0.0 to 2.0, controlled via settings menu
var debug_log_enabled: bool = true  # Show debug log overlay (default on)
var debug_all_pcs_unlocked: bool = false  # Bypass spotlight gates (autobattle_locked) on all PCs; off by default so the W1 spotlight-unlock arc plays normally
var show_controller_overlay: bool = true  # Show controller hint overlay during autogrind/battle
var music_volume: int = 100  # 0-100 percent
var sfx_volume: int = 100  # 0-100 percent
var default_battle_speed: float = 1.0  # Default speed index value
var text_speed: String = "normal"  # slow | normal | fast | instant
# Tick 222: accessibility text-size multiplier. Consumers (CutsceneDialogue etc.) multiply base font sizes by this. 1.0 = default, 0.8 = compact, 1.25/1.5/2.0 = larger for readability.
var text_size_scale: float = 1.0  # 0.8 | 1.0 | 1.25 | 1.5 | 2.0
# Tick 226: color-blind friendly palette. When true, DamageNumber swaps lime green → cyan (heal) and orange → bright yellow (crit) — both safer for deuteranopia/protanopia (red-green color blindness, ~5% of males).
var color_blind_mode: bool = false
var screen_shake_enabled: bool = true  # Master gate for camera/screen shake effects
## Wave C: dynamic-dialogue master switch persisted to user settings. Off by
## default on web (no HTTP backend reachable from WASM); on by default on
## desktop. SettingsMenu mirrors this to LLMService.llm_enabled at runtime.
var llm_enabled: bool = not OS.has_feature("web")

## Phase-1 LLM-strategic-boss flag — opt-in; see BattleManager._should_use_llm_strategy.
var boss_llm_strategy_enabled: bool = false

## Party LLM dialogue flag — opt-in; see BattleManager._maybe_fire_party_line.
var party_llm_dialogue_enabled: bool = false

## ── BYOK (Bring Your Own Key) — user-provided cloud LLM endpoint ──
##
## User directive 2026-06-22: power users want to plug in their own
## OpenAI / Anthropic-via-OpenRouter / Groq / etc key for a deeper
## model than the desktop default. The HTTPBackend already supports
## base_url + api_format + model + api_key — these fields persist the
## user's choice. SettingsMenu (future tick) writes them; LLMService
## reads them at backend probe time.
##
## Persisted ONLY in settings.json (per-machine), NEVER in per-save
## data — importing someone else's save must not carry their key.
##
## Web export: BYOK is gated off entirely because the browser sandbox
## can't safely hold secrets. Same gate as llm_enabled.
var llm_custom_backend_enabled: bool = false
var llm_custom_base_url: String = ""
var llm_custom_api_format: String = "openai"  ## "openai" | "ollama"
var llm_custom_model: String = ""
var llm_custom_api_key: String = ""  ## SENSITIVE — never log, never print


## ── LLM Rebalance Daemon ───────────────────────────────────────────
##
## User directive 2026-06-22: "the game needs to be constantly
## attempting to rebalance itself using the llm as guidance".
## Opt-in master switch; daemon is the RebalanceDaemon instance below.
var llm_rebalance_enabled: bool = false
var rebalance_daemon: RebalanceDaemon = null


## Mask the API key for UI display: 'sk-abcd…WXYZ' style. The full key
## stays in llm_custom_api_key. This helper is the ONLY safe way to
## surface the key value in logs, settings panels, or telemetry.
func get_llm_custom_api_key_masked() -> String:
	var k := llm_custom_api_key
	if k == "":
		return ""
	if k.length() <= 8:
		return "•".repeat(k.length())
	return k.substr(0, 4) + "…" + k.substr(k.length() - 4)

## Game constants (modifiable by Scriptweaver and other meta jobs)
var game_constants: Dictionary = {
	"exp_multiplier": 1.0,
	"gold_multiplier": 1.0,
	"damage_multiplier": 1.0,
	"healing_multiplier": 1.0,
	"encounter_rate": 1.0,
	"drop_rate_multiplier": 1.0,
}

## Tick 418: persistent battle counter. Pre-fix this lived only on
## GameLoop.battles_won as a session-local int that never made it to
## save data — every game restart reset to 0. SaveSystem and
## CutsceneDirector both tried to read a non-existent
## BattleManager.total_battles_won field and silently got 0
## (CutsceneDirector's "playstyle has been more automated" gating
## requires total_battles >= 20 and never fired). Now GameState owns
## the canonical count, persisted via to_dict, and GameLoop syncs
## its session counter to match.
var battles_won: int = 0

## Meta-save features (unlocked by Time Mage)
var meta_features: Dictionary = {
	"autosave_enabled": false,
	"rewind_enabled": false,
	"restore_points_enabled": false,
	"max_restore_points": 0
}

## Save history for Time Mage rewind
var save_history: Array[Dictionary] = []
var max_history_size: int = 10

## Corruption effects
var corruption_effects: Array[String] = []

## World progression — tracks which worlds are unlocked and story flags
var current_world: int = 1  # 1-6
var worlds_unlocked: int = 1  # Highest world unlocked (1 = only medieval)
var story_flags: Dictionary = {}  # Generic flag store: "w1_boss_defeated": true, etc.

## Pending boss defeat — set by dungeon scenes before triggering a boss battle.
## Read by GameLoop._on_battle_ended on victory to apply the appropriate flags.
## Schema: {
##   "story_flags": Array[String] (always-set on victory),
##   "constants": Array[String] (game_constants[k]=true on victory),
##   "dungeon_flag": String (optional, set on game_constants["dungeon_flags"] — tick 154; legacy saves stored on player_party[0]),
##   "unlock_world": bool (optional, advance worlds_unlocked once),
##   "unlock_story_flag": String (optional, set as story flag on victory),
##   "defeat_cutscene": String (optional, played by dungeon when scene re-instantiates)
## }
var pending_boss_defeat: Dictionary = {}

var playtime_paused: bool = false

## LLM event log — append-only ring buffer of deterministic game facts.
## Instantiated in _ready() so it is always available to LLM subsystems.
var event_log: EventLog = null


## Story flag helpers
func set_story_flag(flag_name: String, value: bool = true) -> void:
	story_flags[flag_name] = value

func get_story_flag(flag_name: String) -> bool:
	return story_flags.get(flag_name, false)


## Tick 335: centralized dual-namespace story-flag check. Mirrors the
## ad-hoc pattern in WanderingNPC._flag_set (line ~291), QuestLog
## ._is_quest_flag_set (line ~334), and QuestTracker (line ~94) so
## scattered call sites can converge on a single source of truth.
##
## Checks three places:
##   1. story_flags[flag]                       (the canonical store)
##   2. game_constants["cutscene_flag_" + flag] (cutscene-side writes)
##   3. game_constants[flag]                    (legacy bare-name writes)
##
## Pre-fix the bare get_story_flag() was used by ~7 readers
## (OverworldScene Castle Harmonia gate, HarmoniaVillage Suburban
## portal gate, etc) that would silently disagree with QuestLog /
## WanderingNPC after a save format migration or debug toggle that
## set ONLY the cutscene_flag_ variant. Routing those readers through
## this helper closes the disagreement at the boundary.
func is_story_flag_set(flag_name: String) -> bool:
	if flag_name == "":
		return false
	if story_flags.get(flag_name, false):
		return true
	if game_constants.get("cutscene_flag_" + flag_name, false):
		return true
	return bool(game_constants.get(flag_name, false))

func unlock_next_world() -> void:
	if worlds_unlocked < 6:
		worlds_unlocked += 1
		print("[GAMESTATE] World %d unlocked!" % worlds_unlocked)

func is_world_unlocked(world_num: int) -> bool:
	return world_num <= worlds_unlocked


func _ready() -> void:
	_ensure_save_directory()
	event_log = EventLog.new()
	rebalance_daemon = RebalanceDaemon.new()


func _process(delta: float) -> void:
	if not playtime_paused:
		playtime_seconds += delta


## Save/Load system
func _ensure_save_directory() -> void:
	"""Create save directory if it doesn't exist"""
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)


func _create_save_data() -> Dictionary:
	"""Create save data dictionary.
	Bug fix (2026-04-30): added macro_volatility and current_save_name —
	previously these were declared as state but never serialized, so
	macro_volatility (Speculator drift) reset to 0.0 on every load."""
	return {
		"version": "0.1.0",
		"timestamp": Time.get_unix_time_from_system(),
		"playtime": playtime_seconds,
		"corruption_level": corruption_level,
		"macro_volatility": macro_volatility,
		"party_gold": party_gold,
		"player_party": player_party.duplicate(true),
		"party_leader_index": party_leader_index,
		"game_constants": game_constants.duplicate(),
		"meta_features": meta_features.duplicate(),
		"corruption_effects": corruption_effects.duplicate(),
		"current_world": current_world,
		"worlds_unlocked": worlds_unlocked,
		"story_flags": story_flags.duplicate(),
		"current_save_name": current_save_name,
		# Wave C: dynamic-dialogue switch is also written into per-save data so
		# loading an old save doesn't blow away the user's preference. The
		# settings.json copy in SaveSystem is the primary store; this is the
		# secondary so per-save imports stay self-contained.
		"llm_enabled": llm_enabled,
		"boss_llm_strategy_enabled": boss_llm_strategy_enabled,
		"party_llm_dialogue_enabled": party_llm_dialogue_enabled,
		"llm_rebalance_enabled": llm_rebalance_enabled,
		"event_log": event_log.serialize() if event_log != null else [],
		"rebalance_daemon": rebalance_daemon.to_dict() if rebalance_daemon != null else {},
		## Tick 418: persist the canonical battle counter so
		## CutsceneDirector's autobattle-ratio gating and any other
		## "total battles >= N" thresholds actually fire after enough
		## play. Pre-fix this lived only on GameLoop and reset to 0
		## every restart.
		"battles_won": battles_won,
		## Tick 413: persist save_history so Time Mage rewinds and
		## tick-412 restore points survive save+quit cycles. Pre-fix
		## save_history was in-memory only — quit the game and every
		## restore point evaporated, defeating the "you can revert
		## later" design of the restore_point ability. Strip nested
		## save_history from each snapshot to prevent recursive bloat
		## (each snapshot is already a full save_data; embedding
		## another save_history inside would double the file size per
		## generation). The serialized list is capped naturally by
		## max_history_size (5 default).
		"save_history": _serialize_save_history(),
	}


## Tick 413: deep-strip nested save_history from each snapshot so
## persisting the rewind ring buffer doesn't cause recursive bloat.
func _serialize_save_history() -> Array:
	var out: Array = []
	for snapshot in save_history:
		if not (snapshot is Dictionary):
			continue
		var stripped: Dictionary = snapshot.duplicate(true)
		if stripped.has("save_history"):
			stripped.erase("save_history")
		out.append(stripped)
	return out


func _apply_save_data(save_data: Dictionary) -> void:
	"""Apply loaded save data to game state"""
	if save_data.has("playtime"):
		playtime_seconds = save_data["playtime"]
	if save_data.has("corruption_level"):
		## Tick 156: float() coerce + clampf to documented [0.0, 1.0]
		## range. Pre-fix a corrupted save with negative or >1.0 value
		## would propagate: add_corruption clamps on add but read sites
		## (save_corrupted signal arg, _apply_random_corruption_effect)
		## could fire with out-of-range. Sealing at load.
		corruption_level = clampf(float(save_data["corruption_level"]), 0.0, 1.0)
	if save_data.has("macro_volatility"):
		macro_volatility = float(save_data["macro_volatility"])
	if save_data.has("party_gold"):
		party_gold = save_data["party_gold"]
	if save_data.has("player_party"):
		# JSON.parse returns generic Array — direct assignment to
		# Array[Dictionary] silently fails (SCRIPT ERROR, no crash) and
		# leaves player_party at its default []. (2026-05-12 audit:
		# same root cause as the Combatant.from_dict typed-array fix.)
		## Tick 163: cap at MAX_PARTY_SIZE (CLAUDE.md strict-5) +
		## sanitize per-entry inventory dict (mirrors tick 162's
		## Combatant.inventory cleanup but on the GameState snapshot
		## dict, which ShopScene reads directly without going through
		## Combatant.from_dict). Drops oldest-first if oversized so
		## party_leader_index resolution against position 0 stays
		## meaningful for the player's primary character.
		const MAX_PARTY_SIZE: int = 5
		var typed_party: Array[Dictionary] = []
		for entry in save_data["player_party"]:
			if not (entry is Dictionary):
				continue
			var copied: Dictionary = entry.duplicate(true)
			if copied.has("inventory") and copied["inventory"] is Dictionary:
				var raw_inv: Dictionary = copied["inventory"]
				var sanitized: Dictionary = {}
				for item_id in raw_inv.keys():
					var key: String = str(item_id)
					if key == "":
						continue
					var qty: int = int(raw_inv[item_id])
					if qty <= 0:
						continue
					sanitized[key] = qty
				copied["inventory"] = sanitized
			typed_party.append(copied)
		while typed_party.size() > MAX_PARTY_SIZE:
			# Drop newest (back) — strict-5 party means positions 0-4
			# are the canonical starters (Fighter/Cleric/Mage/Rogue/
			# Bard). Anything beyond is save corruption or migration
			# from an older variable-size design. Trim the tail so the
			# canonical roster's leader-position semantics survive.
			typed_party.pop_back()
		# Resolve legacy job_aliases here too — without this, the carefully-
		# resolved IDs that SaveSystem._deserialize_party writes BEFORE
		# from_dict get silently overwritten with raw aliased IDs (white_mage
		# / black_mage / thief) when game_state.player_party deserializes.
		# Resolving in-place means any caller of from_dict — SaveSystem,
		# time-rewind restore, save-migration tooling — gets canonical IDs.
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		var job_system: Node = null
		if tree != null and tree.root != null:
			job_system = tree.root.get_node_or_null("JobSystem")
		if job_system != null and job_system.has_method("resolve_job_id"):
			for entry in typed_party:
				if entry.has("job_id") and entry["job_id"] is String:
					entry["job_id"] = job_system.resolve_job_id(entry["job_id"])
				if entry.has("job") and entry["job"] is String:
					entry["job"] = job_system.resolve_job_id(entry["job"])
				if entry.has("secondary_job_id") and entry["secondary_job_id"] is String:
					entry["secondary_job_id"] = job_system.resolve_job_id(entry["secondary_job_id"])
		player_party = typed_party
	if save_data.has("party_leader_index"):
		## Tick 155: int() coerce (JSON.parse returns numeric as
		## float) + clamp to valid range. Pre-fix a corrupted save
		## with an out-of-range index would crash the next consumer
		## reading player_party[party_leader_index]. The clamp uses
		## the loaded player_party.size() — make sure this line
		## stays AFTER the player_party load above. If the saved
		## index is invalid we fall back to 0 (defensive: max with 0
		## handles the empty-party edge case where size()-1 = -1).
		var raw_idx: int = int(save_data["party_leader_index"])
		var max_idx: int = max(0, player_party.size() - 1)
		party_leader_index = clampi(raw_idx, 0, max_idx)
	## Tick 363: type-guard Dictionary/Array reads so a corrupted save
	## with null / int / string in these slots warns + skips instead of
	## crashing _apply_save_data with `Trying to assign a value of type
	## 'X' to a variable of type 'Dictionary'`. Same defensive shape as
	## tick 362's player.position guard in SaveSystem.
	if save_data.has("game_constants"):
		# Tick 112: MERGE saved values onto the default dict instead of
		# replacing the dict wholesale. Old saves predate later-added keys
		# (exp_multiplier, encounter_rate, drop_rate_multiplier, …), and a
		# direct replace wiped the defaults, leaving consumers like
		# GameState.add_gold to crash on KeyError when accessing the
		# missing key. Merging preserves both the saved daemon nudges
		# AND the defaults for new keys the save didn't know about.
		var raw_gc: Variant = save_data["game_constants"]
		if raw_gc is Dictionary:
			var saved: Dictionary = raw_gc
			for key in saved.keys():
				game_constants[key] = saved[key]
		else:
			push_warning("[GameState] _apply_save_data: game_constants malformed (type=%s) — keeping defaults" % typeof(raw_gc))
	if save_data.has("meta_features"):
		## Tick 150: same MERGE pattern as game_constants (tick 112).
		## Pre-fix this replaced the dict wholesale — old saves missing
		## later-added default keys (e.g. a new "restore_points_v2" entry)
		## would silently lose the defaults on load, leaving consumers
		## crashing on missing-key access. Merging preserves both the
		## saved values AND any defaults the save didn't know about.
		var raw_meta: Variant = save_data["meta_features"]
		if raw_meta is Dictionary:
			var saved_meta: Dictionary = raw_meta
			for key in saved_meta.keys():
				meta_features[key] = saved_meta[key]
		else:
			push_warning("[GameState] _apply_save_data: meta_features malformed (type=%s) — keeping defaults" % typeof(raw_meta))
	if save_data.has("corruption_effects"):
		var raw_ce: Variant = save_data["corruption_effects"]
		if raw_ce is Array:
			var typed_corruption: Array[String] = []
			for ce in raw_ce:
				typed_corruption.append(str(ce))
			corruption_effects = typed_corruption
		else:
			push_warning("[GameState] _apply_save_data: corruption_effects malformed (type=%s) — keeping current list" % typeof(raw_ce))
	## Tick 156: world bookkeeping is int 1-6 (matches the 6 worlds
	## shipped). Coerce from JSON's float + clamp to valid range so
	## a corrupted save with 0 or 99 doesn't leak into is_world_unlocked
	## (which compares world_num <= worlds_unlocked — 99 would
	## "unlock" all worlds) or WorldMapMenu's display label.
	if save_data.has("current_world"):
		current_world = clampi(int(save_data["current_world"]), 1, 6)
	if save_data.has("worlds_unlocked"):
		worlds_unlocked = clampi(int(save_data["worlds_unlocked"]), 1, 6)
	if save_data.has("story_flags"):
		# Tick 363: type-guard before .duplicate() — a corrupted save with
		# story_flags=null would crash with Invalid call .duplicate on Nil.
		var raw_sf: Variant = save_data["story_flags"]
		if raw_sf is Dictionary:
			story_flags = raw_sf.duplicate()
		else:
			push_warning("[GameState] _apply_save_data: story_flags malformed (type=%s) — keeping current flags" % typeof(raw_sf))
	if save_data.has("current_save_name"):
		current_save_name = save_data["current_save_name"]
	if save_data.has("llm_enabled"):
		llm_enabled = bool(save_data["llm_enabled"])
	if save_data.has("boss_llm_strategy_enabled"):
		boss_llm_strategy_enabled = bool(save_data["boss_llm_strategy_enabled"])
	if save_data.has("party_llm_dialogue_enabled"):
		party_llm_dialogue_enabled = bool(save_data["party_llm_dialogue_enabled"])
	if save_data.has("llm_rebalance_enabled"):
		llm_rebalance_enabled = bool(save_data["llm_rebalance_enabled"])
	# Wave D: restore EventLog. We lazily instantiate if _ready() somehow
	# hasn't run yet (defensive — _apply_save_data is normally called via
	# SaveSystem after autoloads are live). EventLog.restore() handles the
	# typed-array coercion, so we hand the raw Array straight through.
	if event_log == null:
		event_log = EventLog.new()
	if save_data.has("event_log"):
		event_log.restore(save_data["event_log"])
	else:
		event_log.clear()
	# Rebalance daemon: same lazy-instantiate pattern as event_log,
	# then restore pending + applied histories so the player's review
	# queue survives a quit-and-resume.
	if rebalance_daemon == null:
		rebalance_daemon = RebalanceDaemon.new()
	if save_data.has("rebalance_daemon"):
		rebalance_daemon.from_dict(save_data["rebalance_daemon"])

	## Tick 418: restore the canonical battle counter. max(0, ...)
	## clamp defends against a corrupted save with a negative value.
	if save_data.has("battles_won"):
		battles_won = max(0, int(save_data["battles_won"]))

	## Tick 413: restore save_history from the persisted snapshot.
	## Type-guarded with explicit typed-Array coercion to dodge the
	## documented Array[Dictionary] silent-fail trap (CLAUDE.md
	## Common Pitfalls). Cap at max_history_size on load so a
	## corrupted save with 1000 snapshots doesn't bloat the live
	## ring buffer.
	if save_data.has("save_history"):
		var raw_history: Variant = save_data["save_history"]
		if raw_history is Array:
			var typed_history: Array[Dictionary] = []
			for entry in raw_history:
				if entry is Dictionary:
					typed_history.append(entry.duplicate(true))
			while typed_history.size() > max_history_size:
				typed_history.pop_front()
			save_history = typed_history
		else:
			push_warning("[GameState] _apply_save_data: save_history malformed (type=%s) — keeping current ring buffer" % typeof(raw_history))


## Corruption system
func add_corruption(amount: float) -> void:
	"""Add corruption to current save"""
	var old_level = corruption_level
	corruption_level = clampf(corruption_level + amount, 0.0, 1.0)

	if corruption_level > old_level:
		save_corrupted.emit(corruption_level)
		_apply_random_corruption_effect()


func _apply_corruption_to_save(save_data: Dictionary) -> Dictionary:
	"""Apply corruption effects when saving"""
	var corrupted_data = save_data.duplicate(true)

	if randf() < corruption_level:
		# Random corruption effects
		var corruption_type = randi() % 5

		match corruption_type:
			0:  # Corrupt player HP
				if corrupted_data.has("player_party"):
					for character in corrupted_data["player_party"]:
						if randf() < 0.3:
							character["current_hp"] = int(character["current_hp"] * randf_range(0.5, 0.9))
			1:  # Corrupt stats
				if corrupted_data.has("player_party"):
					for character in corrupted_data["player_party"]:
						if randf() < 0.3:
							character["attack"] = int(character["attack"] * randf_range(0.8, 1.0))
			2:  # Corrupt BP
				if corrupted_data.has("player_party"):
					for character in corrupted_data["player_party"]:
						character["current_bp"] = randi_range(-2, 0)
			3:  # Add fake corruption effect marker
				if not corrupted_data.has("corruption_effects"):
					corrupted_data["corruption_effects"] = []
				corrupted_data["corruption_effects"].append("data_integrity_compromised")
			4:  # Corrupt game constants
				if corrupted_data.has("game_constants") and game_constants.size() > 0:
					var keys = game_constants.keys()
					var constant = keys[randi() % keys.size()]
					corrupted_data["game_constants"][constant] *= randf_range(0.7, 1.3)

	return corrupted_data


func _apply_random_corruption_effect() -> void:
	"""Apply a random corruption effect to gameplay"""
	var effects = [
		"visual_glitch",
		"stat_drain",
		"bp_instability",
		"encounter_surge",
		"ability_corruption"
	]

	var effect = effects[randi() % effects.size()]
	if not effect in corruption_effects:
		corruption_effects.append(effect)
		## Tick 178: emit the signal so UI surfaces can show a
		## Toast (or any other indicator). Pre-fix only print()
		## fired — debug console only, invisible to the player.
		## The save_corrupted signal already exists but has no
		## listeners; this gives a more specific event ("which
		## effect just landed") for the UI to react to.
		corruption_effect_added.emit(effect)
		print("Corruption effect applied: %s" % effect)


## Game constant modification (Scriptweaver ability)
func modify_constant(constant_name: String, new_value: float) -> bool:
	"""Modify a game constant (causes corruption)"""
	if not game_constants.has(constant_name):
		# Tick 303: surface unknown-constant failures via push_warning
		# (matches JobSystem.assign_job tick 180 pattern). Pre-fix
		# print() only — silent in production debugger panel and
		# invisible to CI. A Scriptweaver typo'd constant name would
		# return false without any diagnostic, looking like the
		# modification succeeded but rolled back.
		push_warning("[GameState] modify_constant: constant '%s' not found in game_constants dict — modification failed (typo? save-format drift?)" % constant_name)
		return false

	var old_value = game_constants[constant_name]
	game_constants[constant_name] = new_value

	# Modifying game constants causes corruption
	var corruption_amount = abs(new_value - old_value) * 0.1
	add_corruption(corruption_amount)

	game_constant_modified.emit(constant_name, old_value, new_value)
	print("Game constant modified: %s = %s (was %s)" % [constant_name, new_value, old_value])
	return true


func get_constant(constant_name: String) -> float:
	"""Get current value of a game constant"""
	return game_constants.get(constant_name, 1.0)


## Time Mage features
func unlock_time_mage_features() -> void:
	"""Unlock meta-save features (called when Time Mage job is obtained)"""
	meta_features["autosave_enabled"] = true
	meta_features["rewind_enabled"] = true
	meta_features["restore_points_enabled"] = true
	meta_features["max_restore_points"] = 5
	print("Time Mage features unlocked!")


func record_history_checkpoint(force: bool = false) -> bool:
	"""Snapshot current state into save_history for Time Mage rewind.

	Bug fix (2026-06-14): save_history was dead — _add_to_history (the only
	function that appends to the ring buffer) had ZERO callers anywhere in
	src/, so save_history stayed empty forever and rewind_to_previous_save()
	always tripped the 'No previous save state' guard. The Time Mage
	'time_rewind' ability (abilities.json 'rewind' → meta_effect 'time_rewind'
	→ BattleManager → GameState.rewind_to_previous_save) was therefore
	permanently non-functional.

	Public checkpoint hook: callers (SaveSystem on save success, BattleManager
	at battle start) invoke this to feed the history. Gated on rewind_enabled
	so we don't pay the deep-duplicate cost before the Time Mage unlock; pass
	force=true to snapshot regardless (used by tests / explicit quicksave).
	Returns true if a checkpoint was actually recorded."""
	if not force and not meta_features.get("rewind_enabled", false):
		return false
	_add_to_history(_create_save_data())
	return true


func _add_to_history(save_data: Dictionary) -> void:
	"""Add save state to history for rewind"""
	save_history.append(save_data.duplicate(true))

	# Keep history size limited
	while save_history.size() > max_history_size:
		save_history.pop_front()


func rewind_to_previous_save() -> bool:
	"""Rewind to previous save state (Time Mage ability)"""
	if not meta_features["rewind_enabled"]:
		print("Error: Rewind not unlocked")
		return false

	if save_history.size() < 2:
		print("Error: No previous save state to rewind to")
		return false

	# Remove current state
	save_history.pop_back()

	# Restore previous state
	var previous_state = save_history.back()
	_apply_save_data(previous_state)

	print("Rewound to previous save state")
	return true


## Economy methods
func add_gold(amount: int) -> void:
	"""Add gold to party (applies gold_multiplier).
	Tick 113: defensive .get() so a future debug path or pathological
	save that removed the key doesn't crash the entire victory flow.
	Matches the tick 109/110 defensive read pattern in BattleManager
	exp_multiplier + OverworldController encounter_rate, and clamps
	into the same [0.1, 10.0] band as the daemon's safe-delta floor."""
	## Tick 372: refuse negative amounts. Pre-fix add_gold(-50)
	## silently DRAINED 50 gold through `party_gold += -50`. Same
	## exploitable class as ticks 368-371's heal/restore_mp/spend_ap/
	## gain_ap/spend_mp/add_item negative-amount footguns. A typo'd
	## reward table or Scriptweaver mod could silently bankrupt the
	## party. Use spend_gold for legitimate drain.
	if amount < 0:
		push_warning("[GameState] add_gold(%d) — negative amount refused (use spend_gold to drain)" % amount)
		return
	var multiplier: float = clampf(
		float(game_constants.get("gold_multiplier", 1.0)),
		0.1, 10.0)
	var multiplied_amount = int(amount * multiplier)
	party_gold += multiplied_amount
	print("Gold gained: %d (base: %d)" % [multiplied_amount, amount])


func spend_gold(amount: int) -> bool:
	"""Spend gold (returns false if insufficient funds)"""
	## Tick 372: refuse negative amounts. Pre-fix spend_gold(-50)
	## passed the `party_gold < -50` gate (always false for valid
	## gold), then ran `party_gold -= -50` GRANTING 50 gold AND
	## returning true so the caller believed it had been spent.
	## Symmetric with spend_mp / remove_item bypasses. Use add_gold
	## for legitimate gain.
	if amount < 0:
		push_warning("[GameState] spend_gold(%d) — negative amount refused (use add_gold to grant)" % amount)
		return false
	if party_gold < amount:
		print("Error: Insufficient gold (have %d, need %d)" % [party_gold, amount])
		return false

	party_gold -= amount
	print("Gold spent: %d (remaining: %d)" % [amount, party_gold])
	return true


func get_gold() -> int:
	"""Get current party gold"""
	return party_gold


## Party leader methods
func get_party_leader() -> Dictionary:
	if player_party.is_empty():
		return {}
	var idx = clampi(party_leader_index, 0, player_party.size() - 1)
	return player_party[idx]


func cycle_party_leader(delta: int) -> void:
	if player_party.is_empty():
		return
	party_leader_index = (party_leader_index + delta + player_party.size()) % player_party.size()


## Utility
func get_playtime_formatted() -> String:
	"""Get formatted playtime string"""
	var hours = int(playtime_seconds / 3600)
	var minutes = int((playtime_seconds - hours * 3600) / 60)
	var seconds = int(playtime_seconds - hours * 3600 - minutes * 60)
	return "%02d:%02d:%02d" % [hours, minutes, seconds]


func reset_game_state() -> void:
	"""Reset game state to defaults.
	Bug fix (2026-04-30): now also clears story_flags, worlds_unlocked,
	current_world, meta_features, party_leader_index, macro_volatility,
	current_save_name. Pre-fix, New Game preserved all these from the
	prior playthrough, so a second New Game would skip prologue and have
	all 6 worlds unlocked from the start. Mirrors _create_save_data."""
	playtime_seconds = 0.0
	corruption_level = 0.0
	macro_volatility = 0.0
	party_gold = 500
	player_party.clear()
	corruption_effects.clear()
	save_history.clear()

	# Story / world progression
	story_flags.clear()
	current_world = 1
	worlds_unlocked = 1
	current_save_name = ""
	party_leader_index = 0
	pending_boss_defeat = {}

	# Reset game constants
	game_constants = {
		"exp_multiplier": 1.0,
		"gold_multiplier": 1.0,
		"damage_multiplier": 1.0,
		"healing_multiplier": 1.0,
		"encounter_rate": 1.0,
		"drop_rate_multiplier": 1.0,
	}

	# Reset meta features (autosave / rewind / restore points) — start fresh.
	# Mirror the var-default at GameState.gd:50.
	meta_features = {
		"autosave_enabled": false,
		"rewind_enabled": false,
		"restore_points_enabled": false,
		"max_restore_points": 0
	}

	# Wave D: drain EventLog so a New Game doesn't bleed prior-run facts
	# into the next playthrough's LLM prompts. (Without this, a fresh
	# party would still see "Boss Pyrroth defeated" in their first NPC
	# conversation.)
	if event_log != null:
		event_log.clear()


## Serialization methods for SaveSystem
func to_dict() -> Dictionary:
	"""Serialize game state for saving"""
	return _create_save_data()


func from_dict(data: Dictionary) -> void:
	"""Restore game state from saved data"""
	_apply_save_data(data)


func get_play_time() -> float:
	"""Get current playtime in seconds"""
	return playtime_seconds
