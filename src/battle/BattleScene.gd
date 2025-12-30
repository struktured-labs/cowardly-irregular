extends Control

## BattleScene - Main battle UI controller
## Handles user input and displays battle state

@onready var battle_log: RichTextLabel = $VBoxContainer/BattleLog
@onready var action_menu: VBoxContainer = $VBoxContainer/ActionMenu
@onready var player_info: VBoxContainer = $VBoxContainer/PlayerInfo
@onready var enemy_info: VBoxContainer = $VBoxContainer/EnemyInfo
@onready var turn_info: Label = $VBoxContainer/TurnInfo

## Action buttons
@onready var btn_attack: Button = $VBoxContainer/ActionMenu/AttackButton
@onready var btn_abilities: Button = $VBoxContainer/ActionMenu/AbilitiesButton
@onready var btn_items: Button = $VBoxContainer/ActionMenu/ItemsButton
@onready var btn_default: Button = $VBoxContainer/ActionMenu/DefaultButton
@onready var btn_brave: Button = $VBoxContainer/ActionMenu/BraveButton

## Test combatants
var test_player: Combatant
var test_enemy: Combatant


func _ready() -> void:
	# Connect to BattleManager signals
	BattleManager.battle_started.connect(_on_battle_started)
	BattleManager.battle_ended.connect(_on_battle_ended)
	BattleManager.turn_started.connect(_on_turn_started)
	BattleManager.turn_ended.connect(_on_turn_ended)
	BattleManager.action_executed.connect(_on_action_executed)

	# Connect button signals
	btn_attack.pressed.connect(_on_attack_pressed)
	btn_abilities.pressed.connect(_on_abilities_pressed)
	btn_items.pressed.connect(_on_items_pressed)
	btn_default.pressed.connect(_on_default_pressed)
	btn_brave.pressed.connect(_on_brave_pressed)

	# Start a test battle
	_start_test_battle()


func _start_test_battle() -> void:
	"""Start a test battle with dummy combatants"""
	log_message("=== Cowardly Irregular - Battle Test ===")
	log_message("Initializing battle system...")

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

	# Assign Fighter job
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

	# Connect combatant signals
	test_player.hp_changed.connect(_on_player_hp_changed)
	test_player.bp_changed.connect(_on_player_bp_changed)
	test_enemy.hp_changed.connect(_on_enemy_hp_changed)
	test_enemy.died.connect(_on_enemy_died)

	# Start battle
	BattleManager.start_battle([test_player], [test_enemy])

	_update_ui()


func _update_ui() -> void:
	"""Update all UI elements"""
	_update_player_info()
	_update_enemy_info()
	_update_action_buttons()


func _update_player_info() -> void:
	"""Update player info display"""
	if not test_player:
		return

	var info_text = "[b]%s[/b] (Fighter)\n" % test_player.combatant_name
	info_text += "HP: %d/%d (%.0f%%)\n" % [test_player.current_hp, test_player.max_hp, test_player.get_hp_percentage()]
	info_text += "MP: %d/%d\n" % [test_player.current_mp, test_player.max_mp]
	info_text += "BP: %d\n" % test_player.current_bp
	info_text += "ATK: %d | DEF: %d | SPD: %d" % [test_player.attack, test_player.defense, test_player.speed]

	if player_info:
		# For now, just print to console until we set up the UI nodes
		pass


func _update_enemy_info() -> void:
	"""Update enemy info display"""
	if not test_enemy or not test_enemy.is_alive:
		return

	var info_text = "[b]%s[/b]\n" % test_enemy.combatant_name
	info_text += "HP: %d/%d (%.0f%%)" % [test_enemy.current_hp, test_enemy.max_hp, test_enemy.get_hp_percentage()]


func _update_action_buttons() -> void:
	"""Enable/disable action buttons based on battle state"""
	var is_player_turn = BattleManager.current_state == BattleManager.BattleState.PLAYER_TURN
	var current = BattleManager.current_combatant

	if action_menu:
		btn_attack.disabled = not is_player_turn
		btn_abilities.disabled = not is_player_turn
		btn_items.disabled = not is_player_turn
		btn_default.disabled = not is_player_turn

		# Brave button requires BP >= 0
		if current and is_player_turn:
			btn_brave.disabled = current.current_bp < 0
		else:
			btn_brave.disabled = true


func _update_turn_info() -> void:
	"""Update turn information display"""
	if not BattleManager.current_combatant:
		return

	var current = BattleManager.current_combatant
	var info = "Round %d | %s's Turn | BP: %d" % [BattleManager.current_round, current.combatant_name, current.current_bp]

	if turn_info:
		turn_info.text = info
	else:
		log_message(info)


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
		BattleManager.player_attack(test_enemy)


func _on_abilities_pressed() -> void:
	"""Handle Abilities button - Test with Power Strike for now"""
	if not test_player or not test_player.job:
		log_message("No job assigned!")
		return

	var abilities = test_player.job.get("abilities", [])
	if abilities.size() == 0:
		log_message("No abilities available!")
		return

	# For testing, use the first ability (Power Strike for Fighter)
	var ability_id = abilities[0]
	var ability = JobSystem.get_ability(ability_id)

	if ability.is_empty():
		log_message("Ability not found: %s" % ability_id)
		return

	log_message("Using ability: %s (MP: %d)" % [ability["name"], ability.get("mp_cost", 0)])

	# Determine targets based on ability type
	var targets = []
	var target_type = ability.get("target_type", "single_enemy")

	match target_type:
		"single_enemy":
			if test_enemy and test_enemy.is_alive:
				targets = [test_enemy]
		"all_enemies":
			if test_enemy and test_enemy.is_alive:
				targets = [test_enemy]
		"single_ally":
			targets = [test_player]
		"all_allies":
			targets = [test_player]

	if targets.size() > 0:
		BattleManager.player_use_ability(ability_id, targets)
	else:
		log_message("No valid targets!")


func _on_items_pressed() -> void:
	"""Handle Items button"""
	log_message("Items menu - TODO")
	# TODO: Show items menu


func _on_default_pressed() -> void:
	"""Handle Default button"""
	BattleManager.player_default()


func _on_brave_pressed() -> void:
	"""Handle Brave button - queue 2 attacks as example"""
	log_message("Using Brave with 2 attacks")

	var actions = [
		{"type": "attack", "target": test_enemy},
		{"type": "attack", "target": test_enemy}
	]

	BattleManager.player_brave(actions)


## Battle event handlers
func _on_battle_started() -> void:
	"""Handle battle start"""
	log_message("Battle started!")
	_update_ui()


func _on_battle_ended(victory: bool) -> void:
	"""Handle battle end"""
	if victory:
		log_message("\n=== VICTORY ===")
	else:
		log_message("\n=== DEFEAT ===")

	_update_ui()


func _on_turn_started(combatant: Combatant) -> void:
	"""Handle turn start"""
	log_message("\n--- %s's turn ---" % combatant.combatant_name)
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


func _on_player_bp_changed(old_value: int, new_value: int) -> void:
	"""Handle player BP change"""
	_update_ui()


func _on_enemy_hp_changed(old_value: int, new_value: int) -> void:
	"""Handle enemy HP change"""
	_update_ui()


func _on_enemy_died() -> void:
	"""Handle enemy death"""
	log_message("%s has been defeated!" % test_enemy.combatant_name)
	_update_ui()
