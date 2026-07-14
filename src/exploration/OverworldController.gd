extends Node
class_name OverworldController

## OverworldController - Manages exploration state, encounters, and transitions
## Orchestrates the exploration → encounter → battle → exploration loop

const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")

signal battle_triggered(enemies: Array)
signal menu_requested()

@export var player: CharacterBody2D  # OverworldPlayer
@export var encounter_enabled: bool = true
@export var current_area_id: String = "overworld"

## encounter_surge save-corruption boost — corruption = instability = more fights (was announced via Toast but inert)
const ENCOUNTER_SURGE_MULT: float = 1.5

## Area configuration
var _is_safe_zone: bool = false
var _encounter_rate: float = 0.05
var _enemy_pool: Array = ["slime", "bat"]
var _paused: bool = false


func _ready() -> void:
	if player:
		player.moved.connect(_on_player_moved)
		player.menu_requested.connect(_on_menu_requested)
		player.interaction_requested.connect(_on_interaction_requested)


func _exit_tree() -> void:
	"""Disconnect from player signals when freed"""
	# A controller freed while paused stranded its GLOBAL lock — the player sat frozen until the 10s stale-expiry (web-smoke soft-error budget find 2026-07-11).
	if _paused:
		var ilm = get_tree().root.get_node_or_null("InputLockManager") if is_inside_tree() else null
		if ilm:
			ilm.pop_lock("exploration_paused")
	if player and is_instance_valid(player):
		if player.moved.is_connected(_on_player_moved):
			player.moved.disconnect(_on_player_moved)
		if player.menu_requested.is_connected(_on_menu_requested):
			player.menu_requested.disconnect(_on_menu_requested)
		if player.interaction_requested.is_connected(_on_interaction_requested):
			player.interaction_requested.disconnect(_on_interaction_requested)


func _on_player_moved(steps: int) -> void:
	if not encounter_enabled or _is_safe_zone or _paused:
		return
	# struktured 2026-07-11: the RE system must be OFF before any critical overworld event — an encounter roll raced the village-entry cutscene on the same step. Locks (cutscene/transition) and a pending story beat both suppress rolls.
	var ilm = get_tree().root.get_node_or_null("InputLockManager") if is_inside_tree() else null
	if ilm and ilm.is_locked():
		return
	var gl = get_tree().root.get_node_or_null("GameLoop") if is_inside_tree() else null
	if gl and gl.has_method("_get_pending_story_cutscene") and str(gl._get_pending_story_cutscene()) != "":
		return

	# Check for random encounter
	if _check_encounter():
		_trigger_battle()


