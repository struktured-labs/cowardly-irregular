extends Control

## BattleScene - FF-style battle UI with sprites
## Enemies on left, party on right, classic JRPG layout

# Preload class dependencies to ensure they're registered before use
const BattleAnimatorClass = preload("res://src/battle/BattleAnimator.gd")
const RetroFontClass = preload("res://src/ui/RetroFont.gd")
const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")

## UI References
@onready var battle_log: RichTextLabel = $UI/BattleLogPanel/MarginContainer/VBoxContainer/BattleLog
@onready var turn_info: Label = $UI/TurnInfoPanel/TurnInfo

## Action buttons (legacy - hidden when using Win98 menu)
@onready var action_menu_panel: PanelContainer = $UI/ActionMenuPanel
@onready var btn_attack: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/AttackButton
@onready var btn_ability: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/AbilityButton
@onready var btn_item: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/ItemButton
@onready var btn_default: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/DefaultButton
@onready var btn_bide: Button = $UI/ActionMenuPanel/MarginContainer/VBoxContainer/BideButton

## Win98 style menu
var active_win98_menu: Win98MenuClass = null
var use_win98_menus: bool = true  # Toggle for Win98 style menus

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
var party_members: Array[Combatant] = []
var test_enemies: Array[Combatant] = []

## Sprite nodes
var party_sprite_nodes: Array[AnimatedSprite2D] = []
var enemy_sprite_nodes: Array[AnimatedSprite2D] = []

## Animators
var party_animators: Array[BattleAnimatorClass] = []
var enemy_animators: Array[BattleAnimatorClass] = []

## Legacy single-player references (point to first party member)
var test_player: Combatant:
	get: return party_members[0] if party_members.size() > 0 else null
var player_sprite: AnimatedSprite2D:
	get: return party_sprite_nodes[0] if party_sprite_nodes.size() > 0 else null
var player_animator: BattleAnimatorClass:
	get: return party_animators[0] if party_animators.size() > 0 else null

## Target selection state
var pending_action: Dictionary = {}
var is_selecting_target: bool = false

## External party flag
var _has_external_party: bool = false


func set_player(player: Combatant) -> void:
	"""Set external player from GameLoop (legacy single player)"""
	party_members = [player]
	_has_external_party = true


func set_party(party: Array[Combatant]) -> void:
	"""Set external party from GameLoop"""
	party_members = party
	_has_external_party = true


func _ready() -> void:
	# Apply retro font styling
	RetroFontClass.configure_battle_log(battle_log)

	# Connect to BattleManager signals
	BattleManager.battle_started.connect(_on_battle_started)
	BattleManager.battle_ended.connect(_on_battle_ended)
	BattleManager.turn_started.connect(_on_turn_started)
	BattleManager.turn_ended.connect(_on_turn_ended)
	BattleManager.action_executed.connect(_on_action_executed)

	# Connect button signals (for legacy mode)
	btn_attack.pressed.connect(_on_attack_pressed)
	btn_ability.pressed.connect(_on_ability_pressed)
	btn_item.pressed.connect(_on_item_pressed)
	btn_default.pressed.connect(_on_default_pressed)
	btn_bide.pressed.connect(_on_bide_pressed)

	# Hide legacy action panel if using Win98 menus
	if use_win98_menus:
		action_menu_panel.visible = false
		action_menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Disable focus on all buttons to prevent accidental activation
		btn_attack.focus_mode = Control.FOCUS_NONE
		btn_ability.focus_mode = Control.FOCUS_NONE
		btn_item.focus_mode = Control.FOCUS_NONE
		btn_default.focus_mode = Control.FOCUS_NONE
		btn_bide.focus_mode = Control.FOCUS_NONE

	# Add autobattle toggle
	_create_autobattle_toggle()

	# Load default autobattle script
	BattleManager.set_autobattle_script("Aggressive")

	# Start a test battle
	_start_test_battle()


func _create_autobattle_toggle() -> void:
	"""Create autobattle toggle checkbox"""
	var action_menu = $UI/ActionMenuPanel/MarginContainer/VBoxContainer

	# Add separator
	var separator = HSeparator.new()
	action_menu.add_child(separator)

	# Add autobattle checkbox
	var autobattle_check = CheckBox.new()
	autobattle_check.name = "AutobattleToggle"
	autobattle_check.text = "Autobattle (Aggressive)"
	autobattle_check.toggled.connect(_on_autobattle_toggled)
	action_menu.add_child(autobattle_check)


func _start_test_battle() -> void:
	"""Start a test battle with sprite display"""
	log_message("[color=cyan]=== COWARDLY IRREGULAR ===[/color]")
	log_message("[color=yellow]Battle Start![/color]")

	# Use external party if provided, otherwise create default party
	if not _has_external_party:
		_create_default_party()

	# Create test enemies (1-3 random enemies)
	_spawn_enemies()

	# Connect party member signals
	for i in range(party_members.size()):
		var member = party_members[i]
		if not member.hp_changed.is_connected(_on_party_hp_changed):
			member.hp_changed.connect(_on_party_hp_changed.bind(i))
		if not member.ap_changed.is_connected(_on_party_ap_changed):
			member.ap_changed.connect(_on_party_ap_changed.bind(i))

	# Create sprites
	_create_battle_sprites()

	# Start battle
	BattleManager.start_battle(party_members, test_enemies)


