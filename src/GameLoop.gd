extends Node

## GameLoop - Controls the exploration → battle → menu game loop
## Manages scene transitions and player persistence

const BattleSceneRes = preload("res://src/battle/BattleScene.tscn")
const BattleSceneScript = preload("res://src/battle/BattleScene.gd")
const OverworldSceneRes = preload("res://src/exploration/OverworldScene.tscn")
const CharacterCreationScreenClass = preload("res://src/ui/CharacterCreationScreen.gd")
const CustomizationScript = preload("res://src/character/CharacterCustomization.gd")
const TitleScreenClass = preload("res://src/ui/TitleScreen.gd")

const HarmoniaVillageRes = preload("res://src/maps/villages/HarmoniaVillage.tscn")
const WhisperingCaveRes = preload("res://src/maps/dungeons/WhisperingCave.tscn")
const TavernInteriorScript = preload("res://src/maps/interiors/TavernInterior.gd")
const InnInteriorScript = preload("res://src/maps/interiors/InnInterior.gd")
const ScripturaPlazaScript = preload("res://src/maps/villages/ScripturaPlaza.gd")
const ScripturaGuildInteriorScript = preload("res://src/maps/interiors/ScripturaGuildInterior.gd")
const ScripturaBookshopInteriorScript = preload("res://src/maps/interiors/ScripturaBookshopInterior.gd")
const ShopInteriorScript = preload("res://src/maps/interiors/ShopInterior.gd")
const BlacksmithInteriorScript = preload("res://src/maps/interiors/BlacksmithInterior.gd")
const HarmoniaChapelInteriorScript = preload("res://src/maps/interiors/HarmoniaChapelInterior.gd")
const HarmoniaCartographerInteriorScript = preload("res://src/maps/interiors/HarmoniaCartographerInterior.gd")
const EldertreeGraftingHouseInteriorScript = preload("res://src/maps/interiors/EldertreeGraftingHouseInterior.gd")
const IronhavenStrikeRegistryInteriorScript = preload("res://src/maps/interiors/IronhavenStrikeRegistryInterior.gd")
const FrostholdMeltwaterClockInteriorScript = preload("res://src/maps/interiors/FrostholdMeltwaterClockInterior.gd")
const SandriftRainLedgerInteriorScript = preload("res://src/maps/interiors/SandriftRainLedgerInterior.gd")
const MapleGarageSaleInteriorScript = preload("res://src/maps/interiors/MapleGarageSaleInterior.gd")
const BrasstonRedundancyArchiveInteriorScript = preload("res://src/maps/interiors/BrasstonRedundancyArchiveInterior.gd")
const RivetRowIncidentBoardInteriorScript = preload("res://src/maps/interiors/RivetRowIncidentBoardInterior.gd")
const NodePrimeCacheInteriorScript = preload("res://src/maps/interiors/NodePrimeCacheInterior.gd")
const GrimhollowLanternDebtInteriorScript = preload("res://src/maps/interiors/GrimhollowLanternDebtInterior.gd")
const HarmoniaLibraryInteriorScript = preload("res://src/maps/interiors/HarmoniaLibraryInterior.gd")
const EldertreeHollowTreeInteriorScript = preload("res://src/maps/interiors/EldertreeHollowTreeInterior.gd")
const FrostholdWardenHutInteriorScript = preload("res://src/maps/interiors/FrostholdWardenHutInterior.gd")
const SandriftGlassmakerInteriorScript = preload("res://src/maps/interiors/SandriftGlassmakerInterior.gd")
const GrimhollowWitchHutInteriorScript = preload("res://src/maps/interiors/GrimhollowWitchHutInterior.gd")
const IronhavenWatchtowerInteriorScript = preload("res://src/maps/interiors/IronhavenWatchtowerInterior.gd")
const MapleHeightsArcadeInteriorScript = preload("res://src/maps/interiors/MapleHeightsArcadeInterior.gd")
const BrasstonClockworkLoftInteriorScript = preload("res://src/maps/interiors/BrasstonClockworkLoftInterior.gd")
const RivetRowUnionHallInteriorScript = preload("res://src/maps/interiors/RivetRowUnionHallInterior.gd")
const NodePrimeDaemonLoungeInteriorScript = preload("res://src/maps/interiors/NodePrimeDaemonLoungeInterior.gd")
const VertexThresholdInteriorScript = preload("res://src/maps/interiors/VertexThresholdInterior.gd")
const RebalanceDaemonScript = preload("res://src/llm/RebalanceDaemon.gd")
const FrostholdVillageScript = preload("res://src/maps/villages/FrostholdVillage.gd")
const EldertreeVillageScript = preload("res://src/maps/villages/EldertreeVillage.gd")
const GrimhollowVillageScript = preload("res://src/maps/villages/GrimhollowVillage.gd")
const SandriftVillageScript = preload("res://src/maps/villages/SandriftVillage.gd")
const IronhavenVillageScript = preload("res://src/maps/villages/IronhavenVillage.gd")
const MapleHeightsVillageScript = preload("res://src/maps/villages/MapleHeightsVillage.gd")
const MapleStripMallScript = preload("res://src/maps/villages/MapleStripMall.gd")
const MapleCommunityCenterInteriorScript = preload("res://src/maps/interiors/MapleCommunityCenterInterior.gd")
const EnrichmentAnnexInteriorScript = preload("res://src/maps/interiors/EnrichmentAnnexInterior.gd")
const BrasstonVillageScript = preload("res://src/maps/villages/BrasstonVillage.gd")
const RivetRowVillageScript = preload("res://src/maps/villages/RivetRowVillage.gd")
const NodePrimeVillageScript = preload("res://src/maps/villages/NodePrimeVillage.gd")
const VertexVillageScript = preload("res://src/maps/villages/VertexVillage.gd")
const IceDragonCaveScript = preload("res://src/maps/dungeons/IceDragonCave.gd")
const ShadowDragonCaveScript = preload("res://src/maps/dungeons/ShadowDragonCave.gd")
const LightningDragonCaveScript = preload("res://src/maps/dungeons/LightningDragonCave.gd")
const FireDragonCaveScript = preload("res://src/maps/dungeons/FireDragonCave.gd")
const AssemblyCoreScript = preload("res://src/maps/dungeons/AssemblyCore.gd")
const RootProcessScript = preload("res://src/maps/dungeons/RootProcess.gd")
const NullChamberScript = preload("res://src/maps/dungeons/NullChamber.gd")
const SuburbanUndergroundScript = preload("res://src/maps/dungeons/SuburbanUnderground.gd")
const CastleHarmoniaScript = preload("res://src/maps/dungeons/CastleHarmonia.gd")
const SteampunkMechanismScript = preload("res://src/maps/dungeons/SteampunkMechanism.gd")
const SteampunkOverworldScript = preload("res://src/exploration/SteampunkOverworld.gd")
const SuburbanOverworldScript = preload("res://src/exploration/SuburbanOverworld.gd")
const IndustrialOverworldScript = preload("res://src/exploration/IndustrialOverworld.gd")
const FuturisticOverworldScript = preload("res://src/exploration/FuturisticOverworld.gd")
const AbstractOverworldScript = preload("res://src/exploration/AbstractOverworld.gd")

enum LoopState {
	TITLE,
	BATTLE,
	EXPLORATION,
	AUTOGRIND,
	CUTSCENE
}

var current_state: LoopState = LoopState.EXPLORATION
var current_scene: Node = null

## Persistent party data
var party: Array[Combatant] = []
var battles_won: int = 0

## Shared equipment pool (unequipped items available to all party members)
var equipment_pool: Dictionary = {
	"weapons": [],
	"armors": [],
	"accessories": []
}


## Autobattle editor overlay
var _autobattle_editor: Control = null
var _autobattle_layer: CanvasLayer = null  # Separate layer to avoid camera zoom


## Exploration state
var _current_map_id: String = "overworld"

## When entering an interior scene (tavern/inn/shop), the source village id is
## saved here so the interior's exit door can target "village_return" and we
## resolve back to where the player came from. The existing INTERIOR_MAP_IDS
## const (declared near _get_transition_type) is the authoritative interior set.
var _village_origin_id: String = ""


## Public read of the current map_id — exposed so SaveSystem.can_quick_save()
## and others can interrogate location without needing to grep the scene tree.
func get_current_map_id() -> String:
	return _current_map_id


## Tick 307: setter that keeps MapSystem.current_map_id in sync with our
## _current_map_id. Pre-fix MapSystem.current_map_id was only updated by
## MapSystem.load_map, which is bypassed by GameLoop's direct scene routing
## for villages/dungeons/interiors. Result: bestiary mark_seen/mark_defeated
## (BattleScene/BattleManager/HeadlessBattleResolver), WorldMapMenu location
## label, autogrind dashboard location, and the save serialization all read
## a stale value (empty string or last MapSystem.load_map target — usually
## "overworld") regardless of where the player actually was. A monster
## defeated in fire_dragon_cave was logged as defeated in "overworld" in
## the bestiary; save records of a player at a dungeon save crystal stored
## the wrong map_id. Keeping MapSystem.current_map_id in sync via this
## setter fixes every read site at once without touching the load path.
func _set_current_map_id(id: String) -> void:
	_current_map_id = id
	if MapSystem and "current_map_id" in MapSystem:
		MapSystem.current_map_id = id
	# Tick 310: also sync GameState.current_world from the map_id so
	# GameOverScreen + LLMContext + any other reader sees the correct
	# world. Pre-fix current_world was set ONLY by autogrind's region-
	# advance signal, so a player dying in suburban_overworld with a
	# fresh save (never touched autogrind) saw the W1 game-over title.
	# Skip when GameState is unreachable (test envs).
	if GameState and "current_world" in GameState:
		var w: int = _get_world_for_map(id)
		if w != GameState.current_world:
			GameState.current_world = w
	# Tick 311: derive _current_terrain from the map_id at the same point
	# so save-load and autogrind hand-off see fresh terrain. Pre-fix the
	# terrain was only re-derived on battle-trigger and area-transition;
	# loading a save inside fire_dragon_cave and immediately starting
	# autogrind passed "plains" (the default) into start_grind, which
	# rendered the wrong battle background until the first ENEMY scripted
	# event ticked. Closes the same drift class as the world sync above.
	_current_terrain = _get_terrain_for_map(id)


## Tick 310: derive world number (1-6) from a map_id. Used by
## _set_current_map_id to keep GameState.current_world in sync with
## exploration. Heuristic-based prefix matching: W2 (suburban), W3
## (steampunk), W4 (industrial), W5 (futuristic), W6 (abstract) keys
## are distinctive; everything else falls back to W1 (medieval —
## covers harmonia / dragon caves / 5 side villages / Castle Harmonia
## / Whispering Cave). Adding a new W2-W6 region without updating
## this needs a push_warning at the call site so the gap is loud.
func _get_world_for_map(id: String) -> int:
	# W2 — Suburban
	if id.begins_with("suburban_") or id.begins_with("maple_heights"):
		return 2
	# W3 — Steampunk
	if id.begins_with("steampunk_") or id.begins_with("brasston"):
		return 3
	# W4 — Industrial
	if id.begins_with("industrial_") or id.begins_with("rivet_row") or id.begins_with("assembly_"):
		return 4
	# W5 — Futuristic
	if id.begins_with("futuristic_") or id.begins_with("node_prime") or id == "root_process":
		return 5
	# W6 — Abstract
	if id.begins_with("abstract_") or id.begins_with("vertex") or id == "null_chamber":
		return 6
	# W1 — Medieval (default; covers all original-world ids)
	return 1


## True when the player is inside one of the small village-side interior
## rooms. SaveSystem skips auto-save in this state because MapSystem
## doesn't track interiors (they're loaded by GameLoop's scene-routing,
## not MapSystem.load_map), so MapSystem.current_map_id would be stale —
## the resume path would either spawn the player in the wrong location
## or fail to load any map at all.
func is_inside_interior() -> bool:
	return _current_map_id in INTERIOR_MAP_IDS

var _spawn_point: String = "default"
var _exploration_scene: Node = null
var _player_position: Vector2 = Vector2.ZERO  # Save position for battle return
var _current_cave_floor: int = 1  # Track current floor in multi-floor dungeons
var _current_terrain: String = "plains"  # Current terrain type for battle backgrounds

## Last battle config for retry
var _last_battle_enemies: Array = []  # Enemy IDs from last battle
var _last_battle_is_encounter: bool = false  # Was it a random encounter?

## Tick 471: Spotlight Duel state. `start_solo_battle` sets these
## before firing `_start_battle_async`; `_on_battle_ended` reads them
## to short-circuit its normal exploration-return flow (the cutscene
## is still driving; we don't fade/scene-swap). Cleared by
## `start_solo_battle` after `spotlight_battle_ended` is emitted.
var _spotlight_duel_active: bool = false
var _pending_spotlight_unlock: String = ""  # PC job id ("fighter", etc.); "" when no unlock target
var _spotlight_saved_party: Array[Combatant] = []
signal spotlight_battle_ended(victory: bool)

## Area transition fade overlay (reused across all area transitions)
var _area_fade_layer: CanvasLayer = null
var _area_fade_rect: ColorRect = null

## Overworld menu
var _overworld_menu: Control = null
var _overworld_menu_layer: CanvasLayer = null
var _menu_hidden_hud: Array = []

## Party Chat (opt-in flavor cutscenes)
var _party_chat_menu: Control = null
var _party_chat_menu_layer: CanvasLayer = null
var _party_chat_indicator: Control = null
var _party_chat_indicator_layer: CanvasLayer = null

## Autogrind
var _autogrind_controller: Node = null
var _autogrind_ui: Control = null
var _autogrind_ui_layer: CanvasLayer = null
var _is_autogrinding: bool = false
var _autogrind_dashboard: Control = null
var _autogrind_overlay: Control = null
var _autogrind_overlay_layer: CanvasLayer = null
var _autogrind_battle_summaries: Array = []
var _autogrind_summary: Control = null
var _controller_overlay: ControllerOverlay = null
var _controller_overlay_layer: CanvasLayer = null

## Character creation
var _character_creation_screen: Control = null
var _first_launch: bool = true  # True if no save exists

## Title screen
var _title_screen: Control = null
var _title_layer: CanvasLayer = null

## R9 (inference_failed breadcrumb, principle #7): one-time latch so the FIRST
## LLM fallback in a session surfaces a brief, in-voice notice instead of being
## truly silent. Subsequent failures stay quiet (no toast spam).
var _llm_notice_shown: bool = false

## Companion latch — first successful non-fallback LLM response in a session
## surfaces a "Dynamic dialogue active" toast so desktop+Ollama players know
## the LLM is wired up. Subsequent successes stay quiet.
var _llm_success_notice_shown: bool = false

## First-open latch for the autobattle editor — fires the autobattle_intro
## tutorial hint once per save (TutorialHints itself enforces the once-per-save).
var _autobattle_editor_ever_opened: bool = false

func _ready() -> void:
	## Boot canary (2026-07-01 gray-void post-mortem): if load-bearing
	## scene scripts failed to compile (stale class cache after new
	## class_name merges), the game used to boot into an empty
	## default-clear viewport with live input and 37 SCRIPT ERRORs
	## buried in the log. Detect it and put an actionable message on
	## screen instead.
	_check_boot_canaries()

	# Initialize equipment pool with extra items
	_init_equipment_pool()

	## Tick 178: surface save corruption events to the player.
	## Pre-fix save_corrupted and the new corruption_effect_added
	## signals fired but had NO listeners — player corrupted their
	## save via Scriptweaver/etc. and got zero visible feedback
	## that the corruption increased or that a NEW effect landed.
	## Toast banner is the right surface (matches the existing
	## save-toast / autosave-toast pattern at _on_any_save_completed).
	if GameState:
		if GameState.has_signal("save_corrupted") and not GameState.save_corrupted.is_connected(_on_save_corruption_increased):
			GameState.save_corrupted.connect(_on_save_corruption_increased)
		if GameState.has_signal("corruption_effect_added") and not GameState.corruption_effect_added.is_connected(_on_corruption_effect_added):
			GameState.corruption_effect_added.connect(_on_corruption_effect_added)
		## Tick 179: surface Scriptweaver edits to game constants.
		## game_constant_modified fires from modify_constant (the
		## Scriptweaver's main verb) but had ZERO listeners — same
		## silent failure class as tick 178's save_corrupted gap.
		if GameState.has_signal("game_constant_modified") and not GameState.game_constant_modified.is_connected(_on_game_constant_modified):
			GameState.game_constant_modified.connect(_on_game_constant_modified)
		# Tick 264: bestiary kill-milestone toast — fires once per
		# (monster, threshold) pair across the save.
		if GameState.has_signal("bestiary_kill_milestone") and not GameState.bestiary_kill_milestone.is_connected(_on_bestiary_kill_milestone):
			GameState.bestiary_kill_milestone.connect(_on_bestiary_kill_milestone)

	## Tick 254: surface party-chat event unlocks. Pre-fix the player
	## triggered an event flag (boss kill, level 10, magic shop, etc.)
	## and the chat silently appeared in PartyChatMenu — they wouldn't
	## notice until next menu visit. Toast banner ("New chat: <title>")
	## gives the immediate feedback signal.
	if PartyChatSystem and PartyChatSystem.has_signal("event_chat_unlocked") \
			and not PartyChatSystem.event_chat_unlocked.is_connected(_on_event_chat_unlocked):
		PartyChatSystem.event_chat_unlocked.connect(_on_event_chat_unlocked)

	# Create the persistent area-transition fade overlay (layer=90, below BattleTransition=100)
	_area_fade_layer = CanvasLayer.new()
	_area_fade_layer.layer = 90
	add_child(_area_fade_layer)
	_area_fade_rect = ColorRect.new()
	_area_fade_rect.color = Color.BLACK
	_area_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_area_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area_fade_rect.modulate.a = 0.0
	_area_fade_layer.add_child(_area_fade_rect)

	# Gamepad diagnostic overlay (F11)
	var diag_layer = CanvasLayer.new()
	diag_layer.layer = 99
	add_child(diag_layer)
	var diag = GamepadDiagnostic.new()
	diag_layer.add_child(diag)

	# Check for existing save to determine if this is first launch
	_first_launch = not _save_exists()

	# Toast on any save (manual or auto)
	if SaveSystem and SaveSystem.has_signal("save_completed"):
		if not SaveSystem.save_completed.is_connected(_on_any_save_completed):
			SaveSystem.save_completed.connect(_on_any_save_completed)

	# Toast on any save failure — pre-fix, save_failed had ZERO listeners
	# so a player who pressed Save in the chapel got silent rejection
	# with no feedback. Surface the specific reason from _save_block_reason.
	if SaveSystem and SaveSystem.has_signal("save_failed"):
		if not SaveSystem.save_failed.is_connected(_on_any_save_failed):
			SaveSystem.save_failed.connect(_on_any_save_failed)

	# Flush runtime party → GameState BEFORE every save reads it.
	# Pre-fix this only ran when the overworld menu opened, so battle
	# gains since the last menu open vanished from auto-saves.
	if SaveSystem and SaveSystem.has_signal("pre_save_sync"):
		if not SaveSystem.pre_save_sync.is_connected(_sync_party_to_game_state):
			SaveSystem.pre_save_sync.connect(_sync_party_to_game_state)

	# Always show title screen first
	_show_title_screen()

	# R9 (inference_failed breadcrumb): connect deferred — LLMService autoloads
	# late, so /root/LLMService may not exist yet at our _ready. Deferring runs
	# the hookup after the current frame's autoload init settles.
	_connect_llm_breadcrumb.call_deferred()

	# Log startup
	if DebugLogOverlay:
		DebugLogOverlay.log("[GAME] Started")

	# Arg-gated render smoke — see _maybe_run_battle_smoke.
	_maybe_run_battle_smoke()


## `xvfb-run godot -- --battle-smoke` (battle only) or `-- --render-smoke` (overworld walk frames + battle) — pixels catch what source pins can't
func _maybe_run_battle_smoke() -> void:
	var full: bool = "--render-smoke" in OS.get_cmdline_user_args()
	if not full and not ("--battle-smoke" in OS.get_cmdline_user_args()):
		return
	# Smoke runs are headed (xvfb) so the headless auto-mute never engages — mute here or music hits real speakers.
	AudioServer.set_bus_mute(0, true)
	await get_tree().create_timer(1.0).timeout
	print("[SMOKE] render smoke starting (full=%s)" % str(full))
	# Deterministic smoke: neutralize this box's dev flags — debug_all_pcs_unlocked force-clears is_player_trusted (BattleManager) and breaks the game-over leg's auto-play.
	if GameState and "debug_all_pcs_unlocked" in GameState:
		GameState.debug_all_pcs_unlocked = false
	_close_title_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	_create_party()
	DirAccess.make_dir_recursive_absolute("user://smoke")
	if full:
		_cutscene_cooldown = true
		_set_current_map_id("overworld")
		await _start_exploration()
		await get_tree().create_timer(1.5).timeout
		# mid-stride captures — the garbled-walk sprite class is only visible while moving
		for dir_action in ["ui_right", "ui_left"]:
			Input.action_press(dir_action)
			await get_tree().create_timer(0.7).timeout
			await _smoke_shot("overworld_walk_%s" % dir_action.trim_prefix("ui_"))
			Input.action_release(dir_action)
		# village: NPC sheets + quest markers in one frame
		_cutscene_cooldown = true
		_set_current_map_id("harmonia_village")
		await _start_exploration()
		await get_tree().create_timer(1.5).timeout
		await _smoke_shot("village")
		# settings (Start) then the overworld/party menu (X) — the week's UI churn surfaces
		_smoke_tap("ui_menu")
		await get_tree().create_timer(1.0).timeout
		await _smoke_shot("settings")
		_smoke_tap("ui_cancel")
		await get_tree().create_timer(0.5).timeout
		_smoke_key(KEY_X)
		await get_tree().create_timer(1.0).timeout
		await _smoke_shot("overworld_menu")
		# cursor rests on Quest Log — one confirm renders the QuestSystem UI
		_smoke_tap("ui_accept")
		await get_tree().create_timer(1.0).timeout
		await _smoke_shot("quest_log")
		_smoke_tap("ui_cancel")
		await get_tree().create_timer(0.4).timeout
		_smoke_tap("ui_cancel")
		await get_tree().create_timer(0.5).timeout
		# autobattle grid editor (F5) — the design-pillar surface, never before in automation
		_smoke_key(KEY_F5)
		await get_tree().create_timer(1.2).timeout
		await _smoke_shot("autobattle_editor")
		# verified close: the tutorial hint consumes one keypress, so a blind F5 left the editor ghosting under later screens
		for close_try in range(3):
			_smoke_key(KEY_F5)
			await get_tree().create_timer(0.6).timeout
			if _autobattle_editor == null or not is_instance_valid(_autobattle_editor):
				break
		# Formations + Records reference pages (v3.33.66/.72) — direct-instanced so
		# render coverage doesn't depend on brittle menu-cursor driving
		var FormationsScript = load("res://src/ui/FormationsMenu.gd")
		if FormationsScript:
			var fm = FormationsScript.new()
			fm.party = party
			add_child(fm)
			await get_tree().create_timer(0.6).timeout
			await _smoke_shot("formations_page")
			fm.queue_free()
			await get_tree().process_frame
		var RecordsScript = load("res://src/ui/RecordsMenu.gd")
		if RecordsScript:
			var rm = RecordsScript.new()
			add_child(rm)
			await get_tree().create_timer(0.6).timeout
			await _smoke_shot("records_page")
			rm.queue_free()
			await get_tree().process_frame
		# shop UI via the real VillageShop path — the progression item's purchase surface
		var smoke_shop = load("res://src/exploration/VillageShop.gd").new()
		smoke_shop.shop_type = VillageShop.ShopType.BLACK_MAGIC
		smoke_shop.shop_name = "The Arcanum"
		add_child(smoke_shop)
		smoke_shop._show_shop_menu(null)
		await get_tree().create_timer(1.2).timeout
		await _smoke_shot("shop")
		if smoke_shop._shop_layer and is_instance_valid(smoke_shop._shop_layer):
			smoke_shop._shop_layer.queue_free()
		smoke_shop.queue_free()
		await get_tree().create_timer(0.5).timeout
		# cave, then battle FROM it — the scene that leaked under battle 2026-07-02
		_cutscene_cooldown = true
		_set_current_map_id("whispering_cave")
		await _start_exploration()
		await get_tree().create_timer(1.5).timeout
		await _smoke_shot("cave")
	await _start_battle_async(["goblin"], true)
	await get_tree().create_timer(2.5).timeout
	var xform := get_viewport().get_canvas_transform()
	print("[SMOKE] canvas transform origin=%s scale=%s" % [str(xform.origin), str(xform.get_scale())])
	if xform.origin != Vector2.ZERO:
		_smoke_failed = true
	await _smoke_shot("battle_smoke")
	# the duel must wait for the live battle to end — a fixed sleep raced RNG-length battles
	var _bwait := 0.0
	while BattleManager.current_state != BattleManager.BattleState.INACTIVE and _bwait < 30.0:
		await get_tree().create_timer(0.5).timeout
		_bwait += 0.5
	# dismiss victory and walk the battle→exploration seam — the gray-screen regression class
	_smoke_tap("ui_accept")
	await get_tree().create_timer(2.0).timeout
	await _smoke_shot("post_battle_return")
	if full:
		# spotlight duel leg: trust the fighter so turns auto-play, capture mid-duel
		for m in party:
			if m and is_instance_valid(m) and "player_trust" in m:
				m.player_trust = true
		start_solo_battle("fighter", "fighter_skeleton_knight")
		await get_tree().create_timer(4.0).timeout
		await _smoke_shot("duel_smoke")
		# game-over leg: force-resolve the duel, cripple the party, lose to a dragon
		BattleManager.end_battle(true)
		var _gwait := 0.0
		while BattleManager.current_state != BattleManager.BattleState.INACTIVE and _gwait < 20.0:
			await get_tree().create_timer(0.5).timeout
			_gwait += 0.5
		for m in party:
			if m and is_instance_valid(m):
				m.current_hp = 1
		await _start_battle_async(["shadow_dragon"], true)
		_gwait = 0.0
		var game_over_node: Node = null
		while game_over_node == null and _gwait < 30.0:
			await get_tree().create_timer(0.5).timeout
			_gwait += 0.5
			for c in get_children():
				if c is GameOverScreen:
					game_over_node = c
					break
		if game_over_node == null:
			print("[SMOKE] game_over screen never appeared within 30s")
			_smoke_failed = true
		else:
			await get_tree().create_timer(1.0).timeout
			await _smoke_shot("game_over", 0.97)
	await get_tree().create_timer(0.2).timeout
	print("[SMOKE] VERDICT: %s" % ("FAIL" if _smoke_failed else "PASS"))
	get_tree().quit(1 if _smoke_failed else 0)


var _smoke_failed: bool = false


## raw key event — the overworld menu binds to physical keys, not an action
func _smoke_key(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)