func _check_encounter() -> bool:
	# Apply settings multiplier from GameState — runtime lookup keeps
	# this file preload-safe for tests (GameState as a global identifier
	# doesn't resolve in preload() parse contexts).
	var rate_multiplier = 1.0
	var gs = get_tree().root.get_node_or_null("GameState") if is_inside_tree() else null
	if gs:
		rate_multiplier = gs.encounter_rate_multiplier
		# Tick 110: compose the RebalanceDaemon's encounter_rate knob into
		# the chance calc. Pre-fix, game_constants["encounter_rate"] was
		# one of three ALLOWED_CONSTANTS the daemon could nudge — set,
		# persisted, audited — but NO code path read it. Daemon
		# proposals to change encounter frequency had zero effect.
		# Compose multiplicatively with the user's settings slider:
		# daemon trims the curve, slider expresses player preference,
		# both stack. Defensive clampf into a wide-but-finite band so
		# debug overrides or post-load corruption can't blow up.
		if "game_constants" in gs:
			var daemon_rate: float = clampf(
				float(gs.game_constants.get("encounter_rate", 1.0)),
				0.1, 10.0)
			rate_multiplier *= daemon_rate
		# encounter_surge save-corruption: inert before (announced, never read) — now it actually surges
		if "corruption_effects" in gs and "encounter_surge" in gs.corruption_effects:
			rate_multiplier *= ENCOUNTER_SURGE_MULT

	# If multiplier is 0, no encounters
	if rate_multiplier <= 0.0:
		return false

	# Use EncounterSystem autoload if present (Engine.has_singleton is ALWAYS
	# FALSE for autoloads in Godot 4 — look up via scene tree root).
	var es: Node = get_tree().root.get_node_or_null("EncounterSystem") if is_inside_tree() else null
	if es != null:
		# Compose the settings multiplier with ES's chance calculation by
		# scaling encounter_rate_modifier for the duration of one check.
		# Pre-fix this did `es.check_for_encounter() and randf() < rate_multiplier`
		# as a SECONDARY roll. For settings_multiplier > 1.0 (UI exposes
		# 0..2x), `randf() < 1.5` is always true so the bonus did nothing —
		# the slider effectively capped at 1x. Scaling the ES modifier
		# pre-roll makes the full UI range honest. Restore after so item
		# debuffs / Repel state aren't polluted. Clamp to the ES allowed
		# range so a bad UI value can't push past the engine's contract.
		var original_modifier: float = es.encounter_rate_modifier
		var composite: float = clampf(
			original_modifier * rate_multiplier,
			0.0, es.ENCOUNTER_RATE_MODIFIER_MAX)
		es.encounter_rate_modifier = composite
		# Tick 324: ALSO push the controller's per-area _encounter_rate
		# into ES.encounter_rate for this check. Pre-fix set_area_config
		# stored _encounter_rate (dungeon floors set 6-10% with floor
		# progression) but ES.encounter_rate stayed at its default 5%.
		# OverworldController's normal path then called ES.check_for_encounter
		# which used `encounter_rate * encounter_rate_modifier` from ES's
		# OWN fields, totally ignoring the controller's _encounter_rate.
		# Dungeons effectively had a flat 5% rate regardless of floor or
		# area config. Same swap-restore idiom as the modifier above.
		var original_rate: float = es.encounter_rate
		es.encounter_rate = _encounter_rate
		var triggered: bool = es.check_for_encounter()
		es.encounter_rate = original_rate
		es.encounter_rate_modifier = original_modifier
		return triggered

	# Fallback: simple random check with multiplier
	return randf() < (_encounter_rate * rate_multiplier)


func _trigger_battle() -> void:
	var enemies = _generate_enemies()
	print("[ENCOUNTER] Battle triggered! Enemies: %s" % str(enemies))
	battle_triggered.emit(enemies)


func _generate_enemies() -> Array:
	# Use EncounterSystem autoload if present (Engine.has_singleton is ALWAYS
	# FALSE for autoloads in Godot 4 — look up via scene tree root).
	var es: Node = get_tree().root.get_node_or_null("EncounterSystem") if is_inside_tree() else null
	if es != null:
		return es.generate_enemy_party()

	# Return empty if no enemies in pool (boss-only floors)
	if _enemy_pool.is_empty():
		return []

	# Fallback: generate 1-3 random enemies from pool
	var count = randi_range(1, 3)
	var enemies = []
	for i in range(count):
		var enemy_type = _enemy_pool[randi() % _enemy_pool.size()]
		enemies.append(enemy_type)
	return enemies


func _on_menu_requested() -> void:
	menu_requested.emit()


## Runtime lookup helper — DebugLogOverlay as a global identifier
## doesn't resolve in preload() parse contexts used by the test suite.
func _dlog(msg: String) -> void:
	var overlay = get_tree().root.get_node_or_null("DebugLogOverlay") if is_inside_tree() else null
	if overlay:
		overlay.log(msg)