func _create_default_party() -> void:
	"""Create default party for standalone mode"""
	party_members.clear()

	# Create Hero (Fighter)
	var hero = Combatant.new()
	hero.initialize({
		"name": "Hero",
		"max_hp": 150,
		"max_mp": 50,
		"attack": 25,
		"defense": 15,
		"magic": 12,
		"speed": 12
	})
	add_child(hero)
	JobSystem.assign_job(hero, "fighter")
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
	party_members.append(hero)

	# Create Mira (White Mage)
	var mira = Combatant.new()
	mira.initialize({
		"name": "Mira",
		"max_hp": 100,
		"max_mp": 120,
		"attack": 10,
		"defense": 12,
		"magic": 28,
		"speed": 14
	})
	add_child(mira)
	JobSystem.assign_job(mira, "white_mage")
	EquipmentSystem.equip_weapon(mira, "oak_staff")
	EquipmentSystem.equip_armor(mira, "cloth_robe")
	EquipmentSystem.equip_accessory(mira, "magic_ring")
	mira.learn_passive("magic_boost")
	mira.learn_passive("mp_boost")
	PassiveSystem.equip_passive(mira, "magic_boost")
	PassiveSystem.equip_passive(mira, "mp_boost")
	party_members.append(mira)

	# Create Zack (Thief)
	var zack = Combatant.new()
	zack.initialize({
		"name": "Zack",
		"max_hp": 90,
		"max_mp": 40,
		"attack": 18,
		"defense": 10,
		"magic": 8,
		"speed": 22
	})
	add_child(zack)
	JobSystem.assign_job(zack, "thief")
	EquipmentSystem.equip_weapon(zack, "iron_dagger")
	EquipmentSystem.equip_armor(zack, "thief_garb")
	EquipmentSystem.equip_accessory(zack, "speed_boots")
	zack.learn_passive("critical_strike")
	zack.learn_passive("speed_boost")
	PassiveSystem.equip_passive(zack, "critical_strike")
	PassiveSystem.equip_passive(zack, "speed_boost")
	party_members.append(zack)

	# Create Vex (Black Mage)
	var vex = Combatant.new()
	vex.initialize({
		"name": "Vex",
		"max_hp": 80,
		"max_mp": 150,
		"attack": 8,
		"defense": 8,
		"magic": 35,
		"speed": 12
	})
	add_child(vex)
	JobSystem.assign_job(vex, "black_mage")
	EquipmentSystem.equip_weapon(vex, "shadow_rod")
	EquipmentSystem.equip_armor(vex, "dark_robe")
	EquipmentSystem.equip_accessory(vex, "mp_amulet")
	vex.learn_passive("magic_boost")
	vex.learn_passive("mp_efficiency")
	PassiveSystem.equip_passive(vex, "magic_boost")
	PassiveSystem.equip_passive(vex, "mp_efficiency")
	party_members.append(vex)


## Available monster types for random encounters
const MONSTER_TYPES = [
	{
		"id": "slime",
		"name": "Slime",
		"color": Color(0.3, 0.8, 0.3),
		"stats": {"max_hp": 80, "max_mp": 20, "attack": 10, "defense": 8, "magic": 5, "speed": 8},
		"weaknesses": ["fire"],
		"resistances": ["ice"]
	},
	{
		"id": "bat",
		"name": "Bat",
		"color": Color(0.4, 0.3, 0.5),
		"stats": {"max_hp": 50, "max_mp": 15, "attack": 12, "defense": 5, "magic": 6, "speed": 18},
		"weaknesses": ["fire", "lightning"],
		"resistances": []
	},
	{
		"id": "mushroom",
		"name": "Fungoid",
		"color": Color(0.6, 0.4, 0.3),
		"stats": {"max_hp": 100, "max_mp": 25, "attack": 8, "defense": 12, "magic": 10, "speed": 5},
		"weaknesses": ["fire"],
		"resistances": ["poison"]
	},
	{
		"id": "imp",
		"name": "Imp",
		"color": Color(0.8, 0.3, 0.3),
		"stats": {"max_hp": 70, "max_mp": 50, "attack": 8, "defense": 8, "magic": 18, "speed": 14},
		"weaknesses": ["ice", "holy"],
		"resistances": ["fire", "dark"]
	},
	{
		"id": "goblin",
		"name": "Goblin",
		"color": Color(0.5, 0.6, 0.3),
		"stats": {"max_hp": 120, "max_mp": 30, "attack": 15, "defense": 10, "magic": 8, "speed": 12},
		"weaknesses": ["lightning"],
		"resistances": []
	},
	{
		"id": "skeleton",
		"name": "Skeleton",
		"color": Color(0.9, 0.9, 0.85),
		"stats": {"max_hp": 90, "max_mp": 10, "attack": 14, "defense": 6, "magic": 3, "speed": 10},
		"weaknesses": ["holy", "fire"],
		"resistances": ["dark", "poison"]
	},
	{
		"id": "wolf",
		"name": "Dire Wolf",
		"color": Color(0.4, 0.35, 0.3),
		"stats": {"max_hp": 110, "max_mp": 15, "attack": 18, "defense": 8, "magic": 4, "speed": 16},
		"weaknesses": ["fire"],
		"resistances": ["ice"]
	},
	{
		"id": "ghost",
		"name": "Specter",
		"color": Color(0.7, 0.8, 0.9),
		"stats": {"max_hp": 60, "max_mp": 80, "attack": 6, "defense": 4, "magic": 20, "speed": 14},
		"weaknesses": ["holy"],
		"resistances": ["physical", "dark"]
	},
	{
		"id": "snake",
		"name": "Viper",
		"color": Color(0.3, 0.5, 0.2),
		"stats": {"max_hp": 70, "max_mp": 30, "attack": 12, "defense": 7, "magic": 8, "speed": 20},
		"weaknesses": ["ice"],
		"resistances": ["poison"]
	}
]


func _spawn_enemies() -> void:
	"""Spawn 1-3 random enemies for the battle"""
	# Clear any existing enemies
	for enemy in test_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	test_enemies.clear()

	# Random number of enemies (2-3, limited by available positions)
	var max_enemies = mini(3, enemy_positions.size())
	var num_enemies = randi_range(2, max_enemies)

	# Pick a random monster type for this encounter
	var monster_type = MONSTER_TYPES[randi() % MONSTER_TYPES.size()]

	for i in range(num_enemies):
		var enemy = Combatant.new()
		var suffix = "" if num_enemies == 1 else " " + ["A", "B", "C"][i]
		var stats = monster_type["stats"].duplicate()
		stats["name"] = monster_type["name"] + suffix
		# Slight speed variation for turn order variety
		stats["speed"] = stats["speed"] + i
		enemy.initialize(stats)
		add_child(enemy)

		# Add weaknesses/resistances from monster type
		for weakness in monster_type.get("weaknesses", []):
			enemy.elemental_weaknesses.append(weakness)
		for resistance in monster_type.get("resistances", []):
			enemy.elemental_resistances.append(resistance)

		# Connect signals
		enemy.hp_changed.connect(_on_enemy_hp_changed.bind(i))
		enemy.died.connect(_on_enemy_died.bind(i))

		test_enemies.append(enemy)

	log_message("[color=gray]%d %s(s) appeared![/color]" % [num_enemies, monster_type["name"]])

	_update_ui()