## real InputEventAction pair — Input.action_press only sets poll-state and never reaches event handlers
func _smoke_tap(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _smoke_shot(shot_name: String, max_dominant: float = 0.92) -> void:
	var img: Image = null
	var dominant: float = 1.0
	# a solid frame is usually a capture racing a scene fade — ride it out before calling it a void
	for attempt in range(4):
		img = get_viewport().get_texture().get_image()
		if img == null or img.is_empty():
			# headless has no viewport texture — smoke there is for log mining, not pixels
			print("[SMOKE] %s skipped (no viewport texture — headless run)" % shot_name)
			return
		dominant = _dominant_color_ratio(img)
		if dominant < max_dominant:
			break
		await get_tree().create_timer(0.7).timeout
	var err := img.save_png("user://smoke/%s.png" % shot_name)
	# past the cap = a void/black screen wearing a UI — the boot-canary class, but caught pre-deploy
	var ok: bool = err == OK and dominant < max_dominant
	if not ok:
		_smoke_failed = true
	print("[SMOKE] %s saved err=%d size=%s dominant=%.2f %s" % [shot_name, err, str(img.get_size()), dominant, "OK" if ok else "FAIL"])


func _dominant_color_ratio(img: Image) -> float:
	var counts: Dictionary = {}
	var total: int = 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var c: Color = img.get_pixel(x, y)
			var key: int = (int(c.r * 15) << 8) | (int(c.g * 15) << 4) | int(c.b * 15)
			counts[key] = int(counts.get(key, 0)) + 1
			total += 1
	var best: int = 0
	for k in counts:
		best = maxi(best, int(counts[k]))
	return float(best) / float(maxi(1, total))


func _connect_llm_breadcrumb() -> void:
	"""R9: safe-connect to LLMService.inference_failed. Guards the singleton
	(autoload may not exist if the subsystem is stripped) AND the signal (so a
	future LLMService refactor that renames/drops it degrades to a no-op rather
	than a crash). Idempotent — won't double-connect on a re-entrant call."""
	var llm := get_node_or_null("/root/LLMService")
	if not llm:
		return
	if not llm.has_signal("inference_failed"):
		return
	if not llm.inference_failed.is_connected(_on_llm_inference_failed):
		llm.inference_failed.connect(_on_llm_inference_failed)
	# Companion-success breadcrumb — symmetric to inference_failed.
	if llm.has_signal("inference_succeeded") and not llm.inference_succeeded.is_connected(_on_llm_inference_succeeded):
		llm.inference_succeeded.connect(_on_llm_inference_succeeded)


func _on_llm_inference_failed(_mode: String, reason: String) -> void:
	"""R9 (principle #7 — silent failures are worse than crashes): the FIRST
	time dynamic dialogue falls back in a session, surface a brief, unobtrusive,
	in-voice notice so the player knows scripted lines are a fallback, not a bug.
	Latched to one-shot via _llm_notice_shown so repeated failures never spam.
	Toast auto-dismisses (~2s hold + fade); no input is stolen.

	Reason-aware gating: inference_failed is a BROAD telemetry signal emitted on
	EVERY fallback — including per-response guard rejections (one refusal-pattern
	line or one schema-invalid JSON) from a perfectly HEALTHY backend. Those are
	NOT an outage: dynamic dialogue is available, one turn just fell back. Only
	surface the "unavailable" breadcrumb for genuine backend-availability
	failures; quiet otherwise (whitelist, so a future outage reason simply won't
	toast rather than mis-toast as available)."""
	const _AVAILABILITY_REASONS := ["no ready backend", "request failed or cancelled", "client_timeout"]
	if reason not in _AVAILABILITY_REASONS:
		return  # quiet: guard rejection from a working backend, not an outage
	if _llm_notice_shown:
		return
	_llm_notice_shown = true
	if current_state == LoopState.TITLE:
		return  # Nothing dialogue-facing on the title screen — stay quiet there.
	if Toast:
		Toast.show(self, "Dynamic dialogue unavailable — falling back to scripted lines.", Toast.WARNING_COLOR)


func _on_llm_inference_succeeded(_mode: String) -> void:
	"""Companion to _on_llm_inference_failed: one-shot confirmation that the
	LLM is alive in this session. Closes the telemetry loop for desktop+Ollama
	players who otherwise can't tell scripted from dynamic dialogue."""
	if _llm_success_notice_shown:
		return
	if current_state == LoopState.TITLE:
		return
	# defer (not consume) during battle presentation — first inference is often the boss's own dialogue, and the toast landed center-screen mid-duel
	if BattleManager and BattleManager.current_state != BattleManager.BattleState.INACTIVE:
		return
	# boss INTRO dialogue runs before BattleManager arms — gate on the loop state too or the toast slips in pre-battle
	if current_state == LoopState.BATTLE:
		return
	_llm_success_notice_shown = true
	if Toast:
		Toast.show(self, "Dynamic dialogue active.", Toast.SUCCESS_COLOR)


## Helper for the EXPLORATION→BATTLE transition race that ticks 15/16
## first caught. An encounter pushes 'encounter_transition' onto
## InputLockManager and awaits ~0.5s of BattleTransition. During that
## window current_state is still EXPLORATION, but opening any menu
## puts it under the loading battle scene. Returns true ONLY for the
## EXPLORATION + locked combination, so BATTLE-state dialogue locks
## (which legitimately want to allow some hotkeys) aren't affected.
##
## Tick 79 extension: also true during area-transition fade-IN.
## _transition_in_progress is set true at the start of
## _on_area_transition and stays true until the match block clears
## the fade-out. The 'area_transition_fade' InputLockManager lock
## only covers fade-OUT (tick 77 — pushed after _start_exploration's
## pop_all), so fade-IN previously slipped past callers that only
## checked InputLockManager. Now F5/F6/Select autobattle inputs are
## blocked across the entire fade window, not just fade-out.
func _in_exploration_transition() -> bool:
	if current_state != LoopState.EXPLORATION:
		return false
	if _transition_in_progress:
		return true
	return InputLockManager != null and InputLockManager.is_locked()


func _input(event: InputEvent) -> void:
	# F12 screenshot — always available, any state
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_F12:
		_take_screenshot()
		get_viewport().set_input_as_handled()
		return

	# F2 quick-save / F3 quick-load — global hotkeys, any in-game state.
	# Skipped during title screen, character creation, and active battles
	# (SaveSystem.can_quick_save also enforces no-battle, but we early-exit
	# here too so the toast doesn't try to flash mid-cutscene).
	# Added 2026-05-03 per QOL audit.
	if event is InputEventKey and event.pressed and not event.is_echo():
		# F2 quick-save is blocked during CUTSCENE state (Spotlight Duels
		# spec, cowir-main msg 1964): mid-cutscene captures an ambiguous
		# state because the cutscene now embeds a battle step. SaveSystem.
		# can_quick_save() also gates on cutscene state (belt + suspenders
		# so a stray call from anywhere else in the tree hits the same
		# defense).
		if event.keycode == KEY_F2 and current_state != LoopState.TITLE and current_state != LoopState.CUTSCENE and not _character_creation_screen:
			_quick_save_with_toast()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F3 and current_state != LoopState.TITLE and current_state != LoopState.CUTSCENE and not _character_creation_screen:
			_quick_load_with_toast()
			get_viewport().set_input_as_handled()
			return

	# Block input handling during title screen or character creation
	if current_state == LoopState.TITLE or _character_creation_screen:
		return

	# During autogrind, block editor/menu but allow B to stop
	if current_state == LoopState.AUTOGRIND:
		if _autogrind_ui and is_instance_valid(_autogrind_ui):
			return  # UI handles its own input
		if event.is_action_pressed("ui_cancel"):
			_stop_autogrind("Manual stop")
			get_viewport().set_input_as_handled()
			return
		# Y button toggles turbo mode
		if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y:
			if current_scene and current_scene.has_method("set") and "turbo_mode" in current_scene:
				current_scene.turbo_mode = not current_scene.turbo_mode
				BattleManager.turbo_mode = current_scene.turbo_mode
				print("[AUTOGRIND] Turbo mode: %s" % ("ON" if current_scene.turbo_mode else "OFF"))
			get_viewport().set_input_as_handled()
			return
		# Y key (keyboard) toggles turbo mode
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Y:
			if current_scene and "turbo_mode" in current_scene:
				current_scene.turbo_mode = not current_scene.turbo_mode
				BattleManager.turbo_mode = current_scene.turbo_mode
				print("[AUTOGRIND] Turbo mode: %s" % ("ON" if current_scene.turbo_mode else "OFF"))
			get_viewport().set_input_as_handled()
			return
		# T key (keyboard) cycles tier
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
			if _autogrind_controller and is_instance_valid(_autogrind_controller):
				_autogrind_controller.cycle_tier()
			get_viewport().set_input_as_handled()
			return
		# P key toggles pause/resume
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
			_toggle_autogrind_pause()
			get_viewport().set_input_as_handled()
			return
		# L+R shoulder together cycles tier
		if event is InputEventJoypadButton and event.pressed:
			if event.button_index == JOY_BUTTON_LEFT_SHOULDER or event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
				if Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER) and Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER):
					if _autogrind_controller and is_instance_valid(_autogrind_controller):
						_autogrind_controller.cycle_tier()
					get_viewport().set_input_as_handled()
					return
		return

	# F5 = Open autobattle editor for current/first player
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		if _in_exploration_transition():
			get_viewport().set_input_as_handled()
			return
		_toggle_autobattle_editor()
		get_viewport().set_input_as_handled()

	# F6 or Select button = Toggle autobattle for ALL players
	if event is InputEventKey and event.pressed and event.keycode == KEY_F6:
		if _in_exploration_transition():
			get_viewport().set_input_as_handled()
			return
		_toggle_all_autobattle()
		get_viewport().set_input_as_handled()

	# Gamepad Select button (button 4 on most controllers)
	# IMPORTANT: skip in BATTLE state — BattleScene._input has its own
	# battle_toggle_auto handler that fires on the same Minus press, and
	# BOTH firing means GameLoop toggles ON→OFF then BattleScene sees OFF
	# and toggles back to ON. Net effect: nothing. (Audit-fix 2026-05-04
	# for the persistent "I press Minus, autobattle stays on" bug.)
	# Block when autogrind UI is open — don't toggle autobattle behind it.
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		if _autogrind_ui and is_instance_valid(_autogrind_ui):
			get_viewport().set_input_as_handled()
		elif current_state == LoopState.BATTLE:
			# Pass through — BattleScene._input handles it
			pass
		elif _in_exploration_transition():
			get_viewport().set_input_as_handled()
		else:
			_toggle_all_autobattle()
			get_viewport().set_input_as_handled()

	# Start button = context-dependent:
	# - Autogrind UI open: consumed here so AutogrindUI handles it (toggle grinding)
	# - In battle: SMART — if autobattle is currently ON for any character,
	#   disable it (matches user expectation that pressing the obvious button
	#   stops the auto-fighting). If autobattle is OFF, open the editor (the
	#   pre-2026-05-03 behavior, preserved so existing tutorial hints and
	#   NPC dialogue references stay accurate).
	#   User feedback: "I pressed start/select etc. and I didn't auto battle
	#   disable" — pressing Plus expecting toggle, but it opened the editor
	#   instead with no obvious way to disable from there.
	# - In exploration/village/cave: open settings menu
	if event.is_action_pressed("ui_menu"):
		if _autogrind_ui and is_instance_valid(_autogrind_ui):
			# Let AutogrindUI._input handle Start → toggle grinding
			# Do NOT consume input here — AutogrindUI needs to see it
			pass
		elif current_state == LoopState.BATTLE:
			if not _autobattle_editor or not is_instance_valid(_autobattle_editor):
				# Decide: toggle off if any party has autobattle on, else open editor
				var any_auto_on := false
				for member in party:
					var char_id: String = member.combatant_name.to_lower().replace(" ", "_")
					if AutobattleSystem.is_autobattle_enabled(char_id):
						any_auto_on = true
						break
				if any_auto_on:
					_toggle_all_autobattle()  # disables (since any was on)
				else:
					_toggle_autobattle_editor()
				get_viewport().set_input_as_handled()
		elif current_state == LoopState.EXPLORATION:
			# Escape belongs to the overworld menu (x_pressed block below).
			# ui_menu ALSO binds it, so one press opened Settings stacked
			# OVER the overworld menu (web-smoke stage-3 find 2026-07-11).
			if event is InputEventKey and event.keycode == KEY_ESCAPE:
				pass
			else:
				# Block during battle transition (encounter fired but state
				# hasn't flipped to BATTLE yet — that flip happens after the
				# transition await in _on_exploration_battle_triggered, so
				# raw state-check leaves a ~0.5s window where Start would
				# open settings UNDER the loading battle scene).
				if InputLockManager and InputLockManager.is_locked():
					get_viewport().set_input_as_handled()
					return
				_open_settings_menu()
				get_viewport().set_input_as_handled()

	# X key or gamepad X/Y button = Open overworld menu (only in exploration mode)
	# Note: JOY_BUTTON_X=2 (Xbox X), JOY_BUTTON_Y=3 (Xbox Y) - support both for different controllers
	var x_pressed = false
	if event is InputEventKey and event.pressed and event.keycode == KEY_X:
		x_pressed = true
	elif event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_X, JOY_BUTTON_Y]:
		x_pressed = true
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		x_pressed = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		x_pressed = true

	if x_pressed:
		if current_state == LoopState.EXPLORATION and not _overworld_menu:
			# Same race as the Start→settings guard above: an
			# encounter-transition holds the lock but current_state is
			# still EXPLORATION until _start_battle_async flips it.
			# Opening the overworld menu in that window puts it under
			# the loading battle scene.
			if InputLockManager and InputLockManager.is_locked():
				get_viewport().set_input_as_handled()
				return
			# Tick 78: also block menu open during area-transition fade-IN.
			# _transition_in_progress is true from the moment a transition
			# starts until the fade-out finishes. Without this gate, the
			# player can press Esc mid-fade-in — pausing the OLD scene
			# that's about to be freed by _start_exploration, while the
			# NEW scene runs unpaused behind the menu overlay.
			if _transition_in_progress:
				get_viewport().set_input_as_handled()
				return
			_open_overworld_menu()
			get_viewport().set_input_as_handled()

	# L shoulder / L key = open Party Chat menu (exploration only, opt-in flavor cutscenes)
	if event.is_action_pressed("party_chat"):
		if current_state == LoopState.EXPLORATION and not _party_chat_menu and not _overworld_menu:
			if InputLockManager and InputLockManager.is_locked():
				get_viewport().set_input_as_handled()
				return
			if _transition_in_progress:
				get_viewport().set_input_as_handled()
				return
			if PartyChatSystem and PartyChatSystem.has_available_chats():
				_open_party_chat_menu()
				get_viewport().set_input_as_handled()


func _toggle_autobattle_editor() -> void:
	"""Toggle the autobattle grid editor overlay"""
	if _autobattle_editor and is_instance_valid(_autobattle_editor):
		# Save before closing!
		if _autobattle_editor.has_method("save_and_close"):
			_autobattle_editor.save_and_close()
		else:
			_autobattle_editor.queue_free()
		_autobattle_editor = null
		if _autobattle_layer:
			_autobattle_layer.queue_free()
			_autobattle_layer = null
		# Show battle menu again if it was hidden
		_set_battle_menu_visible(true)
		# Resume exploration if we were in exploration mode
		if current_state == LoopState.EXPLORATION and _exploration_scene and _exploration_scene.has_method("resume"):
			_exploration_scene.resume()
		SoundManager.play_ui("autobattle_close")
		print("Autobattle editor closed (saved)")
		return

	# Pause exploration while editor is open (no encounters)
	if current_state == LoopState.EXPLORATION and _exploration_scene and _exploration_scene.has_method("pause"):
		_exploration_scene.pause()

	# Hide the battle menu while editor is open
	_set_battle_menu_visible(false)

	# During battle, open for currently selecting player
	var combatant: Combatant = null
	var char_id = "hero"
	var char_name = "Hero"

	if BattleManager and BattleManager.is_selecting() and BattleManager.current_combatant:
		var current = BattleManager.current_combatant
		if current in BattleManager.player_party:
			combatant = current
			char_id = current.combatant_name.to_lower().replace(" ", "_")
			char_name = current.combatant_name
	elif party.size() > 0:
		combatant = party[0]
		char_id = party[0].combatant_name.to_lower().replace(" ", "_")
		char_name = party[0].combatant_name

	# Create CanvasLayer to isolate from camera zoom
	_autobattle_layer = CanvasLayer.new()
	_autobattle_layer.layer = 50  # Above game, below BattleTransition
	add_child(_autobattle_layer)

	var AutobattleGridEditorClass = load("res://src/ui/autobattle/AutobattleGridEditor.gd")
	_autobattle_editor = AutobattleGridEditorClass.new()
	_autobattle_editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_autobattle_layer.add_child(_autobattle_editor)
	_autobattle_editor.setup(char_id, char_name, combatant, party)  # Pass party for R to cycle
	_autobattle_editor.closed.connect(_on_autobattle_editor_closed)
	SoundManager.play_ui("autobattle_open")
	# Fire the catalog's authored autobattle intro hint on first open per save.
	if not _autobattle_editor_ever_opened:
		_autobattle_editor_ever_opened = true
		TutorialHints.show(self, "autobattle_intro")
	print("Autobattle editor opened for %s (R to switch character, Start to save & exit)" % char_name)


func _set_battle_menu_visible(visible: bool) -> void:
	"""Show or hide the battle menu in the current scene"""
	# Try the proper method first
	if current_scene and current_scene.has_method("set_command_menu_visible"):
		current_scene.set_command_menu_visible(visible)
	# Fallback to direct property access
	elif current_scene and current_scene.has_method("get"):
		var menu = current_scene.get("active_win98_menu")
		if menu and is_instance_valid(menu):
			menu.visible = visible


func _toggle_all_autobattle() -> void:
	"""Toggle the GLOBAL/STICKY autobattle state for all party members.
	Persists across turns AND across battles AND in the overworld.
	(Per user feedback 2026-05-03: 'Minus button = enable for all players,
	continues for future turns including future battles. Pressing - in
	the overworld should also disable autobattle.')

	Distinct from the per-character menu 'Auto' pick which is one-shot."""
	if party.size() == 0:
		return

	# Check if any are enabled - if so, disable all; otherwise enable all
	var any_enabled = false
	for member in party:
		var char_id = member.combatant_name.to_lower().replace(" ", "_")
		if AutobattleSystem.is_autobattle_enabled(char_id):
			any_enabled = true
			break

	# Toggle all to opposite state
	var new_state = not any_enabled
	for member in party:
		var char_id = member.combatant_name.to_lower().replace(" ", "_")
		AutobattleSystem.set_autobattle_enabled(char_id, new_state)

	# Also clear the queue side-effects so the toggle is INSTANT.
	# Without this, when toggling OFF mid-execution the already-queued
	# autobattle actions kept playing through the current round before
	# the user could regain manual control.
	if not new_state:
		AutobattleSystem.cancel_all_next_turn = false
		# Strip player actions from the queue. Keep enemy actions —
		# clearing them would stall the round.
		if BattleManager and BattleManager.has_method("clear_pending_player_actions"):
			BattleManager.clear_pending_player_actions()
	else:
		# Enabling: if a player is currently in PLAYER_SELECTING, kick off
		# their autobattle decision immediately so they don't sit waiting
		# for manual input. Mirrors the BattleScene._enable_all_autobattle
		# behavior so the AUTO button click feels identical to pressing
		# Minus on the gamepad. (Audit 2026-05-04 consistency fix.)
		if BattleManager and BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING:
			if BattleManager.has_method("execute_autobattle_for_current"):
				BattleManager.execute_autobattle_for_current()

	var status = "ON" if new_state else "OFF"
	if new_state:
		SoundManager.play_ui("autobattle_on")
	else:
		SoundManager.play_ui("autobattle_off")
	print("[AUTOBATTLE] All party members: %s (F6/Select to toggle)" % status)
	# Visual feedback Toast — works in overworld AND battle (battle scene
	# also has its own log_message but the Toast is more discoverable).
	# Only show in non-battle states; in battle the existing log_message
	# from _enable_all_autobattle / _cancel_all_autobattle is enough.
	if current_state != LoopState.BATTLE:
		var msg = "Autobattle: %s" % status
		if Toast:
			if new_state:
				Toast.show_success(self, msg)
			else:
				Toast.show_warning(self, msg)
	# Live-refresh the OverworldMenu label if it's open. Without this, the
	# user could open the menu, hit Minus to toggle, and the menu label
	# would stay stale until reopened. Audit-fix 2026-05-04.
	if _overworld_menu and is_instance_valid(_overworld_menu) \
			and _overworld_menu.has_method("refresh_autobattle_label"):
		_overworld_menu.refresh_autobattle_label()


func _on_autobattle_editor_closed() -> void:
	"""Handle editor close"""
	if _autobattle_editor and is_instance_valid(_autobattle_editor):
		_autobattle_editor.queue_free()
		_autobattle_editor = null
	if _autobattle_layer and is_instance_valid(_autobattle_layer):
		_autobattle_layer.queue_free()
		_autobattle_layer = null
	# Show battle menu again
	_set_battle_menu_visible(true)
	# Resume exploration if we were in exploration mode
	if current_state == LoopState.EXPLORATION and _exploration_scene and _exploration_scene.has_method("resume"):
		_exploration_scene.resume()


func _sync_party_to_game_state() -> void:
	"""Sync runtime Combatant party into GameState.player_party for menus + saving.

	Bug fix (2026-04-30): previously this synthesized a 5-field dict
	(name + job_id + equipment IDs only). When SaveSystem serialized
	GameState.player_party, all level/HP/MP/EXP/abilities were lost.
	On load, _create_party() then constructed fresh defaults from scratch,
	silently resetting every saved character to level 1 / starter gear.

	Now uses Combatant.to_dict() (which was also expanded today) so the
	full character state survives save → load cycles. Companion change:
	GameLoop.gd added _restore_party_from_save_data() which reconstructs
	live Combatants from this dict array and is wired into the load paths.
	"""
	GameState.player_party.clear()
	for member in party:
		if not is_instance_valid(member) or not (member is Combatant):
			continue
		GameState.player_party.append(member.to_dict())
	# Clamp leader index in case party size changed
	if not GameState.player_party.is_empty():
		GameState.party_leader_index = clampi(GameState.party_leader_index, 0, GameState.player_party.size() - 1)


func _open_overworld_menu() -> void:
	"""Open the overworld/pause menu"""
	if _overworld_menu and is_instance_valid(_overworld_menu):
		return  # Already open

	# Sync party data into GameState so leader cycling has job info
	_sync_party_to_game_state()

	# Pause exploration
	if _exploration_scene and _exploration_scene.has_method("pause"):
		_exploration_scene.pause()
	_set_field_hud_hidden(true)

	# Create menu in CanvasLayer
	_overworld_menu_layer = CanvasLayer.new()
	_overworld_menu_layer.layer = 50
	add_child(_overworld_menu_layer)

	var OverworldMenuClass = load("res://src/ui/OverworldMenu.gd")
	_overworld_menu = OverworldMenuClass.new()
	_overworld_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overworld_menu_layer.add_child(_overworld_menu)
	_overworld_menu.setup(party)
	_overworld_menu.closed.connect(_on_overworld_menu_closed)
	_overworld_menu.menu_action.connect(_on_overworld_menu_action)
	_overworld_menu.quit_to_title.connect(_on_quit_to_title)
	if _overworld_menu.has_signal("start_boss_battle"):
		_overworld_menu.start_boss_battle.connect(_on_settings_boss_battle)
	if _overworld_menu.has_signal("teleport_requested"):
		_overworld_menu.teleport_requested.connect(_on_teleport_requested)
	if _overworld_menu.has_signal("party_leader_changed"):
		_overworld_menu.party_leader_changed.connect(_on_party_leader_changed)
	SoundManager.play_ui("menu_open")
	print("Overworld menu opened")


func _on_overworld_menu_closed() -> void:
	"""Handle overworld menu close"""
	if _overworld_menu and is_instance_valid(_overworld_menu):
		_overworld_menu.queue_free()
		_overworld_menu = null
	if _overworld_menu_layer and is_instance_valid(_overworld_menu_layer):
		_overworld_menu_layer.queue_free()
		_overworld_menu_layer = null

	# Resume exploration
	if _exploration_scene and _exploration_scene.has_method("resume"):
		_exploration_scene.resume()
	_set_field_hud_hidden(false)
	_flush_chat_toasts()


## Field-HUD props on exploration scenes; each is either a CanvasItem or a Node wrapping a _canvas CanvasLayer (minimap/tracker/arrows all sit on layers ABOVE the menu's 50).
const _FIELD_HUD_PROPS := ["_minimap", "_quest_tracker", "_objective_arrow", "_border_indicator", "_threat_meter", "_danger_zone"]


func _set_field_hud_hidden(hidden: bool) -> void:
	# JRPG convention: field HUD must not paint over the pause menu — the quest tracker covered the PARTY header and the objective arrow crossed the Mage row (web-smoke stage-3 find 2026-07-11).
	if not hidden:
		for n in _menu_hidden_hud:
			if n and is_instance_valid(n):
				n.visible = true
		_menu_hidden_hud.clear()
		return
	_menu_hidden_hud.clear()
	if _exploration_scene == null or not is_instance_valid(_exploration_scene):
		return
	for prop in _FIELD_HUD_PROPS:
		if not (prop in _exploration_scene):
			continue
		var w = _exploration_scene.get(prop)
		if w == null or (w is Object and not is_instance_valid(w)):
			continue
		var target = null
		if w is CanvasItem or w is CanvasLayer:
			target = w
		elif w is Node and "_canvas" in w and w._canvas is CanvasLayer:
			target = w._canvas
		if target and is_instance_valid(target) and target.visible:
			target.visible = false
			_menu_hidden_hud.append(target)


## Party Chat helpers

func _ensure_party_chat_indicator() -> void:
	"""Show the [L] Party Chat indicator in exploration if any chats are available."""
	if current_state != LoopState.EXPLORATION:
		_remove_party_chat_indicator()
		return
	if not PartyChatSystem:
		return
	# Only mount when needed; the indicator hides itself when empty
	if _party_chat_indicator and is_instance_valid(_party_chat_indicator):
		return
	_party_chat_indicator_layer = CanvasLayer.new()
	_party_chat_indicator_layer.layer = 45
	add_child(_party_chat_indicator_layer)
	var IndicatorScript = load("res://src/ui/PartyChatIndicator.gd")
	_party_chat_indicator = IndicatorScript.new()
	_party_chat_indicator_layer.add_child(_party_chat_indicator)
	## Tick 470: mouse-click on the indicator opens the chat menu,
	## mirroring the party_chat action (L key / gamepad button). Gated
	## the same way as the input path so a click with no available
	## chats is a no-op instead of an empty menu.
	if _party_chat_indicator.has_signal("clicked"):
		_party_chat_indicator.clicked.connect(func():
			if current_state == LoopState.EXPLORATION and not _party_chat_menu and not _overworld_menu \
					and PartyChatSystem and PartyChatSystem.has_available_chats():
				_open_party_chat_menu())


func _remove_party_chat_indicator() -> void:
	if _party_chat_indicator and is_instance_valid(_party_chat_indicator):
		_party_chat_indicator.queue_free()
	_party_chat_indicator = null
	if _party_chat_indicator_layer and is_instance_valid(_party_chat_indicator_layer):
		_party_chat_indicator_layer.queue_free()
	_party_chat_indicator_layer = null


func _open_party_chat_menu() -> void:
	if _party_chat_menu and is_instance_valid(_party_chat_menu):
		return
	if _exploration_scene and _exploration_scene.has_method("pause"):
		_exploration_scene.pause()
	_party_chat_menu_layer = CanvasLayer.new()
	_party_chat_menu_layer.layer = 60
	add_child(_party_chat_menu_layer)
	var MenuScript = load("res://src/ui/PartyChatMenu.gd")
	_party_chat_menu = MenuScript.new()
	_party_chat_menu_layer.add_child(_party_chat_menu)
	_party_chat_menu.closed.connect(_on_party_chat_closed)
	SoundManager.play_ui("menu_open")


func _on_party_chat_closed(_played_id: String) -> void:
	if _party_chat_menu and is_instance_valid(_party_chat_menu):
		_party_chat_menu.queue_free()
	_party_chat_menu = null
	if _party_chat_menu_layer and is_instance_valid(_party_chat_menu_layer):
		_party_chat_menu_layer.queue_free()
	_party_chat_menu_layer = null
	if _exploration_scene and _exploration_scene.has_method("resume"):
		_exploration_scene.resume()


func _on_party_leader_changed(new_index: int) -> void:
	"""Update the overworld player sprite when the party leader changes"""
	if party.is_empty() or new_index >= party.size():
		return
	var leader = party[new_index]
	print("[LEADER] Party leader changed to index %d: %s" % [new_index, leader.combatant_name])
	if _exploration_scene:
		if _exploration_scene.has_method("set_player_appearance"):
			_exploration_scene.set_player_appearance(leader)
		elif _exploration_scene.has_method("set_player_job"):
			var job_id = "fighter"
			if leader.job and leader.job is Dictionary:
				job_id = leader.job.get("id", "fighter")
			_exploration_scene.set_player_job(job_id)


func _on_quit_to_title() -> void:
	"""Handle quit to title from overworld menu settings"""
	print("[GAME] Returning to title screen")

	# Clean up overworld menu
	if _overworld_menu and is_instance_valid(_overworld_menu):
		_overworld_menu.queue_free()
		_overworld_menu = null
	if _overworld_menu_layer and is_instance_valid(_overworld_menu_layer):
		_overworld_menu_layer.queue_free()
		_overworld_menu_layer = null

	# Clean up exploration scene
	if _exploration_scene and is_instance_valid(_exploration_scene):
		_exploration_scene.queue_free()
		_exploration_scene = null

	# Clear party
	party.clear()

	# Show title screen
	_show_title_screen()


func _on_settings_boss_battle(boss_id: String) -> void:
	"""Handle boss battle request from settings debug menu"""
	print("[GAME] Debug fight boss: %s" % boss_id)
	if _overworld_menu and is_instance_valid(_overworld_menu):
		_overworld_menu.queue_free()
		_overworld_menu = null
	if _overworld_menu_layer and is_instance_valid(_overworld_menu_layer):
		_overworld_menu_layer.queue_free()
		_overworld_menu_layer = null
	current_state = LoopState.EXPLORATION
	_start_battle_async([boss_id], false)


func _on_overworld_menu_action(action: String, target: Combatant) -> void:
	"""Handle menu action from overworld menu"""
	match action:
		"autobattle":
			# Close menu first, then open autobattle editor
			_on_overworld_menu_closed()
			if target:
				var char_id = target.combatant_name.to_lower().replace(" ", "_")
				_open_autobattle_for_character(char_id, target.combatant_name, target)
		"autobattle_toggle":
			# Sticky global toggle from overworld menu (mouse path,
			# matches Minus button behavior). Toast feedback comes from
			# _toggle_all_autobattle itself when not in BATTLE state.
			_toggle_all_autobattle()
		"autogrind":
			# Close menu first, then open autogrind config UI
			_on_overworld_menu_closed()
			_open_autogrind_ui()


func _open_autobattle_for_character(char_id: String, char_name: String, combatant: Combatant) -> void:
	"""Open autobattle editor for a specific character"""
	if _autobattle_editor and is_instance_valid(_autobattle_editor):
		return  # Already open

	# Pause exploration
	if _exploration_scene and _exploration_scene.has_method("pause"):
		_exploration_scene.pause()

	_autobattle_layer = CanvasLayer.new()
	_autobattle_layer.layer = 50
	add_child(_autobattle_layer)

	var AutobattleGridEditorClass = load("res://src/ui/autobattle/AutobattleGridEditor.gd")
	_autobattle_editor = AutobattleGridEditorClass.new()
	_autobattle_editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_autobattle_layer.add_child(_autobattle_editor)
	_autobattle_editor.setup(char_id, char_name, combatant, party)
	_autobattle_editor.closed.connect(_on_autobattle_editor_closed)
	SoundManager.play_ui("autobattle_open")
	print("Autobattle editor opened for %s" % char_name)


## Character Creation

func _save_exists() -> bool:
	"""Check if a save file exists (new or legacy format)"""
	# Check for new customization save
	if FileAccess.file_exists("user://save_data.json"):
		return true
	# Check for legacy save format
	if FileAccess.file_exists("user://saves/save_00.json"):
		return true
	return false


## Title Screen

func _show_title_screen() -> void:
	"""Show the title screen"""
	current_state = LoopState.TITLE

	# Create title screen in its own layer
	_title_layer = CanvasLayer.new()
	_title_layer.layer = 100
	add_child(_title_layer)

	_title_screen = TitleScreenClass.new()
	_title_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_layer.add_child(_title_screen)

	# Connect signals
	_title_screen.new_game_selected.connect(_on_title_new_game)
	_title_screen.continue_selected.connect(_on_title_continue)
	_title_screen.settings_selected.connect(_on_title_settings)

	print("[GAME] Showing title screen")


func _close_title_screen() -> void:
	"""Close the title screen"""
	if _title_screen and is_instance_valid(_title_screen):
		_title_screen.queue_free()
		_title_screen = null
	if _title_layer and is_instance_valid(_title_layer):
		_title_layer.queue_free()
		_title_layer = null


## Cutscene system
var _cutscene_director: Node = null

func _on_title_new_game() -> void:
	"""Handle new game selected from title screen"""
	print("[GAME] New Game selected")
	_close_title_screen()
	# Wait for title screen to actually be removed before starting
	await get_tree().process_frame
	await get_tree().process_frame
	# Clear autobattle state for new game — default to manual combat
	AutobattleSystem.autobattle_enabled.clear()
	AutobattleSystem.cancel_all_next_turn = false
	BattleManager.is_autobattle_enabled = false
	# Per-RUN gameplay settings reset (struktured 2026-07-11: "started a new
	# game, battle speed was 16x, encounter rate 50%... prob not the right
	# choice"). System settings (volumes, text, accessibility) persist;
	# run-pacing choices start fresh.
	if GameState:
		GameState.default_battle_speed = 0.25
		GameState.encounter_rate_multiplier = 1.0
	var BattleSceneScript = load("res://src/battle/BattleScene.gd")
	BattleSceneScript._battle_speed_index = 0
	if SaveSystem and SaveSystem.has_method("save_settings"):
		SaveSystem.save_settings()
	# Wipe persistent GameState so a fresh playthrough doesn't inherit
	# story flags / unlocked worlds / meta features from the prior session.
	# Bug fix (2026-04-30): pre-fix, New Game on a save where you'd beaten
	# the game would still show all 6 worlds unlocked and skip the prologue
	# (since cutscene_flag_prologue_complete persisted in story_flags).
	if GameState and GameState.has_method("reset_game_state"):
		GameState.reset_game_state()
	# Skip character creation — use default party (fighter/cleric/rogue/mage)
	_create_party()
	# Go straight to exploration — prologue triggers on first Theron interaction
	_set_current_map_id("overworld")
	_start_exploration()


## Lazy accessor — CutsceneDirector is GameLoop-owned, NOT an autoload (QuestSystem's cutscene_on_complete flush + both internal lazy-create sites route here).
func get_cutscene_director() -> CutsceneDirector:
	if not _cutscene_director:
		_cutscene_director = CutsceneDirector.new()
		add_child(_cutscene_director)
	return _cutscene_director


func _play_new_game_cutscenes() -> void:
	"""Play prologue cutscene on new game, then start exploration."""
	current_state = LoopState.CUTSCENE
	if not _cutscene_director:
		_cutscene_director = CutsceneDirector.new()
		add_child(_cutscene_director)
	_cutscene_director.cutscene_finished.connect(_on_prologue_finished, CONNECT_ONE_SHOT)
	_cutscene_director.play_cutscene("world1_prologue")


func _on_prologue_finished(_cutscene_id: String) -> void:
	"""After prologue, chain into chapter1 (Elder Theron briefing)."""
	_cutscene_director.cutscene_finished.connect(_on_chapter1_finished, CONNECT_ONE_SHOT)
	_cutscene_director.play_cutscene("world1_chapter1")


func _on_chapter1_finished(_cutscene_id: String) -> void:
	"""After chapter1 briefing, start exploration."""
	current_state = LoopState.EXPLORATION
	_start_exploration()


func check_pending_cutscene() -> void:
	# One at a time: pending checks fired while a scene was ALREADY playing double-played it (the completion flag only lands at the end).
	if _cutscene_director and is_instance_valid(_cutscene_director) and "_active" in _cutscene_director and _cutscene_director._active:
		return
	"""Public: called by NPCs after setting story flags to trigger pending cutscenes."""
	var pending = _get_pending_story_cutscene()
	if pending != "":
		## Tick 401: Skiptrotter skip_cutscene meta_effect sets the
		## meta_skip_next_cutscene flag. Consume it here by writing the
		## cutscene's completion flag (so it doesn't replay) and
		## skipping the actual playback. The single-shot flag clears
		## itself so subsequent cutscenes play normally.
		if GameState and "game_constants" in GameState:
			if bool(GameState.game_constants.get("meta_skip_next_cutscene", false)):
				GameState.game_constants["meta_skip_next_cutscene"] = false
				var completion_flag: String = _CUTSCENE_COMPLETION_FLAGS.get(pending, "")
				if completion_flag != "":
					_set_cutscene_flag_and_mirror(completion_flag)
					print("[CUTSCENE] %s skipped via Skiptrotter meta-ability — flag %s set" % [pending, completion_flag])
				return
		_play_story_cutscene(pending)


