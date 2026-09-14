extends SceneTree

## Visual proof for the Advance aura: a real battle, the real handler, counts 1-5, three ways.
##
##   XDG_DATA_HOME=$PWD/tmp/shot_xdg xvfb-run -a godot --audio-driver Dummy --rendering-driver opengl3 \
##     --resolution 1280x720 -s tools/advance_aura_shots.gd
##
## Writes to tmp/advance_aura/:
##   bubble_<n>        FULL 1280x720 frames on round 1 WITH the acting PC's turn_start line up
##   bubble_<n>_wide   a full-width 1:1 band at the actor's height: the bubble AND every layer, nothing downscaled
##   pop_<n>           ~80 ms of REAL time after the press that reaches n — the per-press pop mid-burst
##   clear_<n>         once no speech bubble is live, plus clear_4_of_4 below a full bank
##   strip_*.png       the actor crops side by side; strip_bubble_wide.png stacks the 1:1 bands
##
## LAYER CHECK, in the bubble set and the clear set: each count must show every layer it owns and none it
## does not. Measured ON SCREEN — the tree is paused, the frame is taken with one layer's drawing off, and
## the pixels that changed are that layer. ⛔ This is the instrument that found the .347 disc 70% hidden
## behind its own body: a table can say a layer is on while the screen shows nothing of it.
## Counts 1-2 of the bubble set land while the actor is still stepping out of formation, deliberately:
## that is the frame where the next PC covered the old disc.

const OUT := "res://tmp/advance_aura"
const AuraScript = preload("res://src/battle/AdvanceAura.gd")
const CROP := Vector2i(300, 300)
const WIDE := Vector2i(1280, 460)
const CLEAR_TIMEOUT_MS := 60000
const BUBBLE_APPEAR_TIMEOUT_MS := 15000
## On-screen pixels a layer must change to count as shown, and the most an absent layer may change.
const LAYER_PX_FLOOR := 150
const ABSENT_PX_CEILING := 12
const DIFF_BOX := Vector2i(560, 520)
const STILL_TRIES := 40
## 5/5's gold must out-draw the disc it rings. Measured on-screen gold/disc: full ring + gold outline 1.65 ·
## ring alone 0.74 · gold outline + .348's arc 1.00 · .348's arc 0.10 — so either half regressing fails.
const GOLD_TO_DISC_FLOOR := 1.3
const LAYER_BITS: Array[int] = [AuraScript.LAYER_OUTLINE, AuraScript.LAYER_DISC, AuraScript.LAYER_ARMS, AuraScript.LAYER_MOTES, AuraScript.LAYER_GOLD]
var _fail: int = 0
var _scene: Node
var _sprite: Node2D


func _init() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	if gs and "debug_all_pcs_unlocked" in gs:
		gs.debug_all_pcs_unlocked = false
	DirAccess.make_dir_recursive_absolute(OUT)
	## Tutorial panels cover the lead PC; loud if the id set reads empty, which would suppress nothing.
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

	## Set 1 — round 1, turn_start bubble up. Waits for a bubble, runs on short real-time settles, FAILS
	## any frame taken with none up. Captures are held and diffed after the set, so the bubble outlasts them.
	var bubble_start: int = await _wait_bubble_live()
	if bubble_start < 0:
		print("[SHOT] FAIL: no speech bubble appeared within %d ms — the bubble set has nothing to prove" % BUBBLE_APPEAR_TIMEOUT_MS)
		_fail += 1
	var bubble: Array[Image] = []
	var bubble_wide: Array[Image] = []
	var bubble_layers: Array = []
	for n in range(1, 6):
		_scene._on_advance_queue_changed(n, 5)
		await create_timer(0.12, true, false, true).timeout
		var shot: Dictionary = await _pinned_with_layers("bubble_%d" % n)
		if int(shot["live"]) == 0:
			print("[SHOT] FAIL: bubble_%d — the bubble cleared before this frame; it would not show the aura beside one" % n)
			_fail += 1
		print("[SHOT] bubble_%d live_bubbles=%d +%d ms after the bubble appeared, slide=%+.0f px" % [n, int(shot["live"]), Time.get_ticks_msec() - bubble_start, float(shot["slide"])])
		bubble.append(shot["crop"])
		bubble_wide.append(shot["wide"])
		bubble_layers.append(shot)
	_scene._on_advance_queue_changed(0, 5)
	for i in bubble_layers.size():
		_check_layers(bubble_layers[i], i + 1, true)
	_strip(bubble, "strip_bubble")
	_stack(bubble_wide, "strip_bubble_wide")

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
		print("[SHOT] waited %d ms real time for the last bubble to clear" % waited)
	var clear: Array[Image] = []
	for n in range(1, 6):
		_scene._on_advance_queue_changed(n, 5)
		await create_timer(0.35).timeout
		var shot: Dictionary = await _pinned_with_layers("clear_%d" % n)
		_check_layers(shot, n, true)
		clear.append(shot["crop"])
	_scene._on_advance_queue_changed(0, 4)
	await create_timer(0.1).timeout
	for n in range(1, 5):
		_scene._on_advance_queue_changed(n, 4)
	await create_timer(0.35).timeout
	var below: Dictionary = await _pinned_with_layers("clear_4_of_4")
	_check_layers(below, 4, false)
	clear.append(below["crop"])
	_scene._on_advance_queue_changed(0, 4)
	_strip(clear, "strip_clear")

	print("[SHOT] done, %d failed" % _fail)
	quit(0 if _fail == 0 else 1)


