extends SceneTree

## Visual proof for the Advance aura: a real battle, the real handler, counts 1-5, three ways.
##
##   XDG_DATA_HOME=$PWD/tmp/shot_xdg xvfb-run -a godot --audio-driver Dummy --rendering-driver opengl3 \
##     --resolution 1280x720 -s tools/advance_aura_shots.gd
##
## Writes to tmp/advance_aura/:
##   bubble_<n>   steady frames on round 1 WITH the acting PC's turn_start line up — what a player sees
##                while queueing on the first turn of every fight (cowir-adhoc: that line fires exactly
##                then, and it is the likeliest frame behind "I couldn't see it")
##   pop_<n>      ~80 ms of REAL time after the press that reaches n — the per-press flourish mid-burst
##   clear_<n>    steady frames once no speech bubble is live, plus clear_4_of_4 below a full bank
##   strip_bubble.png · strip_pop.png · strip_clear.png   the crops side by side
##
## The bubble-clear wait is a CONDITION, never a fixed delay: a voiced line holds for its clip length
## plus a tail with no cap, and the first version of this tool captured at 4.7 s with bubbles still up.
## Sandboxed user:// is not optional: this runs the GAME, which resolves user:// by application name.

const OUT := "res://tmp/advance_aura"
const CROP := Vector2i(300, 300)
const CLEAR_TIMEOUT_MS := 60000
var _fail: int = 0
var _scene: Node
var _sprite: Node2D


func _init() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	if gs and "debug_all_pcs_unlocked" in gs:
		gs.debug_all_pcs_unlocked = false
	DirAccess.make_dir_recursive_absolute(OUT)
	## Tutorial panels cover the top of the frame, where the V-formation's lead PC stands. Same
	## suppression as marketing_shots.gd; loud if the id set reads empty, which would suppress nothing.
	var hints = load("res://src/ui/TutorialHints.gd")
	var ids: Array = hints.HINTS.keys() if hints and ("HINTS" in hints) else []
	if ids.is_empty():
		print("[SHOT] FAIL: TutorialHints.HINTS unreadable or empty — hints would cover the actor")
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
	await create_timer(1.0).timeout

	_scene = _find_battle_scene(root)
	if _scene == null:
		print("[SHOT] FAIL: no BattleScene with _on_advance_queue_changed in the tree")
		quit(1)
		return
	var bm = root.get_node("BattleManager")
	var pc = bm.current_combatant
	if pc == null or not (pc in _scene.party_members):
		pc = _scene.party_members[0]
		bm.current_combatant = pc
	_sprite = _scene._get_combatant_sprite(pc)
	print("[SHOT] actor=%s job=%s tier=%d time_scale=%.2f" % [pc.combatant_name, str(pc.job.get("id", "")), int(root.get_node("BattleJuice").battle_tier()), Engine.time_scale])

	## Set 1 — round 1, turn_start bubble up.
	var bubble: Array[Image] = []
	for n in range(1, 6):
		_scene._on_advance_queue_changed(n, 5)
		await create_timer(0.35).timeout
		bubble.append(_capture("bubble_%d" % n, "live_bubbles=%d" % _live_bubbles()))
	_scene._on_advance_queue_changed(0, 5)
	_strip(bubble, "strip_bubble")

	## Set 2 — mid-pop, 80 ms of real time after each rising press.
	var pop: Array[Image] = []
	await create_timer(0.35).timeout
	for n in range(1, 6):
		_scene._on_advance_queue_changed(n, 5)
		await create_timer(0.08, true, false, true).timeout
		pop.append(_capture("pop_%d" % n, "kick=%.2f" % _aura().kick_amount()))
		await create_timer(0.35).timeout
	_scene._on_advance_queue_changed(0, 5)
	_strip(pop, "strip_pop")

	## Set 3 — once no bubble is live.
	var waited: int = await _wait_bubbles_clear()
	if waited < 0:
		print("[SHOT] FAIL: speech bubbles still live after %d ms — the clear frames would not prove what they say" % CLEAR_TIMEOUT_MS)
		_fail += 1
	else:
		print("[SHOT] bubbles cleared after %d ms real time" % waited)
	var clear: Array[Image] = []
	for n in range(1, 6):
		_scene._on_advance_queue_changed(n, 5)
		await create_timer(0.35).timeout
		clear.append(_capture("clear_%d" % n, "live_bubbles=%d" % _live_bubbles()))
	_scene._on_advance_queue_changed(0, 4)
	await create_timer(0.1).timeout
	for n in range(1, 5):
		_scene._on_advance_queue_changed(n, 4)
	await create_timer(0.35).timeout
	clear.append(_capture("clear_4_of_4", "below full bank"))
	_scene._on_advance_queue_changed(0, 4)
	_strip(clear, "strip_clear")

	print("[SHOT] done, %d failed" % _fail)
	quit(0 if _fail == 0 else 1)


func _aura() -> Node:
	for child in _sprite.get_children():
		if child.name == "AdvanceAura":
			return child
	return null


## The same filter BattleSpeechBubble.spawn uses: valid and not queued for deletion.
func _live_bubbles() -> int:
	var cls = load("res://src/battle/BattleSpeechBubble.gd")
	var n: int = 0
	for e in cls._live:
		if is_instance_valid(e["bubble"]) and not e["bubble"].is_queued_for_deletion():
			n += 1
	return n


func _wait_bubbles_clear() -> int:
	var start: int = Time.get_ticks_msec()
	while _live_bubbles() > 0:
		if Time.get_ticks_msec() - start > CLEAR_TIMEOUT_MS:
			return -1
		await process_frame
	return Time.get_ticks_msec() - start


func _capture(tag: String, note: String) -> Image:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, tag])
	var at := Vector2i(_sprite.get_global_transform_with_canvas().origin) - CROP / 2
	at = at.clamp(Vector2i.ZERO, Vector2i(img.get_width(), img.get_height()) - CROP)
	var crop := img.get_region(Rect2i(at, CROP))
	crop.save_png("%s/%s_crop.png" % [OUT, tag])
	var aura = _aura()
	if aura == null or not aura.is_active():
		print("[SHOT] FAIL: %s — no active aura on the actor" % tag)
		_fail += 1
	else:
		var line = aura.outline()
		print("[SHOT] %s count=%d full_bank=%s outline=%s %s" % [tag, aura.count, str(aura.full_bank), str(line != null and line.visible), note])
	return crop


func _strip(crops: Array[Image], name: String) -> void:
	var strip := Image.create(CROP.x * crops.size(), CROP.y, false, Image.FORMAT_RGBA8)
	for i in crops.size():
		strip.blit_rect(crops[i], Rect2i(Vector2i.ZERO, CROP), Vector2i(CROP.x * i, 0))
	strip.save_png("%s/%s.png" % [OUT, name])


func _find_battle_scene(node: Node) -> Node:
	if node.has_method("_on_advance_queue_changed"):
		return node
	for child in node.get_children():
		var hit := _find_battle_scene(child)
		if hit:
			return hit
	return null
