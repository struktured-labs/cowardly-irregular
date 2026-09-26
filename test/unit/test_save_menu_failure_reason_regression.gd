extends GutTest

## Pause-menu Save stacks a second warning on top of save_failed.
## GameLoop already toasts the real blocker ("Cannot save inside this room",
## "Cannot save with the whole party down"). SaveScreen then added
## "Save failed (battle in progress or disk write error)" for every refusal,
## so a player who opened the menu in a chapel and picked a slot was told a
## battle was in progress. The wiped party below is the same branch — any
## non-battle refusal hits that one banner.

var _saved_party: Array = []
var _saved_battle_state: int = 0
var _reasons: Array[String] = []


func before_each() -> void:
	_saved_party = GameState.player_party.duplicate(true)
	_saved_battle_state = BattleManager.current_state
	BattleManager.current_state = BattleManager.BattleState.INACTIVE
	_reasons.clear()
	_clear_toasts()


func after_each() -> void:
	if SaveSystem.save_failed.is_connected(_grab_reason):
		SaveSystem.save_failed.disconnect(_grab_reason)
	GameState.player_party = _saved_party
	BattleManager.current_state = _saved_battle_state
	_clear_toasts()


func _grab_reason(reason: String) -> void:
	_reasons.append(reason)


func _wiped_party() -> Array:
	return [
		{"name": "Fighter", "job_id": "fighter", "is_alive": false, "current_hp": 0},
		{"name": "Cleric", "job_id": "cleric", "is_alive": false, "current_hp": 0},
	]


func _set_party(arr: Array) -> void:
	var typed: Array[Dictionary] = []
	for m in arr:
		typed.append(m)
	GameState.player_party = typed


func _clear_toasts() -> void:
	for layer in Toast._active_layers:
		if is_instance_valid(layer):
			layer.queue_free()
	Toast._active_layers.clear()


func _toast_texts() -> Array[String]:
	var out: Array[String] = []
	for layer in Toast._active_layers:
		if not is_instance_valid(layer):
			continue
		for child in layer.get_children():
			if child is Label and not out.has(child.text):
				out.append(child.text)
	return out


func test_menu_save_refusal_does_not_blame_a_battle() -> void:
	_set_party(_wiped_party())
	var screen = load("res://src/ui/SaveScreen.gd").new()
	add_child_autofree(screen)
	SaveSystem.save_failed.connect(_grab_reason)
	screen._do_save(0)
	assert_eq(_reasons.size(), 1, "the menu save must still report exactly one blocker")
	assert_eq(_reasons[0], "Cannot save with the whole party down",
		"the blocker the player is owed is the wipe, not a phantom battle")
	var banners := _toast_texts()
	for banner in banners:
		assert_false(banner.contains("battle"),
			"the save menu must not claim a battle is in progress: '%s'" % banner)
		assert_false(banner.contains("disk"),
			"the save menu must not claim a disk error: '%s'" % banner)
		assert_eq(banner, _reasons[0],
			"if the menu also toasts, it must repeat the real blocker and nothing else")