## Pause the tree, pin the aura at phase 0 with no kick, and measure each layer as an on/off/on sandwich.
## ⛔ Pausing does not freeze the screen: Win98Menu runs PROCESS_MODE_ALWAYS, so the command menu keeps
## opening and its cursor keeps blinking — the first run of this check read 18,000 px of menu as "the disc
## draws at count 1". A sandwich counts only when both ON frames are byte-identical around the actor.
func _pinned_with_layers(tag: String) -> Dictionary:
	var aura = _aura()
	paused = true
	if aura:
		aura._t = 0.0
		aura._kick = 0.0
	var centre := Vector2i(_sprite.get_global_transform_with_canvas().origin)
	var pairs := {}
	var full: Image = null
	var live: int = 0
	if aura:
		for bit in LAYER_BITS:
			for attempt in STILL_TRIES:
				var on1: Image = await _frame_with(aura, AuraScript.LAYER_ALL)
				var off: Image = await _frame_with(aura, AuraScript.LAYER_ALL & ~bit)
				var on2: Image = await _frame_with(aura, AuraScript.LAYER_ALL)
				var box := _clamped(centre - DIFF_BOX / 2, DIFF_BOX, on1)
				pairs[bit] = [on1, off]
				if on1.get_region(box).get_data() == on2.get_region(box).get_data():
					break
				if attempt == STILL_TRIES - 1:
					print("[SHOT] FAIL: %s — the screen never held still for the %s layer in %d tries" % [tag, str(AuraScript.LAYER_NAMES[bit]), STILL_TRIES])
					_fail += 1
			if full == null:
				full = pairs[bit][0]
				live = _live_bubbles()
	else:
		await process_frame
		full = root.get_texture().get_image()
	var slide: float = _sprite.position.x - float(_sprite.get_meta("home_position", _sprite.position).x)
	paused = false
	full.save_png("%s/%s.png" % [OUT, tag])
	var crop := full.get_region(_clamped(centre - CROP / 2, CROP, full))
	crop.save_png("%s/%s_crop.png" % [OUT, tag])
	var wide := full.get_region(_clamped(Vector2i(0, centre.y - WIDE.y / 2), WIDE, full))
	wide.save_png("%s/%s_wide.png" % [OUT, tag])
	if aura == null or not aura.is_active():
		print("[SHOT] FAIL: %s — no active aura on the actor" % tag)
		_fail += 1
	return {"tag": tag, "pairs": pairs, "centre": centre, "crop": crop, "wide": wide, "live": live, "slide": slide,
		"count": aura.count if aura else 0, "full_bank": aura.full_bank if aura else false}


func _frame_with(aura, mask: int) -> Image:
	aura.set_draw_layers(mask)
	await process_frame
	await process_frame
	return root.get_texture().get_image()