func _get_pending_story_cutscene() -> String:
	"""Check if a story cutscene should play based on flags.
	Returns cutscene ID or empty string."""
	var flags = GameState.game_constants
	# Prologue: first time entering Harmonia Village (triggered by Theron interaction)
	if not flags.get("cutscene_flag_prologue_complete", false):
		if _current_map_id == "harmonia_village":
			return "world1_prologue"
	# Chapter 1: triggers when player talks to Elder Theron (flag set by NPC interaction)
	if flags.get("talked_to_theron", false) and not flags.get("cutscene_flag_chapter1_complete", false):
		if _current_map_id == "harmonia_village":
			return "world1_chapter1"
	# Bram's shield gift (struktured 2026-07-11): first smith talk, gated
	# after chapter1 so the opening beat always wins the race.
	if flags.get("talked_to_bram_smith", false) and flags.get("cutscene_flag_chapter1_complete", false) \
			and not flags.get("cutscene_flag_world1_bram_shield_complete", false):
		if _current_map_id == "harmonia_village":
			return "world1_bram_shield"
	# Chapter 2: SKIPPED — party road commentary now opt-in
	# Auto-set the flag so chapter 3 can trigger
	# Tick 97: cleric spotlight unlock — fires in Harmonia village after
	# chapter1 cutscene (Mira/Cleric joins the player's controllable
	# roster at the village well). Pre-fix, spotlight cutscenes were
	# referenced by _CUTSCENE_COMPLETION_FLAGS + _reconcile_spotlight_locks
	# but NEVER triggered by any code path — so non-Fighter PCs were
	# permanently locked into autobattle. Gating on chapter1_complete +
	# being in harmonia_village makes the cleric unlock at the natural
	# story moment, matching the design comment at line ~1607.
	# 2026-07-12: previously guarded on `not _chaining_story_cutscene` which blocked chapter1→cleric chain, leaving the player wondering "wait, what now?" after Theron's briefing. Drop the guard so the spotlight fires as chapter1's payoff.
	if flags.get("cutscene_flag_chapter1_complete", false) and not flags.get("cutscene_flag_spotlight_unlocked_cleric", false):
		if _current_map_id == "harmonia_village":
			return "world1_spotlight_cleric_ch1"
	if flags.get("cutscene_flag_chapter1_complete", false) and not flags.get("cutscene_flag_chapter2_complete", false):
		# Tick 220: auto-advance via helper so QuestLog's chapter2 objective also flips.
		_set_cutscene_flag_and_mirror("cutscene_flag_chapter2_complete")
	# Chapter 3: plays when first entering the cave (key story beat)
	if flags.get("cutscene_flag_chapter2_complete", false) and not flags.get("cutscene_flag_chapter3_complete", false):
		if _current_map_id == "whispering_cave":
			return "world1_chapter3"
	# Tick 98: rogue + mage spotlight unlocks — fire IN the Whispering
	# Cave after chapter3 (the party discovers Rogue and Mage need
	# manual control to navigate the dungeon). Rogue first (chapter3
	# discovery beat), Mage next visit (gated on rogue already
	# unlocked so they sequence cleanly across map re-entries instead
	# of stacking on a single trigger). _cutscene_cooldown prevents
	# back-to-back firing on the same entry.
	if flags.get("cutscene_flag_chapter3_complete", false) and not flags.get("cutscene_flag_spotlight_unlocked_rogue", false):
		if _current_map_id == "whispering_cave":
			return "world1_spotlight_rogue_ch3"
	if flags.get("cutscene_flag_spotlight_unlocked_rogue", false) and not flags.get("cutscene_flag_spotlight_unlocked_mage", false) and not _chaining_story_cutscene:
		if _current_map_id == "whispering_cave":
			return "world1_spotlight_mage_ch3"
	# Fighter spotlight — the antechamber skeleton duel (Spotlight Duels
	# spec msg 1950: skeleton duel is Fighter's; chapter3's prose beat was
	# stripped to a breadcrumb pointing here). Sequenced after mage so the
	# three cave duels space across separate cave entries per cowir-story's
	# pacing directive (rogue → mage → fighter). Fighter is never
	# autobattle_locked (he's the lead), so the _unlocked_ flag here is
	# purely the duel-completion gate, not a control unlock. Pre-fix this
	# cutscene was authored + mapped but NO gate fired it — the exact
	# authored-but-never-wired class the tick-97/98/99 comments describe.
	if flags.get("cutscene_flag_spotlight_unlocked_mage", false) and not flags.get("cutscene_flag_spotlight_unlocked_fighter", false) and not _chaining_story_cutscene:
		if _current_map_id == "whispering_cave":
			return "world1_spotlight_fighter_ch2"
	# Rat king defeat cutscene: plays IN the cave right after victory, before chapter4.
	if flags.get("cutscene_flag_rat_king_defeated", false) and not flags.get("cutscene_flag_world1_rat_king_defeat_complete", false):
		if _current_map_id == "whispering_cave":
			return "world1_rat_king_defeat"
	# Chapter 4: plays after rat king boss defeat (key story beat)
	if flags.get("cutscene_flag_rat_king_defeated", false) and not flags.get("cutscene_flag_chapter4_complete", false):
		if _current_map_id == "overworld":
			return "world1_chapter4"
	# Tick 99: bard spotlight unlock — completes the spotlight series.
	# Original design point was "capital gate" (Scriptura) but
	# village_capital is registered in locations.json without an
	# actual scene route, so the capital isn't reachable in W1. Bard
	# instead unlocks on return to harmonia_village after the rat
	# king is defeated (matching the cleric spotlight cadence at the
	# same village). chapter4_complete is the natural trigger — it's
	# set by world1_chapter4 (post-rat-king cutscene in overworld),
	# so the player heading back to town for re-supply gets Bard's
	# join cutscene next.
	if flags.get("cutscene_flag_chapter4_complete", false) and not flags.get("cutscene_flag_spotlight_unlocked_bard", false) and not _chaining_story_cutscene:
		if _current_map_id == "harmonia_village":
			return "world1_spotlight_bard_ch7"
	# Chapters 5-9: auto-set flags — party commentary now opt-in via NPCs
	# These cutscenes are still available but won't auto-trigger on map entry
	if flags.get("cutscene_flag_chapter4_complete", false) and not flags.get("cutscene_flag_chapter9_complete", false):
		for skip_flag in ["chapter5_complete", "chapter5_forest_entered", "chapter7_complete", "chapter8_complete", "chapter9_complete"]:
			if not flags.get("cutscene_flag_" + skip_flag, false):
				# Tick 220: route auto-skipped chapter flags through the helper so QuestLog stays consistent.
				_set_cutscene_flag_and_mirror("cutscene_flag_" + skip_flag)

	# Tick 104: W1 Mordaine post-defeat dialogue — plays IN Castle
	# Harmonia on return from final-boss victory. Mirrors the W2-W5
	# defeat-cutscene gates added in ticks 102-103. Pre-fix, the
	# world1_mordaine_defeat cutscene was never played (DragonCave._on_boss_defeated
	# code path is dead). The post-Mordaine moment — the W1 narrative
	# closer — was silently skipped, sending the player straight to
	# W2 prologue with no Mordaine resolution.
	if flags.get("cutscene_flag_world1_mordaine_defeated", false) and not flags.get("cutscene_flag_world1_mordaine_defeat_complete", false):
		if _current_map_id == "castle_harmonia":
			return "world1_mordaine_defeat"

	# ===== WORLD 2: THE MUNDANE SPRAWL (Suburban) =====
	# W2 Prologue: portal arrival, gear transformation
	if flags.get("cutscene_flag_world1_mordaine_defeated", false) and not flags.get("cutscene_flag_world2_prologue_complete", false):
		if _current_map_id == "suburban_overworld":
			return "world2_prologue"
	# W2 Chapter 1: first look at suburb, HOA foreshadow
	if flags.get("cutscene_flag_world2_prologue_complete", false) and not flags.get("cutscene_flag_world2_chapter1_complete", false):
		if _current_map_id == "maple_heights_village":
			return "world2_chapter1"
	# W2 Chapter 2: first suburban combat, mail carrier hints
	if flags.get("cutscene_flag_world2_chapter1_complete", false) and not flags.get("cutscene_flag_world2_chapter2_complete", false):
		if _current_map_id == "suburban_overworld":
			return "world2_chapter2"
	# Tick 102: W2 Warden of Routine defeat cutscene — plays IN the
	# dungeon on return from boss victory. Pre-fix, the world2_warden_defeat
	# cutscene was unreachable because the DragonCave._on_boss_defeated
	# code path is dead (no caller), so tick 95's defeat_cutscene field
	# was a no-op. This gate mirrors the W1 rat_king_defeat pattern:
	# play the defeat cutscene in-place once on return from victory.
	if flags.get("cutscene_flag_warden_suburban_defeated", false) and not flags.get("cutscene_flag_world2_warden_defeat_complete", false):
		if _current_map_id == "suburban_underground":
			return "world2_warden_defeat"
	# W2 Chapter 3: Warden of Routine aftermath
	if flags.get("cutscene_flag_warden_suburban_defeated", false) and not flags.get("cutscene_flag_world2_chapter3_complete", false):
		return "world2_chapter3"
	# W2 Chapter 4 Garage: garage sale encounter, Cleric keeps sweater
	if flags.get("cutscene_flag_world2_chapter3_complete", false) and not flags.get("cutscene_flag_chapter4_garage_complete", false):
		if _current_map_id == "maple_heights_village":
			return "world2_chapter4_garage"
	# W2 Chapter 4: school entry, Arbiter introduction
	if flags.get("cutscene_flag_chapter4_garage_complete", false) and not flags.get("cutscene_flag_arbiter_suburban_intro_complete", false):
		if _current_map_id == "maple_heights_village":
			return "world2_chapter4"
	# Tick 101: auto-set arbiter_suburban_defeated after the arbiter intro
	# cutscene completes. Pre-fix, this flag was set ONLY by
	# world2_arbiter_defeat.json — a cutscene NO code path triggers — so
	# W2 chapter5 was unreachable. The Masterite Arbiter battle is treated
	# as an off-screen narrative beat that happens between intro and the
	# community center reveal. Mirror of the chapter5→curator auto-set
	# below for the same reason.
	if flags.get("cutscene_flag_arbiter_suburban_intro_complete", false) and not flags.get("cutscene_flag_arbiter_suburban_defeated", false):
		_set_cutscene_flag_and_mirror("cutscene_flag_arbiter_suburban_defeated")
	# W2 Chapter 5: community center, Coordinator reveal
	if flags.get("cutscene_flag_arbiter_suburban_defeated", false) and not flags.get("cutscene_flag_world2_chapter5_complete", false):
		return "world2_chapter5"
	# Tick 101: auto-set curator_suburban_defeated after chapter5
	# (Coordinator reveal). world2_curator_defeat.json exists but has no
	# code path — same situation as arbiter above. The Curator battle is
	# treated as an off-screen narrative beat between chapter5 (reveal)
	# and chapter7_infrastructure (feral shopping cart aftermath).
	if flags.get("cutscene_flag_world2_chapter5_complete", false) and not flags.get("cutscene_flag_curator_suburban_defeated", false):
		_set_cutscene_flag_and_mirror("cutscene_flag_curator_suburban_defeated")
	# W2 Chapter 7: feral shopping cart (after curator defeat)
	if flags.get("cutscene_flag_curator_suburban_defeated", false) and not flags.get("cutscene_flag_chapter7_infrastructure_complete", false):
		return "world2_chapter7_infrastructure"
	# W2 Chapter 8: Coordinator's memos found
	if flags.get("cutscene_flag_chapter7_infrastructure_complete", false) and not flags.get("cutscene_flag_chapter8_memos_found", false):
		return "world2_chapter8_memos"
	# W2 Chapter 11: incomplete memo + suburb→steampunk transition
	# Gates on all W2 Masterites being defeated (memos found = last Masterite chain)
	if flags.get("cutscene_flag_chapter8_memos_found", false) and not flags.get("cutscene_flag_chapter11_complete", false):
		return "world2_chapter11"
	# Tick 100: auto-set world2_complete when chapter11 finishes — pre-fix,
	# nothing set this flag, so the W3 prologue gate at line ~1092 (which
	# reads cutscene_flag_world2_complete) was never satisfied. Players
	# couldn't progress past W2 even after finishing chapter11.
	if flags.get("cutscene_flag_chapter11_complete", false) and not flags.get("cutscene_flag_world2_complete", false):
		_set_cutscene_flag_and_mirror("cutscene_flag_world2_complete")

	# ===== WORLD 3: STEAMPUNK =====
	if flags.get("cutscene_flag_world2_complete", false) and not flags.get("cutscene_flag_world3_prologue_complete", false):
		if _current_map_id == "steampunk_overworld":
			return "world3_prologue"
	if flags.get("cutscene_flag_world3_prologue_complete", false) and not flags.get("cutscene_flag_world3_chapter1_complete", false):
		if _current_map_id == "brasston_village":
			return "world3_chapter1"
	if flags.get("cutscene_flag_world3_chapter1_complete", false) and not flags.get("cutscene_flag_world3_chapter2_complete", false):
		if _current_map_id == "steampunk_overworld":
			return "world3_chapter2"
	if flags.get("cutscene_flag_world3_chapter2_complete", false) and not flags.get("cutscene_flag_world3_chapter3_complete", false):
		return "world3_chapter3"
	# Tick 102: W3 Tempo of the Shift defeat cutscene — plays IN the
	# Mechanism on return from boss victory. Same pattern as the W2
	# warden defeat gate above.
	if flags.get("cutscene_flag_tempo_steampunk_defeated", false) and not flags.get("cutscene_flag_world3_tempo_defeat_complete", false):
		if _current_map_id == "steampunk_mechanism":
			return "world3_tempo_defeat"
	if flags.get("cutscene_flag_world3_chapter3_complete", false) and not flags.get("cutscene_flag_world3_chapter4_complete", false):
		# Tick 96: was gated on `cutscene_flag_warden_industrial_defeated`
		# (a W4 flag set by AssemblyCore), so W3 chapter4 — the
		# Regulator post-defeat dialogue — only triggered after the
		# player beat W4's dungeon. Now correctly gated on the W3
		# Mechanism's own boss-defeat flag set by SteampunkMechanism.
		if flags.get("cutscene_flag_tempo_steampunk_defeated", false):
			return "world3_chapter4"
	if flags.get("cutscene_flag_world3_chapter4_complete", false) and not flags.get("cutscene_flag_world3_chapter5_complete", false):
		return "world3_chapter5"
	# Tick 100: auto-set world3_complete after chapter5 — same fix pattern
	# as W2. Unblocks the W4 prologue gate which reads world3_complete.
	if flags.get("cutscene_flag_world3_chapter5_complete", false) and not flags.get("cutscene_flag_world3_complete", false):
		_set_cutscene_flag_and_mirror("cutscene_flag_world3_complete")

	# ===== WORLD 4: INDUSTRIAL / DIGITAL =====
	# Tick 102: W4 Warden of Industrial defeat cutscene — plays IN
	# Assembly Core on return from boss victory.
	if flags.get("cutscene_flag_warden_industrial_defeated", false) and not flags.get("cutscene_flag_world4_warden_defeat_complete", false):
		if _current_map_id == "assembly_core":
			return "world4_warden_defeat"
	if flags.get("cutscene_flag_world3_complete", false) and not flags.get("cutscene_flag_world4_prologue_complete", false):
		if _current_map_id == "industrial_overworld":
			return "world4_prologue"
	if flags.get("cutscene_flag_world4_prologue_complete", false) and not flags.get("cutscene_flag_world4_chapter1_complete", false):
		if _current_map_id == "rivet_row_village":
			return "world4_chapter1"
	if flags.get("cutscene_flag_world4_chapter1_complete", false) and not flags.get("cutscene_flag_world4_chapter2_complete", false):
		if _current_map_id == "industrial_overworld":
			return "world4_chapter2"
	if flags.get("cutscene_flag_world4_chapter2_complete", false) and not flags.get("cutscene_flag_world4_chapter3_complete", false):
		return "world4_chapter3"
	if flags.get("cutscene_flag_world4_chapter3_complete", false) and not flags.get("cutscene_flag_world4_chapter4_complete", false):
		return "world4_chapter4"
	if flags.get("cutscene_flag_world4_chapter4_complete", false) and not flags.get("cutscene_flag_world4_chapter5_complete", false):
		return "world4_chapter5"
	# Tick 100: auto-set world4_complete after chapter5.
	if flags.get("cutscene_flag_world4_chapter5_complete", false) and not flags.get("cutscene_flag_world4_complete", false):
		_set_cutscene_flag_and_mirror("cutscene_flag_world4_complete")

	# ===== WORLD 5: ABSTRACT / NETWORK =====
	# Tick 103: W5 Arbiter of Futuristic defeat cutscene — plays IN
	# Root Process on return from boss victory. Same pattern as W2-W4
	# defeat gates (tick 102).
	if flags.get("cutscene_flag_arbiter_futuristic_defeated", false) and not flags.get("cutscene_flag_world5_arbiter_defeat_complete", false):
		if _current_map_id == "root_process":
			return "world5_arbiter_defeat"
	if flags.get("cutscene_flag_world4_complete", false) and not flags.get("cutscene_flag_world5_prologue_complete", false):
		if _current_map_id == "abstract_overworld":
			return "world5_prologue"
	if flags.get("cutscene_flag_world5_prologue_complete", false) and not flags.get("cutscene_flag_world5_chapter1_complete", false):
		if _current_map_id == "node_prime_village":
			return "world5_chapter1"
	if flags.get("cutscene_flag_world5_chapter1_complete", false) and not flags.get("cutscene_flag_world5_chapter2_complete", false):
		if _current_map_id == "abstract_overworld":
			return "world5_chapter2"
	if flags.get("cutscene_flag_world5_chapter2_complete", false) and not flags.get("cutscene_flag_world5_chapter3_complete", false):
		return "world5_chapter3"
	if flags.get("cutscene_flag_world5_chapter3_complete", false) and not flags.get("cutscene_flag_world5_chapter4_complete", false):
		return "world5_chapter4"
	if flags.get("cutscene_flag_world5_chapter4_complete", false) and not flags.get("cutscene_flag_world5_chapter5_complete", false):
		return "world5_chapter5"
	# Tick 100: auto-set world5_complete after chapter5 — unblocks W6
	# prologue gate.
	if flags.get("cutscene_flag_world5_chapter5_complete", false) and not flags.get("cutscene_flag_world5_complete", false):
		_set_cutscene_flag_and_mirror("cutscene_flag_world5_complete")

	# ===== WORLD 6: THE VERTEX (Final) =====
	if flags.get("cutscene_flag_world5_complete", false) and not flags.get("cutscene_flag_world6_prologue_complete", false):
		if _current_map_id == "vertex_village":
			return "world6_prologue"
	if flags.get("cutscene_flag_world6_prologue_complete", false) and not flags.get("cutscene_flag_world6_chapter1_complete", false):
		if _current_map_id == "vertex_village":
			return "world6_chapter1"
	if flags.get("cutscene_flag_world6_chapter1_complete", false) and not flags.get("cutscene_flag_world6_chapter2_complete", false):
		return "world6_chapter2"
	if flags.get("cutscene_flag_world6_chapter2_complete", false) and not flags.get("cutscene_flag_world6_chapter3_complete", false):
		return "world6_chapter3"
	# Tick 107: W6 endgame closer — chapter3 (The Question) → calibrant
	# defeat (the answer + class offer) → ending (worlds reform). Pre-fix,
	# the W6 chain stopped at chapter3 and the player had no narrative
	# closer despite world6_calibrant_defeat.json and world6_ending.json
	# being authored on disk. The Calibrant "battle" is elided as
	# narrative — matches the W2 Masterite auto-sets pattern (tick 101)
	# since no Calibrant arena/dungeon exists.
	if flags.get("cutscene_flag_world6_chapter3_complete", false) and not flags.get("cutscene_flag_world6_calibrant_defeat_complete", false):
		if _current_map_id == "vertex_village":
			return "world6_calibrant_defeat"
	if flags.get("cutscene_flag_world6_calibrant_defeat_complete", false) and not flags.get("cutscene_flag_world6_ending_complete", false):
		if _current_map_id == "vertex_village":
			return "world6_ending"

	# ===== GUIDANCE HINTS — disabled (now opt-in via party chat) =====
	# These were auto-triggering too aggressively. Guidance hints are now
	# available via NPC dialogue hints instead of forced cutscenes.
	return ""


## Prevents back-to-back story cutscenes on same map entry
var _cutscene_cooldown: bool = false

## Live-playtest fix 2026-07-11 (intercom 2359): completing a story cutscene can satisfy the NEXT gate on the same entry (chapter3 → rogue spotlight), but the completion path's _start_exploration consumed _cutscene_cooldown and skipped the recheck — the player had to exit/re-enter the cave.
const _STORY_CHAIN_CAP: int = 3
var _story_chain_depth: int = 0
## True only while the post-completion recheck runs; gates authored for cross-entry pacing (cleric/mage/fighter/bard spotlights) refuse to fire as chain targets.
var _chaining_story_cutscene: bool = false


## Pure decision: the cutscene to chain after finished_id, or "" (capped, same-id, or nothing pending).
func _next_chained_story_cutscene(finished_id: String) -> String:
	if _story_chain_depth >= _STORY_CHAIN_CAP:
		return ""
	_chaining_story_cutscene = true
	var next: String = _get_pending_story_cutscene()
	_chaining_story_cutscene = false
	if next == finished_id:
		return ""
	return next

## Maps cutscene_id → GameState flag that marks it complete.
## Without this, _get_pending_story_cutscene returns the same id every
## map-enter forever (talked-to-theron + !chapter1_complete loops).
## (Bug fix 2026-05-20: cutscene completion flags were never being set
## by _play_story_cutscene — only chapter2 auto-set itself inline.)
# Tick 214: defeat flags that _get_pending_story_cutscene actually reads. When a subclass declares defeat_cutscene_flags = ["cutscene_flag_X"] and X isn't here, the flag gets set but no gate fires — silent narrative drop. Update both this set AND the gate when adding a new boss defeat cutscene.
const _KNOWN_DEFEAT_CUTSCENE_FLAGS := {
	"cutscene_flag_arbiter_futuristic_defeated": true,
	"cutscene_flag_arbiter_suburban_defeated": true,
	"cutscene_flag_curator_suburban_defeated": true,
	"cutscene_flag_rat_king_defeated": true,
	"cutscene_flag_tempo_steampunk_defeated": true,
	"cutscene_flag_warden_industrial_defeated": true,
	"cutscene_flag_warden_suburban_defeated": true,
	"cutscene_flag_world1_mordaine_defeated": true,
}


# Tick 214: check whether a defeat flag name is consumed by any _get_pending_story_cutscene gate.
func _is_known_defeat_flag(flag: String) -> bool:
	return _KNOWN_DEFEAT_CUTSCENE_FLAGS.has(flag)


# Tick 220: set a cutscene_flag_X game_constant AND mirror to story_flags as bare 'X'. QuestLog reads story_flags — without the mirror, objective lines stay stale even after the cutscene fires and the game_constants flag is set. Pre-fix this mirror lived only in _play_story_cutscene; direct game_constants writes elsewhere (boss defeats via _apply_pending_boss_defeat, chapter auto-advance gates) silently skipped it. Same bug class as 2026-06-04 Elder Theron.
func _set_cutscene_flag_and_mirror(flag: String) -> void:
	if not GameState or flag == "":
		return
	GameState.game_constants[flag] = true
	if flag.begins_with("cutscene_flag_"):
		var bare = flag.substr("cutscene_flag_".length())
		GameState.set_story_flag(bare)


const _CUTSCENE_COMPLETION_FLAGS := {
	# World 1 (medieval) — flags drop the "world1_" prefix
	"world1_prologue":                  "cutscene_flag_prologue_complete",
	"world1_chapter1":                  "cutscene_flag_chapter1_complete",
	"world1_bram_shield":               "cutscene_flag_world1_bram_shield_complete",
	"world1_chapter3":                  "cutscene_flag_chapter3_complete",
	"world1_chapter4":                  "cutscene_flag_chapter4_complete",
	"world1_rat_king_defeat":           "cutscene_flag_world1_rat_king_defeat_complete",
	# Tick 104: W1 Mordaine final post-defeat dialogue
	"world1_mordaine_defeat":           "cutscene_flag_world1_mordaine_defeat_complete",
	# W1 spotlight cutscenes — dual-signal per Spotlight Duels spec (cowir-
	# main msg 1950, 2026-06-30). Cutscene finish now writes the _watched_
	# flag ("player saw the intro/aftermath narration"). The _unlocked_
	# flag ("PC manual control granted") is written separately by
	# _on_battle_ended's spotlight-duel short-circuit (GameLoop:2224) on
	# battle_won — that path also calls _reconcile_spotlight_locks(). The
	# _get_pending_story_cutscene gates below still key off _unlocked_
	# because story-progression should require the duel win, not just
	# watching the beat. Filenames stay as-is (fighter_ch2, bard_ch7
	# vestigial per option B).
	"world1_spotlight_cleric_ch1":      "cutscene_flag_spotlight_watched_cleric",
	"world1_spotlight_fighter_ch2":     "cutscene_flag_spotlight_watched_fighter",
	"world1_spotlight_rogue_ch3":       "cutscene_flag_spotlight_watched_rogue",
	"world1_spotlight_mage_ch3":        "cutscene_flag_spotlight_watched_mage",
	"world1_spotlight_bard_ch7":        "cutscene_flag_spotlight_watched_bard",
	# World 2 (suburban) — irregular naming mirrored from _get_pending
	"world2_prologue":                  "cutscene_flag_world2_prologue_complete",
	"world2_chapter1":                  "cutscene_flag_world2_chapter1_complete",
	"world2_chapter2":                  "cutscene_flag_world2_chapter2_complete",
	"world2_chapter3":                  "cutscene_flag_world2_chapter3_complete",
	"world2_chapter4_garage":           "cutscene_flag_chapter4_garage_complete",
	"world2_chapter4":                  "cutscene_flag_arbiter_suburban_intro_complete",
	"world2_chapter5":                  "cutscene_flag_world2_chapter5_complete",
	"world2_chapter7_infrastructure":   "cutscene_flag_chapter7_infrastructure_complete",
	"world2_chapter8_memos":            "cutscene_flag_chapter8_memos_found",
	"world2_chapter11":                 "cutscene_flag_chapter11_complete",
	# Tick 102: W2 Warden of Routine post-defeat dialogue
	"world2_warden_defeat":             "cutscene_flag_world2_warden_defeat_complete",
	# World 3 (steampunk)
	"world3_prologue":                  "cutscene_flag_world3_prologue_complete",
	"world3_chapter1":                  "cutscene_flag_world3_chapter1_complete",
	"world3_chapter2":                  "cutscene_flag_world3_chapter2_complete",
	"world3_chapter3":                  "cutscene_flag_world3_chapter3_complete",
	"world3_chapter4":                  "cutscene_flag_world3_chapter4_complete",
	"world3_chapter5":                  "cutscene_flag_world3_chapter5_complete",
	# Tick 102: W3 Tempo of the Shift post-defeat dialogue
	"world3_tempo_defeat":              "cutscene_flag_world3_tempo_defeat_complete",
	# World 4 (industrial)
	"world4_prologue":                  "cutscene_flag_world4_prologue_complete",
	"world4_chapter1":                  "cutscene_flag_world4_chapter1_complete",
	"world4_chapter2":                  "cutscene_flag_world4_chapter2_complete",
	"world4_chapter3":                  "cutscene_flag_world4_chapter3_complete",
	"world4_chapter4":                  "cutscene_flag_world4_chapter4_complete",
	"world4_chapter5":                  "cutscene_flag_world4_chapter5_complete",
	# Tick 102: W4 Warden of Industrial post-defeat dialogue
	"world4_warden_defeat":             "cutscene_flag_world4_warden_defeat_complete",
	# World 5 (digital/abstract)
	"world5_prologue":                  "cutscene_flag_world5_prologue_complete",
	"world5_chapter1":                  "cutscene_flag_world5_chapter1_complete",
	"world5_chapter2":                  "cutscene_flag_world5_chapter2_complete",
	"world5_chapter3":                  "cutscene_flag_world5_chapter3_complete",
	"world5_chapter4":                  "cutscene_flag_world5_chapter4_complete",
	"world5_chapter5":                  "cutscene_flag_world5_chapter5_complete",
	# Tick 103: W5 Arbiter of Futuristic post-defeat dialogue
	"world5_arbiter_defeat":            "cutscene_flag_world5_arbiter_defeat_complete",
	# World 6 (vertex/final)
	"world6_prologue":                  "cutscene_flag_world6_prologue_complete",
	"world6_chapter1":                  "cutscene_flag_world6_chapter1_complete",
	"world6_chapter2":                  "cutscene_flag_world6_chapter2_complete",
	"world6_chapter3":                  "cutscene_flag_world6_chapter3_complete",
	# Tick 107: W6 endgame closer
	"world6_calibrant_defeat":          "cutscene_flag_world6_calibrant_defeat_complete",
	"world6_ending":                    "cutscene_flag_world6_ending_complete",
}


func _play_story_cutscene(cutscene_id: String) -> void:
	"""Play a story cutscene, then resume exploration."""
	current_state = LoopState.CUTSCENE
	_cutscene_cooldown = true  # Suppress next check on same map entry
	_remove_party_chat_indicator()
	if not _cutscene_director:
		_cutscene_director = CutsceneDirector.new()
		add_child(_cutscene_director)
	_cutscene_director.cutscene_finished.connect(func(_id: String):
		# completing an aborted run would lock the spotlight PC forever (flag blocks the replay)
		if _cutscene_director.has_method("last_finished_was_aborted") and _cutscene_director.last_finished_was_aborted():
			push_warning("[GameLoop] '%s' was ABORTED — completion flag skipped; it will replay when runnable" % cutscene_id)
			_story_chain_depth = 0
			return
		# Mark this story cutscene complete so it won't replay.
		# (Bug 2026-05-20: chapter1_complete was never set, so Elder
		# Theron's cutscene looped forever and quest log stayed stale.)
		var completion_flag: String = _CUTSCENE_COMPLETION_FLAGS.get(cutscene_id, "")
		# Tick 212: surface missing map entries loudly. Pre-fix a new cutscene id added to _get_pending without a matching map entry silently played → loop forever, no signal in the editor logs. Same class of silent failure as the 2026-05-20 Elder Theron bug.
		if completion_flag == "":
			push_warning("[GameLoop] _play_story_cutscene: '%s' missing from _CUTSCENE_COMPLETION_FLAGS — flag NOT set, cutscene will replay on next gate check (loop bug)" % cutscene_id)
		if completion_flag != "" and GameState:
			# Tick 220: route through the shared helper so the constant + story_flags mirror always travel together (this site WAS the only mirror pre-fix; the other 8 game_constants writes silently skipped it — see ticks 212/214 audit + the 2026-06-04 Elder Theron user report that prompted the original mirror here).
			_set_cutscene_flag_and_mirror(completion_flag)
			print("[CUTSCENE] %s complete → set flag %s" % [cutscene_id, completion_flag])
			# W1 spotlight completion also unlocks the matching PC's
			# manual control. Reconcile is idempotent so a no-op for
			# non-spotlight cutscenes.
			if completion_flag.begins_with("cutscene_flag_spotlight_unlocked_"):
				_reconcile_spotlight_locks()
			# Tick 108: world6_ending is the game's narrative closer.
			# Mark the run as complete + surface a celebratory toast so
			# the player has acknowledgment that they finished, rather
			# than just dropping back into vertex_village wandering.
			# The flag is durable + per-save so NG+ flows / replay UI
			# can branch on it without re-deriving from cutscene state.
			if cutscene_id == "world6_ending":
				GameState.game_constants["game_complete"] = true
				GameState.set_story_flag("game_complete")
				if Toast:
					Toast.show_success(self,
						"Calibration complete — thank you for playing Cowardly Irregular.")
		# Wave D: record cutscene completion in the EventLog so LLM-driven
		# NPC dialogue can reference recently-witnessed story beats. The
		# completion_flag is already in game_constants so LLMContext picks
		# it up — but the EventLog gives the LLM a chronological "what just
		# happened" rather than a sparse boolean flag soup.
		if GameState and "event_log" in GameState and GameState.event_log != null:
			GameState.event_log.record(
				EventLog.TYPE_STORY_FLAG,
				"Cutscene complete: %s" % cutscene_id,
				{"cutscene_id": cutscene_id, "flag": completion_flag}
			)
		# Chain a newly-satisfied gate NOW — _start_exploration's own recheck is eaten by the cooldown this play just set (intercom 2359: chapter3 → rogue needed an exit/re-enter).
		var chained: String = _next_chained_story_cutscene(cutscene_id)
		if chained != "":
			_story_chain_depth += 1
			print("[CUTSCENE] chaining '%s' after '%s' (depth %d/%d)" % [chained, cutscene_id, _story_chain_depth, _STORY_CHAIN_CAP])
			_play_story_cutscene(chained)
			return
		_story_chain_depth = 0
		_start_exploration()
		_flush_chat_toasts()
	, CONNECT_ONE_SHOT)
	_cutscene_director.play_cutscene(cutscene_id)


