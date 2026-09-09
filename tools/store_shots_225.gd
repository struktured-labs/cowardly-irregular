extends SceneTree
## Store screenshots for cowir-main's .225 list (msg 8474). Companion to
## tools/marketing_shots.gd, which covers the villages/interiors/battle baseline; this one
## covers the shots that need STATE — a specific dungeon floor, a weather condition — rather
## than just a scene.
##
## Every capture prints its byte size. That is the cheap tell for the failure this whole
## family of scripts keeps hitting: a dungeon that loads, captures, and exits 0 while
## rendering an EMPTY GREY VOID. Measured on DragonCave 2026-08-30 — 7.7 KB where populated
## scenes are 50-300 KB. A scene an order of magnitude smaller than its peers photographed
## nothing, and nothing in the exit code says so.
##
## Bare instantiation is legitimate here and is what GameLoop itself does: _create_dragon_cave
## does `ScriptRes.new()` then sets current_floor before the caller adds it to the tree, so
## _ready() builds the floor from the subclass's own floor_layouts. Verified on
## ContrarianDepths 2026-09-07: floors 1-4 rendered 248-310 KB, all real geometry.
##
##   XDG_DATA_HOME=$PWD/tmp/shot_xdg xvfb-run -a godot --rendering-driver opengl3 \
##       --audio-driver Dummy -s tools/store_shots_225.gd
##
## SANDBOXED XDG IS MANDATORY. user:// is one directory shared by every cowir-* checkout on
## this machine, and struktured plays on it. Nothing here may touch his profile.

const VOID_BYTES := 20000  ## below this a capture is almost certainly an empty void

var _ok := 0
var _fail := 0
var _suspect: Array[String] = []


func _init() -> void:
	# Autoloads land AFTER a -s script's _init.
	await process_frame
	await process_frame

	_suppress_furniture()
	DirAccess.make_dir_recursive_absolute("res://tmp/marketing")

	# ── dungeon floors (state-dependent) ────────────────────────────────────
	await _shoot_floor("warren_wrap_field", "res://src/maps/dungeons/ContrarianDepths.gd", 2)
	await _shoot_floor("warren_lever_portals", "res://src/maps/dungeons/ContrarianDepths.gd", 3)
	for f in [2, 3, 4]:
		await _shoot_floor("infernal_grotto_f%d" % f, "res://src/maps/dungeons/FireDragonCave.gd", f)

	# ── villages re-shot after the 2026-09-06 elevation pass ────────────────
	# The Aug 30 set predates it, so the spiral descent and the canopy tier are simply not
	# in those frames — a stale screenshot is wrong in the one way a store page cannot
	# afford, it advertises a game that no longer looks like this.
	await _shoot_scene("grimhollow_spiral", "res://src/maps/villages/GrimhollowVillage.gd")
	await _shoot_scene("eldertree_canopy", "res://src/maps/villages/EldertreeVillage.gd")
	await _shoot_scene("brasston_lift", "res://src/maps/villages/BrasstonVillage.gd")

	# ── battle under storm ──────────────────────────────────────────────────
	await _shoot_battle_storm()

	print("[SHOT] done: %d captured, %d failed" % [_ok, _fail])
	if not _suspect.is_empty():
		print("[SHOT] ⚠ SUSPECT (under %d bytes — likely an empty void, do NOT ship unreviewed): %s"
			% [VOID_BYTES, ", ".join(_suspect)])
	quit(0 if _fail == 0 else 1)


