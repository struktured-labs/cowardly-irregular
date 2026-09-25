extends TreasureChest
class_name MimicChest

## A DungeonPuzzleLayer trap_chests entry -- opens like any TreasureChest, but the payoff is a battle instead of loot.

var cave_ref: Node = null
var mimic_monster_id: String = "treasure_mimic"
var _ambush_started: bool = false
## Held across the teeth line so cancel/step encounters cannot start a fight this emit will lose.
var _ambush_lock: Node = null

const _TELLS := [
	"The GM's notes, found later: 'chest, contains: teeth.'",
	"Somewhere, a loot table laughs at you specifically.",
	"It was never going to be a potion.",
]


func _exit_tree() -> void:
	_release_ambush_lock()


func _hold_ambush_lock() -> void:
	if not is_inside_tree():
		return
	_ambush_lock = get_tree().root.get_node_or_null("InputLockManager")
	if _ambush_lock and _ambush_lock.has_method("push_lock"):
		_ambush_lock.push_lock("mimic_ambush")


func _release_ambush_lock() -> void:
	if _ambush_lock and is_instance_valid(_ambush_lock) and _ambush_lock.has_method("pop_lock"):
		_ambush_lock.pop_lock("mimic_ambush")
	_ambush_lock = null


## GameLoop drops some emits after this chest would already be spent. No GameLoop (unit harness) means the emit itself is the battle.
func _ambush_would_be_dropped() -> bool:
	if not is_inside_tree():
		return false
	var gl := get_tree().root.get_node_or_null("GameLoop")
	if gl == null or not gl.has_method("battle_trigger_would_be_dropped"):
		return false
	return bool(gl.call("battle_trigger_would_be_dropped"))


func _clear_pending_tell() -> void:
	if GameState == null or not ("game_constants" in GameState):
		return
	if str(GameState.game_constants.get("pending_battle_flavor_line", "")) in _TELLS:
		GameState.game_constants.erase("pending_battle_flavor_line")


func _restore_closed_prompt() -> void:
	_clear_pending_tell()
	if name_label:
		name_label.text = "Treasure"
		name_label.add_theme_color_override("font_color", Color.GOLD)
		name_label.visible = _player_nearby
	if dialogue_box:
		dialogue_box.visible = false


func _open_chest(_player: Node2D) -> void:
	if _ambush_started:
		return
	_ambush_started = true
	_hold_ambush_lock()
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
	_release_ambush_lock()
	# Floor change during this line deletes the chest; a menu or an in-flight battle drops the emit. Neither may spend it.
	if not (cave_ref and is_instance_valid(cave_ref) and cave_ref.has_signal("battle_triggered")) or _ambush_would_be_dropped():
		_ambush_started = false
		_restore_closed_prompt()
		return
	dialogue_box.visible = false
	GameState.set_story_flag("chest_" + chest_id)
	cave_ref.battle_triggered.emit([mimic_monster_id])