func _on_title_continue() -> void:
	"""Handle continue selected from title screen"""
	print("[GAME] Continue selected")
	_close_title_screen()
	# Load most recent save FIRST (writes into GameState), THEN restore the
	# live party from the loaded GameState. Bug fix (2026-04-30): previously
	# we went straight to _create_party() (defaults) and ignored the save.
	var loaded = false
	var slot := -1
	if SaveSystem and SaveSystem.has_method("load_game"):
		slot = SaveSystem.get_most_recent_slot() if SaveSystem.has_method("get_most_recent_slot") else -1
		if slot >= 0:
			loaded = SaveSystem.load_game(slot)
	if loaded and _restore_party_from_save_data():
		print("[GAME] Continue: restored party from save")
	else:
		# Silent fallback to default party was a UX trap — the player clicks
		# Continue expecting to resume, gets a brand-new party with no
		# explanation, and assumes their progress is gone. Toast the failure
		# so they at least know what happened before the fresh game begins.
		var why: String = "no save found" if slot < 0 \
			else ("save load failed (slot %d)" % slot) if not loaded \
			else ("save restored but party data was empty (slot %d)" % slot)
		print("[GAME] Continue: %s — creating default party" % why)
		Toast.show_warning(self, "Continue: %s. Starting fresh." % why)
		_create_party()
	if _area_fade_rect:
		_area_fade_rect.modulate.a = 1.0
	await _start_exploration()
	await _area_fade_from_black()


func _open_settings_menu() -> void:
	"""Open settings menu during exploration (Start button)"""
	print("[GAME] Settings menu opened from exploration")
	var SettingsMenuClass = load("res://src/ui/SettingsMenu.gd")
	if SettingsMenuClass:
		var settings_layer = CanvasLayer.new()
		settings_layer.layer = 110
		add_child(settings_layer)
		var settings_menu = SettingsMenuClass.new()
		settings_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
		settings_layer.add_child(settings_menu)
		if _exploration_scene and _exploration_scene.has_method("pause"):
			_exploration_scene.pause()
		settings_menu.closed.connect(func():
			settings_layer.queue_free()
			if _exploration_scene and _exploration_scene.has_method("resume"):
				_exploration_scene.resume()
		)
		settings_menu.start_boss_battle.connect(_on_settings_boss_battle)
		# Debug teleport from settings menu — same handler as the OverworldMenu
		# teleport, which closes the menu first then transitions.
		if settings_menu.has_signal("teleport_requested"):
			settings_menu.teleport_requested.connect(_on_settings_teleport_requested)


func _on_title_settings() -> void:
	"""Handle settings selected from title screen"""
	print("[GAME] Settings selected from title")
	# Create settings menu overlay
	var SettingsMenuClass = load("res://src/ui/SettingsMenu.gd")
	if SettingsMenuClass:
		var settings_layer = CanvasLayer.new()
		settings_layer.layer = 110  # Above title screen
		add_child(settings_layer)

		var settings_menu = SettingsMenuClass.new()
		settings_menu.from_title = true
		settings_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
		settings_layer.add_child(settings_menu)

		# Connect close signal
		settings_menu.closed.connect(func():
			settings_layer.queue_free()
			# Rebuild title menu in case settings changed (e.g., save deleted)
			if _title_screen and is_instance_valid(_title_screen):
				if _title_screen.has_method("_build_menu"):
					_title_screen._build_menu()
		)
		settings_menu.start_boss_battle.connect(_on_settings_boss_battle)


func _show_character_creation() -> void:
	"""Show the character creation screen"""
	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	_character_creation_screen = CharacterCreationScreenClass.new()
	_character_creation_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_character_creation_screen)

	_character_creation_screen.creation_complete.connect(_on_character_creation_complete.bind(layer))
	_character_creation_screen.creation_skipped.connect(_on_character_creation_skipped.bind(layer))

	print("[GAME] Showing character creation screen")


func _on_character_creation_complete(customizations: Array, layer: CanvasLayer) -> void:
	"""Handle character creation completion"""
	print("[GAME] Character creation complete with %d characters" % customizations.size())

	# Create party from customizations
	_create_party_from_customizations(customizations)

	# Clean up creation screen
	if layer:
		layer.queue_free()
	_character_creation_screen = null

	# Save customizations
	_save_customizations(customizations)

	# Start exploration
	_start_exploration()


func _on_character_creation_skipped(layer: CanvasLayer) -> void:
	"""Handle character creation skip - use defaults"""
	print("[GAME] Character creation skipped, using defaults")

	# Clean up creation screen
	if layer:
		layer.queue_free()
	_character_creation_screen = null

	# Create default party
	_create_party()

	# Start exploration
	_start_exploration()


func _create_party_from_customizations(customizations: Array) -> void:
	"""Create party members based on customizations"""
	party.clear()

	# Base stats for party members
	var base_stats_list = [
		{"max_hp": 150, "max_mp": 50, "attack": 25, "defense": 15, "magic": 12, "speed": 12},
		{"max_hp": 100, "max_mp": 120, "attack": 10, "defense": 12, "magic": 28, "speed": 14},
		{"max_hp": 90, "max_mp": 40, "attack": 18, "defense": 10, "magic": 8, "speed": 22},
		{"max_hp": 80, "max_mp": 150, "attack": 8, "defense": 8, "magic": 35, "speed": 12}
	]

	for i in range(min(customizations.size(), 4)):
		var custom = customizations[i]
		var base_stats = base_stats_list[i] if i < base_stats_list.size() else base_stats_list[0]

		var member = Combatant.new()
		member.initialize({
			"name": custom.name,
			"max_hp": base_stats["max_hp"],
			"max_mp": base_stats["max_mp"],
			"attack": base_stats["attack"],
			"defense": base_stats["defense"],
			"magic": base_stats["magic"],
			"speed": base_stats["speed"]
		})
		add_child(member)

		# Store customization reference for portraits
		member.customization = custom

		# Apply personality stat bonus
		custom.apply_stat_bonus(member)

		# Assign first job
		if custom.starting_jobs.size() > 0:
			JobSystem.assign_job(member, custom.starting_jobs[0])

		# Assign secondary job
		if custom.starting_jobs.size() > 1:
			JobSystem.assign_secondary_job(member, custom.starting_jobs[1])

		# Add starting items from personality
		var starting_items = custom.get_starting_items()
		for item_id in starting_items:
			member.add_item(item_id, starting_items[item_id])

		# Add phoenix down for all
		member.add_item("phoenix_down", 1)

		party.append(member)
		print("[PARTY] Created %s (%s) - %s personality" % [
			custom.name,
			custom.starting_jobs[0] if custom.starting_jobs.size() > 0 else "none",
			CustomizationScript.get_personality_name(custom.personality)
		])

	# Fresh party starts at FULL — same init-order gap as the default path (personality bonuses + jobs raise max after initialize).
	for m in party:
		m.current_hp = m.max_hp
		m.current_mp = m.max_mp

	# Tick 82: wire leveled_up + ability_learned signals so the new
	# party fires Toast on every level-up and ability unlock. Without
	# this, character-creation players got silent level-ups —
	# discord/inspiring_melody (Bard), shield_bash/slash (Fighter),
	# regenerate/crystal_heal (Cleric), etc. all popped without
	# feedback. _create_party() (the default-party path) already calls
	# this; the character-creation path was the only one missing it.
	_wire_party_level_up_listeners()


func _save_customizations(customizations: Array) -> void:
	"""Save character customizations to file"""
	var data = []
	for custom in customizations:
		data.append(custom.to_dict())

	var file = FileAccess.open("user://save_data.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"party_customizations": data}))
		file.close()
		print("[SAVE] Saved party customizations")


func _load_customizations() -> Array:
	"""Load character customizations from file"""
	if not FileAccess.file_exists("user://save_data.json"):
		return []

	var file = FileAccess.open("user://save_data.json", FileAccess.READ)
	if not file:
		return []

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) != OK:
		return []

	var data = json.data
	if not data.has("party_customizations"):
		return []

	var customizations = []
	for custom_data in data["party_customizations"]:
		customizations.append(CustomizationScript.from_dict_with_script(custom_data, CustomizationScript))

	print("[LOAD] Loaded %d character customizations" % customizations.size())
	return customizations


func _restore_party_from_save_data() -> bool:
	"""Reconstruct runtime party from GameState.player_party (post-load).

	Returns true if a party was restored, false if no save data available
	(in which case caller should fall back to _create_party() defaults).

	Bug fix (2026-04-30): SaveSystem.load_game wrote into GameState but
	GameLoop.party was never rehydrated — every Continue / Game Over →
	Continue from save effectively reset the party to defaults. This
	function closes the gap. Pairs with the expanded Combatant.to_dict /
	from_dict and the full-state _sync_party_to_game_state.
	"""
	if not GameState or GameState.player_party.is_empty():
		return false

	# Tear down any existing live party — we're replacing it.
	for old in party:
		if is_instance_valid(old):
			old.queue_free()
	party.clear()

	for entry in GameState.player_party:
		if not (entry is Dictionary):
			continue
		var c = Combatant.new()
		add_child(c)
		c.from_dict(entry)
		# Reapply job dict + abilities via JobSystem (the dict is data-driven
		# and not safe to serialize verbatim — we keep job_id and rebuild).
		var job_id = entry.get("job_id", "fighter")
		# Legacy saves may have stored the synthetic "job" string instead of "job_id"
		if job_id == "" and entry.has("job") and entry["job"] is String:
			job_id = entry["job"]
		if job_id == "":
			job_id = "fighter"
		# Tick 188: assign_job failure fell silently before — fall back to fighter so character has a valid job.
		if not JobSystem.assign_job(c, job_id):
			push_warning("[GameLoop] _restore_party_from_save_data: assign_job('%s') failed for %s — falling back to 'fighter'" % [job_id, c.combatant_name])
			JobSystem.assign_job(c, "fighter")
		# pre-pare saves (no purchased_abilities key) owned the full kit innately — never repossess
		if not entry.has("purchased_abilities"):
			JobSystem.learn_abilities_for_level(c, 99)
		var sec_id = entry.get("secondary_job_id", "")
		if sec_id != "":
			# Secondary is optional — failure leaves it unset, no fallback.
			if not JobSystem.assign_secondary_job(c, sec_id):
				push_warning("[GameLoop] _restore_party_from_save_data: assign_secondary_job('%s') failed for %s — leaving secondary unset" % [sec_id, c.combatant_name])
		# Re-apply equipment so stat mods attach; tick 189 warns on equip failure (unknown id, removed item). Empty is valid — no fallback.
		var w = entry.get("equipped_weapon", "")
		if w != "" and not EquipmentSystem.equip_weapon(c, w):
			push_warning("[GameLoop] _restore_party_from_save_data: equip_weapon('%s') failed for %s — slot left empty" % [w, c.combatant_name])
		var a = entry.get("equipped_armor", "")
		if a != "" and not EquipmentSystem.equip_armor(c, a):
			push_warning("[GameLoop] _restore_party_from_save_data: equip_armor('%s') failed for %s — slot left empty" % [a, c.combatant_name])
		var acc = entry.get("equipped_accessory", "")
		if acc != "" and not EquipmentSystem.equip_accessory(c, acc):
			push_warning("[GameLoop] _restore_party_from_save_data: equip_accessory('%s') failed for %s — slot left empty" % [acc, c.combatant_name])
		# from_dict already filled equipped_passives; re-equipping tripped idempotency (never applied mods) — validate ids + recalc once (cowir-main live-log 2026-07-04)
		for pid in c.equipped_passives.duplicate():
			if PassiveSystem.get_passive(pid).is_empty():
				c.equipped_passives.erase(pid)
				push_warning("[GameLoop] _restore_party_from_save_data: passive '%s' no longer in passives table — dropped from %s" % [pid, c.combatant_name])
		c.recalculate_stats()
		party.append(c)

	# After equip/passive reapply, restore HP/MP/AP from the saved data
	# (EquipmentSystem may have bumped max_hp via equipment, which clamps
	# current_hp upward in some equip paths). We re-clamp to saved values.
	for i in party.size():
		if i >= GameState.player_party.size():
			break
		var saved = GameState.player_party[i]
		if not (saved is Dictionary):
			continue
		var c: Combatant = party[i]
		if saved.has("current_hp"):
			c.current_hp = clampi(saved["current_hp"], 0, c.max_hp)
		if saved.has("current_mp"):
			c.current_mp = clampi(saved["current_mp"], 0, c.max_mp)
		if saved.has("current_ap"):
			c.current_ap = clampi(saved["current_ap"], -4, 4)
		if saved.has("is_alive"):
			c.is_alive = saved["is_alive"]
	# Spotlight reconcile after load — flags persist in game_constants
	# so a save mid-W1 may carry already-unlocked PCs even though the
	# Combatant.autobattle_locked field is freshly set by from_dict.
	_reconcile_spotlight_locks()
	# tick 55: rewire level-up listeners after a load — the freshly-
	# constructed Combatants don't carry connections from the previous
	# session.
	_wire_party_level_up_listeners()
	# Tick 308: pull the saved map_id out of MapSystem.current_map_id (which
	# SaveSystem._apply_save_data wrote unconditionally) and sync our private
	# _current_map_id so _start_exploration routes to the right scene. Pre-
	# fix Continue/quick_load always landed the player on whatever GameLoop
	# was already showing (typically "overworld") regardless of where the
	# save was taken — symptom looked like "the save didn't remember my
	# location". Skip empty/unknown ids so a corrupt save doesn't strand the
	# player on a no-match scene.
	if MapSystem and "current_map_id" in MapSystem:
		var saved_map_id: String = str(MapSystem.current_map_id)
		if saved_map_id != "" and saved_map_id != _current_map_id:
			_set_current_map_id(saved_map_id)
	# Tick 309: pull the pending player position from SaveSystem (set by
	# _apply_save_data) into _player_position so the post-_start_exploration
	# restore step in Continue / quick_load snaps the player to the saved
	# coords. Pre-fix the saved position was teleported to a stale scene's
	# player that got queue_free()'d during scene swap, and the new scene's
	# player spawned at its default marker — saved position silently lost
	# every Continue from anywhere except the in-overworld autosave path.
	if SaveSystem and "pending_player_position" in SaveSystem:
		var pending: Vector2 = SaveSystem.pending_player_position
		if pending != Vector2.INF:
			_player_position = pending
			SaveSystem.pending_player_position = Vector2.INF
	return true


func _create_party() -> void:
	"""Create the persistent party"""
	party.clear()

	# Get default customizations
	var default_customs = CustomizationScript.create_default_party_with_script(CustomizationScript)

	# Create Fighter (primary: Fighter / secondary: Rogue)
	var hero = Combatant.new()
	hero.initialize({
		"name": "Fighter",
		"max_hp": 150,
		"max_mp": 50,
		"attack": 25,
		"defense": 15,
		"magic": 12,
		"speed": 12
	})
	add_child(hero)
	hero.customization = default_customs[0] if default_customs.size() > 0 else null
	JobSystem.assign_job(hero, "fighter")
	JobSystem.assign_secondary_job(hero, "rogue")
	EquipmentSystem.equip_weapon(hero, "iron_sword")
	EquipmentSystem.equip_armor(hero, "leather_armor")
	EquipmentSystem.equip_accessory(hero, "power_ring")
	hero.learn_passive("weapon_mastery")
	hero.learn_passive("hp_boost")
	PassiveSystem.equip_passive(hero, "weapon_mastery")
	PassiveSystem.equip_passive(hero, "hp_boost")
	hero.add_item("potion", 5)
	hero.add_item("hi_potion", 2)
	hero.add_item("ether", 3)
	hero.add_item("phoenix_down", 1)
	party.append(hero)

	# Spotlight pattern: party_leader_index=0 (hero/Fighter) is the default
	# lead PC and is freely controllable. The other 4 PCs join the party
	# from the prologue (canon-respecting 5-PC roster) but their turns are
	# routed through autobattle until their spotlight cutscene fires (see
	# _CUTSCENE_COMPLETION_FLAGS spotlight_unlocked_<job> entries). The
	# debug flag GameState.debug_all_pcs_unlocked overrides all locks.
	hero.autobattle_locked = false

	# Create Cleric (primary: Cleric / secondary: Bard)
	var mira = Combatant.new()
	mira.initialize({
		"name": "Cleric",
		"max_hp": 100,
		"max_mp": 120,
		"attack": 10,
		"defense": 12,
		"magic": 28,
		"speed": 14
	})
	add_child(mira)
	mira.customization = default_customs[1] if default_customs.size() > 1 else null
	JobSystem.assign_job(mira, "cleric")
	JobSystem.assign_secondary_job(mira, "bard")
	EquipmentSystem.equip_weapon(mira, "oak_staff")
	EquipmentSystem.equip_armor(mira, "cloth_robe")
	EquipmentSystem.equip_accessory(mira, "magic_ring")
	mira.learn_passive("magic_boost")
	mira.learn_passive("mp_boost")
	PassiveSystem.equip_passive(mira, "magic_boost")
	PassiveSystem.equip_passive(mira, "mp_boost")
	mira.autobattle_locked = true  # spotlight unlock via world1_spotlight_cleric_ch1
	party.append(mira)

	# Create Rogue (primary: Rogue / secondary: Fighter)
	var rogue = Combatant.new()
	rogue.initialize({
		"name": "Rogue",
		"max_hp": 90,
		"max_mp": 40,
		"attack": 18,
		"defense": 10,
		"magic": 8,
		"speed": 22
	})
	add_child(rogue)
	rogue.customization = default_customs[2] if default_customs.size() > 2 else null
	JobSystem.assign_job(rogue, "rogue")
	JobSystem.assign_secondary_job(rogue, "fighter")
	EquipmentSystem.equip_weapon(rogue, "iron_dagger")
	EquipmentSystem.equip_armor(rogue, "thief_garb")
	EquipmentSystem.equip_accessory(rogue, "speed_boots")
	rogue.learn_passive("critical_strike")
	rogue.learn_passive("speed_boost")
	PassiveSystem.equip_passive(rogue, "critical_strike")
	PassiveSystem.equip_passive(rogue, "speed_boost")
	rogue.autobattle_locked = true  # spotlight unlock via world1_spotlight_rogue_ch3
	party.append(rogue)

	# Create Mage (primary: Mage / secondary: Cleric)
	var vex = Combatant.new()
	vex.initialize({
		"name": "Mage",
		"max_hp": 80,
		"max_mp": 150,
		"attack": 8,
		"defense": 8,
		"magic": 35,
		"speed": 12
	})
	add_child(vex)
	vex.customization = default_customs[3] if default_customs.size() > 3 else null
	JobSystem.assign_job(vex, "mage")
	JobSystem.assign_secondary_job(vex, "cleric")
	EquipmentSystem.equip_weapon(vex, "shadow_rod")
	EquipmentSystem.equip_armor(vex, "dark_robe")
	EquipmentSystem.equip_accessory(vex, "mp_amulet")
	vex.learn_passive("magic_boost")
	vex.learn_passive("mp_efficiency")
	PassiveSystem.equip_passive(vex, "magic_boost")
	PassiveSystem.equip_passive(vex, "mp_efficiency")
	vex.autobattle_locked = true  # spotlight unlock via world1_spotlight_mage_ch3
	party.append(vex)

	# Create Bard (primary: Bard / secondary: Rogue)
	# Internal ID "bard" matches the job_id — story chose class-title as
	# placeholder rather than a fantasy codename, may be revisited later.
	var bard = Combatant.new()
	bard.initialize({
		"name": "Bard",
		"max_hp": 95,
		"max_mp": 90,
		"attack": 12,
		"defense": 9,
		"magic": 22,
		"speed": 16
	})
	add_child(bard)
	bard.customization = default_customs[4] if default_customs.size() > 4 else null
	JobSystem.assign_job(bard, "bard")
	JobSystem.assign_secondary_job(bard, "rogue")
	EquipmentSystem.equip_weapon(bard, "piano_scythe")
	EquipmentSystem.equip_armor(bard, "cloth_robe")
	EquipmentSystem.equip_accessory(bard, "magic_ring")
	bard.learn_passive("magic_boost")
	bard.learn_passive("mp_boost")
	PassiveSystem.equip_passive(bard, "magic_boost")
	PassiveSystem.equip_passive(bard, "mp_boost")
	bard.autobattle_locked = true  # spotlight unlock via world1_spotlight_bard_ch7
	party.append(bard)
	# Fresh party starts at FULL: passives/equipment raise max_hp AFTER initialize set current=max, so Fighter spawned visibly damaged at 132/181 (web-smoke shot, 2026-07-11).
	for m in party:
		m.current_hp = m.max_hp
		m.current_mp = m.max_mp
	# Apply any spotlight unlocks already in flags (relevant for NG+ or
	# debug fast-travel — usually a no-op on a fresh game).
	_reconcile_spotlight_locks()
	# tick 55: wire the level-up listener so the rebalance daemon sees
	# the passive progression signal in addition to wipes / boss defeats.
	_wire_party_level_up_listeners()


## tick 55: connect each Combatant's leveled_up signal to the daemon
## bridge. Idempotent — checking is_connected before connecting so
## save/load reuse paths don't double-connect.
## tick 58: also connects ability_learned so level-up unlocks Toast
## the player.
func _wire_party_level_up_listeners() -> void:
	for member in party:
		if not (member is Combatant):
			continue
		if member.has_signal("leveled_up"):
			if not member.leveled_up.is_connected(_on_party_leveled_up):
				member.leveled_up.connect(_on_party_leveled_up.bind(member))
		if member.has_signal("ability_learned"):
			if not member.ability_learned.is_connected(_on_party_ability_learned):
				member.ability_learned.connect(_on_party_ability_learned.bind(member))


## Handler for any party Combatant's leveled_up signal. Records the
## event in EventLog AND (if rebalance is enabled) fires a consider
## trigger so the daemon can react to passive progression — not just
## the high-stakes wipe/defeat signals.
##
## Throttling: the daemon's own min_consideration_interval guards
## against firing on every level when the player chain-levels in a
## grinding session. Recording is unconditional so the audit log has
## the level changes regardless of rebalance opt-in.
## tick 58: Toast on ability unlock so the player sees the reward.
func _on_party_ability_learned(ability_id: String, member: Combatant) -> void:
	if member == null:
		return
	# Tick 128: prefer the JobSystem's canonical display name; fall
	# back to the prettified ability_id (snake_case → Title Case)
	# rather than the raw key. Pre-fix, a Combatant.learn_ability
	# call for an id JobSystem couldn't resolve (debug paths,
	# Scriptweaver custom abilities, save-format drift) surfaced
	# "Mira learned shield_bash!" with the underscore — ugly and
	# clearly an engineer-facing string.
	var ability_name: String = ability_id.replace("_", " ").capitalize()
	if JobSystem and JobSystem.has_method("get_ability"):
		var a: Dictionary = JobSystem.get_ability(ability_id)
		if not a.is_empty() and a.has("name"):
			ability_name = str(a["name"])
	if Toast:
		Toast.show(self,
			"%s learned %s!" % [member.combatant_name, ability_name],
			Toast.SUCCESS_COLOR)


func _on_party_leveled_up(new_level: int, member: Combatant) -> void:
	if GameState == null:
		return
	# Tick 313: world key now uses current_world (where THIS event happened)
	# instead of worlds_unlocked (progression marker). Pre-fix `world` meant
	# "highest unlocked" not "current location" — the rebalance LLM seeing
	# a level-up event with world=4 thought the level-up happened in W4
	# even when the player was in W2. Both fields surface so the LLM has
	# the full picture; "world" is renamed via the comment, the dict key
	# stays "world" for backward compatibility with existing EventLog rows
	# and tests pinning the key name.
	var ctx: Dictionary = {
		"member": member.combatant_name if member else "?",
		"new_level": new_level,
		"map_id": _current_map_id,
		"world": GameState.current_world,
		"worlds_unlocked": GameState.worlds_unlocked,
	}
	if "event_log" in GameState and GameState.event_log != null:
		GameState.event_log.record(
			EventLog.TYPE_LEVEL_UP,
			"%s reached level %d" % [str(ctx["member"]), new_level],
			ctx)
	# tick 60: Toast the level-up unless we're in battle (the battle's
	# own victory screen already surfaces per-character level info, so
	# a parallel Toast would just be noise — but out-of-battle leveling
	# from debug paths / future event-driven exp sources still wants
	# a visible cue).
	# VICTORY/DEFEAT count as in-battle here — the results screen shows its own level rows, so toasts must stay suppressed through presentation
	var in_battle: bool = BattleManager != null and BattleManager.current_state != BattleManager.BattleState.INACTIVE
	if Toast and not in_battle and member != null:
		Toast.show(self,
			"%s reached job level %d!" % [member.combatant_name, new_level],
			Toast.SUCCESS_COLOR)
	if GameState.llm_rebalance_enabled and GameState.rebalance_daemon != null:
		var fired: bool = GameState.rebalance_daemon.consider(
			RebalanceDaemonScript.TRIGGER_LEVEL_UP, ctx)
		if fired:
			_kick_off_rebalance_fetch.call_deferred(
				GameState.rebalance_daemon.pending.size() - 1)
	# Tick 247 / 254: ratchet "Double Digits" event flag via the
	# centralized helper so a toast fires on first unlock.
	if new_level >= 10 and PartyChatSystem:
		PartyChatSystem.fire_event_flag("event_flag_level_10_reached")


func _reconcile_spotlight_locks() -> void:
	# Walk the party and unlock any PC whose spotlight cutscene flag is
	# set. Idempotent — safe to call on init, post-load, or after any
	# cutscene completes. Debug flag is handled at the lock-check sites
	# (BattleManager turn routing, UI gates) rather than mutating state
	# here so toggling the debug flag at runtime takes effect immediately.
	if not GameState:
		return
	var flags = GameState.game_constants
	var any_flipped: bool = false
	for member in party:
		if member == null or not "autobattle_locked" in member:
			continue
		if not member.job is Dictionary:
			continue
		var job_id: String = member.job.get("id", "")
		if job_id.is_empty():
			continue
		var flag = "cutscene_flag_spotlight_unlocked_" + job_id
		if flags.get(flag, false) and member.autobattle_locked:
			member.autobattle_locked = false
			any_flipped = true
	# Mid-battle locked → unlocked transition fires the spotlight_unlock
	# tutorial hint exactly once per session (TutorialHints handles the
	# session dedupe). Out-of-battle flips are silent — the affordance
	# only matters while a battle is on screen.
	if any_flipped and BattleManager and BattleManager.current_state != BattleManager.BattleState.INACTIVE:
		var scene = get_tree().current_scene if is_inside_tree() else null
		if scene:
			TutorialHints.show(scene, "spotlight_unlock")


## Boot canary (2026-07-01): try-load a handful of load-bearing scene
## scripts. load() returns null when a script failed to parse — the
## signature of a stale global class cache (new class_name merged
## without --import). On any failure: push_error per script + a
## fullscreen red overlay telling the player exactly how to fix it.
## Canaries chosen as the cascade roots from the real incident
## (OverworldScene + SavePoint) plus the battle scene.
const _BOOT_CANARY_SCRIPTS: Array = [
	"res://src/exploration/OverworldScene.gd",
	"res://src/exploration/SavePoint.gd",
	"res://src/battle/BattleScene.gd",
]


func _check_boot_canaries() -> void:
	var failed: Array[String] = []
	for path in _BOOT_CANARY_SCRIPTS:
		var script: Variant = load(path)
		if script == null:
			failed.append(str(path))
			push_error("[BOOT-CANARY] failed to load %s — stale class cache? Run: godot --headless --import (or ./launch.sh)" % path)
	if failed.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.name = "BootCanaryOverlay"
	layer.layer = 128
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.0, 0.0, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85))
	label.add_theme_font_size_override("font_size", 22)
	label.text = "ASSETS OUT OF DATE\n\n%d core script(s) failed to compile:\n%s\n\nThis usually means new scripts were merged without reimporting.\nFix: close the game and run  ./launch.sh  (it reimports automatically)\nor:  godot --headless --import" % [failed.size(), "\n".join(failed)]
	layer.add_child(label)


## Tick 471: enter a solo-duel battle for the Spotlight Duels step
## type. Benches all but the spotlight PC (looked up by job id), fires
## the standard _start_battle_async pipeline, awaits our own
## spotlight_battle_ended signal (emitted from _on_battle_ended's
## short-circuit path), restores the party, and returns "victory" |
## "defeat" so CutsceneDirector._step_battle can drive its retry loop.
## Cutscene stays paused across attempts — _on_battle_ended skips its
## normal exploration-return flow while _spotlight_duel_active is on.
func start_solo_battle(job_id: String, enemy_id: String, _opts: Dictionary = {}) -> String:
	# entering mid-battle frees the live battle's combatants under BattleManager — freed-instance errors every frame
	if BattleManager.current_state != BattleManager.BattleState.INACTIVE:
		push_warning("GameLoop.start_solo_battle: refused — a battle is already active (state %d)" % BattleManager.current_state)
		return "unavailable"
	var spotlight_pc: Combatant = null
	for m in party:
		if m == null or not is_instance_valid(m):
			continue
		var m_job_id: String = ""
		if m.job is Dictionary:
			m_job_id = str((m.job as Dictionary).get("id", ""))
		if m_job_id == job_id:
			spotlight_pc = m
			break
	if spotlight_pc == null:
		# "defeat" would retry forever — "unavailable" tells the cutscene to abort
		push_warning("GameLoop.start_solo_battle: no party member with job '%s' — cutscene battle skipped" % job_id)
		return "unavailable"
	_spotlight_saved_party = party.duplicate()
	party = [spotlight_pc]
	_pending_spotlight_unlock = job_id
	_spotlight_duel_active = true
	# the spotlight short-circuit skips post-battle healing, so a retry would re-enter at 0 HP
	_restore_duelist(spotlight_pc)
	# step win_condition overrides; monsters.json is the data fallback (agreement ratchet-tested)
	if BattleManager:
		var wc: Variant = _opts.get("win_condition", {})
		if wc is Dictionary and not (wc as Dictionary).is_empty():
			BattleManager._win_condition = (wc as Dictionary).duplicate()
		elif EncounterSystem and EncounterSystem.monster_database.has(enemy_id):
			var mdata: Dictionary = EncounterSystem.monster_database[enemy_id]
			var monster_wc: Variant = mdata.get("win_condition", {})
			if monster_wc is Dictionary and not (monster_wc as Dictionary).is_empty():
				BattleManager._win_condition = (monster_wc as Dictionary).duplicate()
				print("[SPOTLIGHT] win_condition from monsters.json fallback: %s" % str(monster_wc))
	await _start_battle_async([enemy_id], false)
	var result: bool = await spotlight_battle_ended
	party = _spotlight_saved_party.duplicate()
	_spotlight_saved_party.clear()
	_spotlight_duel_active = false
	_pending_spotlight_unlock = ""
	# Tear the stale BattleScene down under the cutscene's opaque layer so aftermath narration doesn't overlay a live battle: boss music kept playing + survive_turns re-fired end_battle every tick (the "background restart"), and _unfreeze_player at cutscene end had no player behind the layer (Rogue "frozen" after "everyone back"). Skip on defeat: the retry loop owns the next _start_battle_async which frees the scene itself.
	if result:
		_cutscene_cooldown = true  # skip pending-story re-fire from _start_exploration
		await _return_to_exploration()
	return "victory" if result else "defeat"


## statuses cleared via remove_status (not .clear()) so buff bookkeeping stays consistent
static func _restore_duelist(pc: Combatant) -> void:
	if pc == null or not is_instance_valid(pc):
		return
	if not pc.is_alive and pc.has_method("revive"):
		pc.revive(pc.max_hp)
	pc.current_hp = pc.max_hp
	pc.current_mp = pc.max_mp
	if "status_effects" in pc:
		for s in (pc.status_effects as Array).duplicate():
			# the permadeath marker must survive every restore or a later Raise undoes it
			if str(s) == "permakilled":
				continue
			if pc.has_method("remove_status"):
				pc.remove_status(str(s))


