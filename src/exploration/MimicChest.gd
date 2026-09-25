extends TreasureChest
class_name MimicChest

## A DungeonPuzzleLayer trap_chests entry -- opens like any TreasureChest, but the payoff is a battle instead of loot.

var cave_ref: Node = null
var mimic_monster_id: String = "treasure_mimic"
var _ambush_started: bool = false

const _TELLS := [
	"The GM's notes, found later: 'chest, contains: teeth.'",
	"Somewhere, a loot table laughs at you specifically.",
	"It was never going to be a potion.",
]


func _open_chest(_player: Node2D) -> void:
	if _ambush_started:
		return
	_ambush_started = true
	if SoundManager:
		SoundManager.play_ui("chest_open")
	name_label.text = "?!"
	name_label.add_theme_color_override("font_color", Color.RED)
	name_label.visible = true
	_clamp_dialogue_box_to_viewport()
	dialogue_box.visible = true
	dialogue_label.text = "It has teeth."
	if GameState and "game_constants" in GameState:
		GameState.game_constants["pending_battle_flavor_line"] = _TELLS[randi() % _TELLS.size()]
	await get_tree().create_timer(0.6).timeout
	if not is_instance_valid(self):
		return
	dialogue_box.visible = false
	# Spend the chest only once a battle is actually emitted — a floor change during this line used to delete it with no fight.
	if cave_ref and is_instance_valid(cave_ref) and cave_ref.has_signal("battle_triggered"):
		GameState.set_story_flag("chest_" + chest_id)
		cave_ref.battle_triggered.emit([mimic_monster_id])
		return
	_ambush_started = false
