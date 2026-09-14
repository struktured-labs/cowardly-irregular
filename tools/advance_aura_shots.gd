extends SceneTree

## Visual proof for the Advance aura: a real battle, the real handler, counts 1-5.
##
##   XDG_DATA_HOME=$PWD/tmp/shot_xdg xvfb-run -a godot --audio-driver Dummy --rendering-driver opengl3 \
##     --resolution 1280x720 -s tools/advance_aura_shots.gd
##
## Writes tmp/advance_aura/count_<n>.png (full frame), a crop per count, and strip.png — the five
## crops side by side plus 4/4 below a full bank, so the gold rim reads against its control.
## Sandboxed user:// is not optional: this runs the GAME, which resolves user:// by application
## name and would otherwise land in the player's live save directory.

const OUT := "res://tmp/advance_aura"
const CROP := Vector2i(260, 260)
var _fail: int = 0


func _init() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	if gs and "debug_all_pcs_unlocked" in gs:
		gs.debug_all_pcs_unlocked = false
	DirAccess.make_dir_recursive_absolute(OUT)
	## Tutorial panels cover the top of the frame — where the V-formation's lead PC stands. The same
	## suppression marketing_shots.gd uses: TutorialHint.show_hint short-circuits on
	## game_constants["tutorial_" + id]. Loud if the id set reads empty, which would suppress nothing.
	var hints = load("res://src/ui/TutorialHints.gd")
	var ids: Array = hints.HINTS.keys() if hints and ("HINTS" in hints) else []
	if ids.is_empty():
		print("[SHOT] FAIL: TutorialHints.HINTS unreadable or empty — hints would cover the actor")
		quit(1)
		return
	for id in ids:
		gs.game_constants["tutorial_" + str(id)] = true
	print("[SHOT] suppressed %d tutorial hints" % ids.size())

	var gl: Node = (load("res://src/GameLoop.tscn") as PackedScene).instantiate()
	root.add_child(gl)
	for i in 4:
		await process_frame
	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await process_frame
	gl._create_party()
	await gl._start_battle_async(["goblin"], true)
	await create_timer(2.5).timeout

	var scene: Node = _find_battle_scene(root)
	if scene == null:
		print("[SHOT] FAIL: no BattleScene with _on_advance_queue_changed in the tree")
		quit(1)
		return
	var bm = root.get_node("BattleManager")
	var pc = bm.current_combatant
	if pc == null or not (pc in scene.party_members):
		pc = scene.party_members[0]
		bm.current_combatant = pc
	var sprite: Node2D = scene._get_combatant_sprite(pc)
	print("[SHOT] actor=%s job=%s tier=%d time_scale=%.2f" % [pc.combatant_name, str(pc.job.get("id", "")), int(root.get_node("BattleJuice").battle_tier()), Engine.time_scale])

	var crops: Array[Image] = []
	for n in range(1, 6):
		scene._on_advance_queue_changed(n, 5)
		await create_timer(0.35).timeout
		crops.append(_capture("count_%d" % n, sprite))
	## The control for the gold rim: a full queue BELOW a full bank.
	scene._on_advance_queue_changed(0, 4)
	await create_timer(0.1).timeout
	for n in range(1, 5):
		scene._on_advance_queue_changed(n, 4)
	await create_timer(0.35).timeout
	crops.append(_capture("count_4_of_4", sprite))
	scene._on_advance_queue_changed(0, 4)

	var strip := Image.create(CROP.x * crops.size(), CROP.y, false, Image.FORMAT_RGBA8)
	for i in crops.size():
		strip.blit_rect(crops[i], Rect2i(Vector2i.ZERO, CROP), Vector2i(CROP.x * i, 0))
	strip.save_png(OUT + "/strip.png")
	print("[SHOT] strip: 1/5 2/5 3/5 4/5 5/5(full bank) | 4/4(below full bank)  -> %s/strip.png" % OUT)
	quit(0 if _fail == 0 else 1)


func _capture(tag: String, sprite: Node2D) -> Image:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, tag])
	var at := Vector2i(sprite.get_global_transform_with_canvas().origin) - CROP / 2
	at = at.clamp(Vector2i.ZERO, Vector2i(img.get_width(), img.get_height()) - CROP)
	var crop := img.get_region(Rect2i(at, CROP))
	crop.save_png("%s/%s_crop.png" % [OUT, tag])
	var aura = null
	for child in sprite.get_children():
		if child.name == "AdvanceAura":
			aura = child
	if aura == null or not aura.is_active():
		print("[SHOT] FAIL: %s — no active aura on the actor" % tag)
		_fail += 1
	else:
		print("[SHOT] %s count=%d full_bank=%s at=%s" % [tag, aura.count, str(aura.full_bank), str(at)])
	return crop


func _find_battle_scene(node: Node) -> Node:
	if node.has_method("_on_advance_queue_changed"):
		return node
	for child in node.get_children():
		var hit := _find_battle_scene(child)
		if hit:
			return hit
	return null