func _create_battle_sprites() -> void:
	"""Create animated battle sprites (12-bit style)"""

	# Clear existing party sprites
	for sprite in party_sprite_nodes:
		if is_instance_valid(sprite):
			sprite.queue_free()
	party_sprite_nodes.clear()

	for animator in party_animators:
		if is_instance_valid(animator):
			animator.queue_free()
	party_animators.clear()

	# Clear existing enemy sprites
	for sprite in enemy_sprite_nodes:
		if is_instance_valid(sprite):
			sprite.queue_free()
	enemy_sprite_nodes.clear()

	for animator in enemy_animators:
		if is_instance_valid(animator):
			animator.queue_free()
	enemy_animators.clear()

	# Create party member sprites
	for i in range(party_members.size()):
		var member = party_members[i]
		var sprite = AnimatedSprite2D.new()

		# Choose sprite based on job
		var job_id = member.job.get("id", "fighter") if member.job else "fighter"
		match job_id:
			"white_mage":
				sprite.sprite_frames = BattleAnimatorClass.create_mage_sprite_frames(Color(0.9, 0.9, 1.0))
			"black_mage":
				sprite.sprite_frames = BattleAnimatorClass.create_mage_sprite_frames(Color(0.15, 0.1, 0.25))
			"thief":
				sprite.sprite_frames = BattleAnimatorClass.create_thief_sprite_frames()
			_:
				sprite.sprite_frames = BattleAnimatorClass.create_hero_sprite_frames()

		sprite.position = party_positions[i].global_position if i < party_positions.size() else Vector2(600, 100 + i * 100)
		sprite.flip_h = true  # Flip to face left
		sprite.play("idle")
		party_sprites.add_child(sprite)
		party_sprite_nodes.append(sprite)

		var animator = BattleAnimatorClass.new()
		animator.setup(sprite)
		add_child(animator)
		party_animators.append(animator)

		# Add label with character name
		_add_sprite_label(sprite, member.combatant_name.to_upper(), Vector2(-20, 40))

	# Create enemy sprites
	for i in range(test_enemies.size()):
		var enemy = test_enemies[i]

		var sprite = AnimatedSprite2D.new()
		sprite.sprite_frames = BattleAnimatorClass.create_slime_sprite_frames()
		sprite.position = enemy_positions[i].global_position if i < enemy_positions.size() else Vector2(200 + i * 100, 300)
		sprite.play("idle")
		$BattleField/EnemySprites.add_child(sprite)
		enemy_sprite_nodes.append(sprite)

		var animator = BattleAnimatorClass.new()
		animator.setup(sprite)
		add_child(animator)
		enemy_animators.append(animator)

		# Add label with enemy name
		_add_sprite_label(sprite, enemy.combatant_name.to_upper(), Vector2(-20, 40))


func _add_sprite_label(sprite: AnimatedSprite2D, text: String, offset: Vector2) -> void:
	"""Add a label below a sprite"""
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = offset
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	sprite.add_child(label)


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


## Dynamic party status UI elements
var _party_status_boxes: Array = []


func _update_character_status() -> void:
	"""Update character status display for all party members"""
	if party_members.size() == 0:
		return

	# Create status boxes if needed
	_ensure_party_status_boxes()

	# Update each party member's status
	for i in range(party_members.size()):
		if i >= _party_status_boxes.size():
			break
		_update_member_status(i, party_members[i])


func _ensure_party_status_boxes() -> void:
	"""Ensure we have status boxes for all party members (only creates once)"""
	# Skip if already created for this party
	if _party_status_boxes.size() == party_members.size():
		var all_valid = true
		for box in _party_status_boxes:
			if not is_instance_valid(box):
				all_valid = false
				break
		if all_valid:
			return

	var container = $UI/PartyStatusPanel/VBoxContainer

	# Clear existing dynamic boxes
	for box in _party_status_boxes:
		if is_instance_valid(box):
			box.queue_free()
	_party_status_boxes.clear()

	# Hide the static Character1 node if it exists
	var char1_node = container.get_node_or_null("Character1")
	if char1_node:
		char1_node.visible = false

	# Create status boxes for each party member
	for i in range(party_members.size()):
		var member = party_members[i]
		var box = _create_character_status_box(i, member)
		container.add_child(box)
		_party_status_boxes.append(box)


func _create_character_status_box(idx: int, member: Combatant) -> VBoxContainer:
	"""Create a status box for a party member"""
	var box = VBoxContainer.new()
	box.name = "Character%d" % (idx + 1)

	# Name label
	var name_label = Label.new()
	name_label.name = "Name"
	var job_name = member.job.get("name", "None") if member.job else "None"
	name_label.text = "%s (%s)" % [member.combatant_name, job_name]
	box.add_child(name_label)

	# HP bar
	var hp_bar = ProgressBar.new()
	hp_bar.name = "HP"
	hp_bar.custom_minimum_size = Vector2(0, 18)
	hp_bar.max_value = member.max_hp
	hp_bar.value = member.current_hp
	hp_bar.show_percentage = false
	box.add_child(hp_bar)

	# HP label inside bar
	var hp_label = Label.new()
	hp_label.name = "HPLabel"
	hp_label.text = "HP: %d/%d" % [member.current_hp, member.max_hp]
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_bar.add_child(hp_label)

	# MP bar
	var mp_bar = ProgressBar.new()
	mp_bar.name = "MP"
	mp_bar.custom_minimum_size = Vector2(0, 14)
	mp_bar.max_value = member.max_mp
	mp_bar.value = member.current_mp
	mp_bar.show_percentage = false
	box.add_child(mp_bar)

	# MP label inside bar
	var mp_label = Label.new()
	mp_label.name = "MPLabel"
	mp_label.text = "MP: %d/%d" % [member.current_mp, member.max_mp]
	mp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	mp_bar.add_child(mp_label)

	# AP/Status label
	var ap_label = RichTextLabel.new()
	ap_label.name = "AP"
	ap_label.bbcode_enabled = true
	ap_label.fit_content = true
	ap_label.custom_minimum_size = Vector2(0, 16)
	ap_label.text = "AP: 0"
	box.add_child(ap_label)

	return box