func _on_interaction_requested() -> void:
	# Check for nearby interactables
	# Tick 232: surface wiring bug. Pre-fix the @export var player being unassigned (forgotten in a new village scene, broken signal binding) silently dropped every interaction — player tapped Z, nothing happened, no diagnostic.
	if not player:
		push_warning("[OverworldController] _on_interaction_requested: player ref is null — @export var player likely unwired in the scene setup")
		return

	_dlog("[INTERACT] At pos: %s" % player.global_position)

	# Get nearby Area2D nodes and try to interact
	var space = player.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()

	# 80px suits the Mode 7 overworld's perspective; flat villages/interiors read the same probe as a 3-4 tile grabber arm ("opened a chest from 3-4 squares away" — struktured 2026-07-11).
	var reach: float = 80.0 if Mode7Overlay.is_active else 40.0
	var check_offset = Vector2.ZERO
	match player.current_direction:
		OverworldPlayerScript.Direction.DOWN:
			check_offset = Vector2(0, reach)
		OverworldPlayerScript.Direction.UP:
			check_offset = Vector2(0, -reach)
		OverworldPlayerScript.Direction.LEFT:
			check_offset = Vector2(-reach, 0)
		OverworldPlayerScript.Direction.RIGHT:
			check_offset = Vector2(reach, 0)

	query.position = player.global_position + check_offset
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 4  # Layer 4 = interactables (NPCs, transitions, etc.)

	var results = space.intersect_point(query)
	# 2026-07-13: was first-hit-wins — but overworld portals with overlapping AABBs (Castle Harmonia + Cave Entrance 2 tiles apart, dragon caves next to their villages) let the earlier sibling steal every ui_accept. Pick the NEAREST interactable to the player, not the first iteration hit.
	var nearest = _pick_nearest_interactable(results, player.global_position)
	if nearest:
		_dlog("[INTERACT] Found: %s (physics, nearest)" % nearest.name)
		nearest.interact(player)
		return

	# Also check at player's position (for when standing on/in interactable) — same nearest-hit selection.
	query.position = player.global_position
	results = space.intersect_point(query)
	nearest = _pick_nearest_interactable(results, player.global_position)
	if nearest:
		_dlog("[INTERACT] Found: %s (standing, nearest)" % nearest.name)
		nearest.interact(player)
		return

	# Fallback: check interactables group by distance (more reliable than physics queries)
	var interactables = player.get_tree().get_nodes_in_group("interactables")
	var interaction_range = 48.0  # ~1.5 tiles
	for interactable in interactables:
		if interactable.has_method("interact"):
			var dist = player.global_position.distance_to(interactable.global_position)
			if dist <= interaction_range:
				_dlog("[INTERACT] Found: %s (dist: %.0f)" % [interactable.name, dist])
				interactable.interact(player)
				return

	_dlog("[INTERACT] Nothing found")


