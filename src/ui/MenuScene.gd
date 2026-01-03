extends Control

## MenuScene - Hub menu between battles
## Shows status, allows preparation, and continues to next battle

signal continue_pressed
signal status_pressed

@onready var continue_btn: Button = $VBoxContainer/ContinueButton
@onready var status_btn: Button = $VBoxContainer/StatusButton
@onready var status_panel: Panel = $StatusPanel
@onready var status_label: RichTextLabel = $StatusPanel/MarginContainer/StatusLabel

## Player reference (passed from battle)
var player: Combatant = null

## Battle count for progression
var battle_count: int = 0


func _ready() -> void:
	# Connect button signals
	continue_btn.pressed.connect(_on_continue_pressed)
	status_btn.pressed.connect(_on_status_pressed)

	# Hide status panel initially
	if status_panel:
		status_panel.visible = false


func setup(player_combatant: Combatant, battles_completed: int) -> void:
	"""Setup menu with player data"""
	player = player_combatant
	battle_count = battles_completed

	_update_status_display()


func _update_status_display() -> void:
	"""Update the status panel content"""
	if not player:
		return
	if not status_label:
		return

	var job_name = "None"
	if player.job:
		job_name = player.job.get("name", "Unknown")

	var status_text = """[b]=== HERO STATUS ===[/b]

[color=cyan]HP:[/color] %d / %d
[color=blue]MP:[/color] %d / %d

[b]Job:[/b] %s (Lv. %d)
[color=gray]EXP: %d / %d[/color]

[b]Stats:[/b]
  ATK: %d  DEF: %d
  MAG: %d  SPD: %d

[b]Equipment:[/b]
  Weapon: %s
  Armor: %s
  Accessory: %s

[b]Battles Won:[/b] %d
""" % [
		player.current_hp, player.max_hp,
		player.current_mp, player.max_mp,
		job_name,
		player.job_level,
		player.job_exp,
		player.job_level * 100,
		player.attack,
		player.defense,
		player.magic,
		player.speed,
		player.equipped_weapon if player.equipped_weapon else "None",
		player.equipped_armor if player.equipped_armor else "None",
		player.equipped_accessory if player.equipped_accessory else "None",
		battle_count
	]

	status_label.text = status_text


func _on_continue_pressed() -> void:
	"""Handle continue button - go to next battle"""
	continue_pressed.emit()


func _on_status_pressed() -> void:
	"""Toggle status panel visibility"""
	if status_panel:
		status_panel.visible = not status_panel.visible
		_update_status_display()