func _update_member_status(idx: int, member: Combatant) -> void:
	"""Update a single party member's status display"""
	if idx >= _party_status_boxes.size():
		return

	var box = _party_status_boxes[idx]
	if not is_instance_valid(box):
		return

	# Update name
	var name_label = box.get_node_or_null("Name")
	if name_label:
		var job_name = member.job.get("name", "None") if member.job else "None"
		var level_text = " Lv.%d" % member.job_level if member.job_level > 1 else ""
		name_label.text = "%s (%s%s)" % [member.combatant_name, job_name, level_text]

	# Update HP
	var hp_bar = box.get_node_or_null("HP")
	if hp_bar:
		hp_bar.max_value = member.max_hp
		hp_bar.value = member.current_hp
		var hp_label = hp_bar.get_node_or_null("HPLabel")
		if hp_label:
			hp_label.text = "HP: %d/%d" % [member.current_hp, member.max_hp]

	# Update MP
	var mp_bar = box.get_node_or_null("MP")
	if mp_bar:
		mp_bar.max_value = member.max_mp
		mp_bar.value = member.current_mp
		var mp_label = mp_bar.get_node_or_null("MPLabel")
		if mp_label:
			mp_label.text = "MP: %d/%d" % [member.current_mp, member.max_mp]

	# Update AP and status
	var ap_label = box.get_node_or_null("AP")
	if ap_label:
		var ap_color = "white"
		if member.current_ap > 0:
			ap_color = "green"
		elif member.current_ap < 0:
			ap_color = "red"

		var status_text = "[color=%s]AP: %+d[/color]" % [ap_color, member.current_ap]

		# Add status effects
		if member.status_effects.size() > 0:
			status_text += " ["
			for i in range(member.status_effects.size()):
				if i > 0:
					status_text += ", "
				status_text += "[color=yellow]%s[/color]" % member.status_effects[i].capitalize()
			status_text += "]"

		ap_label.text = status_text


func _update_action_buttons() -> void:
	"""Enable/disable action buttons based on battle state"""
	var is_player_turn = BattleManager.current_state == BattleManager.BattleState.PLAYER_TURN
	var current = BattleManager.current_combatant

	btn_attack.disabled = not is_player_turn
	btn_ability.disabled = not is_player_turn
	btn_item.disabled = not is_player_turn
	btn_default.disabled = not is_player_turn

	# Bide requires non-negative AP
	if current and is_player_turn:
		btn_bide.disabled = current.current_ap < 0
	else:
		btn_bide.disabled = true


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
	var alive_enemies = _get_alive_enemies()

	if alive_enemies.size() == 0:
		log_message("No enemies to attack!")
		return

	if alive_enemies.size() == 1:
		# Single target - attack immediately
		_execute_attack(alive_enemies[0])
	else:
		# Multiple targets - show target selection
		pending_action = {"type": "attack"}
		_show_target_selection(alive_enemies)


func _get_alive_enemies() -> Array[Combatant]:
	"""Get all alive enemies"""
	var alive: Array[Combatant] = []
	for enemy in test_enemies:
		if is_instance_valid(enemy) and enemy.is_alive:
			alive.append(enemy)
	return alive


func _show_target_selection(targets: Array[Combatant]) -> void:
	"""Show popup menu for target selection"""
	is_selecting_target = true

	var popup = PopupMenu.new()
	popup.name = "TargetMenu"
	add_child(popup)

	for i in range(targets.size()):
		var target = targets[i]
		var label = "%s (HP: %d/%d)" % [target.combatant_name, target.current_hp, target.max_hp]
		popup.add_item(label, i)

	popup.id_pressed.connect(_on_target_selected.bind(targets))
	popup.close_requested.connect(func(): is_selecting_target = false)
	popup.popup_centered()


func _on_target_selected(idx: int, targets: Array[Combatant]) -> void:
	"""Handle target selection"""
	is_selecting_target = false

	if idx < 0 or idx >= targets.size():
		return

	var target = targets[idx]

	match pending_action.get("type", ""):
		"attack":
			_execute_attack(target)
		"ability":
			_execute_ability(pending_action.get("ability_id", ""), target)

	pending_action = {}


func _get_current_combatant_animator() -> BattleAnimatorClass:
	"""Get the animator for the current combatant"""
	var current = BattleManager.current_combatant
	if not current:
		return null
	var idx = party_members.find(current)
	if idx >= 0 and idx < party_animators.size():
		return party_animators[idx]
	return null


func _execute_attack(target: Combatant) -> void:
	"""Execute attack on target with animations"""
	var target_idx = test_enemies.find(target)
	var attacker_animator = _get_current_combatant_animator()

	# Play attack animation for current combatant
	if attacker_animator:
		attacker_animator.play_attack(func():
			if target_idx >= 0 and target_idx < enemy_animators.size():
				enemy_animators[target_idx].play_hit()
			# Spawn physical hit effect on target
			if target_idx >= 0 and target_idx < enemy_sprite_nodes.size():
				var sprite = enemy_sprite_nodes[target_idx]
				if is_instance_valid(sprite):
					EffectSystem.spawn_effect(EffectSystem.EffectType.PHYSICAL, sprite.global_position)
		)

	BattleManager.player_attack(target)


func _on_ability_pressed() -> void:
	"""Handle Ability button"""
	var current = BattleManager.current_combatant
	if not current or not current.job:
		log_message("No job assigned!")
		return

	var abilities = current.job.get("abilities", [])
	if abilities.size() == 0:
		log_message("No abilities available!")
		return

	# Show ability selection menu
	_show_ability_menu(abilities)


func _show_ability_menu(ability_ids: Array) -> void:
	"""Show popup menu for ability selection"""
	var current = BattleManager.current_combatant
	if not current:
		return

	var popup = PopupMenu.new()
	popup.name = "AbilityMenu"
	add_child(popup)

	for i in range(ability_ids.size()):
		var ability_id = ability_ids[i]
		var ability = JobSystem.get_ability(ability_id)
		if ability.is_empty():
			continue

		var mp_cost = ability.get("mp_cost", 0)
		var can_afford = current.current_mp >= mp_cost
		var label = "%s (MP: %d)" % [ability["name"], mp_cost]

		popup.add_item(label, i)
		if not can_afford:
			popup.set_item_disabled(i, true)

	popup.id_pressed.connect(_on_ability_selected.bind(ability_ids))
	popup.popup_centered()


func _on_ability_selected(idx: int, ability_ids: Array) -> void:
	"""Handle ability selection from menu"""
	if idx < 0 or idx >= ability_ids.size():
		return

	var ability_id = ability_ids[idx]
	var ability = JobSystem.get_ability(ability_id)
	var target_type = ability.get("target_type", "single_enemy")
	var alive_enemies = _get_alive_enemies()

	var current = BattleManager.current_combatant

	match target_type:
		"single_enemy":
			if alive_enemies.size() == 1:
				_execute_ability(ability_id, alive_enemies[0])
			elif alive_enemies.size() > 1:
				pending_action = {"type": "ability", "ability_id": ability_id}
				_show_target_selection(alive_enemies)
			else:
				log_message("No valid targets!")
		"all_enemies":
			if alive_enemies.size() > 0:
				_execute_ability(ability_id, alive_enemies[0], true)
			else:
				log_message("No valid targets!")
		"single_ally", "all_allies", "self":
			_execute_ability(ability_id, current if current else party_members[0])