func _capture(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "res://tmp/marketing/%s.png" % name
	img.save_png(path)
	var fa := FileAccess.open(path, FileAccess.READ)
	var sz := fa.get_length() if fa else 0
	if fa:
		fa.close()
	if sz < VOID_BYTES:
		_suspect.append("%s (%d B)" % [name, sz])
	print("[SHOT] %-24s %7d B  %dx%d" % [name, sz, img.get_width(), img.get_height()])
	_ok += 1


func _shoot_floor(name: String, script_path: String, floor_num: int) -> void:
	var res = load(script_path)
	if res == null:
		print("[SHOT] FAIL: %s — %s did not load" % [name, script_path])
		_fail += 1
		return
	var scene = res.new()
	# Set BEFORE add_child: _ready() is what builds the floor, so assigning after it has
	# run would photograph floor 1 under a floor-3 filename — a mislabel that looks fine.
	if not ("current_floor" in scene):
		print("[SHOT] FAIL: %s — no current_floor on %s" % [name, script_path])
		_fail += 1
		return
	scene.current_floor = floor_num
	root.add_child(scene)
	for i in range(14):
		await process_frame
	_capture(name)
	scene.queue_free()
	await process_frame


func _shoot_scene(name: String, script_path: String) -> void:
	var res = load(script_path)
	if res == null:
		print("[SHOT] FAIL: %s — %s did not load" % [name, script_path])
		_fail += 1
		return
	var scene = res.new()
	root.add_child(scene)
	# Villages stream tiles and spawn NPCs over several frames; 12 caught half-populated
	# markets at 8.
	for i in range(14):
		await process_frame
	_capture(name)
	scene.queue_free()
	await process_frame


func _shoot_battle_storm() -> void:
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("[SHOT] FAIL: battle_storm — GameState absent")
		_fail += 1
		return
	# BattleScene reads GameState.get_weather() and renders tint + rain + lightning + an
	# always-visible "~ STORM ~" tag. Setting the field is what a stormy overworld would
	# have done; nothing here is persisted (sandboxed profile, never saved).
	if not ("weather_condition" in gs):
		print("[SHOT] FAIL: battle_storm — GameState has no weather_condition")
		_fail += 1
		return
	gs.weather_condition = "storm"

	var gl_res := load("res://src/GameLoop.tscn")
	if gl_res == null:
		print("[SHOT] FAIL: battle_storm — GameLoop.tscn did not load")
		_fail += 1
		return
	var gl: Node = gl_res.instantiate()
	root.add_child(gl)
	for i in range(4):
		await process_frame

	# Force-clears is_player_trusted and changes which command menu draws, so a shot with
	# it true is not what a player sees.
	if "debug_all_pcs_unlocked" in gs:
		gs.debug_all_pcs_unlocked = false
	# Re-assert: GameLoop's boot may roll its own weather.
	gs.weather_condition = "storm"

	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await process_frame
	await process_frame
	if not gl.has_method("_create_party") or not gl.has_method("_start_battle_async"):
		print("[SHOT] FAIL: battle_storm — GameLoop's battle API moved")
		_fail += 1
		return
	gl._create_party()
	gs.weather_condition = "storm"
	await gl._start_battle_async(["goblin"], true)
	gs.weather_condition = "storm"
	# 2.5s is the render smoke's own settle time — the intro transition runs and the command
	# menu builds over several frames, so an earlier capture catches a half-drawn HUD.
	await create_timer(2.5).timeout
	_capture("battle_storm")


func _suppress_furniture() -> void:
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		push_error("[SHOT] GameState absent — suppression cannot be applied")
		_fail += 1
		return
	# In-memory only. This flag ALSO gates the only in-game escape route past a broken world
	# transition, so it must never be shipped false — see the deploy lane's standing note.
	if "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)

	# Hint ids are READ FROM THE DICT, never listed here. Two hand-maintained lists were
	# wrong before: a regex gave 18, the "corrected" 19 was still short by 15, and the 15
	# missing were the spotlight_hint_<job>_<n> BATTLE hints — exactly the ones that would
	# have drawn over the battle shot. The live dict has 34.
	var hints_script = load("res://src/ui/TutorialHints.gd")
	if hints_script == null or not ("HINTS" in hints_script):
		push_error("[SHOT] TutorialHints.HINTS unreadable — hints cannot be suppressed")
		_fail += 1
		return
	var ids: Array = hints_script.HINTS.keys()
	if ids.is_empty():
		push_error("[SHOT] TutorialHints.HINTS is EMPTY — suppression is vacuous")
		_fail += 1
		return
	if "game_constants" in gs:
		for id in ids:
			gs.game_constants["tutorial_" + str(id)] = true
	print("[SHOT] suppressed: debug overlay + %d tutorial hints (read from HINTS)" % ids.size())