func _on_battle_ended(victory: bool) -> void:
	"""Handle battle end"""
	## Tick 471: spotlight-duel short-circuit. When a cutscene owns the
	## flow, we do the minimal spotlight bookkeeping (unlock flag on
	## win) and emit spotlight_battle_ended for start_solo_battle to
	## resume. Skip healing, exploration return, transitions — the
	## cutscene is still on screen and will drive the next step (retry
	## or aftermath). Retry loop's next _start_battle_async will
	## queue_free the stale battle scene.
	if _spotlight_duel_active:
		if victory and _pending_spotlight_unlock != "" and GameState and "game_constants" in GameState:
			var flag: String = "cutscene_flag_spotlight_unlocked_" + _pending_spotlight_unlock
			GameState.game_constants[flag] = true
			print("[SPOTLIGHT] battle won → set %s" % flag)
			_reconcile_spotlight_locks()
		spotlight_battle_ended.emit(victory)
		return
	if victory:
		battles_won += 1
		## Tick 418: sync to GameState's persistent counter so SaveSystem
		## and CutsceneDirector can read across save+quit. GameLoop's
		## battles_won stays as a session-local mirror — convenient for
		## the same-frame consumers below (miniboss every 3, dashboard
		## summary, etc.) that don't need to round-trip through GameState.
		if GameState:
			GameState.battles_won += 1

		# Apply pending boss-defeat flags (set by dungeon._trigger_boss_battle).
		# Must happen BEFORE _return_to_exploration so the new dungeon instance
		# can pick up cave_rat_king_defeated / boss_flag_key from dungeon_flags.
		_apply_pending_boss_defeat()

		# Heal party between battles (rest bonus)
		for member in party:
			var heal_amount = int(member.max_hp * 0.25)
			member.heal(heal_amount)
			var mp_restore = int(member.max_mp * 0.25)
			member.restore_mp(mp_restore)
			member.current_ap = 0

		# Wait for player to confirm before leaving victory screen
		await _wait_for_confirm()

		# Play exit transition (iris-close) before returning to overworld
		if BattleTransition:
			await BattleTransition.play_exit_transition(true)

		# Must `await` — _return_to_exploration is async (it awaits the
		# scene-swap _start_exploration). On desktop the scene load is
		# ~1 frame so the bug was invisible; on Android web the scene
		# instantiation takes seconds, the reveal_exploration tween below
		# fired immediately, faded the iris from black to transparent
		# while NO scene was rendered, and the player saw a black screen
		# until the new scene finally appeared.
		await _return_to_exploration()

		# Reveal the overworld with a smooth fade — runs ONLY after the
		# new scene is in the tree.
		if BattleTransition:
			await BattleTransition.reveal_exploration()
	else:
		# Escape vs wipe: type="escape" abilities (Flee) call end_battle(false) —
		# the SAME path as a party wipe — so a successful flee was hitting the
		# game-over screen. A flee leaves LIVING party members; a true wipe leaves
		# none. Gate the whole defeat/game-over flow on the party actually being
		# down: any survivor means we escaped, so just return to the overworld.
		var _escape_survivors := 0
		for _m in party:
			if _m is Combatant and _m.is_alive:
				_escape_survivors += 1
		if _escape_survivors > 0:
			if BattleTransition:
				await BattleTransition.play_exit_transition(true)
			await _return_to_exploration()
			if BattleTransition:
				await BattleTransition.reveal_exploration()
			return
		## Tick 411: consume meta_auto_rewind_pending (set by the Time
		## Mage temporal_shield meta-ability in tick 404). If the
		## player armed the shield and the wipe just hit, fire the
		## rewind BEFORE the game-over flow so the wipe never reaches
		## the screen. Single-shot — clear the flag whether the rewind
		## succeeded or not, so a stuck shield can't infinitely re-arm
		## on every wipe in the same battle. Falls through to the
		## normal game-over path if rewind_to_previous_save returns
		## false (rewind locked, no history, etc.).
		if GameState and "game_constants" in GameState and bool(GameState.game_constants.get("meta_auto_rewind_pending", false)):
			GameState.game_constants["meta_auto_rewind_pending"] = false
			if GameState.rewind_to_previous_save():
				print("[META] temporal_shield auto-rewind consumed — wipe averted")
				# Skip game-over flow entirely; the save data has been
				# restored to a pre-wipe state.
				return
			else:
				print("[META] temporal_shield auto-rewind failed — rewind not enabled or no history; falling through to game over")

		# Game over — show dramatic screen with retry/continue options
		# Clear pending boss spec on defeat so a retry doesn't accidentally
		# fire flags from a battle the player didn't actually win.
		GameState.pending_boss_defeat = {}
		# ── EventLog: record party wipe fact ─────────────────────────────────
		if GameState and "event_log" in GameState and GameState.event_log != null:
			var survivors: int = 0
			for m in party:
				if m is Combatant and m.is_alive:
					survivors += 1
			var enemy_names: Array = []
			for e in BattleManager.enemy_party:
				if e is Combatant:
					var etype: String = e.get_meta("monster_type", e.combatant_name)
					if etype not in enemy_names:
						enemy_names.append(etype)
			var wipe_ctx: Dictionary = {
				"map_id":      _current_map_id,
				"survivors":   survivors,
				"party_size":  party.size(),
				"enemy_types": enemy_names,
				# Tick 313: world = current_world (where the wipe happened),
				# worlds_unlocked carries the progression marker. See the
				# matching comment in _on_party_leveled_up.
				"world":       GameState.current_world,
				"worlds_unlocked": GameState.worlds_unlocked,
			}
			GameState.event_log.record(
				EventLog.TYPE_PARTY_WIPE,
				"Party wiped in %s" % _current_map_id.replace("_", " ").capitalize(),
				wipe_ctx
			)
			# Rebalance trigger: a wipe is the strongest 'this is too hard'
			# signal we have. Daemon's own throttle keeps a streak from
			# spending the LLM budget; opt-in flag keeps this off by default.
			if GameState.llm_rebalance_enabled and GameState.rebalance_daemon != null:
				var fired: bool = GameState.rebalance_daemon.consider(RebalanceDaemonScript.TRIGGER_PARTY_WIPE, wipe_ctx)
				if fired:
					_kick_off_rebalance_fetch.call_deferred(GameState.rebalance_daemon.pending.size() - 1)
		await _show_game_over_screen()


## tick 44: deferred coroutine that fires the LLM call for a freshly
## queued rebalance proposal. call_deferred from the trigger sites so
## the sync wipe/defeat handlers don't block on the await — the LLM
## call happens on the next idle frame and lands in the proposal
## record by the time the player checks the (forthcoming) review UI.
##
## Recent EventLog entries are passed in for trend context — the
## daemon uses them so the LLM can tell "first wipe of the session"
## from "tenth wipe in 20 minutes".
func _kick_off_rebalance_fetch(proposal_idx: int) -> void:
	if GameState == null or GameState.rebalance_daemon == null:
		return
	var recent: Array = []
	if "event_log" in GameState and GameState.event_log != null:
		recent = GameState.event_log.recent(10)
	var ok: bool = await GameState.rebalance_daemon.request_llm_proposal(proposal_idx, recent)
	if not ok:
		return
	# LLM returned a proposal — try to auto-apply it. Safe deltas at
	# high confidence land instantly; out-of-band or low-confidence
	# proposals stay in pending[] for the review UI to surface.
	# Surface the result diegetically via Toast — matches the "what
	# did the AI change for me" directive (not hidden).
	#
	# pending is ordered by append; the proposal we just filled may
	# have moved if older entries were ring-dropped during the await,
	# so re-find it by status rather than trust the idx blindly.
	var fresh_idx: int = -1
	for i in range(GameState.rebalance_daemon.pending.size()):
		var p: Dictionary = GameState.rebalance_daemon.pending[i]
		if str(p.get("status", "")) == "proposed":
			fresh_idx = i
			break
	if fresh_idx < 0:
		return
	var proposal_copy: Dictionary = GameState.rebalance_daemon.pending[fresh_idx].duplicate(true)
	var result: String = GameState.rebalance_daemon.try_auto_apply(fresh_idx)
	if result == GameState.rebalance_daemon.APPLY_APPLIED or result == GameState.rebalance_daemon.APPLY_NO_CHANGE:
		# Look up the moved-to-applied proposal (it has the
		# applied_changes annotation now).
		var summary_target: Dictionary = proposal_copy
		if GameState.rebalance_daemon.applied.size() > 0:
			summary_target = GameState.rebalance_daemon.applied[-1]
		var msg: String = GameState.rebalance_daemon.summarize_applied(summary_target)
		if Toast:
			Toast.show(self, msg, Toast.SUCCESS_COLOR if result == GameState.rebalance_daemon.APPLY_APPLIED else Toast.WARNING_COLOR)
	elif result == GameState.rebalance_daemon.APPLY_NEEDS_REVIEW:
		if Toast:
			Toast.show(self, "Auto-rebalance proposal needs your review (Settings → review queue)", Toast.WARNING_COLOR)


func _apply_pending_boss_defeat() -> void:
	"""Apply GameState.pending_boss_defeat on battle victory.
	Set by dungeon._trigger_boss_battle() before emitting battle_triggered.
	Without this central handler the cave/dungeon instance gets freed during
	_return_to_exploration before any local defeat handler could run, so the
	story flags silently never get set (regression: Rat King quest log)."""
	var spec: Dictionary = GameState.pending_boss_defeat
	if spec.is_empty():
		return
	# Story flags
	for flag in spec.get("story_flags", []):
		GameState.set_story_flag(flag)
	# Game constants (typically cutscene_flag_*)
	# Tick 214: warn on cutscene_flag_* names that don't appear anywhere in this file's body. A subclass typo (e.g. "cutscene_flag_wardin_industrial_defeated") sets the wrong flag silently — defeat applies but no post-defeat cutscene gate ever fires.
	# Tick 220: route through the helper so each flag also mirrors to story_flags. Pre-fix the direct write here meant QuestLog never saw boss defeat objectives flip to "complete".
	for c in spec.get("constants", []):
		_set_cutscene_flag_and_mirror(str(c))
		if c is String and c.begins_with("cutscene_flag_") and not _is_known_defeat_flag(c):
			push_warning("[GameLoop] _apply_pending_boss_defeat: '%s' set but not referenced by any _get_pending_story_cutscene gate — post-defeat cutscene will NOT fire (subclass typo?)" % c)
	## Tick 154: dungeon flag now lives on game_constants
	## (party-leader-independent). Pre-fix it was stored on
	## player_party[0]["dungeon_flags"]; if the player changed
	## leader via GameState.cycle_party_leader, the old leader's
	## flags became invisible to is_alive checks at dungeon
	## re-entry — a defeated boss would silently respawn.
	var df: String = spec.get("dungeon_flag", "")
	if df != "":
		if not GameState.game_constants.has("dungeon_flags"):
			GameState.game_constants["dungeon_flags"] = {}
		GameState.game_constants["dungeon_flags"][df] = true
	# World unlock — either advance once, or to a specific world
	if spec.get("unlock_world", false):
		var target: int = spec.get("unlock_world_target", 0)
		if target > 0:
			while GameState.worlds_unlocked < target:
				GameState.unlock_next_world()
		else:
			GameState.unlock_next_world()
	# Defeat cutscene — left for the dungeon to play after re-instantiation
	# (we don't play it here because the battle scene is still up)
	print("[BOSS] Applied pending defeat: %s" % spec)
	# ── EventLog: record boss defeat fact ────────────────────────────────────
	if GameState and "event_log" in GameState and GameState.event_log != null:
		var boss_id: String = spec.get("dungeon_flag", "")
		if boss_id.is_empty():
			var flags: Array = spec.get("story_flags", [])
			boss_id = flags[0] if flags.size() > 0 else "unknown_boss"
		var boss_name: String = boss_id.replace("_defeated", "").replace("_", " ").capitalize()
		var defeat_data: Dictionary = {
			"boss_id":    boss_id,
			"boss_name":  boss_name,
			"map_id":     _current_map_id,
			# Tick 313: world = current_world (where THIS boss was beaten),
			# worlds_unlocked carries progression. See matching comment
			# in _on_party_leveled_up.
			"world":      GameState.current_world,
			"worlds_unlocked": GameState.worlds_unlocked,
		}
		# Tactics snapshot — HOW the player won, not just THAT they won. NPC
		# dialogue prompts pull this from EventLog so future chats can react
		# ("you autobattled your way past the Rat King?"). BattleManager's
		# tracking flags are still live at this point — they reset on the next
		# start_battle, not on end_battle.
		if BattleManager and BattleManager.has_method("get_battle_tactics_snapshot"):
			defeat_data["tactics"] = BattleManager.get_battle_tactics_snapshot()
		GameState.event_log.record(
			EventLog.TYPE_BOSS_DEFEAT,
			"Defeated %s" % boss_name,
			defeat_data
		)
		# Rebalance trigger: a boss victory is a 'curve looks right' signal
		# (or 'too easy' if the player one-shot it). Daemon decides whether
		# to nudge based on the tactics snapshot — opt-in flag gates the
		# whole call so vanilla play isn't affected.
		if GameState.llm_rebalance_enabled and GameState.rebalance_daemon != null:
			var fired: bool = GameState.rebalance_daemon.consider(RebalanceDaemonScript.TRIGGER_BOSS_DEFEAT, defeat_data)
			if fired:
				_kick_off_rebalance_fetch.call_deferred(GameState.rebalance_daemon.pending.size() - 1)
	# One-shot: clear after applying
	GameState.pending_boss_defeat = {}
	# Auto-save immediately after boss flags land. Without this, a crash or
	# quit between victory and the next area transition / 5-min auto-tick
	# loses the boss-defeat flag entirely — and boss fights are the longest,
	# highest-stakes encounters in the game.
	if SaveSystem and SaveSystem.has_method("auto_save"):
		SaveSystem.auto_save()


func _wait_for_confirm() -> void:
	"""Wait for the player to press confirm (A/Z/Enter/mouse click) before continuing"""
	# Small delay so the press that ended the battle doesn't immediately confirm
	await get_tree().create_timer(0.5).timeout
	while true:
		await get_tree().process_frame
		if Input.is_action_just_pressed("ui_accept"):
			break
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			break


func _show_game_over_screen() -> void:
	"""Show the game over screen and handle retry/continue."""
	var game_over = GameOverScreen.new()
	add_child(game_over)

	# Check if a save exists
	var has_save = SaveSystem != null and SaveSystem.has_method("has_save") and SaveSystem.has_save()

	# Array-wrapped flags because GDScript lambdas capture primitives by VALUE.
	var choice_made: Array[bool] = [false]
	var retry: Array[bool] = [true]

	game_over.retry_selected.connect(func():
		choice_made[0] = true
		retry[0] = true
	)
	game_over.continue_selected.connect(func():
		choice_made[0] = true
		retry[0] = false
	)

	await game_over.show_game_over(has_save)

	# Wait for player choice
	while not choice_made[0]:
		await get_tree().process_frame

	game_over.queue_free()

	if retry[0]:
		# Retry the same battle with the same enemy formation
		if _last_battle_enemies.size() > 0:
			# canonical restore: raw is_alive=true carried statuses into the retry AND resurrected permakilled PCs
			for member in party:
				if is_instance_valid(member):
					_restore_duelist(member)
					member.current_ap = 0
			await _start_battle_async(_last_battle_enemies, _last_battle_is_encounter)
			if BattleTransition:
				await BattleTransition.fade_out()
		else:
			# No battle to retry — restart from overworld
			_create_party()
			battles_won = 0
			## Tick 418: also reset the canonical persistent counter
			## on the new-game-after-defeat path.
			if GameState:
				GameState.battles_won = 0
			_set_current_map_id("overworld")
			_spawn_point = "default"
			await _start_exploration()
	else:
		# Continue: Load most recent save and rehydrate the live party from it.
		var loaded = false
		if SaveSystem and SaveSystem.has_method("load_game"):
			var slot = SaveSystem.get_most_recent_slot() if SaveSystem.has_method("get_most_recent_slot") else -1
			if slot >= 0:
				loaded = SaveSystem.load_game(slot)
		if not (loaded and _restore_party_from_save_data()):
			_create_party()
		await _start_exploration()


## Exploration Management

func _start_exploration() -> void:
	"""Start exploration mode (overworld or interior)"""
	# Check for pending story cutscenes before entering free roam
	# Skip if we just played one (prevents back-to-back on same map entry)
	if _cutscene_cooldown:
		_cutscene_cooldown = false
	else:
		var pending = _get_pending_story_cutscene()
		if pending != "":
			await _play_story_cutscene(pending)
			return

	current_state = LoopState.EXPLORATION
	InputLockManager.pop_all()  # Clear any leaked locks from previous state

	# Ensure normal speed in exploration (battle speed is separate)
	Engine.time_scale = 1.0

	# Clean up victory overlay before freeing battle scene (prevents persistence)
	if current_scene and is_instance_valid(current_scene):
		var victory_overlay = current_scene.get_node_or_null("VictoryResults")
		if victory_overlay and is_instance_valid(victory_overlay):
			victory_overlay.free()  # Immediate free, not queue_free

	# Remove old scene
	if current_scene and is_instance_valid(current_scene):
		current_scene.queue_free()
		await current_scene.tree_exited

	# Create exploration scene based on current map
	var exploration_scene: Node = null

	match _current_map_id:
		"overworld":
			exploration_scene = OverworldSceneRes.instantiate()
		"harmonia_village":
			exploration_scene = _create_village_scene()
		"whispering_cave":
			exploration_scene = _create_cave_scene()
		"tavern_interior":
			exploration_scene = _create_tavern_scene()
		"inn_interior":
			exploration_scene = InnInteriorScript.new()
		"shop_interior_item":
			exploration_scene = _create_shop_interior(0)
		"shop_interior_black_magic":
			exploration_scene = _create_shop_interior(1)
		"shop_interior_white_magic":
			exploration_scene = _create_shop_interior(2)
		"shop_interior_blacksmith":
			exploration_scene = _create_shop_interior(3)
		"blacksmith_interior":
			exploration_scene = BlacksmithInteriorScript.new()
		"scriptura_plaza":
			exploration_scene = ScripturaPlazaScript.new()
		"scriptura_guild":
			exploration_scene = ScripturaGuildInteriorScript.new()
		"scriptura_bookshop":
			exploration_scene = ScripturaBookshopInteriorScript.new()
		"harmonia_chapel":
			exploration_scene = HarmoniaChapelInteriorScript.new()
		"harmonia_library":
			exploration_scene = HarmoniaLibraryInteriorScript.new()
		"harmonia_cartographer":
			exploration_scene = HarmoniaCartographerInteriorScript.new()
		"eldertree_hollow":
			exploration_scene = EldertreeHollowTreeInteriorScript.new()
		"eldertree_grafting_house":
			exploration_scene = EldertreeGraftingHouseInteriorScript.new()
		"frosthold_warden_hut":
			exploration_scene = FrostholdWardenHutInteriorScript.new()
		"frosthold_meltwater_clock":
			exploration_scene = FrostholdMeltwaterClockInteriorScript.new()
		"sandrift_glassmaker":
			exploration_scene = SandriftGlassmakerInteriorScript.new()
		"sandrift_rain_ledger":
			exploration_scene = SandriftRainLedgerInteriorScript.new()
		"grimhollow_witch_hut":
			exploration_scene = GrimhollowWitchHutInteriorScript.new()
		"grimhollow_lantern_debt":
			exploration_scene = GrimhollowLanternDebtInteriorScript.new()
		"ironhaven_watchtower":
			exploration_scene = IronhavenWatchtowerInteriorScript.new()
		"ironhaven_strike_registry":
			exploration_scene = IronhavenStrikeRegistryInteriorScript.new()
		"maple_heights_arcade":
			exploration_scene = MapleHeightsArcadeInteriorScript.new()
		"maple_garage_sale":
			exploration_scene = MapleGarageSaleInteriorScript.new()
		"maple_heights_strip_mall":
			exploration_scene = MapleStripMallScript.new()
		"maple_community_center":
			exploration_scene = MapleCommunityCenterInteriorScript.new()
		"enrichment_annex":
			exploration_scene = EnrichmentAnnexInteriorScript.new()
		"brasston_clockwork_loft":
			exploration_scene = BrasstonClockworkLoftInteriorScript.new()
		"brasston_redundancy_archive":
			exploration_scene = BrasstonRedundancyArchiveInteriorScript.new()
		"rivet_row_union_hall":
			exploration_scene = RivetRowUnionHallInteriorScript.new()
		"rivet_row_incident_board":
			exploration_scene = RivetRowIncidentBoardInteriorScript.new()
		"node_prime_daemon_lounge":
			exploration_scene = NodePrimeDaemonLoungeInteriorScript.new()
		"node_prime_cache":
			exploration_scene = NodePrimeCacheInteriorScript.new()
		"vertex_threshold":
			exploration_scene = VertexThresholdInteriorScript.new()
		"frosthold_village":
			exploration_scene = FrostholdVillageScript.new()
		"eldertree_village":
			exploration_scene = EldertreeVillageScript.new()
		"grimhollow_village":
			exploration_scene = GrimhollowVillageScript.new()
		"sandrift_village":
			exploration_scene = SandriftVillageScript.new()
		"ironhaven_village":
			exploration_scene = IronhavenVillageScript.new()
		"ice_dragon_cave":
			exploration_scene = _create_dragon_cave_from_script(IceDragonCaveScript)
		"shadow_dragon_cave":
			exploration_scene = _create_dragon_cave_from_script(ShadowDragonCaveScript)
		"lightning_dragon_cave":
			exploration_scene = _create_dragon_cave_from_script(LightningDragonCaveScript)
		"fire_dragon_cave":
			exploration_scene = _create_dragon_cave_from_script(FireDragonCaveScript)
		"assembly_core":
			exploration_scene = _create_dragon_cave_from_script(AssemblyCoreScript)
		"root_process":
			exploration_scene = _create_dragon_cave_from_script(RootProcessScript)
		"null_chamber":
			exploration_scene = _create_dragon_cave_from_script(NullChamberScript)
		"suburban_underground":
			exploration_scene = _create_dragon_cave_from_script(SuburbanUndergroundScript)
		"castle_harmonia":
			exploration_scene = _create_dragon_cave_from_script(CastleHarmoniaScript)
		"steampunk_mechanism":
			exploration_scene = _create_dragon_cave_from_script(SteampunkMechanismScript)
		"steampunk_overworld":
			exploration_scene = SteampunkOverworldScript.new()
		"suburban_overworld":
			exploration_scene = SuburbanOverworldScript.new()
		"industrial_overworld":
			exploration_scene = IndustrialOverworldScript.new()
		"futuristic_overworld":
			exploration_scene = FuturisticOverworldScript.new()
		"abstract_overworld":
			exploration_scene = AbstractOverworldScript.new()
		"maple_heights_village":
			exploration_scene = MapleHeightsVillageScript.new()
		"brasston_village":
			exploration_scene = BrasstonVillageScript.new()
		"rivet_row_village":
			exploration_scene = RivetRowVillageScript.new()
		"node_prime_village":
			exploration_scene = NodePrimeVillageScript.new()
		"vertex_village":
			exploration_scene = VertexVillageScript.new()
		_:
			exploration_scene = OverworldSceneRes.instantiate()

	add_child(exploration_scene)
	current_scene = exploration_scene
	_exploration_scene = exploration_scene

	# Mount the [L] Party Chat indicator for exploration
	_ensure_party_chat_indicator()

	# Spawn player at correct position
	if exploration_scene.has_method("spawn_player_at"):
		exploration_scene.spawn_player_at(_spawn_point)

	# Tick 309: override the default spawn marker with _player_position
	# when one is pending. Sources: battle-return path (saved live coords
	# pre-battle) and load-from-save path (_restore_party_from_save_data
	# pulls from SaveSystem.pending_player_position). Consumed-and-cleared
	# semantics so subsequent _start_exploration calls without a pending
	# value (e.g. fresh area transitions) use spawn_player_at's marker.
	# Was previously only applied by _return_to_exploration, missing the
	# load-from-save case entirely — saves outside the in-overworld
	# autosave window respawned the player at the dungeon entrance.
	if _player_position != Vector2.ZERO:
		var scene_player = exploration_scene.get("player") if "player" in exploration_scene else null
		if scene_player:
			scene_player.position = _player_position
		_player_position = Vector2.ZERO

	# Set player appearance based on party leader (respects party_leader_index)
	if party.size() > 0:
		var leader_idx = clampi(GameState.party_leader_index, 0, party.size() - 1)
		var leader = party[leader_idx]
		var leader_job = "fighter"
		if leader.job and leader.job is Dictionary:
			leader_job = leader.job.get("id", "fighter")
		elif leader.job is String:
			leader_job = leader.job

		# Try the new appearance method first, fall back to job-only
		if exploration_scene.has_method("set_player_appearance"):
			exploration_scene.set_player_appearance(leader)
		elif exploration_scene.has_method("set_player_job"):
			exploration_scene.set_player_job(leader_job)

	# Connect signals
	if exploration_scene.has_signal("battle_triggered"):
		exploration_scene.battle_triggered.connect(_on_exploration_battle_triggered)
	if exploration_scene.has_signal("area_transition"):
		exploration_scene.area_transition.connect(_on_area_transition)

	# Pre-warm common area sprites in background (deferred to not block scene setup)
	call_deferred("_prewarm_area_sprites")


func _return_to_exploration() -> void:
	"""Return to exploration after battle"""
	# Reset engine time scale to normal (battle speed shouldn't affect overworld)
	Engine.time_scale = 1.0

	# Keep same map, restore player to saved position
	await _start_exploration()

	# Restore player position after scene is fully set up
	if _player_position != Vector2.ZERO and _exploration_scene:
		var player = _exploration_scene.get("player")
		if player:
			player.position = _player_position
			print("[POSITION] Restored player to: %s" % _player_position)
		else:
			push_warning("[POSITION] Could not get player from scene")

	# Clear saved position after restoring
	_player_position = Vector2.ZERO


func _prewarm_battle_sprites(enemies: Array) -> void:
	"""Pre-warm BattleAnimator sprite cache during battle transition.
	This generates and caches sprites while the transition animation plays,
	so they are ready instantly when BattleScene._create_battle_sprites() runs."""
	var monster_ids: Array = []
	for enemy in enemies:
		if enemy is String:
			if enemy not in monster_ids:
				monster_ids.append(enemy)
		elif enemy is Dictionary:
			var eid = enemy.get("id", enemy.get("type", ""))
			if eid != "" and eid not in monster_ids:
				monster_ids.append(eid)

	# Build party job data for pre-warming hero sprites
	var party_jobs: Array = []
	for member in party:
		if is_instance_valid(member):
			var job_id = "fighter"
			if member.job:
				job_id = member.job.get("id", "fighter")
			var weapon_id = member.equipped_weapon if member.equipped_weapon else ""
			party_jobs.append({"job_id": job_id, "weapon_id": weapon_id})

	if monster_ids.size() > 0 or party_jobs.size() > 0:
		print("[PREWARM] Pre-warming sprite cache: %d monsters, %d party members" % [monster_ids.size(), party_jobs.size()])
		BattleAnimator.prewarm_cache(monster_ids, party_jobs)
		print("[PREWARM] Sprite cache pre-warm complete")


func _prewarm_area_sprites() -> void:
	"""Pre-warm common area enemy sprites on scene load for faster first battle."""
	var common_enemies: Array = []
	match _current_map_id:
		"overworld":
			common_enemies = ["slime", "bat", "goblin"]
		"whispering_cave":
			common_enemies = ["bat", "goblin", "skeleton"]
		"ice_dragon_cave":
			common_enemies = ["bat", "skeleton", "ice_dragon"]
		"shadow_dragon_cave":
			common_enemies = ["specter", "skeleton", "shadow_dragon"]
		"lightning_dragon_cave":
			common_enemies = ["goblin", "bat", "lightning_dragon"]
		"fire_dragon_cave":
			common_enemies = ["imp", "skeleton", "fire_dragon"]
		"assembly_core":
			common_enemies = ["conveyor_gremlin", "toxic_sludge", "assembly_line_automaton", "masterite_warden_industrial"]
		"root_process":
			common_enemies = ["rogue_process", "memory_leak", "recursive_loop", "data_wraith", "masterite_arbiter_futuristic"]
		"null_chamber":
			common_enemies = ["null_entity", "forgotten_variable", "empty_set", "the_absence", "masterite_curator_abstract"]
		"suburban_underground":
			common_enemies = ["spiteful_crow", "unassuming_dog", "skate_punk", "cranky_lady", "masterite_warden_suburban"]
		"steampunk_mechanism":
			common_enemies = ["steam_rat", "cog_swarm", "clockwork_sentinel", "brass_golem", "meta_knight"]
		"steampunk_overworld":
			common_enemies = ["clockwork_sentinel", "steam_rat", "brass_golem", "cog_swarm", "pipe_phantom"]
		"suburban_overworld":
			common_enemies = ["new_age_retro_hippie", "spiteful_crow", "skate_punk"]
		"industrial_overworld":
			common_enemies = ["assembly_line_automaton", "rust_elemental", "toxic_sludge"]
		"futuristic_overworld":
			common_enemies = ["rogue_process", "memory_leak", "firewall_sentinel"]
		"abstract_overworld":
			common_enemies = ["null_entity", "forgotten_variable", "empty_set"]
		_:
			if "cave" in _current_map_id:
				common_enemies = ["bat", "skeleton", "imp"]
			elif "village" in _current_map_id:
				common_enemies = []  # Villages are safe zones
			else:
				common_enemies = ["slime", "bat"]
	if common_enemies.size() > 0:
		var enemy_data: Array = []
		for eid in common_enemies:
			enemy_data.append({"id": eid, "type": eid})
		_prewarm_battle_sprites(enemy_data)


func _on_exploration_battle_triggered(enemies: Array, terrain: String = "") -> void:
	"""Handle battle triggered from exploration"""
	print("[GAMELOOP] _on_exploration_battle_triggered called! state=%s enemies=%s" % [current_state, enemies])
	# Guard against battle triggers during non-exploration states
	if current_state != LoopState.EXPLORATION:
		print("[GAMELOOP] BLOCKED — state is %s, not EXPLORATION" % current_state)
		return
	# Guard against battles while menus/UIs are open
	if _overworld_menu and is_instance_valid(_overworld_menu):
		print("[GAMELOOP] BLOCKED — overworld menu is open")
		return
	if _autogrind_ui and is_instance_valid(_autogrind_ui):
		print("[GAMELOOP] BLOCKED — autogrind UI is open")
		return

	# Dead-stop player during transition; pop_all in _start_exploration clears it.
	if InputLockManager:
		InputLockManager.push_lock("encounter_transition")

	# LoopState.BATTLE blocks player movement — set in _start_battle_async after transition.
	# Do NOT set it here — transition needs EXPLORATION state to render the screenshot.

	# NOTE: Do NOT hide the exploration scene here — BattleTransition needs one rendered
	# frame to capture the overworld screenshot. We hide it at transition_midpoint instead,
	# right before instantiating the battle scene behind the overlay.

	# Save terrain for battle background
	if terrain != "":
		_current_terrain = terrain
	else:
		# Infer terrain from map if not provided
		_current_terrain = _get_terrain_for_map(_current_map_id)
	print("[TERRAIN] Battle terrain: %s" % _current_terrain)

	# Save player position and cave floor before battle
	if _exploration_scene:
		var player = _exploration_scene.get("player")
		if player:
			_player_position = player.position
			print("[POSITION] Saved player at: %s" % _player_position)
			# Movement blocked by LoopState.BATTLE — no manual freeze needed

		# Save current floor if in cave (any multi-floor dungeon)
		if "current_floor" in _exploration_scene:
			_current_cave_floor = _exploration_scene.current_floor
			print("[CAVE] Saved floor: %d" % _current_cave_floor)

	# Extract enemy types for transition visual
	var enemy_types: Array = []
	for enemy in enemies:
		if enemy is Dictionary:
			var enemy_type = enemy.get("name", enemy.get("type", enemy.get("id", "unknown")))
			enemy_types.append(enemy_type)
		elif enemy is String:
			# Boss/specific enemy is passed as string ID
			enemy_types.append(enemy)

	print("[GAMELOOP] Battle triggered with enemies: %s" % [enemies])

	if BattleTransition:
		print("[GAMELOOP] Starting battle transition")

		# Run the transition effect (captures screen, plays animation, ends on black)
		await BattleTransition.play_battle_transition(enemy_types)
		print("[GAMELOOP] Battle transition effect complete")

		# hide AFTER the transition captured its screenshot of the scene
		_hide_exploration_scenes()

		# Load battle scene (uses preloaded resource, always available)
		await _start_battle_async(enemies, true)
		print("[GAMELOOP] Battle started")

		# Reveal the battle scene
		await BattleTransition.fade_out()
		print("[GAMELOOP] Fade out complete - battle should be visible")
	else:
		# No transition — load battle directly
		await _start_battle_async(enemies, true)