func _execute_ability(ability_id: String, target: Combatant, target_all: bool = false) -> void:
	"""Execute ability with animations based on ability type"""
	var targets = []
	if target_all:
		targets = _get_alive_enemies()
	else:
		targets = [target]

	# Get ability animation type
	var ability = JobSystem.get_ability(ability_id)
	var anim_type = ability.get("animation", "cast")

	# Play appropriate animation for current combatant
	var animator = _get_current_combatant_animator()
	if animator:
		_play_ability_animation(anim_type, animator)

	# Spawn visual effects on targets
	_spawn_ability_effects(ability_id, targets)

	BattleManager.player_use_ability(ability_id, targets)


func _spawn_ability_effects(ability_id: String, targets: Array) -> void:
	"""Spawn visual effects for an ability on all targets"""
	var canvas_transform = get_viewport().get_canvas_transform()

	for target in targets:
		if not is_instance_valid(target):
			continue

		# Find target sprite position
		var target_pos = Vector2.ZERO

		# Check if target is an enemy
		var enemy_idx = test_enemies.find(target)
		if enemy_idx >= 0 and enemy_idx < enemy_sprite_nodes.size():
			var sprite = enemy_sprite_nodes[enemy_idx]
			if is_instance_valid(sprite):
				target_pos = sprite.global_position

		# Check if target is a party member
		var party_idx = party_members.find(target)
		if party_idx >= 0 and party_idx < party_sprite_nodes.size():
			var sprite = party_sprite_nodes[party_idx]
			if is_instance_valid(sprite):
				target_pos = sprite.global_position

		if target_pos != Vector2.ZERO:
			EffectSystem.spawn_ability_effect(ability_id, target_pos)


func _play_ability_animation(anim_type: String, animator: BattleAnimatorClass = null) -> void:
	"""Play animation based on ability animation type"""
	if not animator:
		animator = _get_current_combatant_animator()
	if not animator:
		return

	match anim_type:
		"attack":
			animator.play_attack()
		"heal", "buff":
			# Healing/buff - use cast with green/blue tint effect
			animator.play_cast()
		"cast_fire", "cast_ice", "cast_lightning", "cast_dark", "cast_time", "cast_meta":
			# All magic types use cast animation
			animator.play_cast()
		"special":
			# Special abilities use item animation
			animator.play_item()
		_:
			# Default to cast
			animator.play_cast()


func _on_item_pressed() -> void:
	"""Handle Item button"""
	var current = BattleManager.current_combatant
	if not current:
		return

	if current.inventory.is_empty():
		log_message("No items in inventory!")
		return

	# Show item selection menu
	_show_item_menu()


func _show_item_menu() -> void:
	"""Show popup menu for item selection"""
	var current = BattleManager.current_combatant
	if not current:
		return

	var popup = PopupMenu.new()
	popup.name = "ItemMenu"
	add_child(popup)

	var item_ids = []
	var idx = 0

	for item_id in current.inventory.keys():
		var item = ItemSystem.get_item(item_id)
		if item.is_empty():
			continue

		var quantity = current.inventory[item_id]
		var label = "%s x%d" % [item["name"], quantity]

		popup.add_item(label, idx)
		item_ids.append(item_id)
		idx += 1

	if item_ids.size() == 0:
		popup.queue_free()
		log_message("No valid items!")
		return

	popup.id_pressed.connect(_on_item_selected.bind(item_ids))
	popup.popup_centered()


func _on_item_selected(idx: int, item_ids: Array) -> void:
	"""Handle item selection from menu"""
	if idx < 0 or idx >= item_ids.size():
		return

	var item_id = item_ids[idx]
	var item = ItemSystem.get_item(item_id)
	var current = BattleManager.current_combatant

	# Determine targets
	var targets = []
	var target_type = item.get("target_type", ItemSystem.TargetType.SINGLE_ALLY)
	var alive_enemies = _get_alive_enemies()

	match target_type:
		ItemSystem.TargetType.SINGLE_ENEMY:
			if alive_enemies.size() > 0:
				targets = [alive_enemies[0]]  # Default to first alive enemy
		ItemSystem.TargetType.ALL_ENEMIES:
			targets = alive_enemies
		ItemSystem.TargetType.SINGLE_ALLY, ItemSystem.TargetType.ALL_ALLIES, ItemSystem.TargetType.SELF:
			targets = [current if current else party_members[0]]

	if targets.size() > 0:
		# Play item animation for current combatant
		var animator = _get_current_combatant_animator()
		if animator:
			animator.play_item()
		BattleManager.player_item(item_id, targets)
	else:
		log_message("No valid targets!")


func _on_default_pressed() -> void:
	"""Handle Default button"""
	# Play defend animation for current combatant
	var animator = _get_current_combatant_animator()
	if animator:
		animator.play_defend()
	BattleManager.player_default()
	_update_ui()  # Ensure AP display updates


func _on_bide_pressed() -> void:
	"""Handle Bide button - queues multiple attacks"""
	var alive_enemies = _get_alive_enemies()

	if alive_enemies.size() == 0:
		log_message("No enemies to attack!")
		return

	log_message("[color=yellow]Using Bide![/color]")

	# Target first alive enemy for now (could add multi-target selection later)
	var target = alive_enemies[0]
	var actions = [
		{"type": "attack", "target": target},
		{"type": "attack", "target": target}
	]

	# Play attack animation for current combatant
	var animator = _get_current_combatant_animator()
	if animator:
		animator.play_attack()
	BattleManager.player_brave(actions)
	_update_ui()  # Ensure AP display updates


func _on_autobattle_toggled(enabled: bool) -> void:
	"""Handle autobattle toggle"""
	BattleManager.toggle_autobattle(enabled)
	if enabled:
		log_message("[color=green]Autobattle enabled - AI will control your turns[/color]")
	else:
		log_message("[color=gray]Autobattle disabled - manual control[/color]")


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
		# Play victory animation for all party members
		for animator in party_animators:
			if animator:
				animator.play_victory()
	else:
		log_message("\n[color=red]=== DEFEAT ===[/color]")
		# Play defeat animation for all party members
		for animator in party_animators:
			if animator:
				animator.play_defeat()

	_update_ui()