## Overlap-safe interactable pick — returns the nearest collider that has an interact() method, or null. Overworld transitions with adjacent-tile spacing have overlapping AABBs by design (dragon cave next to its village); this disambiguates by distance instead of iteration order.
func _pick_nearest_interactable(results: Array, from_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d2: float = INF
	for result in results:
		var collider = result.get("collider", null)
		if collider == null or not is_instance_valid(collider) or not collider.has_method("interact"):
			continue
		var d2: float = collider.global_position.distance_squared_to(from_pos)
		if d2 < best_d2:
			best_d2 = d2
			best = collider
	return best


## Tick 326: push the current pool into the EncounterSystem autoload so
## es.generate_enemy_party() spawns the controller's intended monsters.
## Explicit Array → Array[String] coercion (same idiom as the typed-
## array save-roundtrip fixes in Combatant/GameState) dodges the silent
## typed-array-assignment failure that GDScript exhibits when the source
## array isn't already typed as Array[String]. EncounterSystem.set_enemy_pool
## requires Array[String]; passing a plain Array would silently no-op the
## inner .duplicate() call.
func _push_pool_to_encounter_system(pool: Array) -> void:
	var es: Node = get_tree().root.get_node_or_null("EncounterSystem") if is_inside_tree() else null
	if es == null or not es.has_method("set_enemy_pool"):
		return
	var typed: Array[String] = []
	for entry in pool:
		typed.append(str(entry))
	es.set_enemy_pool(typed)


## Configure area for encounters
func set_area_config(area_id: String, safe_zone: bool, encounter_rate: float, enemy_pool: Array) -> void:
	current_area_id = area_id
	_is_safe_zone = safe_zone
	_encounter_rate = encounter_rate
	_enemy_pool = enemy_pool
	# Tick 326: push the new pool into EncounterSystem.current_enemy_pool
	# so es.generate_enemy_party() actually spawns the dungeon/area's
	# intended monsters. Pre-fix set_area_config stored _enemy_pool but
	# never told ES — ES.current_enemy_pool stayed at its default
	# (["slime", "bat"]) or whatever the LAST ES.set_enemy_pool call
	# pushed. So a fire dungeon configured with ["fire_imp", "salamander"]
	# kept spawning slimes and bats. Same stored-locally-never-pushed
	# class as tick 324 (encounter_rate). Same coercion idiom as tick 304
	# — Array → Array[String] explicit loop to dodge the silent typed-
	# array assignment failure.
	_push_pool_to_encounter_system(enemy_pool)


## Set enemy pool directly (convenience method)
func set_enemy_pool(pool_id: String) -> void:
	"""Load enemy pool from enemy_pools.json by ID"""
	var pools = _load_enemy_pools()
	if pools.has(pool_id):
		_enemy_pool = pools[pool_id]
		print("Loaded enemy pool '%s': %s" % [pool_id, _enemy_pool])
		# Tick 326: see set_area_config above for the rationale.
		_push_pool_to_encounter_system(pools[pool_id])
	else:
		## Tick 183: surface missing pool. Pre-fix print() only —
		## player would wander an area silently using whatever the
		## last loaded pool was (or empty). Common cause: a new
		## overworld zone added without its enemy_pools.json entry.
		push_warning("[OverworldController] enemy pool '%s' not found in enemy_pools.json — current pool stays at last value, encounters may be wrong for this area" % pool_id)


func _load_enemy_pools() -> Dictionary:
	"""Load enemy pools from data file"""
	var file_path = "res://data/enemy_pools.json"
	# Tick 232: 4-stage loud-fail surfaces. Pre-fix each error path silently returned {} so set_enemy_pool's "pool not found" warning fired but the root cause (file missing, parse error, etc.) was invisible. Mirrors the BestiarySystem._load_json pattern.
	if not FileAccess.file_exists(file_path):
		push_warning("[OverworldController] enemy_pools.json missing at %s — no encounter pools available" % file_path)
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_warning("[OverworldController] enemy_pools.json exists but FileAccess.open failed (error %d) — no encounter pools available" % FileAccess.get_open_error())
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result := json.parse(json_string)
	if parse_result != OK:
		push_warning("[OverworldController] enemy_pools.json parse error: %s — no encounter pools available" % json.get_error_message())
		return {}
	if not (json.data is Dictionary):
		push_warning("[OverworldController] enemy_pools.json parsed but root is not a Dictionary — no encounter pools available")
		return {}
	return json.data


## Resume player control after battle or menu
func resume_exploration() -> void:
	_paused = false
	# Runtime lookup for preload safety (see _dlog for rationale).
	var ilm = get_tree().root.get_node_or_null("InputLockManager") if is_inside_tree() else null
	if ilm:
		ilm.pop_lock("exploration_paused")


## Pause player control
func pause_exploration() -> void:
	_paused = true
	var ilm = get_tree().root.get_node_or_null("InputLockManager") if is_inside_tree() else null
	if ilm:
		ilm.push_lock("exploration_paused")


func _process(_delta: float) -> void:
	# Heartbeat while paused: push_lock refreshes the timestamp, so a menu held open >10s no longer trips the stale expiry and unfreezes the player behind the open menu (web-smoke budget find #2, 2026-07-11). Dead holders release via _exit_tree.
	if _paused and is_inside_tree():
		var ilm = get_tree().root.get_node_or_null("InputLockManager")
		if ilm:
			ilm.push_lock("exploration_paused")
