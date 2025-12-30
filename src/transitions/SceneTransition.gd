extends CanvasLayer

## SceneTransition - Handles transitions between scenes (exploration ↔ battle)
## Provides fade effects and connects encounters to battles

signal transition_started()
signal transition_finished()
signal battle_transition_started()
signal battle_transition_finished()

## Transition config
@export var fade_duration: float = 0.5

## UI nodes
var fade_rect: ColorRect


func _ready() -> void:
	# Create fade overlay
	_create_fade_overlay()

	# Connect to encounter system
	if EncounterSystem:
		EncounterSystem.encounter_triggered.connect(_on_encounter_triggered)


func _create_fade_overlay() -> void:
	"""Create black fade overlay"""
	fade_rect = ColorRect.new()
	fade_rect.name = "FadeOverlay"
	fade_rect.color = Color.BLACK
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Cover entire screen
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.modulate.a = 0.0  # Start transparent

	add_child(fade_rect)


## Fade transitions
func fade_to_black() -> void:
	"""Fade screen to black"""
	var tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", 1.0, fade_duration)
	await tween.finished


func fade_from_black() -> void:
	"""Fade screen from black"""
	var tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", 0.0, fade_duration)
	await tween.finished


func fade_transition(callable: Callable) -> void:
	"""Fade out, execute callable, fade in"""
	transition_started.emit()

	await fade_to_black()
	callable.call()
	await fade_from_black()

	transition_finished.emit()


## Battle transitions
func transition_to_battle(enemy_data: Array) -> void:
	"""Transition from exploration to battle"""
	battle_transition_started.emit()
	print("Transitioning to battle...")

	# Fade out
	await fade_to_black()

	# Hide player controller
	var player = MapSystem.get_player()
	if player:
		player.set_can_move(false)
		player.visible = false

	# Create battle scene
	_start_battle(enemy_data)

	# Fade in
	await fade_from_black()

	battle_transition_finished.emit()


func transition_from_battle(victory: bool) -> void:
	"""Transition from battle back to exploration"""
	print("Transitioning from battle... Victory: %s" % victory)

	# Fade out
	await fade_to_black()

	# Destroy battle scene (if exists)
	var battle_scene = get_tree().root.find_child("BattleScene", true, false)
	if battle_scene:
		battle_scene.queue_free()

	# Show player controller
	var player = MapSystem.get_player()
	if player:
		player.visible = true
		player.set_can_move(true)

		# Reset step counter to prevent immediate re-encounter
		player.reset_step_count()
		EncounterSystem.reset_encounter_counter()

	# Fade in
	await fade_from_black()


func _start_battle(enemy_data: Array) -> void:
	"""Start a battle with given enemies"""
	# Load battle scene
	var battle_scene_path = "res://src/battle/BattleScene.tscn"
	var battle_scene_resource = load(battle_scene_path)
	var battle_scene = battle_scene_resource.instantiate()

	# Add to scene tree
	get_tree().root.add_child(battle_scene)

	# Create enemy combatants
	var enemies: Array[Combatant] = []
	for enemy_dict in enemy_data:
		var enemy = Combatant.new()
		enemy.initialize(enemy_dict)
		enemies.append(enemy)

	# Get player party (for now, just the single test player)
	# In full game, would get full party from GameState
	var players: Array[Combatant] = []
	if battle_scene.has_node("TestPlayer"):
		players.append(battle_scene.get_node("TestPlayer"))

	# Start battle
	if not enemies.is_empty() and not players.is_empty():
		BattleManager.start_battle(players, enemies)

	# Connect to battle end
	if not BattleManager.battle_ended.is_connected(_on_battle_ended):
		BattleManager.battle_ended.connect(_on_battle_ended)


func _on_battle_ended(victory: bool) -> void:
	"""Handle battle ending"""
	await get_tree().create_timer(1.0).timeout  # Wait a moment
	transition_from_battle(victory)


func _on_encounter_triggered(enemy_data: Array) -> void:
	"""Handle random encounter trigger"""
	transition_to_battle(enemy_data)


## Map transitions
func transition_to_map(map_id: String, spawn_point: String = "default") -> void:
	"""Transition to a different map"""
	await fade_transition(func():
		MapSystem.transition_to_map(map_id, spawn_point)
	)