## Every layer the count owns must change at least LAYER_PX_FLOOR pixels; every layer it lacks, none.
func _check_layers(shot: Dictionary, n: int, max_five: bool) -> void:
	var owned: int = AuraScript.layers_for(n, max_five and n >= 5)
	var row: Array = []
	for bit in LAYER_BITS:
		if not (shot["pairs"] as Dictionary).has(bit):
			continue
		var px: int = _changed_px(shot["pairs"][bit][0], shot["pairs"][bit][1], shot["centre"])
		var name: String = str(AuraScript.LAYER_NAMES[bit])
		var want: bool = (owned & bit) != 0
		row.append("%s=%d%s" % [name, px, "" if want else "(absent)"])
		if want and px < LAYER_PX_FLOOR:
			print("[SHOT] FAIL: %s — the %s layer changes only %d px on screen (needs %d)" % [shot["tag"], name, px, LAYER_PX_FLOOR])
			_fail += 1
		elif not want and px > ABSENT_PX_CEILING:
			print("[SHOT] FAIL: %s — the %s layer draws %d px at a count that does not own it" % [shot["tag"], name, px])
			_fail += 1
	if (owned & AuraScript.LAYER_GOLD) != 0 and (shot["pairs"] as Dictionary).has(AuraScript.LAYER_GOLD):
		var gold: int = _changed_px(shot["pairs"][AuraScript.LAYER_GOLD][0], shot["pairs"][AuraScript.LAYER_GOLD][1], shot["centre"])
		var disc: int = _changed_px(shot["pairs"][AuraScript.LAYER_DISC][0], shot["pairs"][AuraScript.LAYER_DISC][1], shot["centre"])
		var ratio: float = float(gold) / maxf(1.0, float(disc))
		row.append("gold/disc=%.2f" % ratio)
		if ratio < GOLD_TO_DISC_FLOOR:
			print("[SHOT] FAIL: %s — the full bank's gold draws %.2fx the disc on screen (needs %.2fx); it has faded back toward an arc" % [shot["tag"], ratio, GOLD_TO_DISC_FLOOR])
			_fail += 1
	print("[SHOT] %s count=%d full_bank=%s on-screen px: %s" % [shot["tag"], int(shot["count"]), str(shot["full_bank"]), " ".join(row)])


func _changed_px(a: Image, b: Image, centre: Vector2i) -> int:
	var box := _clamped(centre - DIFF_BOX / 2, DIFF_BOX, a)
	var n: int = 0
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.03:
				n += 1
	return n


func _clamped(at: Vector2i, size: Vector2i, img: Image) -> Rect2i:
	var s := Vector2i(mini(size.x, img.get_width()), mini(size.y, img.get_height()))
	return Rect2i(at.clamp(Vector2i.ZERO, img.get_size() - s), s)


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


## Wall-clock ms at which a bubble was first seen live, or -1 if none appeared within the timeout.
func _wait_bubble_live() -> int:
	var start: int = Time.get_ticks_msec()
	while _live_bubbles() == 0:
		if Time.get_ticks_msec() - start > BUBBLE_APPEAR_TIMEOUT_MS:
			return -1
		await process_frame
	return Time.get_ticks_msec()


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
	var at := Vector2i(_sprite.get_global_transform_with_canvas().origin)
	var crop := img.get_region(_clamped(at - CROP / 2, CROP, img))
	crop.save_png("%s/%s_crop.png" % [OUT, tag])
	var aura = _aura()
	if aura == null or not aura.is_active():
		print("[SHOT] FAIL: %s — no active aura on the actor" % tag)
		_fail += 1
	else:
		print("[SHOT] %s count=%d full_bank=%s %s" % [tag, aura.count, str(aura.full_bank), note])
	return crop


func _stack(images: Array[Image], name: String) -> void:
	var size: Vector2i = images[0].get_size()
	var strip := Image.create(size.x, size.y * images.size(), false, Image.FORMAT_RGBA8)
	for i in images.size():
		strip.blit_rect(images[i], Rect2i(Vector2i.ZERO, size), Vector2i(0, size.y * i))
	strip.save_png("%s/%s.png" % [OUT, name])


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
