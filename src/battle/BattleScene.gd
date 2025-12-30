extends Control

## BattleScene - FF-style battle UI with sprites
## Enemies on left, party on right, classic JRPG layout

## UI References
@onready var battle_log: RichTextLabel = $UI/BattleLogPanel/MarginContainer/VBoxContainer/BattleLog
@onready var turn_info: Label = $UI/TurnInfoPanel/TurnInfo

## Action buttons
@onready var btn_attack: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/AttackButton
@onready var btn_ability: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/AbilityButton
@onready var btn_item: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/ItemButton
@onready var btn_default: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/DefaultButton
@onready var btn_brave: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/BraveButton

## Party status UI
@onready var char1_name: Label = $UI/PartyStatusPanel/VBoxContainer/Character1/Name
@onready var char1_hp: ProgressBar = $UI/PartyStatusPanel/VBoxContainer/Character1/HP
@onready var char1_hp_label: Label = $UI/PartyStatusPanel/VBoxContainer/Character1/HP/HPLabel
@onready var char1_mp: ProgressBar = $UI/PartyStatusPanel/VBoxContainer/Character1/MP
@onready var char1_mp_label: Label = $UI/PartyStatusPanel/VBoxContainer/Character1/MP/MPLabel
@onready var char1_ap: Label = $UI/PartyStatusPanel/VBoxContainer/Character1/AP

## Sprite containers
@onready var enemy_sprites: Node2D = $BattleField/EnemySprites
@onready var party_sprites: Node2D = $BattleField/PartySprites

## Sprite positions
@onready var enemy_positions: Array[Marker2D] = [
	$BattleField/EnemyArea/Enemy1Pos,
	$BattleField/EnemyArea/Enemy2Pos,
	$BattleField/EnemyArea/Enemy3Pos
]

@onready var party_positions: Array[Marker2D] = [
	$BattleField/PartyArea/Player1Pos,
	$BattleField/PartyArea/Player2Pos,
	$BattleField/PartyArea/Player3Pos,
	$BattleField/PartyArea/Player4Pos
]

## Test combatants
var test_player: Combatant
var test_enemy: Combatant

## Sprite nodes
var player_sprite: Sprite2D
var enemy_sprite: Sprite2D


func _ready() -> void:
	# Connect to BattleManager signals
	BattleManager.battle_started.connect(_on_battle_started)
	BattleManager.battle_ended.connect(_on_battle_ended)
	BattleManager.turn_started.connect(_on_turn_started)
	BattleManager.turn_ended.connect(_on_turn_ended)
	BattleManager.action_executed.connect(_on_action_executed)

	# Connect button signals
	btn_attack.pressed.connect(_on_attack_pressed)
	btn_ability.pressed.connect(_on_ability_pressed)
	btn_item.pressed.connect(_on_item_pressed)
	btn_default.pressed.connect(_on_default_pressed)
	btn_brave.pressed.connect(_on_brave_pressed)

	# Start a test battle
	_start_test_battle()


func _start_test_battle() -> void:
	"""Start a test battle with sprite display"""
	log_message("[color=cyan]=== COWARDLY IRREGULAR ===[/color]")
	log_message("[color=yellow]Battle Start![/color]")

	# Create test player
	test_player = Combatant.new()
	test_player.initialize({
		"name": "Hero",
		"max_hp": 120,
		"max_mp": 50,
		"attack": 15,
		"defense": 12,
		"magic": 10,
		"speed": 10
	})
	add_child(test_player)
	JobSystem.assign_job(test_player, "fighter")

	# Create test enemy
	test_enemy = Combatant.new()
	test_enemy.initialize({
		"name": "Slime",
		"max_hp": 80,
		"max_mp": 20,
		"attack": 10,
		"defense": 8,
		"magic": 5,
		"speed": 8
	})
	add_child(test_enemy)

	# Add weaknesses/resistances for testing
	test_enemy.elemental_weaknesses.append("fire")
	test_enemy.elemental_resistances.append("ice")

	# Connect combatant signals
	test_player.hp_changed.connect(_on_player_hp_changed)
	test_player.ap_changed.connect(_on_player_ap_changed)
	test_enemy.hp_changed.connect(_on_enemy_hp_changed)
	test_enemy.died.connect(_on_enemy_died)

	# Create sprites
	_create_battle_sprites()

	# Start battle
	BattleManager.start_battle([test_player], [test_enemy])

	_update_ui()


