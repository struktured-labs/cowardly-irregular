extends SceneTree

## A live two-link chain through the real GameLoop, for struktured's "too abrupt" (2026-11-01). Run through
## tools/chain_shots.sh (sandboxed). Writes tmp/chain_shots/{1_first_banner,2_card,3_second_banner}.png.

const OUT := "res://tmp/chain_shots"


func _init() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var hints = load("res://src/ui/TutorialHints.gd")
	if gs and hints and ("HINTS" in hints):
		for id in hints.HINTS.keys():
			gs.game_constants["tutorial_" + str(id)] = true
	DirAccess.make_dir_recursive_absolute(OUT)
	var gl: Node = (load("res://src/GameLoop.tscn") as PackedScene).instantiate()
	root.add_child(gl)
	for i in 4:
		await process_frame
	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await process_frame
	gl._create_party()
	gl._chain_links = [[["bat", "bat"]]]
	gl._chain_total = 2
	gl._chain_index = 1
	gl._chain_engaged = 1
	gl.chain_card_seconds = 6.0
	await gl._start_battle_async(["slime"], true)
	if not await _wait_for("ChainBanner", 300):
		print("[SHOT] FAIL: battle one never showed its chain banner")
		quit(1)
		return
	_hide_menu()
	await _save("%s/1_first_banner.png" % OUT)
	gl._continue_chain()
	if not await _wait_for("ChainCard", 300):
		print("[SHOT] FAIL: no card between the links")
		quit(1)
		return
	for i in 20:
		await process_frame
	await _save("%s/2_card.png" % OUT)
	var card = gl.get_node_or_null("ChainCard")
	if card:
		card._finish()
	for i in 600:
		await process_frame
		var b := _find_named(root, "ChainBanner")
		if b and b is Label and (b as Label).text.begins_with("CHAIN 2/"):
			break
	_hide_menu()
	for i in 10:
		await process_frame
	await _save("%s/3_second_banner.png" % OUT)
	print("[SHOT] done")
	quit(0)


func _wait_for(n: String, frames: int) -> bool:
	for i in frames:
		await process_frame
		if _find_named(root, n) != null:
			return true
	return false


func _hide_menu() -> void:
	var scene := _find_named(root, "BattleScene")
	var menu = scene.get("active_win98_menu") if scene else null
	if menu and is_instance_valid(menu):
		menu.visible = false


func _save(path: String) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[SHOT] SCREEN %s %dx%d" % [path, img.get_width(), img.get_height()])


func _find_named(node: Node, n: String) -> Node:
	if str(node.name).begins_with(n):
		return node
	for child in node.get_children():
		var hit := _find_named(child, n)
		if hit:
			return hit
	return null