func _on_turn_started(combatant: Combatant) -> void:
	"""Handle turn start"""
	log_message("\n[color=aqua]--- %s's turn ---[/color]" % combatant.combatant_name)
	_update_turn_info()
	_update_ui()

	# Show Win98 menu for player turns (use BattleManager.player_party for correct object identity)
	var is_player = combatant in BattleManager.player_party
	if is_player:
		# Play da-ding sound for player turn
		SoundManager.play_ui("player_turn")
	if use_win98_menus and is_player:
		_show_win98_command_menu(combatant)


func _on_turn_ended(combatant: Combatant) -> void:
	"""Handle turn end"""
	_close_win98_menu()
	_update_ui()


func _on_action_executed(combatant: Combatant, action: Dictionary, targets: Array) -> void:
	"""Handle action execution"""
	_update_ui()


## Combatant event handlers
func _on_party_hp_changed(old_value: int, new_value: int, member_idx: int) -> void:
	"""Handle party member HP change"""
	_update_ui()
	if new_value < old_value and member_idx < party_animators.size():
		# Play hit animation when taking damage
		party_animators[member_idx].play_hit()


func _on_party_ap_changed(old_value: int, new_value: int, member_idx: int) -> void:
	"""Handle party member AP change"""
	_update_ui()


# Legacy aliases for backwards compatibility
func _on_player_hp_changed(old_value: int, new_value: int) -> void:
	_on_party_hp_changed(old_value, new_value, 0)


func _on_player_ap_changed(old_value: int, new_value: int) -> void:
	_on_party_ap_changed(old_value, new_value, 0)


func _on_enemy_hp_changed(old_value: int, new_value: int, enemy_idx: int) -> void:
	"""Handle enemy HP change"""
	if new_value < old_value and enemy_idx < enemy_animators.size():
		# Play hit animation when taking damage
		enemy_animators[enemy_idx].play_hit()


func _on_enemy_died(enemy_idx: int) -> void:
	"""Handle enemy death"""
	if enemy_idx < test_enemies.size():
		var enemy = test_enemies[enemy_idx]
		log_message("[color=yellow]%s has been defeated![/color]" % enemy.combatant_name)

		if enemy_idx < enemy_animators.size() and enemy_idx < enemy_sprite_nodes.size():
			var animator = enemy_animators[enemy_idx]
			var sprite = enemy_sprite_nodes[enemy_idx]
			# Play defeat animation
			animator.play_defeat(func():
				# Fade out after defeat animation completes
				if is_instance_valid(sprite):
					var tween = create_tween()
					tween.tween_property(sprite, "modulate:a", 0.0, 0.5)
			)


## Win98 Menu Functions
func _unhandled_input(event: InputEvent) -> void:
	"""Handle input for menu and Brave/Default controls"""
	if event is InputEventKey and event.pressed and not event.echo:
		var current = BattleManager.current_combatant
		var is_player_turn = current and party_members.has(current)

		# R key = Default (skip turn, gain BP)
		if event.keycode == KEY_R and is_player_turn:
			_close_win98_menu()
			log_message("[color=cyan]%s defaults![/color]" % current.combatant_name)
			var animator = _get_current_combatant_animator()
			if animator:
				animator.play_defend()
			BattleManager.player_default()
			get_viewport().set_input_as_handled()
			return

		# L key = Brave (queue another action after current - TODO: implement action queue)
		if event.keycode == KEY_L and is_player_turn:
			log_message("[color=yellow]Brave! Queue another action...[/color]")
			# TODO: Implement action queuing system
			get_viewport().set_input_as_handled()
			return

		# Reopen menu on Space/Enter/Z if menu is closed
		if use_win98_menus and is_player_turn:
			if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_Z]:
				if not active_win98_menu or not is_instance_valid(active_win98_menu):
					_show_win98_command_menu(current)
					get_viewport().set_input_as_handled()


func _show_win98_command_menu(combatant: Combatant) -> void:
	"""Show retro command menu for the combatant"""
	# Close any existing menu
	_close_win98_menu()

	# Get character's sprite position (use BattleManager.player_party for correct object identity)
	var combatant_idx = BattleManager.player_party.find(combatant)
	if combatant_idx < 0 or combatant_idx >= party_sprite_nodes.size():
		return

	var sprite = party_sprite_nodes[combatant_idx]
	if not is_instance_valid(sprite):
		return

	var viewport_size = get_viewport_rect().size

	# Convert sprite position to screen coordinates
	# The sprite is in 2D world space, need to get its screen position
	var canvas_transform = get_viewport().get_canvas_transform()
	var screen_pos = canvas_transform * sprite.global_position

	# Position menu to the LEFT of the character sprite (menu expands left)
	# Menu width is ~140, place it so the right edge is near the sprite
	var menu_x = clamp(screen_pos.x - 150, 10, viewport_size.x - 150)
	var menu_y = clamp(screen_pos.y - 40, 10, viewport_size.y - 120)
	var menu_pos = Vector2(menu_x, menu_y)

	# Get character class for styling
	var job_id = combatant.job.get("id", "fighter") if combatant.job else "fighter"

	# Build menu items with enemy targets as submenus
	var menu_items = _build_command_menu_items_with_targets(combatant)

	# Create menu directly as child with high z_index
	active_win98_menu = Win98MenuClass.new()
	active_win98_menu.expand_left = true  # Expand submenus to the left
	active_win98_menu.expand_up = true  # Expand submenus upward
	active_win98_menu.is_root_menu = true  # Root menu can't be closed
	active_win98_menu.z_index = 100  # Render on top
	active_win98_menu.visible = true  # Ensure visible
	add_child(active_win98_menu)
	active_win98_menu.setup(combatant.combatant_name, menu_items, menu_pos, job_id)

	# Connect signals
	active_win98_menu.item_selected.connect(_on_win98_menu_selection)
	active_win98_menu.menu_closed.connect(_on_win98_menu_closed)
	active_win98_menu.actions_submitted.connect(_on_win98_actions_submitted)
	active_win98_menu.defer_requested.connect(_on_win98_defer_requested)

	# Set max queue size based on current AP (can queue up to AP+4 actions total)
	var max_queue = combatant.current_ap + 4  # First action is free, can go to -4 debt
	active_win98_menu.set_max_queue_size(max_queue)