func _create_battle_sprites() -> void:
	"""Create placeholder battle sprites (12-bit style)"""

	# Create player sprite (Knight/Fighter)
	player_sprite = _create_character_sprite(Color(0.2, 0.6, 0.9), "FIGHTER")
	player_sprite.position = party_positions[0].global_position
	player_sprite.scale = Vector2(-1, 1)  # Flip to face left
	party_sprites.add_child(player_sprite)

	# Create enemy sprite (Slime)
	enemy_sprite = _create_enemy_sprite(Color(0.3, 0.8, 0.3), "SLIME")
	enemy_sprite.position = enemy_positions[0].global_position
	enemy_sprites.add_child(enemy_sprite)


func _create_character_sprite(color: Color, label: String) -> Sprite2D:
	"""Create a placeholder character sprite with 12-bit aesthetic"""
	var sprite = Sprite2D.new()

	# Create a simple colored sprite placeholder
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Draw character silhouette (simple rectangle for now)
	for y in range(10, 60):
		for x in range(20, 44):
			var c = color
			# Add simple shading
			if x < 24 or y < 15:
				c = color.lightened(0.2)
			elif x > 38 or y > 50:
				c = color.darkened(0.2)
			img.set_pixel(x, y, c)

	# Add label
	var texture = ImageTexture.create_from_image(img)
	sprite.texture = texture
	sprite.centered = true

	# Add label below sprite
	var label_node = Label.new()
	label_node.text = label
	label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_node.position = Vector2(-32, 35)
	sprite.add_child(label_node)

	return sprite