## Scenes hide via three routes because they parent three ways: tracked ref, MapSystem (/root), or directly under GameLoop
func _hide_exploration_scenes() -> void:
	var hidden_names: Array = []
	if _exploration_scene and is_instance_valid(_exploration_scene):
		_exploration_scene.visible = false
		hidden_names.append(_exploration_scene.name)
	if MapSystem and "current_map" in MapSystem and MapSystem.current_map \
			and is_instance_valid(MapSystem.current_map):
		MapSystem.current_map.visible = false
		hidden_names.append("map:" + str(MapSystem.current_map.name))
	for child in get_children():
		if child is Node2D and not child.name.begins_with("BattleScene"):
			child.visible = false
			hidden_names.append(str(child.name))
	print("[GAMELOOP] Exploration hidden — %d scene(s): %s" % [hidden_names.size(), str(hidden_names)])


func _start_battle_async(specific_enemies: Array = [], is_encounter: bool = false) -> void:
	"""Start battle using async-loaded scene"""
	current_state = LoopState.BATTLE
	_remove_party_chat_indicator()
	# every battle-entry path funnels through here — sweep once, not per call site
	_hide_exploration_scenes()

	# Save battle config for retry
	_last_battle_enemies = specific_enemies.duplicate()
	_last_battle_is_encounter = is_encounter

	# Remove old scene
	if current_scene and is_instance_valid(current_scene):
		current_scene.queue_free()
		await current_scene.tree_exited

	# Clear stale exploration reference (scene is freed)
	_exploration_scene = null

	# Reset viewport camera to prevent exploration zoom from contaminating battle
	var viewport = get_viewport()
	if viewport:
		var cam = viewport.get_camera_2d()
		if cam and is_instance_valid(cam):
			cam.zoom = Vector2(1.0, 1.0)

	# Extract enemy IDs from mixed formats (String or Dict)
	var enemy_ids: Array = []
	for entry in specific_enemies:
		if entry is String:
			enemy_ids.append(entry)
		elif entry is Dictionary:
			enemy_ids.append(entry.get("type", entry.get("id", "slime")))

	var has_enemies = enemy_ids.size() > 0

	# Check if this is a miniboss battle (every 3rd battle), but not if forced enemies
	var is_miniboss_battle = not has_enemies and (battles_won + 1) % 3 == 0 and battles_won > 0

	# Use preloaded battle scene (always available, no race conditions)
	var battle_scene = BattleSceneRes.instantiate()

	# Set flags and party BEFORE adding to tree (since _ready() uses these)
	battle_scene.managed_by_game_loop = true
	battle_scene.set_party(party)

	# Route enemies to the correct BattleScene property
	if has_enemies and is_encounter:
		# Random encounter from exploration — use encounter_enemies path
		battle_scene.encounter_enemies = enemy_ids
		print("[ENCOUNTER] Spawning encounter enemies: %s" % [enemy_ids])
		battle_scene.set_terrain(_current_terrain)
	elif has_enemies:
		# Boss/scripted battle — use forced_enemies path
		battle_scene.forced_enemies = enemy_ids
		print("[BOSS] Forcing specific enemies: %s" % [enemy_ids])
		battle_scene.set_terrain("boss")
	elif is_miniboss_battle:
		battle_scene.force_miniboss = true
		print("[MINIBOSS] Battle %d - A miniboss approaches!" % (battles_won + 1))
		battle_scene.set_terrain(_current_terrain)
	else:
		# Regular battle - use current terrain
		battle_scene.set_terrain(_current_terrain)

	add_child(battle_scene)
	current_scene = battle_scene

	# Wait for battle scene to be fully ready before proceeding
	await get_tree().process_frame
	print("[GAMELOOP] BattleScene added - visible: %s, in tree: %s, parent: %s" % [battle_scene.visible, battle_scene.is_inside_tree(), battle_scene.get_parent().name])

	# Connect to battle end
	BattleManager.battle_ended.connect(_on_battle_ended, CONNECT_ONE_SHOT)


func _on_teleport_requested(target_map: String, spawn_point: String) -> void:
	"""Handle debug teleport from overworld menu"""
	# Close the overworld menu first
	_on_overworld_menu_closed()
	# Then transition
	_on_area_transition(target_map, spawn_point)


func _on_settings_teleport_requested(target_map: String, spawn_point: String) -> void:
	"""Handle debug teleport from settings menu.
	The settings_menu emits `closed` BEFORE `teleport_requested` (see
	SettingsMenu._on_teleport_chosen) so its CanvasLayer is already
	queue-freed by the time we arrive here. We just need to fire the
	transition. Mirrors _on_teleport_requested but skips the overworld-
	menu close path."""
	if _exploration_scene and _exploration_scene.has_method("resume"):
		_exploration_scene.resume()
	_on_area_transition(target_map, spawn_point)


func _area_fade_to_black() -> void:
	"""Fade the area-transition overlay to opaque black (0.3s). Generic fallback."""
	if not _area_fade_rect:
		return
	var tween = create_tween()
	tween.tween_property(_area_fade_rect, "modulate:a", 1.0, 0.3)
	await tween.finished


func _area_fade_from_black() -> void:
	"""Fade the area-transition overlay back to transparent (0.3s). Generic fallback."""
	if not _area_fade_rect:
		return
	var tween = create_tween()
	tween.tween_property(_area_fade_rect, "modulate:a", 0.0, 0.3)
	await tween.finished


## Interior map_ids — stepping into one of these should use the
## quick interior transition, not the dramatic "Arriving at..." wipe
## meant for entering a new village from the overworld.
const INTERIOR_MAP_IDS: PackedStringArray = [
	"harmonia_chapel", "harmonia_library", "tavern_interior",
	"eldertree_hollow", "frosthold_warden_hut", "sandrift_glassmaker",
	"grimhollow_witch_hut", "ironhaven_watchtower",
	"maple_heights_arcade", "brasston_clockwork_loft",
	"rivet_row_union_hall", "node_prime_daemon_lounge",
	"vertex_threshold",
	# W2 quest interiors (forms_in_triplicate / relocated / fine_print).
	"maple_community_center", "enrichment_annex",
	# Generic village-scene interiors reused across all 11 villages —
	# routed by VillageInn / VillageShop's transition_triggered emission.
	"inn_interior",
	"shop_interior_item", "shop_interior_black_magic",
	"shop_interior_white_magic", "shop_interior_blacksmith",
	# Dedicated forge-experience scene (atmospheric, not the shop UI).
	"blacksmith_interior",
	# Scriptura capital-district interiors (Guild + bookshop).
	"scriptura_guild", "scriptura_bookshop",
	# Village-interior expansion: Cartographer's Attic (Harmonia PPP building)
	# + the Grafting House (Eldertree GGG garden) + the Strike Registry
	# (Ironhaven MMM building).
	"harmonia_cartographer", "eldertree_grafting_house", "ironhaven_strike_registry",
	"frosthold_meltwater_clock", "sandrift_rain_ledger", "grimhollow_lantern_debt",
	"maple_garage_sale", "brasston_redundancy_archive", "rivet_row_incident_board",
	"node_prime_cache",
]


func _get_transition_type(map_id: String) -> String:
	"""Classify destination into interior, cave, village, overworld, or generic."""
	if map_id in INTERIOR_MAP_IDS:
		return "interior"
	var t = map_id.to_lower()
	if "cave" in t or "dungeon" in t:
		return "cave"
	if "village" in t or "town" in t or "heights" in t or "row" in t \
			or "prime" in t or "vertex" in t or "brasston" in t \
			or "harmonia" in t or "tavern" in t or "frosthold" in t \
			or "eldertree" in t or "grimhollow" in t or "sandrift" in t \
			or "ironhaven" in t or "scriptura_plaza" in t:
		return "village"
	if "overworld" in t or t == "overworld":
		return "overworld"
	return "generic"


func _get_location_display_name(map_id: String) -> String:
	"""Return the human-readable name from locations.json, or a formatted fallback."""
	var file = FileAccess.open("res://data/locations.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data = json.data
			if data is Dictionary:
				for key in data:
					var entry = data[key]
					if entry is Dictionary and entry.get("map_id", key) == map_id:
						return entry.get("name", map_id.replace("_", " ").capitalize())
		file.close()
	return map_id.replace("_", " ").capitalize()


func _make_location_label(text: String, layer: CanvasLayer) -> Label:
	"""Create a centred location-name label styled to the game aesthetic."""
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.78))
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.modulate.a = 0.0
	layer.add_child(lbl)
	return lbl


func _area_cave_transition_in(location_name: String) -> void:
	"""Stone-door slam effect: dim then two rects close from top and bottom."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_to_black()
		return

	# door_close SFX layers under the stone-door slam animation (cowir-sfx msg 2165)
	if SoundManager:
		SoundManager.play_ui("door_close")

	var screen_size = get_viewport().get_visible_rect().size

	# Dim phase (0.25s)
	var dim_tween = create_tween()
	dim_tween.tween_property(_area_fade_rect, "modulate:a", 0.55, 0.25)
	await dim_tween.finished

	# Create top and bottom stone door rects
	var top_door = ColorRect.new()
	top_door.color = Color(0.08, 0.07, 0.09)
	top_door.size = Vector2(screen_size.x, screen_size.y * 0.5 + 4)
	top_door.position = Vector2(0, -screen_size.y * 0.5 - 4)
	_area_fade_layer.add_child(top_door)

	var bottom_door = ColorRect.new()
	bottom_door.color = Color(0.08, 0.07, 0.09)
	bottom_door.size = Vector2(screen_size.x, screen_size.y * 0.5 + 4)
	bottom_door.position = Vector2(0, screen_size.y)
	_area_fade_layer.add_child(bottom_door)

	# Door slam (0.35s) — ease in for weight
	var slam_tween = create_tween()
	slam_tween.set_parallel(true)
	slam_tween.tween_property(top_door, "position:y", 0.0, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	slam_tween.tween_property(bottom_door, "position:y", screen_size.y * 0.5, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await slam_tween.finished

	# Snap base rect to full black so it covers when doors are removed later
	_area_fade_rect.modulate.a = 1.0

	# Location label fade in
	var lbl = _make_location_label("Entering " + location_name + "...", _area_fade_layer)
	var lbl_tween = create_tween()
	lbl_tween.tween_property(lbl, "modulate:a", 1.0, 0.2)
	await lbl_tween.finished
	await get_tree().create_timer(0.35).timeout

	# Clean up doors and label (base rect stays black)
	top_door.queue_free()
	bottom_door.queue_free()
	lbl.queue_free()


func _area_cave_transition_out() -> void:
	"""Stone doors open vertically to reveal the cave."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_from_black()
		return

	var screen_size = get_viewport().get_visible_rect().size

	# Create doors starting in closed position
	var top_door = ColorRect.new()
	top_door.color = Color(0.08, 0.07, 0.09)
	top_door.size = Vector2(screen_size.x, screen_size.y * 0.5 + 4)
	top_door.position = Vector2(0, 0)
	_area_fade_layer.add_child(top_door)

	var bottom_door = ColorRect.new()
	bottom_door.color = Color(0.08, 0.07, 0.09)
	bottom_door.size = Vector2(screen_size.x, screen_size.y * 0.5 + 4)
	bottom_door.position = Vector2(0, screen_size.y * 0.5)
	_area_fade_layer.add_child(bottom_door)

	_area_fade_rect.modulate.a = 0.0  # Let doors carry the black

	# Open doors (0.45s) — ease out for smooth reveal
	var open_tween = create_tween()
	open_tween.set_parallel(true)
	open_tween.tween_property(top_door, "position:y", -screen_size.y * 0.5 - 4, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	open_tween.tween_property(bottom_door, "position:y", screen_size.y, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await open_tween.finished

	top_door.queue_free()
	bottom_door.queue_free()


func _area_village_transition_in(location_name: String) -> void:
	"""Warm amber horizontal wipe left-to-right."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_to_black()
		return

	var screen_size = get_viewport().get_visible_rect().size

	# Amber wipe bar — starts off-screen left
	var wipe = ColorRect.new()
	wipe.color = Color(0.72, 0.48, 0.12)
	wipe.size = Vector2(screen_size.x * 1.1, screen_size.y)
	wipe.position = Vector2(-screen_size.x * 1.1, 0)
	_area_fade_layer.add_child(wipe)

	# Trailing black fill that follows the wipe
	var fill = ColorRect.new()
	fill.color = Color(0.04, 0.03, 0.02)
	fill.size = Vector2(screen_size.x * 1.1, screen_size.y)
	fill.position = Vector2(-screen_size.x * 2.1, 0)
	_area_fade_layer.add_child(fill)

	_area_fade_rect.modulate.a = 0.0

	var wipe_tween = create_tween()
	wipe_tween.set_parallel(true)
	wipe_tween.tween_property(wipe, "position:x", screen_size.x, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	wipe_tween.tween_property(fill, "position:x", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await wipe_tween.finished

	# Snap base rect to full black, remove wipe bar
	_area_fade_rect.modulate.a = 1.0
	wipe.queue_free()
	fill.queue_free()

	# Show location label with animated dots
	var lbl = _make_location_label("Arriving at " + location_name + "...", _area_fade_layer)
	var lbl_tween = create_tween()
	lbl_tween.tween_property(lbl, "modulate:a", 1.0, 0.18)
	await lbl_tween.finished
	await get_tree().create_timer(0.38).timeout
	lbl.queue_free()


func _area_village_transition_out() -> void:
	"""Reverse amber wipe: right-to-left to reveal village."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_from_black()
		return

	var screen_size = get_viewport().get_visible_rect().size

	var wipe = ColorRect.new()
	wipe.color = Color(0.72, 0.48, 0.12)
	wipe.size = Vector2(screen_size.x * 1.1, screen_size.y)
	wipe.position = Vector2(-screen_size.x * 0.05, 0)
	_area_fade_layer.add_child(wipe)

	_area_fade_rect.modulate.a = 0.0

	var wipe_tween = create_tween()
	wipe_tween.tween_property(wipe, "position:x", screen_size.x * 1.1, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await wipe_tween.finished

	wipe.queue_free()


func _area_interior_transition_in(location_name: String) -> void:
	"""Quick black fade with a subtle bottom-left room label. Distinct
	from the dramatic village wipe — the player is stepping into a
	small room within the village they already know, not arriving at
	a new town."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_to_black()
		return

	# door_open SFX cues the interior threshold (cowir-sfx msg 2165)
	if SoundManager:
		SoundManager.play_ui("door_open")

	var fade_tween = create_tween()
	fade_tween.tween_property(_area_fade_rect, "modulate:a", 1.0, 0.20).set_ease(Tween.EASE_IN)
	await fade_tween.finished

	# Subtle small label in the lower-left — just the room name, no prefix.
	var lbl = Label.new()
	lbl.text = location_name
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.80, 0.70))
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.position = Vector2(32, get_viewport().get_visible_rect().size.y - 56)
	lbl.modulate.a = 0.0
	_area_fade_layer.add_child(lbl)
	var lbl_tween = create_tween()
	lbl_tween.tween_property(lbl, "modulate:a", 1.0, 0.12)
	await lbl_tween.finished
	await get_tree().create_timer(0.22).timeout
	lbl.queue_free()


func _area_interior_transition_out() -> void:
	"""Quick black fade-out to reveal the interior. ~half the duration
	of village fade — the room should feel close at hand."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_from_black()
		return
	var fade_tween = create_tween()
	fade_tween.tween_property(_area_fade_rect, "modulate:a", 0.0, 0.18).set_ease(Tween.EASE_OUT)
	await fade_tween.finished


func _area_overworld_transition_in() -> void:
	"""Circular iris-out: screen shrinks to a point at center, hold black."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_to_black()
		return

	# Use a shader-based approach via a SubViewport is complex; instead we approximate
	# an iris with radial segments drawn via a Control's _draw, using a tween on a
	# custom property. As a clean fallback we use a fast vignette fade instead.
	# True circle masking in Godot without shaders needs a CanvasItem shader or
	# a SubViewport which is too heavy for a transition. We use concentric rects
	# growing inward to approximate the iris closing.
	var screen_size = get_viewport().get_visible_rect().size
	var cx = screen_size.x * 0.5
	var cy = screen_size.y * 0.5

	# Four black rects collapsing toward center from all four sides
	# (no anchor preset on left_r — explicit size/position is correct,
	# and PRESET_FULL_RECT would fight the tween that animates size:x).
	var left_r = ColorRect.new()
	left_r.color = Color.BLACK
	left_r.size = Vector2(cx, screen_size.y)
	left_r.position = Vector2(0, 0)
	left_r.pivot_offset = Vector2(0, 0)

	var right_r = ColorRect.new()
	right_r.color = Color.BLACK
	right_r.size = Vector2(cx, screen_size.y)
	right_r.position = Vector2(screen_size.x, 0)

	var top_r = ColorRect.new()
	top_r.color = Color.BLACK
	top_r.size = Vector2(screen_size.x, cy)
	top_r.position = Vector2(0, 0)

	var bottom_r = ColorRect.new()
	bottom_r.color = Color.BLACK
	bottom_r.size = Vector2(screen_size.x, cy)
	bottom_r.position = Vector2(0, screen_size.y)

	for r in [left_r, right_r, top_r, bottom_r]:
		r.modulate.a = 0.0
		_area_fade_layer.add_child(r)

	_area_fade_rect.modulate.a = 0.0

	var dur = 0.5
	var iris_tween = create_tween()
	iris_tween.set_parallel(true)
	# Fade in all four and slide them inward simultaneously
	iris_tween.tween_property(left_r, "modulate:a", 1.0, dur * 0.3)
	iris_tween.tween_property(right_r, "modulate:a", 1.0, dur * 0.3)
	iris_tween.tween_property(top_r, "modulate:a", 1.0, dur * 0.3)
	iris_tween.tween_property(bottom_r, "modulate:a", 1.0, dur * 0.3)
	iris_tween.tween_property(left_r, "size:x", cx, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	iris_tween.tween_property(right_r, "position:x", cx, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	iris_tween.tween_property(top_r, "size:y", cy, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	iris_tween.tween_property(bottom_r, "position:y", cy, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await iris_tween.finished

	# Snap full black, clean up rects
	_area_fade_rect.modulate.a = 1.0
	left_r.queue_free()
	right_r.queue_free()
	top_r.queue_free()
	bottom_r.queue_free()

	# Hold black briefly
	await get_tree().create_timer(0.2).timeout


func _area_overworld_transition_out() -> void:
	"""Iris opens from center revealing the overworld (0.5s)."""
	if not _area_fade_rect or not _area_fade_layer:
		await _area_fade_from_black()
		return

	var screen_size = get_viewport().get_visible_rect().size
	var cx = screen_size.x * 0.5
	var cy = screen_size.y * 0.5

	var left_r = ColorRect.new()
	left_r.color = Color.BLACK
	left_r.size = Vector2(cx, screen_size.y)
	left_r.position = Vector2(0, 0)

	var right_r = ColorRect.new()
	right_r.color = Color.BLACK
	right_r.size = Vector2(cx, screen_size.y)
	right_r.position = Vector2(cx, 0)

	var top_r = ColorRect.new()
	top_r.color = Color.BLACK
	top_r.size = Vector2(screen_size.x, cy)
	top_r.position = Vector2(0, 0)

	var bottom_r = ColorRect.new()
	bottom_r.color = Color.BLACK
	bottom_r.size = Vector2(screen_size.x, cy)
	bottom_r.position = Vector2(0, cy)

	for r in [left_r, right_r, top_r, bottom_r]:
		_area_fade_layer.add_child(r)

	_area_fade_rect.modulate.a = 0.0

	var dur = 0.5
	var iris_tween = create_tween()
	iris_tween.set_parallel(true)
	iris_tween.tween_property(left_r, "position:x", -cx, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	iris_tween.tween_property(right_r, "position:x", screen_size.x, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	iris_tween.tween_property(top_r, "position:y", -cy, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	iris_tween.tween_property(bottom_r, "position:y", screen_size.y, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await iris_tween.finished

	left_r.queue_free()
	right_r.queue_free()
	top_r.queue_free()
	bottom_r.queue_free()


var _transition_in_progress: bool = false

func _on_area_transition(target_map: String, spawn_point: String) -> void:
	"""Handle contextual area transition based on destination type."""
	if _transition_in_progress:
		return
	_transition_in_progress = true

	# R2 (scene-change abort): kill any in-flight NPC dialogue LLM requests so a
	# slow inference from the OLD map can't resolve into the NEW scene (stale
	# bubble / wrong-NPC line). LLMService is an autoload that lands late in the
	# boot order, so guard the lookup. GameLoop does not hold a reference to the
	# active DynamicConversation — cancel_all is sufficient: the conversation's
	# _safe await path takes its null fallback and its own teardown clears UI.
	var _llm := get_node_or_null("/root/LLMService")
	if _llm and _llm.has_method("cancel_all"):
		_llm.cancel_all("scene_change")
	# Idempotent UI/movement reset for any active conversation (cancel_all only
	# unblocks awaits — the choice menu + frozen player needed an explicit abort).
	if _llm and _llm.has_method("abort_all_conversations"):
		_llm.abort_all_conversations()

	# If an interior is asking to "return to the village we came from", resolve
	# the magic token to the saved origin map. Falls back to overworld if we
	# somehow never set one (e.g. dev jump).
	if target_map == "village_return":
		if _village_origin_id != "":
			target_map = _village_origin_id
			# The interior's spawn name (inn_exit / shop_exit) is specific to
			# interior types, but villages won't have those spawn points
			# registered. Substitute a name the village does know.
			spawn_point = "default"
		else:
			target_map = "overworld"
			spawn_point = "default"

	# Capture origin if entering an interior so its exit can route back.
	if target_map in INTERIOR_MAP_IDS:
		# Don't overwrite if we're already inside an interior (interior→interior
		# isn't a thing today, but if it ever happens, keep the original village).
		if not (_current_map_id in INTERIOR_MAP_IDS):
			_village_origin_id = _current_map_id

	_set_current_map_id(target_map)
	_spawn_point = spawn_point
	_player_position = Vector2.ZERO
	_current_terrain = _get_terrain_for_map(target_map)

	var transition_type = _get_transition_type(target_map)
	var display_name = _get_location_display_name(target_map)

	# Hold a movement lock through the fade-out: _start_exploration sets
	# state=EXPLORATION and pops all locks, so without this the player
	# can press D-pad and start walking before the fade-out reveals the
	# new scene. Push AFTER _start_exploration in each arm so pop_all
	# doesn't clobber it. The pop in the safety cleanup block below
	# also covers exception paths.
	match transition_type:
		"cave":
			await _area_cave_transition_in(display_name)
			await _start_exploration()
			InputLockManager.push_lock("area_transition_fade")
			await _area_cave_transition_out()
		"village":
			await _area_village_transition_in(display_name)
			await _start_exploration()
			InputLockManager.push_lock("area_transition_fade")
			await _area_village_transition_out()
		"interior":
			await _area_interior_transition_in(display_name)
			await _start_exploration()
			InputLockManager.push_lock("area_transition_fade")
			await _area_interior_transition_out()
		"overworld":
			await _area_overworld_transition_in()
			await _start_exploration()
			InputLockManager.push_lock("area_transition_fade")
			await _area_overworld_transition_out()
		_:
			await _area_fade_to_black()
			await _start_exploration()
			InputLockManager.push_lock("area_transition_fade")
			await _area_fade_from_black()
	# Release the fade lock — the new scene is now fully visible.
	InputLockManager.pop_lock("area_transition_fade")

	# Safety cleanup: ensure fade overlay is transparent and no stale children remain
	if _area_fade_rect:
		_area_fade_rect.modulate.a = 0.0
	if _area_fade_layer:
		for child in _area_fade_layer.get_children():
			if child != _area_fade_rect:
				child.queue_free()
	_transition_in_progress = false

	# ── EventLog: record area transition fact ────────────────────────────────
	var area_ctx: Dictionary = {}
	if GameState and "event_log" in GameState and GameState.event_log != null:
		var area_display_name: String = _get_location_display_name(target_map)
		area_ctx = {
			"map_id":      target_map,
			"spawn_point": spawn_point,
			# Tick 313: world = current_world (the new area's world),
			# worlds_unlocked carries progression. See matching comment
			# in _on_party_leveled_up.
			"world":       GameState.current_world,
			"worlds_unlocked": GameState.worlds_unlocked,
		}
		GameState.event_log.record(
			EventLog.TYPE_AREA_ENTERED,
			"Entered %s" % area_display_name,
			area_ctx,
		)
	# Tick 252: fire the matching RebalanceDaemon trigger so daemon gets
	# the area-transition signal it was designed to react to (not just
	# the wipe/defeat/level_up triggers). TRIGGER_AREA_ENTERED was
	# defined but unfired before this — the daemon's min_consideration
	# _interval_sec throttle prevents flooding when the player chains
	# transitions.
	if GameState and GameState.llm_rebalance_enabled and GameState.rebalance_daemon != null:
		var fired: bool = GameState.rebalance_daemon.consider(
			RebalanceDaemonScript.TRIGGER_AREA_ENTERED, area_ctx)
		if fired:
			_kick_off_rebalance_fetch.call_deferred(
				GameState.rebalance_daemon.pending.size() - 1)

	# Auto-save on zone transition (villages/overworld only; dungeons use save points;
	# interiors skipped — MapSystem.current_map_id is stale for them).
	# SaveSystem.save_completed signal drives the Toast via _on_any_save_completed.
	if transition_type != "interior" and SaveSystem and SaveSystem.has_method("auto_save"):
		SaveSystem.auto_save()


func _take_screenshot() -> void:
	"""Save a screenshot to user://screenshots/ with timestamp"""
	var img = get_viewport().get_texture().get_image()
	if not img:
		print("[SCREENSHOT] Failed to capture viewport")
		return
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path = "user://screenshots/screenshot_%s.png" % timestamp
	img.save_png(path)
	var abs_path = ProjectSettings.globalize_path(path)
	print("[SCREENSHOT] Saved: %s" % abs_path)
	# Flash feedback
	var flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0.5)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var tween = create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.2)
	tween.tween_callback(flash.queue_free)


func _quick_save_with_toast() -> void:
	"""F2 hotkey: quick-save to the dedicated quicksave slot with toast feedback.
	Blocked mid-battle (via can_quick_save) AND during autogrind — the
	autogrind run statistics and rule state would be lost on a mid-grind
	save and the user would be confused why autogrind didn't resume.
	Tick 80: also blocked during area-transition fade (in or out) — the
	scene swap is in flight, _current_map_id was updated but the scene
	itself isn't loaded yet, so the save would capture inconsistent state."""
	if not SaveSystem:
		return
	if not SaveSystem.has_method("quick_save"):
		return
	if current_state == LoopState.AUTOGRIND:
		Toast.show_warning(self, "Cannot quick-save during autogrind — stop grinding first")
		return
	if _in_exploration_transition():
		Toast.show_warning(self, "Cannot quick-save mid-transition — wait for the scene to settle")
		return
	if not SaveSystem.can_quick_save():
		Toast.show_warning(self, "Cannot quick-save right now")
		return
	var ok: bool = SaveSystem.quick_save()
	if ok:
		# save_completed signal drives the standard Toast; we add nothing here
		# to avoid double-toasting. (See _on_any_save_completed connection in _ready.)
		print("[QUICKSAVE] F2 — quick save committed")
	else:
		Toast.show_warning(self, "Quick-save failed")


func _quick_load_with_toast() -> void:
	"""F3 hotkey: load most recent save with toast feedback.
	Returns to overworld via the same _restore_party_from_save_data path
	used by Continue. Only works if a save exists.
	Blocked during active battle AND during autogrind — mid-grind load
	would corrupt the run statistics and the autogrind state machine.
	Tick 80: also blocked during area-transition fade — loading would
	collide with the in-flight scene swap (MapSystem.load_map racing
	against GameLoop's direct-scene routing for the destination map)."""
	if not SaveSystem:
		return
	if not SaveSystem.has_method("load_game"):
		return
	if BattleManager and BattleManager.is_battle_active():
		Toast.show_warning(self, "Cannot quick-load mid-battle")
		return
	if current_state == LoopState.AUTOGRIND:
		Toast.show_warning(self, "Cannot quick-load during autogrind — stop grinding first")
		return
	if _in_exploration_transition():
		Toast.show_warning(self, "Cannot quick-load mid-transition — wait for the scene to settle")
		return
	var slot: int = SaveSystem.get_most_recent_slot() if SaveSystem.has_method("get_most_recent_slot") else -1
	if slot < 0:
		Toast.show_warning(self, "No save to load")
		return
	var ok: bool = SaveSystem.load_game(slot)
	if not ok:
		Toast.show_warning(self, "Quick-load failed")
		return
	# Rehydrate party + transition into the saved map (mirrors Continue path).
	if not _restore_party_from_save_data():
		Toast.show_warning(self, "Save data could not restore party")
		return
	Toast.show_success(self, "Loaded slot %d" % slot)
	# If we're already exploring, restart exploration to teleport the player
	# to the saved position. If not (e.g. in autogrind UI), do nothing more —
	# the next exploration entry picks up the loaded state.
	if current_state == LoopState.EXPLORATION:
		_start_exploration()


func _get_terrain_for_map(map_id: String) -> String:
	"""Get the terrain type for a given map ID"""
	match map_id:
		"overworld":
			return "plains"
		"whispering_cave":
			return "cave"
		"harmonia_village", "tavern_interior", "harmonia_chapel", "harmonia_library", "harmonia_cartographer":
			return "village"
		"eldertree_hollow", "eldertree_grafting_house":
			return "forest"
		"frosthold_warden_hut", "frosthold_meltwater_clock":
			return "ice"
		"sandrift_glassmaker", "sandrift_rain_ledger":
			return "desert"
		"grimhollow_witch_hut", "grimhollow_lantern_debt":
			return "swamp"
		"ironhaven_watchtower", "ironhaven_strike_registry":
			return "volcanic"
		"maple_heights_arcade", "maple_garage_sale":
			return "suburban"
		"brasston_clockwork_loft", "brasston_redundancy_archive":
			return "steampunk"
		"rivet_row_union_hall", "rivet_row_incident_board":
			return "industrial"
		"node_prime_daemon_lounge", "node_prime_cache":
			return "digital"
		"vertex_threshold":
			return "abstract"
		"frosthold_village":
			return "ice"
		"eldertree_village":
			return "forest"
		"grimhollow_village":
			return "swamp"
		"sandrift_village":
			return "desert"
		"ironhaven_village":
			return "volcanic"
		"ice_dragon_cave":
			return "ice_cave"
		"shadow_dragon_cave":
			return "dark_cave"
		"lightning_dragon_cave":
			return "storm_cave"
		"fire_dragon_cave":
			return "lava_cave"
		"assembly_core":
			return "industrial"
		"root_process":
			return "digital"
		"null_chamber":
			return "void"
		"suburban_underground":
			return "cave"
		"steampunk_mechanism":
			return "steampunk"
		"steampunk_overworld":
			return "steampunk"
		"suburban_overworld":
			return "suburban"
		"industrial_overworld":
			return "industrial"
		"futuristic_overworld":
			return "digital"
		"abstract_overworld":
			return "void"
		# Tick 88: W2-W6 villages map to their WORLD's terrain string,
		# not generic "village". Pre-fix, a battle triggered inside Maple
		# Heights (e.g. from a story cutscene) got the medieval village
		# backdrop instead of the suburban art — visual inconsistency
		# breaking the W2-W6 world identity.
		"maple_heights_village":
			return "suburban"
		"brasston_village":
			return "steampunk"
		"rivet_row_village":
			return "industrial"
		"node_prime_village":
			return "digital"
		"vertex_village":
			return "void"
		# Tick 360: castle_harmonia (W1 final boss arena, indoor stone
		# setting) was falling through to the `_:` default and returning
		# "plains" because no substring keyword matched. Players fought
		# Chancellor Mordaine in front of a plains background instead of
		# a medieval indoor scene. Maps to "village" — same terrain the
		# other medieval indoor spaces use (harmonia_chapel,
		# harmonia_library) for visual continuity.
		"castle_harmonia":
			return "village"
		_:
			if "cave" in map_id or "dungeon" in map_id:
				return "cave"
			elif "castle" in map_id:
				# Tick 360: keyword guard for future castle-style arenas
				# (e.g., castle_<world> if added) so they default to the
				# village-style medieval background instead of plains.
				return "village"
			elif "village" in map_id or "town" in map_id:
				return "village"
			elif "forest" in map_id:
				return "forest"
			return "plains"


func _create_village_scene() -> Node:
	"""Create Harmonia Village scene (the starter village, extends BaseVillage)."""
	return HarmoniaVillageRes.instantiate()


func _create_cave_scene() -> Node:
	"""Create Whispering Cave scene and restore floor state"""
	var cave_scene = WhisperingCaveRes.instantiate()
	if _current_cave_floor > 1 and "current_floor" in cave_scene:
		cave_scene.current_floor = _current_cave_floor
		print("[CAVE] Restoring to floor %d" % _current_cave_floor)
	return cave_scene


func _create_script_scene(script_path: String) -> Node:
	"""Create a scene from a GDScript that self-constructs in _ready()"""
	var ScriptRes = load(script_path)
	if ScriptRes:
		return ScriptRes.new()
	push_warning("%s not found, falling back to overworld" % script_path)
	return OverworldSceneRes.instantiate()


func _create_dragon_cave(script_path: String) -> Node:
	"""Create a dragon cave scene and restore floor state"""
	var ScriptRes = load(script_path)
	if ScriptRes:
		var cave_scene = ScriptRes.new()
		# Restore the floor we were on before battle
		if _current_cave_floor > 1 and "current_floor" in cave_scene:
			cave_scene.current_floor = _current_cave_floor
			print("[CAVE] Restoring to floor %d" % _current_cave_floor)
		return cave_scene
	push_warning("%s not found, falling back to overworld" % script_path)
	return OverworldSceneRes.instantiate()


func _create_dragon_cave_from_script(script_res: GDScript) -> Node:
	"""Create a dragon cave scene from a preloaded script and restore floor state"""
	var cave_scene = script_res.new()
	if _current_cave_floor > 1 and "current_floor" in cave_scene:
		cave_scene.current_floor = _current_cave_floor
		print("[CAVE] Restoring to floor %d" % _current_cave_floor)
	return cave_scene


func _create_tavern_scene() -> Node:
	"""Create The Dancing Tonberry tavern interior scene"""
	return TavernInteriorScript.new()


func _create_shop_interior(shop_type_value: int) -> Node:
	"""Instantiate ShopInterior with the right shop_type and a sensible name.

	`shop_type_value` mirrors VillageShop.ShopType:
	  0 = ITEM, 1 = BLACK_MAGIC, 2 = WHITE_MAGIC, 3 = BLACKSMITH
	The scene self-themes (palette, decoration, NPCs) from this value.
	"""
	var scene = ShopInteriorScript.new()
	scene.shop_type = shop_type_value
	# Default per-type names — outdoor shop instances can pass their own
	# via a future override hook, but for now generic names work everywhere.
	match shop_type_value:
		0: scene.shop_name = "Mystic Remedies"
		1: scene.shop_name = "The Arcanum"
		2: scene.shop_name = "Chapel of Light"
		3: scene.shop_name = "Ironclad Arms"
		_: scene.shop_name = "Shop"
	return scene


## Equipment Pool Management

func _init_equipment_pool() -> void:
	"""Initialize equipment pool with extra items"""
	equipment_pool = {
		"weapons": ["bronze_sword", "wooden_staff"],
		"armors": ["cloth_robe", "iron_armor"],
		"accessories": ["hp_amulet", "speed_boots"]
	}


func get_available_equipment(slot: String) -> Array:
	"""Get list of equipment available in pool for a slot type"""
	var pool_key = slot + "s"  # weapon -> weapons, armor -> armors
	if slot == "accessory":
		pool_key = "accessories"
	return equipment_pool.get(pool_key, [])


func equip_from_pool(combatant: Combatant, slot: String, item_id: String) -> bool:
	"""Equip item from pool to combatant, return old item to pool"""
	var pool_key = slot + "s"
	if slot == "accessory":
		pool_key = "accessories"

	# Check if item is in pool
	if item_id not in equipment_pool.get(pool_key, []):
		return false

	# Get current equipped item
	var old_item: String = ""
	match slot:
		"weapon":
			old_item = combatant.equipped_weapon
		"armor":
			old_item = combatant.equipped_armor
		"accessory":
			old_item = combatant.equipped_accessory

	# Remove new item from pool
	equipment_pool[pool_key].erase(item_id)

	# Add old item to pool if it exists
	if old_item and old_item != "":
		equipment_pool[pool_key].append(old_item)

	# Equip new item
	match slot:
		"weapon":
			EquipmentSystem.equip_weapon(combatant, item_id)
		"armor":
			EquipmentSystem.equip_armor(combatant, item_id)
		"accessory":
			EquipmentSystem.equip_accessory(combatant, item_id)

	return true


func unequip_to_pool(combatant: Combatant, slot: String) -> bool:
	"""Unequip item from combatant and return to pool"""
	var pool_key = slot + "s"
	if slot == "accessory":
		pool_key = "accessories"

	var item_id: String = ""
	match slot:
		"weapon":
			item_id = combatant.equipped_weapon
			combatant.equipped_weapon = ""
		"armor":
			item_id = combatant.equipped_armor
			combatant.equipped_armor = ""
		"accessory":
			item_id = combatant.equipped_accessory
			combatant.equipped_accessory = ""

	if item_id and item_id != "":
		equipment_pool[pool_key].append(item_id)
		combatant.recalculate_stats()
		return true

	return false


## Autogrind System

func _open_autogrind_ui() -> void:
	"""Open the autogrind configuration UI overlay"""
	if _autogrind_ui and is_instance_valid(_autogrind_ui):
		return  # Already open

	# Pause exploration
	if _exploration_scene and _exploration_scene.has_method("pause"):
		_exploration_scene.pause()

	# Create UI overlay in CanvasLayer
	_autogrind_ui_layer = CanvasLayer.new()
	_autogrind_ui_layer.layer = 50
	add_child(_autogrind_ui_layer)

	var AutogrindUIClass = load("res://src/ui/autogrind/AutogrindUI.gd")
	_autogrind_ui = AutogrindUIClass.new()
	_autogrind_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_autogrind_ui_layer.add_child(_autogrind_ui)

	# Get region name from current map
	var region_name = _current_map_id.replace("_", " ").capitalize()
	_autogrind_ui.setup(party, region_name)

	# Connect signals
	_autogrind_ui.closed.connect(_on_autogrind_ui_closed)
	_autogrind_ui.grind_requested.connect(_start_autogrind)
	_autogrind_ui.grind_resume_requested.connect(_resume_autogrind)
	_autogrind_ui.grind_stop_requested.connect(_on_autogrind_stop_requested)
	_autogrind_ui.tier_cycle_requested.connect(_on_ui_tier_cycle_requested)

	SoundManager.play_ui("menu_open")
	print("[AUTOGRIND] Config UI opened")


func _on_autogrind_ui_closed() -> void:
	"""Handle autogrind UI close"""
	if _autogrind_ui and is_instance_valid(_autogrind_ui):
		_autogrind_ui.queue_free()
		_autogrind_ui = null
	if _autogrind_ui_layer and is_instance_valid(_autogrind_ui_layer):
		_autogrind_ui_layer.queue_free()
		_autogrind_ui_layer = null

	# If not grinding, resume exploration
	if not _is_autogrinding:
		if _exploration_scene and _exploration_scene.has_method("resume"):
			_exploration_scene.resume()


func _start_autogrind(config: Dictionary) -> void:
	"""Start the autogrind session"""
	current_state = LoopState.AUTOGRIND
	_is_autogrinding = true

	# Create controller
	var AutogrindControllerClass = load("res://src/autogrind/AutogrindController.gd")
	_autogrind_controller = AutogrindControllerClass.new()
	add_child(_autogrind_controller)

	# Connect controller signals
	_autogrind_controller.grind_battle_requested.connect(_on_grind_battle_requested)
	_autogrind_controller.grind_complete.connect(_on_grind_complete)
	_autogrind_controller.grind_paused.connect(_on_autogrind_paused)
	_autogrind_controller.grind_resumed.connect(_on_autogrind_resumed)
	_autogrind_controller.tier_changed.connect(_on_autogrind_tier_changed)
	_autogrind_controller.region_advanced.connect(_on_autogrind_region_advanced)
	if not AutogrindSystem.region_rotation_suggested.is_connected(_on_autogrind_region_rotation_suggested):
		AutogrindSystem.region_rotation_suggested.connect(_on_autogrind_region_rotation_suggested)
	if not AutogrindSystem.corruption_threshold_crossed.is_connected(_on_autogrind_corruption_band):
		AutogrindSystem.corruption_threshold_crossed.connect(_on_autogrind_corruption_band)

	# Start grinding
	_autogrind_controller.start_grind(party, config, _current_terrain)

	# Clear battle summary ring buffer for new session
	_autogrind_battle_summaries.clear()

	# Switch to dedicated autogrind ambient music
	SoundManager.reset_corruption()
	SoundManager.play_music("autogrind")

	# Show appropriate controller overlay
	if _autogrind_controller.headless_mode:
		_show_controller_overlay(ControllerOverlay.autogrind_ludicrous_context())
		_show_autogrind_dashboard()
		TutorialHints.show(self, "ludicrous_speed")
	else:
		_show_controller_overlay(ControllerOverlay.autogrind_context())

	# Tutorial hint on first autogrind session
	TutorialHints.show(self, "autogrind")

	print("[AUTOGRIND] Session started%s" % (" (LUDICROUS SPEED)" if _autogrind_controller.headless_mode else ""))


func _on_autogrind_stop_requested() -> void:
	"""Handle stop request from UI"""
	_stop_autogrind("Manual stop")


func _stop_autogrind(reason: String) -> void:
	"""Stop the autogrind session"""
	if not _is_autogrinding:
		return

	_is_autogrinding = false

	# Capture stats before controller is stopped and freed
	var final_stats = {}
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		final_stats = _autogrind_controller.get_grind_stats()

	# Clear snapshot on clean stop (user chose to stop)
	AutogrindSystem.clear_grind_snapshot()

	# Disconnect stale battle_ended signal if we stopped mid-battle
	if BattleManager.battle_ended.is_connected(_on_autogrind_battle_ended):
		BattleManager.battle_ended.disconnect(_on_autogrind_battle_ended)

	# Stop controller
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		_autogrind_controller.stop_grind(reason)
		_autogrind_controller.queue_free()
		_autogrind_controller = null

	# Update UI state
	if _autogrind_ui and is_instance_valid(_autogrind_ui):
		_autogrind_ui.set_grinding(false)

	# Reset turbo mode
	BattleManager.turbo_mode = false

	# Clean up dashboard
	if _autogrind_dashboard and is_instance_valid(_autogrind_dashboard):
		_autogrind_dashboard.queue_free()
		_autogrind_dashboard = null

	# Clean up compact overlay
	_destroy_autogrind_overlay()
	_destroy_controller_overlay()

	# Reset engine speed
	Engine.time_scale = 1.0

	# Restore clean audio state and resume area music
	SoundManager.reset_corruption()
	SoundManager.play_area_music(_current_map_id)

	# Play interrupt SFX based on stop reason
	_play_grind_stop_sfx(reason)
	_show_grind_stop_notification(reason)

	print("[AUTOGRIND] Session stopped: %s" % reason)

	# If a BattleScene is still the active scene (grind stopped between/after a battle),
	# tear it down and return to exploration. The AutogrindUI lives on its own CanvasLayer
	# and is not indicative of the active scene — during a grind it stays instantiated but hidden.
	# MUST await — _return_to_exploration is async; firing the summary
	# before the scene swap completes causes a black-summary flash on
	# slow scene-load platforms (Android web through Brave especially).
	if not _exploration_scene or not is_instance_valid(_exploration_scene):
		await _return_to_exploration()
	else:
		current_state = LoopState.EXPLORATION
		InputLockManager.pop_all()  # Clear any leaked locks

	_show_autogrind_summary(final_stats, reason)


func _on_grind_battle_requested(enemies: Array, terrain: String) -> void:
	"""Handle battle request from autogrind controller"""
	# Save player position before battle
	if _exploration_scene:
		var player = _exploration_scene.get("player")
		if player:
			_player_position = player.position

	# Set terrain
	_current_terrain = terrain

	# Headless mode: resolve instantly without BattleScene
	if _autogrind_controller and is_instance_valid(_autogrind_controller) and _autogrind_controller.headless_mode:
		_resolve_headless_battle(enemies)
		return

	# Start battle without transition animation (fast chain)
	await _start_autogrind_battle(enemies)


func _resolve_headless_battle(enemy_data: Array) -> void:
	var resolver = HeadlessBattleResolver.new()

	var enemies: Array = []
	for data in enemy_data:
		var enemy = Combatant.new()
		var stats = data.get("stats", {})
		enemy.initialize({
			"name": data.get("name", "Enemy"),
			"max_hp": stats.get("max_hp", 50),
			"max_mp": stats.get("max_mp", 20),
			"attack": stats.get("attack", 10),
			"defense": stats.get("defense", 8),
			"magic": stats.get("magic", 5),
			"speed": stats.get("speed", 8)
		})
		# Live spawns (BattleEnemySpawner) always set this; its absence here silently
		# no-opped bestiary defeat-credit AND drop lookup for the whole ludicrous path.
		var mtype: String = str(data.get("id", ""))
		if mtype != "":
			enemy.set_meta("monster_type", mtype)
		enemies.append(enemy)

	var result = resolver.resolve_battle(party, enemies)
	var victory = result.get("victory", false)
	var exp_gained = result.get("exp_gained", 0)
	# Tick 342: pick up gold_gained too — the resolver (tick 341) pre-applied
	# gold_multiplier, so we just forward as-is.
	var gold_gained_headless: int = int(result.get("gold_gained", 0))
	var rounds = result.get("rounds", 0)
	var headless_item_drops: Dictionary = result.get("item_drops", {})
	var headless_rare_drops: Array = result.get("rare_drops", [])

	for e in enemies:
		e.free()

	# Route resolver-rolled drops the same way BattleManager does live: equipment
	# → shared pool, consumables → party leader. Rare drops flip the same Glow
	# flag + interrupt-condition flag the live path fires.
	if victory:
		for item_id in headless_item_drops:
			var qty: int = int(headless_item_drops[item_id])
			if not BattleManager.route_drop_to_equipment_pool(item_id):
				if party.size() > 0 and party[0].is_alive:
					party[0].add_item(item_id, qty)
		for rd in headless_rare_drops:
			if PartyChatSystem:
				PartyChatSystem.fire_event_flag("event_flag_rare_drop_found")
			AutogrindSystem.notify_rare_drop(str(rd.get("item", "")), float(rd.get("chance", 0.0)))

	# Heal party using items (same as visual battle path)
	if victory:
		for member in party:
			member.current_ap = 0
			if member.is_alive and member.current_hp < member.max_hp:
				_autogrind_heal_member(member)
			if member.is_alive and member.current_mp < member.max_mp * 0.5:
				_autogrind_restore_mp(member)

	# Track per-character EXP distribution (headless path)
	if victory and exp_gained > 0:
		var alive_count = 0
		for member in party:
			if member is Combatant and member.is_alive:
				alive_count += 1
		if alive_count > 0:
			var per_char_exp = exp_gained / alive_count
			for member in party:
				if member is Combatant and member.is_alive:
					AutogrindSystem.track_character_exp(member.combatant_name, per_char_exp)

	# Forward to controller with headless-computed EXP + gold (tick 342:
	# gold was previously dropped — empty items_gained dict meant the
	# autogrind player got zero gold despite total_gold display).
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		var items_gained: Dictionary = {"gold": gold_gained_headless}
		for item_id in headless_item_drops:
			items_gained[item_id] = int(headless_item_drops[item_id])
		_autogrind_controller.on_battle_ended(victory, exp_gained, items_gained)

		var stats = _autogrind_controller.get_grind_stats()

		# Build summary for console ring buffer
		var summary_text: String
		if victory:
			summary_text = "[color=#44ff44]#%d Victory[/color] +%d EXP (%d rounds) [color=#cc88ff]HEADLESS[/color]" % [stats.get("battles_won", 0), exp_gained, rounds]
			var drop_count: int = 0
			for item_id in headless_item_drops:
				drop_count += int(headless_item_drops[item_id])
			if drop_count > 0:
				summary_text += " [color=#ffcc44]+%d item%s[/color]" % [drop_count, "s" if drop_count > 1 else ""]
		else:
			summary_text = "[color=#ff4444]#%d Defeat[/color] (%d rounds) [color=#cc88ff]HEADLESS[/color]" % [stats.get("battles_won", 0), rounds]
		_autogrind_battle_summaries.append(summary_text)
		if _autogrind_battle_summaries.size() > 50:
			_autogrind_battle_summaries.remove_at(0)

		# Update UI with latest stats
		if _autogrind_ui and is_instance_valid(_autogrind_ui):
			_autogrind_ui.update_stats(stats)
			_autogrind_ui.update_party_status()

		# Update dashboard if in Tier 2
		if _autogrind_dashboard and is_instance_valid(_autogrind_dashboard):
			var region_id = _current_map_id.replace(" ", "_").to_lower()
			_autogrind_dashboard.refresh(stats, region_id)
			_autogrind_dashboard.add_battle_result(victory, rounds, exp_gained)

		# Corruption audio degradation
		var corruption_raw = AutogrindSystem.meta_corruption_level
		var corruption_threshold = AutogrindSystem.corruption_threshold
		var corruption_norm = clamp(corruption_raw / max(corruption_threshold, 0.001), 0.0, 1.0)
		SoundManager.set_corruption_intensity(corruption_norm)

		# Milestone toasts
		var battles = stats.get("battles_won", 0)
		if battles in [10, 20, 30, 50, 100]:
			_show_autogrind_toast(_get_milestone_text(battles))


func _show_autogrind_transition() -> void:
	var battle_num = 0
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		var stats = _autogrind_controller.get_grind_stats()
		battle_num = stats.get("battles_won", 0) + 1

	var speed_text = ""
	if BattleManager.turbo_mode:
		speed_text = "TURBO"
	else:
		var speed_idx = BattleSceneScript._battle_speed_index
		var labels = BattleSceneScript.BATTLE_SPEED_LABELS
		if speed_idx < labels.size():
			speed_text = labels[speed_idx]

	var layer = CanvasLayer.new()
	layer.layer = 95
	add_child(layer)

	var overlay = ColorRect.new()
	overlay.color = Color(0.02, 0.01, 0.05, 0.9)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)

	var battle_label = Label.new()
	battle_label.text = "BATTLE #%d" % battle_num
	battle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	battle_label.set_anchors_preset(Control.PRESET_CENTER)
	battle_label.add_theme_font_size_override("font_size", 32)
	battle_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
	battle_label.position = Vector2(-100, -30)
	battle_label.size = Vector2(200, 40)
	layer.add_child(battle_label)

	if speed_text != "":
		var speed_label = Label.new()
		speed_label.text = speed_text
		speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		speed_label.set_anchors_preset(Control.PRESET_CENTER)
		speed_label.add_theme_font_size_override("font_size", 20)
		var color = Color(0.9, 0.3, 0.3) if speed_text == "TURBO" else Color(0.4, 0.9, 0.4)
		speed_label.add_theme_color_override("font_color", color)
		speed_label.position = Vector2(-60, 10)
		speed_label.size = Vector2(120, 30)
		layer.add_child(speed_label)

	var tween = create_tween()
	tween.tween_property(overlay, "color:a", 0.0, 0.25).set_delay(0.05)
	tween.parallel().tween_property(battle_label, "modulate:a", 0.0, 0.2).set_delay(0.1)
	tween.tween_callback(layer.queue_free)


