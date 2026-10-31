extends SceneTree

const ShotGuard = preload("res://tools/shot_guard.gd")

## Visual proof that a quip bubble sits over its OWN speaker's head, per starter job and world costume
## (struktured 2026-10-31: "the Cleric's speech bubble isn't positioned correctly over her").
## A real battle and the real BattleScene._spawn_quip_bubble; one speaker at a time.
##   tools/bubble_anchor_shots.sh [--world=N]   (N 1-6; the wrapper runs all six)
## Writes tmp/bubble_anchor/w<N>_<job>.png crops (speaker + bubble) and prints each anchor.

const OUT := "res://tmp/bubble_anchor"
const CROP := Vector2i(440, 400)


func _init() -> void:
	var world := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="):
			world = int(a.get_slice("=", 1))
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("[SHOT] FAIL: no GameState")
		quit(1)
		return
	gs.current_world = world
	if "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var hints = load("res://src/ui/TutorialHints.gd")
	for id in (hints.HINTS.keys() if hints and ("HINTS" in hints) else []):
		gs.game_constants["tutorial_" + str(id)] = true
	DirAccess.make_dir_recursive_absolute(OUT)

	var gl: Node = (load("res://src/GameLoop.tscn") as PackedScene).instantiate()
	root.add_child(gl)
	for i in 4:
		await process_frame
	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await process_frame
	gs.current_world = world
	gl._create_party()
	await gl._start_battle_async(["goblin"], true)
	var scene: Node = _find(root)
	if scene == null:
		print("[SHOT] FAIL: no BattleScene")
		quit(1)
		return
	await create_timer(1.0, true, false, true).timeout
	var fails := 0
	var shots := 0
	for pc in scene.party_members:
		_clear_bubbles()
		await process_frame
		var sprite: Node2D = scene._get_combatant_sprite(pc)
		if sprite == null:
			print("[SHOT] FAIL: no sprite for %s" % pc.combatant_name)
			fails += 1
			continue
		if sprite.has_meta("home_position"):
			sprite.position = sprite.get_meta("home_position")
		var job: String = str(pc.job.get("id", "?")) if pc.job is Dictionary else "?"
		var home: Vector2 = sprite.global_position
		var anchor := home + Vector2(BattleSpeechBubble.head_dx(sprite), -BattleSpeechBubble.head_lift(sprite))
		## The open command menu draws over a bubble (z 100 > 95) and pushes it aside; hide it for the frame.
		_hide_menus(scene)
		scene._spawn_quip_bubble(sprite, pc.combatant_name, "Is this over MY head?", scene._get_job_quip_color(pc), 30.0)
		## The fade-in runs in battle time, so 0.6 real s caught it part-transparent at 1x.
		await create_timer(1.5, true, false, true).timeout
		var live := BattleSpeechBubble._live.size()
		var img := root.get_texture().get_image()
		var c0 := Vector2i(int(anchor.x) - CROP.x / 2, int(anchor.y) - 170)
		c0.x = clampi(c0.x, 0, img.get_width() - CROP.x)
		c0.y = clampi(c0.y, 0, img.get_height() - CROP.y)
		var crop := img.get_region(Rect2i(c0, CROP))
		var out := "%s/w%d_%s.png" % [OUT, world, job]
		if live == 0:
			print("[SHOT] FAIL: %s no bubble live" % job)
			fails += 1
		elif ShotGuard.save_or_refuse(crop, out):
			shots += 1
		else:
			fails += 1
		print("[SHOT] w%d %s home=%s anchor=%s head_dx=%.1f lift=%.1f flip=%s scale=%.2f live=%d" % [
			world, job, str(home.round()), str(anchor.round()), BattleSpeechBubble.head_dx(sprite),
			BattleSpeechBubble.head_lift(sprite), str((sprite as AnimatedSprite2D).flip_h) if sprite is AnimatedSprite2D else "-",
			sprite.scale.x, live])
	_clear_bubbles()
	print("[SHOT] done world=%d shots=%d failed=%d" % [world, shots, fails])
	quit(0 if fails == 0 and shots > 0 else 1)


func _hide_menus(scene: Node) -> void:
	var m = scene.get("active_win98_menu")
	while m != null and is_instance_valid(m):
		m.visible = false
		m = m.get("submenu")


func _clear_bubbles() -> void:
	for e in BattleSpeechBubble._live:
		if is_instance_valid(e["bubble"]):
			e["bubble"].queue_free()
	BattleSpeechBubble._live.clear()


func _find(n: Node) -> Node:
	if n.has_method("_spawn_quip_bubble") and "party_members" in n:
		return n
	for c in n.get_children():
		var f := _find(c)
		if f != null:
			return f
	return null