func _build_command_menu_items_with_targets(combatant: Combatant) -> Array:
	"""Build command menu with enemy targets as submenus"""
	var items = []
	var alive_enemies = _get_alive_enemies()
	var canvas_transform = get_viewport().get_canvas_transform()

	# Attack -> submenu of enemy targets
	if alive_enemies.size() > 0:
		var enemy_targets = []
		for enemy in alive_enemies:
			var enemy_idx = test_enemies.find(enemy)
			var target_pos = Vector2.ZERO
			if enemy_idx >= 0 and enemy_idx < enemy_sprite_nodes.size():
				var sprite = enemy_sprite_nodes[enemy_idx]
				if is_instance_valid(sprite):
					target_pos = canvas_transform * sprite.global_position
			enemy_targets.append({
				"id": "attack_" + str(enemy_idx),
				"label": "%s (%d HP)" % [enemy.combatant_name, enemy.current_hp],
				"data": {"target_idx": enemy_idx, "action": "attack", "target_pos": target_pos}
			})
		items.append({
			"id": "attack_menu",
			"label": "Attack",
			"submenu": enemy_targets
		})
	else:
		items.append({
			"id": "attack",
			"label": "Attack",
			"data": null,
			"disabled": true
		})

	# Abilities -> submenu, each ability has enemy targets if offensive
	var abilities = combatant.job.get("abilities", []) if combatant.job else []
	if abilities.size() > 0:
		var ability_items = []
		for ability_id in abilities:
			var ability = JobSystem.get_ability(ability_id)
			if ability.is_empty():
				continue
			var mp_cost = ability.get("mp_cost", 0)
			var can_afford = combatant.current_mp >= mp_cost
			var target_type = ability.get("target_type", "single_enemy")

			# For enemy-targeting abilities, add enemy submenu
			if target_type == "single_enemy" and alive_enemies.size() > 0 and can_afford:
				var enemy_targets = []
				for enemy in alive_enemies:
					var enemy_idx = test_enemies.find(enemy)
					var target_pos = Vector2.ZERO
					if enemy_idx >= 0 and enemy_idx < enemy_sprite_nodes.size():
						var sprite = enemy_sprite_nodes[enemy_idx]
						if is_instance_valid(sprite):
							target_pos = canvas_transform * sprite.global_position
					enemy_targets.append({
						"id": "ability_" + ability_id + "_enemy_" + str(enemy_idx),
						"label": "%s (%d HP)" % [enemy.combatant_name, enemy.current_hp],
						"data": {"ability_id": ability_id, "target_idx": enemy_idx, "target_type": "enemy", "target_pos": target_pos}
					})
				ability_items.append({
					"id": "ability_menu_" + ability_id,
					"label": "%s (%d)" % [ability["name"], mp_cost],
					"submenu": enemy_targets,
					"disabled": not can_afford
				})
			# For ally-targeting abilities (heal, buff), add party submenu
			elif target_type == "single_ally" and can_afford:
				var ally_targets = []
				for i in range(party_members.size()):
					var member = party_members[i]
					if not is_instance_valid(member) or not member.is_alive:
						continue
					var target_pos = Vector2.ZERO
					if i < party_sprite_nodes.size():
						var sprite = party_sprite_nodes[i]
						if is_instance_valid(sprite):
							target_pos = canvas_transform * sprite.global_position
					ally_targets.append({
						"id": "ability_" + ability_id + "_ally_" + str(i),
						"label": "%s (%d/%d HP)" % [member.combatant_name, member.current_hp, member.max_hp],
						"data": {"ability_id": ability_id, "target_idx": i, "target_type": "ally", "target_pos": target_pos}
					})
				ability_items.append({
					"id": "ability_menu_" + ability_id,
					"label": "%s (%d)" % [ability["name"], mp_cost],
					"submenu": ally_targets,
					"disabled": not can_afford
				})
			else:
				ability_items.append({
					"id": "ability_" + ability_id,
					"label": "%s (%d)" % [ability["name"], mp_cost],
					"data": {"ability_id": ability_id},
					"disabled": not can_afford
				})

		if ability_items.size() > 0:
			items.append({
				"id": "ability_menu",
				"label": "Ability",
				"submenu": ability_items
			})

	# Items submenu
	if not combatant.inventory.is_empty():
		var item_items = []
		for item_id in combatant.inventory.keys():
			var item = ItemSystem.get_item(item_id)
			if item.is_empty():
				continue
			var quantity = combatant.inventory[item_id]
			item_items.append({
				"id": "item_" + item_id,
				"label": "%s x%d" % [item["name"], quantity],
				"data": {"item_id": item_id}
			})
		if item_items.size() > 0:
			items.append({
				"id": "item_menu",
				"label": "Item",
				"submenu": item_items
			})

	# Defer - skip turn, gain +1 AP (only available if AP < 4)
	items.append({
		"id": "defer",
		"label": "Defer",
		"data": null,
		"disabled": combatant.current_ap >= 4
	})

	# Note: Advance (queue another action) is R key or Shift+Enter

	return items


func _build_command_menu_items(combatant: Combatant) -> Array:
	"""Build the command menu items for a combatant (legacy)"""
	var items = []

	# Attack
	items.append({
		"id": "attack",
		"label": "Attack",
		"data": null
	})

	# Abilities submenu
	var abilities = combatant.job.get("abilities", []) if combatant.job else []
	if abilities.size() > 0:
		var ability_items = []
		for ability_id in abilities:
			var ability = JobSystem.get_ability(ability_id)
			if ability.is_empty():
				continue
			var mp_cost = ability.get("mp_cost", 0)
			var can_afford = combatant.current_mp >= mp_cost
			ability_items.append({
				"id": "ability_" + ability_id,
				"label": "%s (%d MP)" % [ability["name"], mp_cost],
				"data": {"ability_id": ability_id},
				"disabled": not can_afford
			})
		if ability_items.size() > 0:
			items.append({
				"id": "ability_menu",
				"label": "Ability",
				"submenu": ability_items
			})

	# Items submenu
	if not combatant.inventory.is_empty():
		var item_items = []
		for item_id in combatant.inventory.keys():
			var item = ItemSystem.get_item(item_id)
			if item.is_empty():
				continue
			var quantity = combatant.inventory[item_id]
			item_items.append({
				"id": "item_" + item_id,
				"label": "%s x%d" % [item["name"], quantity],
				"data": {"item_id": item_id}
			})
		if item_items.size() > 0:
			items.append({
				"id": "item_menu",
				"label": "Item",
				"submenu": item_items
			})

	# Defer - skip turn, gain +1 AP (only if AP < 4)
	items.append({
		"id": "defer",
		"label": "Defer",
		"data": null,
		"disabled": combatant.current_ap >= 4
	})

	# Note: Advance is R key or Shift+Enter

	return items