func _start_autogrind_battle(enemy_data: Array) -> void:
	"""Start a battle scene with pre-configured autogrind enemies"""
	_show_autogrind_transition()

	# Remove old scene
	if current_scene and is_instance_valid(current_scene):
		current_scene.queue_free()
		await current_scene.tree_exited

	# Create battle scene using preloaded resource (avoids redundant disk load)
	var battle_scene = BattleSceneRes.instantiate()

	# Configure for autogrind
	battle_scene.managed_by_game_loop = true
	battle_scene.set_party(party)
	battle_scene.autogrind_enemy_data = enemy_data
	battle_scene.set_terrain(_current_terrain)

	add_child(battle_scene)
	current_scene = battle_scene

	# Set turbo mode based on tier
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		var tier = _autogrind_controller.get_current_tier()
		# Both tiers use turbo for fastest execution
		battle_scene.turbo_mode = true
		BattleManager.turbo_mode = true

	# Wait for scene to be ready
	await get_tree().process_frame

	# Enable autogrind console mode (replaces battle log with grind stats feed)
	battle_scene.enable_autogrind_console()

	# Replay recent battle summaries into the new console
	for summary_line in _autogrind_battle_summaries:
		battle_scene.autogrind_console_log(summary_line)

	# Show current stats block
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		battle_scene.update_autogrind_console_stats(_autogrind_controller.get_grind_stats())

	# Connect to battle end with autogrind handler
	BattleManager.battle_ended.connect(_on_autogrind_battle_ended, CONNECT_ONE_SHOT)


func _on_autogrind_battle_ended(victory: bool) -> void:
	"""Handle battle end during autogrind"""
	if not _is_autogrinding:
		# Autogrind was stopped during battle
		_on_battle_ended(victory)
		return

	# Heal party between battles
	var exp_gained = 0
	var items_gained = {}

	if victory:
		# Calculate base EXP from defeated enemies (estimate from enemy stats)
		for enemy in BattleManager.enemy_party:
			if enemy is Combatant:
				exp_gained += int(enemy.max_hp * 0.5 + enemy.attack * 2)
		# Tick 340: apply game_constants["exp_multiplier"] so Scriptweaver
		# nudges and RebalanceDaemon proposals actually affect autogrind
		# EXP gains. Pre-fix the live-autogrind path used the raw enemy-
		# stat formula directly — so an exp_multiplier of 2.0 set via the
		# rebalance system doubled normal-battle EXP but had ZERO effect
		# on autogrind farms (the system that grinds the most). Mirrors
		# BattleManager line ~431's defensive clampf pattern.
		var exp_mult: float = 1.0
		if GameState and "game_constants" in GameState:
			exp_mult = clampf(
				float(GameState.game_constants.get("exp_multiplier", 1.0)),
				0.1, 10.0)
		exp_gained = int(exp_gained * exp_mult)
		# Tick 342: compute + forward gold from defeated enemies. Pre-fix
		# items_gained stayed {} so AutogrindSystem.on_battle_victory's
		# gold tracking (line ~516) summed zeros — player got EXP from
		# autogrind but ZERO actual gold despite the "total_gold" display
		# counter implying otherwise. Same enemy-stat formula as
		# HeadlessBattleResolver._build_results (max_hp * 0.3 + defense)
		# and the same gold_multiplier clampf pattern.
		var gold_gained_live: int = 0
		for enemy in BattleManager.enemy_party:
			if enemy is Combatant:
				gold_gained_live += int(enemy.max_hp * 0.3 + enemy.defense)
		var gold_mult: float = 1.0
		if GameState and "game_constants" in GameState:
			gold_mult = clampf(
				float(GameState.game_constants.get("gold_multiplier", 1.0)),
				0.1, 10.0)
		items_gained["gold"] = int(gold_gained_live * gold_mult)

		# BattleManager already routed these drops to inventory; without this merge
		# the live path reported 0 items in total_items_gained while headless (drop
		# parity fix) reported correctly — dashboard/summary counts diverged by tier.
		for drop_entry in BattleManager.get_battle_results().get("item_drops", []):
			var drop_id: String = str(drop_entry.get("item", ""))
			if drop_id != "":
				items_gained[drop_id] = int(items_gained.get(drop_id, 0)) + int(drop_entry.get("qty", 1))

		# Feed battle action summary into adaptive AI pattern learning
		var region_id = AutogrindSystem.current_region_id
		if not region_id.is_empty():
			var battle_summary = BattleManager._summarize_battle_actions()
			AutogrindSystem.update_learned_patterns(region_id, battle_summary)

		# Heal party using items (no free healing)
		for member in party:
			member.current_ap = 0
			if member.is_alive and member.current_hp < member.max_hp:
				_autogrind_heal_member(member)
			if member.is_alive and member.current_mp < member.max_mp * 0.5:
				_autogrind_restore_mp(member)

	# Track per-character EXP distribution
	if victory and exp_gained > 0:
		var alive_count = 0
		for member in party:
			if member is Combatant and member.is_alive:
				alive_count += 1
		if alive_count > 0:
			var per_char_exp = exp_gained / alive_count
			for member in party:
				if member is Combatant and member.is_alive:
					AutogrindSystem.track_character_exp(member.combatant_name, per_char_exp)

	# Forward to controller
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		_autogrind_controller.on_battle_ended(victory, exp_gained, items_gained)

		var stats = _autogrind_controller.get_grind_stats()

		# Build one-line battle summary for the console ring buffer
		var rounds = BattleManager.current_round
		var summary_text: String
		if victory:
			summary_text = "[color=#44ff44]#%d Victory[/color] +%d EXP (%d rounds)" % [stats.get("battles_won", 0), exp_gained, rounds]
			if BattleManager._one_shot_achieved:
				summary_text += " [color=#ffaa00]ONE-SHOT![/color]"
		else:
			summary_text = "[color=#ff4444]#%d Defeat[/color] (%d rounds)" % [stats.get("battles_won", 0), rounds]
		_autogrind_battle_summaries.append(summary_text)
		if _autogrind_battle_summaries.size() > 50:
			_autogrind_battle_summaries.remove_at(0)

		# Check for new injuries and warn
		var prev_injuries = stats.get("injuries_this_session", 0)
		AutogrindSystem.check_new_injuries()
		var cur_injuries = AutogrindSystem.injuries_this_session
		if cur_injuries > prev_injuries:
			_autogrind_battle_summaries.append("[color=#ff4444]PERMANENT INJURY sustained! Check party status.[/color]")
			if _autogrind_battle_summaries.size() > 50:
				_autogrind_battle_summaries.remove_at(0)
			_show_autogrind_toast("PERMANENT INJURY! A party member took lasting damage.")

		# Update UI with latest stats
		if _autogrind_ui and is_instance_valid(_autogrind_ui):
			_autogrind_ui.update_stats(stats)
			_autogrind_ui.update_party_status()

		# Update dashboard if in Tier 2
		if _autogrind_dashboard and is_instance_valid(_autogrind_dashboard):
			var region_id = _current_map_id.replace(" ", "_").to_lower()
			_autogrind_dashboard.refresh(stats, region_id)

		# Update corruption audio degradation based on current meta-corruption level
		var corruption_raw = AutogrindSystem.meta_corruption_level
		var corruption_threshold = AutogrindSystem.corruption_threshold
		var corruption_norm = clamp(corruption_raw / max(corruption_threshold, 0.001), 0.0, 1.0)
		SoundManager.set_corruption_intensity(corruption_norm)

		# Monster adaptation feedback — warn when enemies level up
		var adapt_level = AutogrindSystem.monster_adaptation_level
		var adapt_battles = AutogrindSystem.battles_completed
		# Adaptation thresholds: level 1 at 5 battles, level 2 at 10, level 3 at 20
		if adapt_battles in [5, 10, 20]:
			var adapt_msg = ""
			if adapt_battles == 5:
				adapt_msg = "[color=#ffaa44]Enemies are studying your patterns...[/color]"
			elif adapt_battles == 10:
				adapt_msg = "[color=#ff8844]Enemies have adapted! Stats +%.0f%%[/color]" % (adapt_level * 15)
			elif adapt_battles == 20:
				adapt_msg = "[color=#ff4444]FULLY ADAPTED! Enemies counter your strategies![/color]"
			_autogrind_battle_summaries.append(adapt_msg)
			if _autogrind_battle_summaries.size() > 50:
				_autogrind_battle_summaries.remove_at(0)
			SoundManager.play_ui("adaptation_warning")

		# Milestone toast notifications
		var battles = stats.get("battles_won", 0)
		if battles in [10, 20, 30, 50, 100]:
			_show_autogrind_toast(_get_milestone_text(battles))

		# Auto-save snapshot every 5 battles for crash recovery
		if battles > 0 and battles % 5 == 0:
			_autogrind_save_snapshot()

		# Log any fatigue event that fired this cycle to the console
		if AutogrindSystem.fatigue_events_triggered > 0:
			var last_fatigue = AutogrindSystem.fatigue_events_triggered
			if current_scene and is_instance_valid(current_scene) and current_scene.has_method("autogrind_console_log"):
				current_scene.autogrind_console_log("[color=#ff8844][FATIGUE #%d] Check system stability[/color]" % last_fatigue)

		# Update battle log on dashboard
		if _autogrind_dashboard and is_instance_valid(_autogrind_dashboard) and _autogrind_dashboard.has_method("add_battle_result"):
			_autogrind_dashboard.add_battle_result(victory, BattleManager.current_round, exp_gained)


func _on_grind_complete(reason: String) -> void:
	"""Handle autogrind session completion"""
	_is_autogrinding = false
	current_state = LoopState.EXPLORATION
	InputLockManager.pop_all()  # Clear any leaked locks

	# Disconnect stale battle_ended signal if grind ended mid-battle
	if BattleManager.battle_ended.is_connected(_on_autogrind_battle_ended):
		BattleManager.battle_ended.disconnect(_on_autogrind_battle_ended)

	# Capture stats before controller is freed
	var final_stats = {}
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		final_stats = _autogrind_controller.get_grind_stats()

	# Clean up controller
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		_autogrind_controller.queue_free()
		_autogrind_controller = null

	# Clean up dashboard
	if _autogrind_dashboard and is_instance_valid(_autogrind_dashboard):
		_autogrind_dashboard.queue_free()
		_autogrind_dashboard = null

	# Clean up compact overlay
	_destroy_autogrind_overlay()
	_destroy_controller_overlay()

	# Reset turbo mode
	BattleManager.turbo_mode = false

	# Reset engine speed
	Engine.time_scale = 1.0

	# Update UI state (hidden in background during a session)
	if _autogrind_ui and is_instance_valid(_autogrind_ui):
		_autogrind_ui.set_grinding(false)

	# If a BattleScene is still the active scene (rule-triggered stop between battles,
	# pre_battle_check interrupt, party wipe, etc.), tear it down and return to exploration.
	# Otherwise the player is stranded in an empty BattleScene with no enemies.
	# MUST await — see _on_battle_ended for the same web/mobile black-screen
	# race when the follow-up code fires before the scene swap completes.
	if not _exploration_scene or not is_instance_valid(_exploration_scene):
		await _return_to_exploration()

	# Play interrupt SFX based on stop reason
	_play_grind_stop_sfx(reason)
	_show_grind_stop_notification(reason)

	print("[AUTOGRIND] Grind complete: %s" % reason)
	_show_autogrind_summary(final_stats, reason)


func _play_grind_stop_sfx(reason: String) -> void:
	"""Play an appropriate sound effect for the autogrind stop reason."""
	var reason_lower = reason.to_lower()
	if "hp" in reason_lower or "health" in reason_lower:
		SoundManager.play_ui("grind_stop_hp")
	elif "died" in reason_lower or "death" in reason_lower or "dead" in reason_lower or "wipe" in reason_lower:
		SoundManager.play_ui("grind_stop_death")
	elif "corruption" in reason_lower or "collapse" in reason_lower:
		SoundManager.play_ui("grind_stop_corruption")
	elif "manual" in reason_lower:
		SoundManager.play_ui("grind_stop_manual")
	else:
		SoundManager.play_ui("grind_stop_generic")


## Full-screen flash + OS taskbar attention + loud sting so the player notices the grind stop even when tabbed out.
## Manual stops skip the fanfare — the player already knows.
func _show_grind_stop_notification(reason: String) -> void:
	if "manual" in reason.to_lower():
		return
	SoundManager.play_ui("autogrind_stop_sting")
	# No-op on headless / unsupported platforms.
	if DisplayServer.has_method("window_request_attention"):
		DisplayServer.window_request_attention()

	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)

	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.95, 0.35, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)

	var banner_bg := ColorRect.new()
	banner_bg.color = Color(0.0, 0.0, 0.0, 0.6)
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x == 0:
		vp_size = Vector2(1280, 720)
	banner_bg.position = Vector2(0, vp_size.y * 0.42)
	banner_bg.size = Vector2(vp_size.x, 56)
	banner_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(banner_bg)

	var banner_lbl := Label.new()
	banner_lbl.text = "AUTOGRIND STOPPED — %s" % reason.to_upper()
	banner_lbl.position = Vector2(0, vp_size.y * 0.42 + 16)
	banner_lbl.size = Vector2(vp_size.x, 24)
	banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_lbl.add_theme_font_size_override("font_size", 22)
	banner_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	banner_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(banner_lbl)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "color:a", 0.55, 0.12)
	tween.chain().tween_property(flash, "color:a", 0.0, 0.55)
	tween.chain().tween_callback(func():
		if is_instance_valid(layer):
			layer.queue_free()
	)