func _create_enemy_sprite(color: Color, label: String) -> Sprite2D:
	"""Create a placeholder enemy sprite"""
	var sprite = Sprite2D.new()

	# Create enemy sprite (blob-like for slime)
	var img = Image.create(80, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Draw blob shape
	for y in range(20, 55):
		for x in range(15, 65):
			var dist_from_center = sqrt(pow(x - 40, 2) + pow(y - 37, 2))
			if dist_from_center < 22:
				var c = color
				# Gradient shading
				if y < 30:
					c = color.lightened(0.3)
				elif y > 45:
					c = color.darkened(0.3)
				img.set_pixel(x, y, c)

	var texture = ImageTexture.create_from_image(img)
	sprite.texture = texture
	sprite.centered = true

	# Add label
	var label_node = Label.new()
	label_node.text = label
	label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_node.position = Vector2(-40, 35)
	sprite.add_child(label_node)

	return sprite


func _update_ui() -> void:
	"""Update all UI elements"""
	_update_character_status()
	_update_action_buttons()


func _update_character_status() -> void:
	"""Update character status display"""
	if not test_player:
		return

	var job_name = test_player.job.get("name", "None") if test_player.job else "None"
	char1_name.text = "%s (%s)" % [test_player.combatant_name, job_name]

	char1_hp.max_value = test_player.max_hp
	char1_hp.value = test_player.current_hp
	char1_hp_label.text = "HP: %d/%d" % [test_player.current_hp, test_player.max_hp]

	char1_mp.max_value = test_player.max_mp
	char1_mp.value = test_player.current_mp
	char1_mp_label.text = "MP: %d/%d" % [test_player.current_mp, test_player.max_mp]

	var ap_color = "white"
	if test_player.current_ap > 0:
		ap_color = "green"
	elif test_player.current_ap < 0:
		ap_color = "red"

	char1_ap.text = "[color=%s]AP: %+d[/color]" % [ap_color, test_player.current_ap]


func _update_action_buttons() -> void:
	"""Enable/disable action buttons based on battle state"""
	var is_player_turn = BattleManager.current_state == BattleManager.BattleState.PLAYER_TURN
	var current = BattleManager.current_combatant

	btn_attack.disabled = not is_player_turn
	btn_ability.disabled = not is_player_turn
	btn_item.disabled = not is_player_turn
	btn_default.disabled = not is_player_turn

	# Brave requires non-negative AP
	if current and is_player_turn:
		btn_brave.disabled = current.current_ap < 0
	else:
		btn_brave.disabled = true


func _update_turn_info() -> void:
	"""Update turn information display"""
	if not BattleManager.current_combatant:
		return

	var current = BattleManager.current_combatant
	turn_info.text = "Round %d - %s's Turn (AP: %+d)" % [
		BattleManager.current_round,
		current.combatant_name,
		current.current_ap
	]


func log_message(message: String) -> void:
	"""Add a message to the battle log"""
	print(message)

	if battle_log:
		battle_log.append_text(message + "\n")
		battle_log.scroll_to_line(battle_log.get_line_count())


## Button handlers
func _on_attack_pressed() -> void:
	"""Handle Attack button"""
	if test_enemy and test_enemy.is_alive:
		_flash_sprite(enemy_sprite, Color.RED)
		BattleManager.player_attack(test_enemy)


func _on_ability_pressed() -> void:
	"""Handle Ability button"""
	if not test_player or not test_player.job:
		log_message("No job assigned!")
		return

	var abilities = test_player.job.get("abilities", [])
	if abilities.size() == 0:
		log_message("No abilities available!")
		return

	# Use first ability (Power Strike for Fighter)
	var ability_id = abilities[0]
	var ability = JobSystem.get_ability(ability_id)

	if ability.is_empty():
		log_message("Ability not found: %s" % ability_id)
		return

	# Determine targets
	var targets = []
	var target_type = ability.get("target_type", "single_enemy")

	match target_type:
		"single_enemy", "all_enemies":
			if test_enemy and test_enemy.is_alive:
				targets = [test_enemy]
		"single_ally", "all_allies":
			targets = [test_player]

	if targets.size() > 0:
		_flash_sprite(enemy_sprite, Color.YELLOW)
		BattleManager.player_use_ability(ability_id, targets)
	else:
		log_message("No valid targets!")


func _on_item_pressed() -> void:
	"""Handle Item button"""
	log_message("[color=gray]Items menu - TODO[/color]")


func _on_default_pressed() -> void:
	"""Handle Default button"""
	_flash_sprite(player_sprite, Color.CYAN)
	BattleManager.player_default()


func _on_brave_pressed() -> void:
	"""Handle Brave button"""
	log_message("[color=yellow]Using Brave![/color]")

	var actions = [
		{"type": "attack", "target": test_enemy},
		{"type": "attack", "target": test_enemy}
	]

	_flash_sprite(player_sprite, Color.ORANGE)
	BattleManager.player_brave(actions)


func _flash_sprite(sprite: Sprite2D, flash_color: Color) -> void:
	"""Flash sprite with color effect"""
	if not sprite:
		return

	var original_modulate = sprite.modulate
	sprite.modulate = flash_color

	# Reset after delay
	await get_tree().create_timer(0.2).timeout
	if sprite:
		sprite.modulate = original_modulate


## Battle event handlers
func _on_battle_started() -> void:
	"""Handle battle start"""
	log_message("[color=yellow]>>> Battle commenced![/color]")
	_update_ui()


func _on_battle_ended(victory: bool) -> void:
	"""Handle battle end"""
	if victory:
		log_message("\n[color=lime]=== VICTORY ===[/color]")
		if enemy_sprite:
			enemy_sprite.modulate = Color(1, 1, 1, 0.3)
	else:
		log_message("\n[color=red]=== DEFEAT ===[/color]")

	_update_ui()


func _on_turn_started(combatant: Combatant) -> void:
	"""Handle turn start"""
	log_message("\n[color=aqua]--- %s's turn ---[/color]" % combatant.combatant_name)
	_update_turn_info()
	_update_ui()


func _on_turn_ended(combatant: Combatant) -> void:
	"""Handle turn end"""
	_update_ui()


func _on_action_executed(combatant: Combatant, action: Dictionary, targets: Array) -> void:
	"""Handle action execution"""
	_update_ui()


## Combatant event handlers
func _on_player_hp_changed(old_value: int, new_value: int) -> void:
	"""Handle player HP change"""
	_update_ui()
	if new_value < old_value and player_sprite:
		_flash_sprite(player_sprite, Color.RED)


func _on_player_ap_changed(old_value: int, new_value: int) -> void:
	"""Handle player AP change"""
	_update_ui()


func _on_enemy_hp_changed(old_value: int, new_value: int) -> void:
	"""Handle enemy HP change"""
	if new_value < old_value and enemy_sprite:
		_flash_sprite(enemy_sprite, Color.RED)


func _on_enemy_died() -> void:
	"""Handle enemy death"""
	log_message("[color=yellow]%s has been defeated![/color]" % test_enemy.combatant_name)
	if enemy_sprite:
		# Fade out animation
		var tween = create_tween()
		tween.tween_property(enemy_sprite, "modulate:a", 0.0, 0.5)
		tween.tween_property(enemy_sprite, "scale", Vector2(0.5, 0.5), 0.5).set_trans(Tween.TRANS_BACK)