func _on_win98_menu_selection(item_id: String, item_data: Variant) -> void:
	"""Handle Win98 menu item selection"""
	# Force close menu first before processing action
	_close_win98_menu()

	var alive_enemies = _get_alive_enemies()
	var current = BattleManager.current_combatant

	# Attack with target from menu tree (attack_0, attack_1, etc)
	if item_id.begins_with("attack_") and item_data is Dictionary:
		var target_idx = item_data.get("target_idx", -1)
		if target_idx >= 0 and target_idx < test_enemies.size():
			var target = test_enemies[target_idx]
			if is_instance_valid(target) and target.is_alive:
				_execute_attack(target)
			else:
				log_message("Target no longer valid!")
		return

	# Ability with target from menu tree (enemy or ally)
	if item_data is Dictionary and item_data.has("ability_id") and item_data.has("target_idx"):
		var ability_id = item_data.get("ability_id", "")
		var target_idx = item_data.get("target_idx", -1)
		var target_type = item_data.get("target_type", "enemy")

		if ability_id != "" and target_idx >= 0:
			var target: Combatant = null

			if target_type == "ally":
				# Ally target (party member)
				if target_idx < party_members.size():
					target = party_members[target_idx]
			else:
				# Enemy target
				if target_idx < test_enemies.size():
					target = test_enemies[target_idx]

			if is_instance_valid(target) and target.is_alive:
				_execute_ability(ability_id, target)
			else:
				log_message("Target no longer valid!")
		return

	# Ability without pre-selected target (self/ally targeting or all enemies)
	if item_id.begins_with("ability_") and item_data is Dictionary:
		var ability_id = item_data.get("ability_id", "")
		if ability_id != "":
			var ability = JobSystem.get_ability(ability_id)
			var target_type = ability.get("target_type", "single_enemy")

			match target_type:
				"all_enemies":
					if alive_enemies.size() > 0:
						_execute_ability(ability_id, alive_enemies[0], true)
					else:
						log_message("No valid targets!")
				"single_ally", "all_allies", "self":
					_execute_ability(ability_id, current if current else party_members[0])
				_:
					# Fallback for single_enemy if somehow no target submenu
					if alive_enemies.size() > 0:
						_execute_ability(ability_id, alive_enemies[0])
		return

	# Item usage
	if item_id.begins_with("item_") and item_data is Dictionary:
		var i_id = item_data.get("item_id", "")
		if i_id != "":
			var item = ItemSystem.get_item(i_id)
			var targets = []
			var target_type = item.get("target_type", ItemSystem.TargetType.SINGLE_ALLY)

			match target_type:
				ItemSystem.TargetType.SINGLE_ENEMY:
					if alive_enemies.size() > 0:
						targets = [alive_enemies[0]]
				ItemSystem.TargetType.ALL_ENEMIES:
					targets = alive_enemies
				ItemSystem.TargetType.SINGLE_ALLY, ItemSystem.TargetType.ALL_ALLIES, ItemSystem.TargetType.SELF:
					targets = [current if current else party_members[0]]

			if targets.size() > 0:
				var animator = _get_current_combatant_animator()
				if animator:
					animator.play_item()
				BattleManager.player_item(i_id, targets)
			else:
				log_message("No valid targets!")
		return

	# Defer - skip turn, gain +1 AP
	if item_id == "defer":
		log_message("[color=cyan]%s defers![/color]" % current.combatant_name)
		var animator = _get_current_combatant_animator()
		if animator:
			animator.play_defend()
		BattleManager.player_default()
		_update_ui()  # Ensure AP display updates
		return


func _on_win98_menu_closed() -> void:
	"""Handle Win98 menu being closed"""
	active_win98_menu = null


func _on_win98_actions_submitted(actions: Array) -> void:
	"""Handle multiple actions submitted via Advance mode (Brave)"""
	active_win98_menu = null
	var current = BattleManager.current_combatant
	if not current:
		return

	# Convert menu actions to battle actions
	var battle_actions: Array[Dictionary] = []
	for action in actions:
		var action_id: String = action.get("id", "")
		var action_data = action.get("data", null)

		# Handle attack actions
		if action_id.begins_with("attack_") and action_data is Dictionary:
			var target_idx = action_data.get("target_idx", -1)
			if target_idx >= 0 and target_idx < test_enemies.size():
				var target = test_enemies[target_idx]
				if is_instance_valid(target):
					battle_actions.append({"type": "attack", "target": target})

		# Handle ability actions (enemy or ally targets)
		elif action_id.begins_with("ability_") and action_data is Dictionary:
			var ability_id = action_data.get("ability_id", "")
			var target_idx = action_data.get("target_idx", -1)
			var target_type = action_data.get("target_type", "enemy")

			if target_idx >= 0:
				var target: Combatant = null
				if target_type == "ally" and target_idx < party_members.size():
					target = party_members[target_idx]
				elif target_idx < test_enemies.size():
					target = test_enemies[target_idx]

				if is_instance_valid(target):
					battle_actions.append({"type": "ability", "ability_id": ability_id, "target": target})

	if battle_actions.size() > 0:
		log_message("[color=yellow]%s advances with %d actions![/color]" % [current.combatant_name, battle_actions.size()])
		var animator = _get_current_combatant_animator()
		if animator:
			animator.play_attack()
		BattleManager.player_brave(battle_actions)
		_update_ui()  # Ensure AP display updates


func _on_win98_defer_requested() -> void:
	"""Handle L button defer request (no queue)"""
	active_win98_menu = null
	var current = BattleManager.current_combatant
	if not current:
		return

	log_message("[color=cyan]%s defers![/color]" % current.combatant_name)
	var animator = _get_current_combatant_animator()
	if animator:
		animator.play_defend()
	BattleManager.player_default()
	_update_ui()  # Ensure AP display updates


func _close_win98_menu() -> void:
	"""Close the active Win98 menu"""
	if active_win98_menu and is_instance_valid(active_win98_menu):
		active_win98_menu.force_close()
		active_win98_menu = null