func _show_autogrind_summary(stats: Dictionary, reason: String) -> void:
	if _autogrind_summary and is_instance_valid(_autogrind_summary):
		return

	var summary_layer = CanvasLayer.new()
	summary_layer.layer = 60
	add_child(summary_layer)

	var AutogrindSummaryClass = load("res://src/ui/autogrind/AutogrindSummary.gd")
	_autogrind_summary = AutogrindSummaryClass.new()
	_autogrind_summary.set_anchors_preset(Control.PRESET_FULL_RECT)
	summary_layer.add_child(_autogrind_summary)

	_autogrind_summary.setup(stats, reason)
	_autogrind_summary.dismissed.connect(func():
		summary_layer.queue_free()
		_autogrind_summary = null
	)


func _on_autogrind_tier_changed(new_tier: int) -> void:
	if new_tier == 1:  # DASHBOARD
		SoundManager.play_ui("tier_zoom_out")
		_show_autogrind_dashboard()
		if _autogrind_overlay and is_instance_valid(_autogrind_overlay):
			_autogrind_overlay.visible = false
	else:  # ACCELERATED
		SoundManager.play_ui("tier_zoom_in")
		_hide_autogrind_dashboard()
		if _autogrind_overlay and is_instance_valid(_autogrind_overlay):
			_autogrind_overlay.visible = true

	if _autogrind_ui and is_instance_valid(_autogrind_ui):
		_autogrind_ui.on_tier_changed(new_tier)


func _toggle_autogrind_pause() -> void:
	"""Toggle pause/resume on the autogrind session."""
	if not _autogrind_controller or not is_instance_valid(_autogrind_controller):
		return

	if _autogrind_controller.is_paused():
		_autogrind_controller.resume_grind()
	else:
		_autogrind_controller.pause_grind()


func _on_autogrind_paused() -> void:
	"""Handle autogrind session pause."""
	# Return to exploration while paused so the player can move around.
	# MUST await — see _on_battle_ended; the summary overlay update
	# below otherwise fires against a half-loaded scene on Android web.
	if not _exploration_scene or not is_instance_valid(_exploration_scene):
		await _return_to_exploration()

	# Update overlay to show paused state
	var summary = _autogrind_overlay.get_node_or_null("SummaryLabel") if _autogrind_overlay and is_instance_valid(_autogrind_overlay) else null
	if summary:
		summary.text = "|| PAUSED — Press P to Resume"
		summary.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))

	_show_autogrind_toast("Autogrind paused. Press P to resume.")
	SoundManager.play_ui("grind_stop_manual")
	print("[AUTOGRIND] Session paused")


func _on_autogrind_resumed() -> void:
	"""Handle autogrind session resume."""
	var summary = _autogrind_overlay.get_node_or_null("SummaryLabel") if _autogrind_overlay and is_instance_valid(_autogrind_overlay) else null
	if summary:
		summary.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))

	SoundManager.play_ui("autobattle_on")
	SoundManager.play_music("autogrind")
	print("[AUTOGRIND] Session resumed")


func _on_autogrind_region_advanced(from_region: String, to_region: String, world_num: int) -> void:
	"""Handle auto-advance to next world region during autogrind."""
	_set_current_map_id(to_region)
	_current_terrain = to_region
	if has_node("/root/GameState"):
		GameState.current_world = world_num

	var world_names = {
		1: "Medieval", 2: "Suburban", 3: "Steampunk",
		4: "Industrial", 5: "Futuristic", 6: "Abstract"
	}
	var world_name = world_names.get(world_num, "World %d" % world_num)

	# Visual warp transition
	_show_region_warp_transition(world_num, world_name)

	# Add to battle log
	_autogrind_battle_summaries.append("[color=#ff88ff]>>> ADVANCED TO WORLD %d: %s <<<[/color]" % [world_num, world_name.to_upper()])
	if _autogrind_battle_summaries.size() > 50:
		_autogrind_battle_summaries.remove_at(0)

	# Update dashboard if active
	if _autogrind_dashboard and is_instance_valid(_autogrind_dashboard):
		var stats = _autogrind_controller.get_grind_stats() if _autogrind_controller and is_instance_valid(_autogrind_controller) else {}
		_autogrind_dashboard.refresh(stats, to_region)

	# Play tier transition sound for the warp feel
	SoundManager.play_ui("tier_zoom_out")

	# Tutorial hint on first world transition
	TutorialHints.show(self, "world_transition")

	print("[AUTOGRIND] Region advanced: %s -> %s (World %d)" % [from_region, to_region, world_num])


func _on_autogrind_corruption_band(band: String, level: float) -> void:
	# One toast per band crossed this session — the signal is already deduped per band by AutogrindSystem.
	var msg: String
	match band:
		"warning":
			msg = "Corruption warning — reality is thinning (%.2f / 5.0)" % level
		"danger":
			msg = "Corruption DANGER — meta-boss risk high (%.2f / 5.0)" % level
		"critical":
			msg = "Corruption CRITICAL — collapse imminent (%.2f / 5.0)" % level
		_:
			msg = "Corruption %s — %.2f / 5.0" % [band, level]
	_show_autogrind_toast(msg)
	_autogrind_battle_summaries.append("[color=#ff6688]>>> CORRUPTION %s: %.2f / 5.0 <<<[/color]" % [band.to_upper(), level])
	if _autogrind_battle_summaries.size() > 50:
		_autogrind_battle_summaries.remove_at(0)


func _on_autogrind_region_rotation_suggested(current_region_id: String, suggested: Dictionary, adaptation_level: float) -> void:
	# Advisory toast — no auto-move; player decides. Fires at most once per region per session (dedup lives in AutogrindSystem).
	var world_names := {
		1: "Medieval", 2: "Suburban", 3: "Steampunk",
		4: "Industrial", 5: "Futuristic", 6: "Abstract"
	}
	var msg: String
	if suggested.is_empty():
		msg = "Adaptation %.1f — monsters here have adapted. No new region available." % adaptation_level
	else:
		var zone_name: String = str(suggested.get("name", suggested.get("region", "next zone")))
		msg = "Consider moving to %s — monsters here have adapted (Adapt %.1f)" % [zone_name, adaptation_level]
	_show_autogrind_toast(msg)
	_autogrind_battle_summaries.append("[color=#ffaa44]>>> ADAPTATION ADVISORY: %s <<<[/color]" % msg)
	if _autogrind_battle_summaries.size() > 50:
		_autogrind_battle_summaries.remove_at(0)
	SoundManager.play_ui("menu_move")
	print("[AUTOGRIND] Region rotation suggested: %s -> %s (adaptation %.2f)" % [current_region_id, suggested.get("region", "n/a"), adaptation_level])


func _show_region_warp_transition(world_num: int, world_name: String) -> void:
	"""Cinematic warp overlay when auto-advancing to a new world region."""
	var layer = CanvasLayer.new()
	layer.layer = 90
	add_child(layer)

	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x == 0:
		vp_size = Vector2(1280, 720)

	# Flash overlay
	var flash = ColorRect.new()
	flash.color = Color(1.0, 1.0, 1.0, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(flash)

	# Dark backdrop for text
	var backdrop = ColorRect.new()
	backdrop.color = Color(0.02, 0.01, 0.05, 0.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)

	# "REGION CRACKED" title
	var title = Label.new()
	title.text = "REGION CRACKED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, vp_size.y * 0.35)
	title.size = Vector2(vp_size.x, 40)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	title.modulate.a = 0.0
	layer.add_child(title)

	# World name subtitle
	var subtitle = Label.new()
	subtitle.text = "Warping to World %d: %s" % [world_num, world_name]
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(0, vp_size.y * 0.35 + 40)
	subtitle.size = Vector2(vp_size.x, 30)
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
	subtitle.modulate.a = 0.0
	layer.add_child(subtitle)

	# "Enemies reset for new region" hint
	var hint = Label.new()
	hint.text = "Enemy adaptation reset — fresh hunting grounds!"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0, vp_size.y * 0.35 + 76)
	hint.size = Vector2(vp_size.x, 24)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	hint.modulate.a = 0.0
	layer.add_child(hint)

	# Animation: flash → dark → text → fade out
	var tween = create_tween()
	# White flash (0.15s)
	tween.tween_property(flash, "color:a", 0.7, 0.15)
	tween.tween_property(flash, "color:a", 0.0, 0.2)
	# Dark backdrop fades in
	tween.parallel().tween_property(backdrop, "color:a", 0.85, 0.3)
	# Text fades in
	tween.tween_property(title, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(subtitle, "modulate:a", 1.0, 0.3)
	tween.tween_property(hint, "modulate:a", 1.0, 0.2)
	# Hold (1.5s)
	tween.tween_interval(1.5)
	# Fade everything out
	tween.tween_property(title, "modulate:a", 0.0, 0.4)
	tween.parallel().tween_property(subtitle, "modulate:a", 0.0, 0.4)
	tween.parallel().tween_property(hint, "modulate:a", 0.0, 0.4)
	tween.parallel().tween_property(backdrop, "color:a", 0.0, 0.4)
	# Cleanup
	tween.tween_callback(layer.queue_free)


func _create_autogrind_overlay() -> void:
	if _autogrind_overlay and is_instance_valid(_autogrind_overlay):
		return

	_autogrind_overlay_layer = CanvasLayer.new()
	_autogrind_overlay_layer.layer = 40
	add_child(_autogrind_overlay_layer)

	_autogrind_overlay = Control.new()
	_autogrind_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_autogrind_overlay_layer.add_child(_autogrind_overlay)

	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x == 0 or vp_size.y == 0:
		vp_size = Vector2(1280, 720)

	var bar_height = 148.0
	var bar_bg = ColorRect.new()
	bar_bg.color = Color(0.03, 0.02, 0.06, 0.85)
	bar_bg.position = Vector2(0, vp_size.y - bar_height)
	bar_bg.size = Vector2(vp_size.x, bar_height)
	_autogrind_overlay.add_child(bar_bg)

	var border = ColorRect.new()
	border.color = Color(0.5, 0.4, 0.6, 0.8)
	border.position = Vector2(0, vp_size.y - bar_height)
	border.size = Vector2(vp_size.x, 2)
	_autogrind_overlay.add_child(border)

	# Summary line — big and readable
	var summary = Label.new()
	summary.name = "SummaryLabel"
	summary.text = "Battle #1 | EXP: 0 | Streak: 0 | Efficiency: 1.0x"
	summary.position = Vector2(16, vp_size.y - bar_height + 6)
	summary.size = Vector2(vp_size.x - 32, 24)
	summary.add_theme_font_size_override("font_size", 16)
	summary.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
	_autogrind_overlay.add_child(summary)

	# Party HP/MP bars — compact row
	var party_container = Control.new()
	party_container.name = "PartyBars"
	party_container.position = Vector2(12, vp_size.y - bar_height + 30)
	party_container.size = Vector2(vp_size.x - 24, 28)
	_autogrind_overlay.add_child(party_container)

	var slot_w = (vp_size.x - 32) / max(party.size(), 1)
	# Tick 269: strict-5 party — was capped at 4. slot_w is already
	# derived from party.size() so the 5th slot was correctly sized
	# but never filled (silent empty column).
	for i in range(min(party.size(), 5)):
		var member = party[i]
		if not member is Combatant:
			continue

		var x = i * slot_w
		# Name
		var name_lbl = Label.new()
		name_lbl.name = "Name_%d" % i
		name_lbl.text = member.combatant_name.left(8)
		name_lbl.position = Vector2(x, 0)
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
		party_container.add_child(name_lbl)

		# HP bar background
		var bar_w = slot_w - 12
		var hp_bg = ColorRect.new()
		hp_bg.color = Color(0.15, 0.05, 0.05)
		hp_bg.position = Vector2(x, 14)
		hp_bg.size = Vector2(bar_w, 6)
		party_container.add_child(hp_bg)

		# HP bar fill
		var hp_fill = ColorRect.new()
		hp_fill.name = "HP_%d" % i
		hp_fill.color = Color(0.2, 0.8, 0.2)
		hp_fill.position = Vector2(x, 14)
		hp_fill.size = Vector2(bar_w, 6)
		party_container.add_child(hp_fill)

		# MP bar background
		var mp_bg = ColorRect.new()
		mp_bg.color = Color(0.05, 0.05, 0.15)
		mp_bg.position = Vector2(x, 22)
		mp_bg.size = Vector2(bar_w, 4)
		party_container.add_child(mp_bg)

		# MP bar fill
		var mp_fill = ColorRect.new()
		mp_fill.name = "MP_%d" % i
		mp_fill.color = Color(0.3, 0.4, 0.9)
		mp_fill.position = Vector2(x, 22)
		mp_fill.size = Vector2(bar_w, 4)
		party_container.add_child(mp_fill)

	# Battle log — last 5 outcomes, right side of party bars row
	var log_rtl = RichTextLabel.new()
	log_rtl.name = "BattleLog"
	log_rtl.bbcode_enabled = true
	log_rtl.scroll_following = true
	log_rtl.position = Vector2(vp_size.x * 0.55, vp_size.y - bar_height + 30)
	log_rtl.size = Vector2(vp_size.x * 0.43, 28)
	log_rtl.add_theme_font_size_override("normal_font_size", 9)
	log_rtl.add_theme_color_override("default_color", Color(0.7, 0.7, 0.8))
	log_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_autogrind_overlay.add_child(log_rtl)

	# Stats strip
	var strip = AutogrindStatsStrip.new()
	strip.name = "StatsStrip"
	strip.position = Vector2(4, vp_size.y - bar_height + 62)
	strip.size = Vector2(vp_size.x - 8, 42)
	_autogrind_overlay.add_child(strip)

	# Control hints
	var hints = Label.new()
	hints.name = "HintsLabel"
	hints.text = "Y: Turbo    +/-: Speed    T: Dashboard    P: Pause    B: Exit"
	hints.position = Vector2(16, vp_size.y - bar_height + 112)
	hints.size = Vector2(vp_size.x - 32, 24)
	hints.add_theme_font_size_override("font_size", 13)
	hints.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_autogrind_overlay.add_child(hints)


func _update_autogrind_overlay(stats: Dictionary) -> void:
	if not _autogrind_overlay or not is_instance_valid(_autogrind_overlay):
		return

	var summary = _autogrind_overlay.get_node_or_null("SummaryLabel")
	if summary:
		var battles = stats.get("battles_won", 0)
		var exp = stats.get("total_exp", 0)
		var wins = stats.get("consecutive_wins", 0)
		var eff = stats.get("efficiency", 1.0)
		var turbo_txt = " TURBO" if BattleManager.turbo_mode else ""
		var tier_txt = ""
		if _autogrind_controller and is_instance_valid(_autogrind_controller):
			var tier = _autogrind_controller.get_current_tier()
			if _autogrind_controller.headless_mode:
				tier_txt = " [LUDICROUS]"
			elif tier == 1:  # DASHBOARD
				tier_txt = " [DASHBOARD]"
			else:
				tier_txt = " [ACCELERATED]"
		summary.text = "Battle #%d | EXP: %d | Streak: %d | Efficiency: %.1fx%s%s" % [battles, exp, wins, eff, turbo_txt, tier_txt]

	# Update party HP/MP bars
	var party_bars = _autogrind_overlay.get_node_or_null("PartyBars")
	if party_bars:
		var vp_size = get_viewport().get_visible_rect().size
		if vp_size.x == 0:
			vp_size = Vector2(1280, 720)
		var slot_w = (vp_size.x - 32) / max(party.size(), 1)
		var bar_w = slot_w - 12
		var char_exp = stats.get("per_character_exp", {})
		# Tick 269: strict-5 party — was capped at 4 (matching the
		# initial build above; both sites needed bumping together).
		for i in range(min(party.size(), 5)):
			var member = party[i]
			if not member is Combatant:
				continue
			# Update name with session EXP total
			var name_lbl = party_bars.get_node_or_null("Name_%d" % i)
			if name_lbl:
				var member_exp = char_exp.get(member.combatant_name, 0)
				if member_exp > 0:
					name_lbl.text = "%s +%d" % [member.combatant_name.left(6), member_exp]
				else:
					name_lbl.text = member.combatant_name.left(8)
			var hp_fill = party_bars.get_node_or_null("HP_%d" % i)
			if hp_fill:
				var hp_pct = member.current_hp / max(float(member.max_hp), 1.0)
				hp_fill.size.x = bar_w * hp_pct
				if hp_pct > 0.5:
					hp_fill.color = Color(0.2, 0.8, 0.2)
				elif hp_pct > 0.25:
					hp_fill.color = Color(0.8, 0.7, 0.1)
				else:
					hp_fill.color = Color(0.9, 0.2, 0.2)
			var mp_fill = party_bars.get_node_or_null("MP_%d" % i)
			if mp_fill:
				var mp_pct = member.current_mp / max(float(member.max_mp), 1.0)
				mp_fill.size.x = bar_w * mp_pct

	# Update battle log with last 5 summaries
	var log_rtl = _autogrind_overlay.get_node_or_null("BattleLog")
	if log_rtl and log_rtl is RichTextLabel:
		log_rtl.clear()
		var show_count = min(_autogrind_battle_summaries.size(), 5)
		var start_idx = _autogrind_battle_summaries.size() - show_count
		for i in range(start_idx, _autogrind_battle_summaries.size()):
			log_rtl.append_text(_autogrind_battle_summaries[i] + "\n")

	var strip = _autogrind_overlay.get_node_or_null("StatsStrip")
	if strip and strip.has_method("refresh"):
		var region_id = _current_map_id.replace(" ", "_").to_lower()
		strip.refresh(stats, region_id)


func _destroy_autogrind_overlay() -> void:
	if _autogrind_overlay and is_instance_valid(_autogrind_overlay):
		_autogrind_overlay.queue_free()
		_autogrind_overlay = null
	if _autogrind_overlay_layer and is_instance_valid(_autogrind_overlay_layer):
		_autogrind_overlay_layer.queue_free()
		_autogrind_overlay_layer = null


func _show_controller_overlay(context: Dictionary) -> void:
	if has_node("/root/GameState"):
		if not GameState.show_controller_overlay:
			return

	if not _controller_overlay:
		_controller_overlay_layer = CanvasLayer.new()
		_controller_overlay_layer.layer = 55  # Above battle scenes and menus
		add_child(_controller_overlay_layer)

		_controller_overlay = ControllerOverlay.new()
		var vp_size = get_viewport().get_visible_rect().size
		if vp_size.x == 0 or vp_size.y == 0:
			vp_size = Vector2(1280, 720)
		_controller_overlay.position = Vector2(vp_size.x - 330, vp_size.y - 200)
		_controller_overlay.size = ControllerOverlay.OVERLAY_SIZE
		_controller_overlay_layer.add_child(_controller_overlay)

	_controller_overlay.set_context(context)
	_controller_overlay.visible = true


func _hide_controller_overlay() -> void:
	if _controller_overlay and is_instance_valid(_controller_overlay):
		_controller_overlay.visible = false


func _destroy_controller_overlay() -> void:
	if _controller_overlay and is_instance_valid(_controller_overlay):
		_controller_overlay.queue_free()
		_controller_overlay = null
	if _controller_overlay_layer and is_instance_valid(_controller_overlay_layer):
		_controller_overlay_layer.queue_free()
		_controller_overlay_layer = null


func _show_autogrind_dashboard() -> void:
	if _autogrind_dashboard and is_instance_valid(_autogrind_dashboard):
		_autogrind_dashboard.visible = true
		return

	var DashboardClass = load("res://src/ui/autogrind/AutogrindDashboard.gd")
	_autogrind_dashboard = DashboardClass.new()
	_autogrind_dashboard.set_anchors_preset(Control.PRESET_FULL_RECT)

	if _autogrind_ui_layer and is_instance_valid(_autogrind_ui_layer):
		_autogrind_ui_layer.add_child(_autogrind_dashboard)
	else:
		add_child(_autogrind_dashboard)

	_autogrind_dashboard.pause_requested.connect(_toggle_autogrind_pause)
	_autogrind_dashboard.exit_requested.connect(func(): _stop_autogrind("Manual stop"))
	_autogrind_dashboard.tier_cycle_requested.connect(func():
		if _autogrind_controller and is_instance_valid(_autogrind_controller):
			_autogrind_controller.cycle_tier()
	)

	# Show ludicrous speed indicator if headless mode is active
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		if _autogrind_dashboard.has_method("set_ludicrous_mode"):
			_autogrind_dashboard.set_ludicrous_mode(_autogrind_controller.headless_mode)

	print("[AUTOGRIND] Dashboard shown (Tier 2)")


func _hide_autogrind_dashboard() -> void:
	if _autogrind_dashboard and is_instance_valid(_autogrind_dashboard):
		_autogrind_dashboard.queue_free()
		_autogrind_dashboard = null
	print("[AUTOGRIND] Dashboard hidden (back to Tier 1)")


func _on_ui_tier_cycle_requested() -> void:
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		_autogrind_controller.cycle_tier()


func _autogrind_heal_member(member: Combatant) -> void:
	var heal_items = [["hi_potion", 200], ["potion", 50]]
	for item_pair in heal_items:
		var item_id = item_pair[0]
		var heal_amount = item_pair[1]
		if member.get_item_count(item_id) > 0:
			member.remove_item(item_id, 1)
			member.heal(heal_amount)
			AutogrindSystem.track_item_consumed(item_id)
			print("[AUTOGRIND] %s used %s (healed %d HP)" % [member.combatant_name, item_id, heal_amount])
			return


func _autogrind_restore_mp(member: Combatant) -> void:
	var mp_items = [["hi_ether", 100], ["ether", 30]]
	for item_pair in mp_items:
		var item_id = item_pair[0]
		var restore = item_pair[1]
		if member.get_item_count(item_id) > 0:
			member.remove_item(item_id, 1)
			member.restore_mp(restore)
			AutogrindSystem.track_item_consumed(item_id)
			print("[AUTOGRIND] %s used %s (restored %d MP)" % [member.combatant_name, item_id, restore])
			return


func _autogrind_save_snapshot() -> void:
	"""Save a grind snapshot for pause/resume recovery."""
	if not _autogrind_controller or not is_instance_valid(_autogrind_controller):
		return
	var ctrl_snapshot = _autogrind_controller.serialize_snapshot()
	AutogrindSystem.save_grind_snapshot(ctrl_snapshot)


func _resume_autogrind() -> void:
	"""Resume a previously saved autogrind session."""
	var snapshot = AutogrindSystem.load_grind_snapshot()
	if snapshot.is_empty():
		print("[AUTOGRIND] No snapshot to resume")
		return

	var ctrl_data = snapshot.get("controller", {})
	var sys_data = snapshot.get("system", {})
	var config = ctrl_data.get("config", {})

	# Inject headless_mode into config so _start_autogrind sets it correctly
	# (controller reads ludicrous_speed from config during start_grind)
	if ctrl_data.get("headless_mode", false) and not config.has("ludicrous_speed"):
		config["ludicrous_speed"] = true

	# Start autogrind first (this resets system state to zero)
	_start_autogrind(config)

	# THEN restore system state on top (overrides the zeros from start_autogrind)
	AutogrindSystem.restore_system_from_snapshot(sys_data)

	# Restore controller-specific state (tier, headless, terrain)
	if _autogrind_controller and is_instance_valid(_autogrind_controller):
		_autogrind_controller.restore_from_snapshot(ctrl_data)

	# Clear the snapshot now that we've successfully resumed
	AutogrindSystem.clear_grind_snapshot()

	print("[AUTOGRIND] Session resumed from snapshot (%d battles, %d EXP)" % [
		sys_data.get("battles_completed", 0), sys_data.get("total_exp_gained", 0)])


func _exit_tree() -> void:
	"""Save snapshot on exit if grinding, then disconnect signals"""
	if _is_autogrinding and _autogrind_controller and is_instance_valid(_autogrind_controller):
		_autogrind_save_snapshot()
		print("[AUTOGRIND] Snapshot saved on exit")
	if _exploration_scene and is_instance_valid(_exploration_scene):
		if _exploration_scene.has_signal("battle_triggered") and _exploration_scene.is_connected("battle_triggered", _on_exploration_battle_triggered):
			_exploration_scene.disconnect("battle_triggered", _on_exploration_battle_triggered)
		if _exploration_scene.has_signal("area_transition") and _exploration_scene.is_connected("area_transition", _on_area_transition):
			_exploration_scene.disconnect("area_transition", _on_area_transition)
		_exploration_scene.queue_free()
		_exploration_scene = null

	if _title_screen and is_instance_valid(_title_screen):
		if _title_screen.is_connected("new_game_selected", _on_title_new_game):
			_title_screen.disconnect("new_game_selected", _on_title_new_game)
		if _title_screen.is_connected("continue_selected", _on_title_continue):
			_title_screen.disconnect("continue_selected", _on_title_continue)
		if _title_screen.is_connected("settings_selected", _on_title_settings):
			_title_screen.disconnect("settings_selected", _on_title_settings)


func _get_milestone_text(battles: int) -> String:
	match battles:
		10: return "ADAPTATION Lv.1 — Enemies are learning..."
		20: return "ADAPTATION Lv.2 — Enemies growing stronger!"
		30: return "SYSTEM FATIGUE — Instability events possible!"
		50: return "DEEP GRIND — Maximum adaptation reached!"
		100: return "LEGENDARY SESSION — Reality is bending..."
		_: return "Milestone: %d battles!" % battles


func _on_any_save_failed(reason: String) -> void:
	"""Surface every save failure as a warning toast. Pre-fix, save_failed
	had no listeners — silent rejection was indistinguishable from
	'something is broken'. Now the player sees the actual blocker
	('Cannot save inside this room — leave to a village or overworld first')."""
	if not Toast:
		return
	var msg: String = reason if reason != "" else "Save failed"
	Toast.show_warning(self, msg)


func _on_any_save_completed(_slot: int) -> void:
	"""Fire a green 'Game Saved ✓ — <location>' toast whenever SaveSystem
	completes a save. The location label is pulled live from MapSystem so the
	player can confirm WHERE the save landed (matters when juggling multiple
	slots across worlds). Falls back to the legacy short form when no map is
	loaded (e.g. saving from the title screen via debug paths)."""
	var location := ""
	if MapSystem and "current_map_id" in MapSystem and MapSystem.current_map_id:
		location = str(MapSystem.current_map_id).capitalize()
	Toast.show_save(self, location)


## Tick 178: surface save-corruption events. The signals were
## firing pre-fix with NO listeners — Scriptweaver / Necromancer
## actions silently corrupted the save and the player got zero
## visible feedback. Now: every corruption level increase shows
## a warning-color toast with the new level, and every NEW
## corruption effect shows a distinct danger-color toast.
func _on_save_corruption_increased(corruption_level: float) -> void:
	## Don't spam the player — only show the toast at meaningful
	## thresholds (10%, 25%, 50%, 75%, 100%) so an Edit Formula
	## that nudges level by 0.01 doesn't yield a noisy toast.
	var pct: int = int(corruption_level * 100.0)
	var prev_threshold: int = -1
	var thresholds: Array[int] = [10, 25, 50, 75, 100]
	for t in thresholds:
		if pct >= t:
			prev_threshold = t
	if prev_threshold < 0:
		return
	# Track which thresholds we've shown so we don't re-show every
	# add_corruption call between thresholds.
	if not has_meta("corruption_thresholds_shown"):
		set_meta("corruption_thresholds_shown", {})
	var shown: Dictionary = get_meta("corruption_thresholds_shown", {})
	if shown.has(prev_threshold):
		return
	shown[prev_threshold] = true
	set_meta("corruption_thresholds_shown", shown)
	Toast.show(self,
		"⚠ Save corruption: %d%%" % prev_threshold,
		Toast.WARNING_COLOR)


func _on_corruption_effect_added(effect: String) -> void:
	## Each new corruption effect is distinct and worth surfacing
	## immediately — these affect gameplay (visual_glitch, stat_drain,
	## etc.) so the player should know which effect just landed.
	var display: String = effect.replace("_", " ").to_upper()
	Toast.show(self,
		"⚠ Reality glitches: %s" % display,
		Toast.DANGER_COLOR)


## Tick 179: Scriptweaver edits via modify_constant fire
## game_constant_modified. Pre-fix nobody listened — the player
## edited a constant and saw zero confirmation that it landed
## (modify_constant returns true but no UI surface). Toast format
## shows the constant name + the change ("3.0 → 4.5"). Uses
## DEFAULT_COLOR (yellow) since this is a player-initiated edit,
## not a corruption-induced event — different severity from the
## corruption Toasts above.
func _on_game_constant_modified(constant_name: String, old_value, new_value) -> void:
	var display_name: String = constant_name.replace("_", " ").capitalize()
	Toast.show(self,
		"✎ %s: %s → %s" % [display_name, str(old_value), str(new_value)],
		Toast.DEFAULT_COLOR)


## Tick 254: visible feedback when an event chat unlocks. Listener
## wired in _ready against PartyChatSystem.event_chat_unlocked, which
## fires from fire_event_flag the moment a registry entry transitions
## from locked to available.
func _on_event_chat_unlocked(_chat_id: String, title: String) -> void:
	# Defer to a CLEAN exploration moment — it fired over GAME OVER, then over the shop Buy menu (smoke-shot finds 2026-07-11). Unlock announcements aren't time-critical.
	_pending_chat_toasts.append(title)
	_flush_chat_toasts()


var _pending_chat_toasts: Array[String] = []


func _flush_chat_toasts() -> void:
	if _pending_chat_toasts.is_empty() or current_state != LoopState.EXPLORATION:
		return
	if InputLockManager and InputLockManager.is_locked():
		return
	if _overworld_menu and is_instance_valid(_overworld_menu):
		return
	for title in _pending_chat_toasts:
		Toast.show_success(self, "New party chat: %s" % title)
	_pending_chat_toasts.clear()


## Tick 264: visible feedback for bestiary kill milestones (10/50/100
## /500 of one monster). Pluralization handled with a naive +s — fine
## for current monster names ("Slime"/"Bat"/"Goblin"); add a real
## pluralizer if monster names start ending in y/s/x.
## Tick 358: simple English pluralization that handles the most common
## non-trivial endings monsters.json names hit: Entity → Entities,
## Process → Processes, Lady → Ladies. Pre-fix the bare `%ss` append
## produced "Entitys", "Processs", "Ladys" toast text on milestone
## hits. Only covers the rules the actual monster name set needs;
## extend the helper as new data lands rather than pulling in a full
## inflection lib for a polish nit.
func _pluralize_monster_name(name: String) -> String:
	if name.is_empty():
		return name
	var lower: String = name.to_lower()
	# -y after a consonant → -ies (Lady → Ladies, Entity → Entities)
	if lower.ends_with("y") and lower.length() >= 2:
		var penultimate: String = lower.substr(lower.length() - 2, 1)
		if not (penultimate in ["a", "e", "i", "o", "u"]):
			return name.substr(0, name.length() - 1) + "ies"
	# -s, -sh, -ch, -x, -z → -es (Process → Processes, Wretch → Wretches)
	if lower.ends_with("sh") or lower.ends_with("ch") or lower.ends_with("s") or lower.ends_with("x") or lower.ends_with("z"):
		return name + "es"
	return name + "s"


func _on_bestiary_kill_milestone(_monster_id: String, monster_name: String, count: int) -> void:
	Toast.show_success(self, "%d %s defeated!" % [count, _pluralize_monster_name(monster_name)])


func _show_autogrind_toast(text: String) -> void:
	var layer = CanvasLayer.new()
	layer.layer = 80
	add_child(layer)

	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x == 0:
		vp_size = Vector2(1280, 720)
	label.position = Vector2(0, 80)
	label.size = Vector2(vp_size.x, 40)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
	label.modulate.a = 0.0
	layer.add_child(label)

	var shadow = Label.new()
	shadow.text = text
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shadow.position = Vector2(2, 82)
	shadow.size = Vector2(vp_size.x, 40)
	shadow.add_theme_font_size_override("font_size", 20)
	shadow.add_theme_color_override("font_color", Color(0, 0, 0, 0.6))
	shadow.modulate.a = 0.0
	layer.add_child(shadow)
	layer.move_child(shadow, 0)

	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(shadow, "modulate:a", 1.0, 0.3)
	tween.tween_interval(2.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.parallel().tween_property(shadow, "modulate:a", 0.0, 0.5)
	tween.tween_callback(layer.queue_free)
