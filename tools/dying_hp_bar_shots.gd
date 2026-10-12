extends SceneTree

const ShotGuard = preload("res://tools/shot_guard.gd")

## Visual proof that a defeated enemy's floating HP bar leaves with it.
##
##   tools/dying_hp_bar_shots.sh              # the fix
##   tools/dying_hp_bar_shots.sh --before     # the same build with the retire made a no-op
##
## Writes tmp/dying_hp_bar/: alive · dissolving (mid-dissolve, the frame the bug lives in) · gone,
## each as a full 1280x720 frame and a crop around the monster, plus strip.png side by side.
##
## --before does NOT edit or fabricate anything: it lifts the enemy out of `_enemy_hp_bars` for the
## duration of the kill, which makes `_retire_enemy_hp_bar` return early — exactly the pre-fix
## handler, which never looked at the bars at all. The rects are the real ones, placed by the real
## `_create_enemy_hp_bar`, on a sprite dissolving under the real shader.

const OUT := "res://tmp/dying_hp_bar"
const CROP := Vector2i(360, 300)
## Into the 0.5s dissolve: late enough that the figure has visibly gone, early enough to still be in it.
## ⛔ Waited in SCENE time, not real time: the battle runs at Engine.time_scale 0.25 ("1x"), so an
## ignore_time_scale timer took its "mid-dissolve" frame at dissolve_amount 0.00.
const MID_DISSOLVE_S := 0.55
const AFTER_S := 1.20
var _fail: int = 0
var _scene: Node
var _crops: Array[Image] = []
var _t_scene: float = 0.0
var _t0: float = 0.0


func _init() -> void:
	await process_frame
	await process_frame
	var before: bool = OS.get_cmdline_user_args().has("--before")
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	DirAccess.make_dir_recursive_absolute(OUT)
	var hints = load("res://src/ui/TutorialHints.gd")
	var ids: Array = hints.HINTS.keys() if hints and ("HINTS" in hints) else []
	if ids.is_empty():
		print("[SHOT] FAIL: TutorialHints.HINTS unreadable — a hint panel would cover the monster")
		quit(1)
		return
	for id in ids:
		gs.game_constants["tutorial_" + str(id)] = true

	var gl: Node = (load("res://src/GameLoop.tscn") as PackedScene).instantiate()
	root.add_child(gl)
	for i in 4:
		await process_frame
	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await process_frame
	gl._create_party()
	await gl._start_battle_async(["goblin"], true)

	_scene = _find_battle_scene(root)
	if _scene == null:
		print("[SHOT] FAIL: no BattleScene with _on_enemy_died in the tree")
		quit(1)
		return
	if _scene.enemy_sprite_nodes.is_empty() or _scene.test_enemies.is_empty():
		print("[SHOT] FAIL: the battle built no enemy, so there is no bar to measure")
		quit(1)
		return
	var sprite: Node2D = _scene.enemy_sprite_nodes[0]
	var foe = _scene.test_enemies[0]
	var bars: Dictionary = _scene._enemy_hp_bars.get(foe, {})
	if bars.is_empty():
		print("[SHOT] FAIL: %s carries no HP bar — nothing to prove either way" % foe.combatant_name)
		quit(1)
		return
	## Half health, so the fill is unmistakably a BAR rather than an empty socket in every frame.
	foe.current_hp = int(max(1, foe.max_hp / 2))
	_scene._update_enemy_hp_bars()
	await create_timer(0.4, true, false, false).timeout
	print("[SHOT] mode=%s foe=%s hp=%d/%d dissolve_shader=%s" % [
		"BEFORE (retire disabled)" if before else "FIX",
		foe.combatant_name, foe.current_hp, foe.max_hp, str(sprite.material is ShaderMaterial)])
	await _frame("alive", sprite, bars)

	_t0 = float(Time.get_ticks_msec())
	if before:
		_scene._enemy_hp_bars.erase(foe)
	foe.current_hp = 0
	_scene._on_enemy_died(0)
	if before:
		_scene._enemy_hp_bars[foe] = bars
	await create_timer(MID_DISSOLVE_S, true, false, false).timeout
	await _frame("dissolving", sprite, bars)
	await create_timer(AFTER_S - MID_DISSOLVE_S, true, false, false).timeout
	await _frame("gone", sprite, bars)
	_strip("strip")
	print("[SHOT] done, %d failed" % _fail)
	quit(0 if _fail == 0 else 1)


## One frame plus the measurement that makes it readable: the alpha the shader cannot reach.
func _frame(tag: String, sprite: Node2D, bars: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	_t_scene = (float(Time.get_ticks_msec()) - _t0) * 0.001 * Engine.time_scale if _t0 > 0.0 else 0.0
	var img := root.get_texture().get_image()
	var alphas: Array = []
	for key in ["bar_bg", "bar_trail", "bar_fill"]:
		var piece = bars.get(key)
		alphas.append("%s=%s" % [key, "freed" if not is_instance_valid(piece) else "%.2f" % piece.modulate.a])
	print("[SHOT] %-11s t=%.2fs scene sprite_a=%.2f dissolve=%.2f  %s" % [
		tag, _t_scene, sprite.modulate.a, _dissolve_of(sprite), " ".join(alphas)])
	if not ShotGuard.save_or_refuse(img, "%s/%s.png" % [OUT, tag]):
		_fail += 1
	var at: Vector2 = sprite.get_global_transform_with_canvas().origin
	var box := Rect2i(Vector2i(at) - CROP / 2, CROP)
	box = box.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if box.size.x <= 0 or box.size.y <= 0:
		print("[SHOT] FAIL: %s — the monster is off screen at %s" % [tag, str(at)])
		_fail += 1
		return
	var crop := img.get_region(box)
	if not ShotGuard.save_or_refuse(crop, "%s/%s_crop.png" % [OUT, tag]):
		_fail += 1
	_crops.append(crop)


func _dissolve_of(sprite: Node2D) -> float:
	if not (sprite.material is ShaderMaterial):
		return -1.0
	var v = sprite.material.get_shader_parameter("dissolve_amount")
	return float(v) if v != null else -1.0


func _strip(name: String) -> void:
	if _crops.is_empty():
		return
	var w: int = 0
	var h: int = 0
	for c in _crops:
		w += c.get_width()
		h = max(h, c.get_height())
	var strip := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var x: int = 0
	for c in _crops:
		strip.blit_rect(c, Rect2i(Vector2i.ZERO, c.get_size()), Vector2i(x, 0))
		x += c.get_width()
	if not ShotGuard.save_or_refuse(strip, "%s/%s.png" % [OUT, name]):
		_fail += 1


func _find_battle_scene(node: Node) -> Node:
	if node.has_method("_on_enemy_died") and node.has_method("_create_enemy_hp_bar"):
		return node
	for child in node.get_children():
		var hit := _find_battle_scene(child)
		if hit:
			return hit
	return null
