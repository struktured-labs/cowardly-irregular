extends SceneTree
## Marketing screenshots for the itch.io page — clean frames, no HUD furniture.
##
## The render smoke's 26 frames are DIAGNOSTIC captures and are unusable as store art:
## every one carries the first-run tutorial panel ("Press any button to dismiss") and the
## Debug/[GAME] Started overlay, because the smoke boots a fresh profile each run and a
## fresh profile is exactly the state that shows tutorials. Measured 2026-08-30 on the
## frames from deploy 486ce42f — battle_smoke had a "Battle Controls" panel over the top
## half, overworld_walk_right a "Movement" panel plus a stray debug label.
##
## Suppression is RUNTIME ONLY and lands in a sandboxed XDG profile. Nothing here is
## persisted to his settings and nothing changes in the shipped build. In particular
## `debug_log_enabled=false` is set on the in-memory GameState for this process only —
## that flag also gates an in-game escape route past a broken world transition, so it must
## never be shipped false.
##
##   xvfb-run -a godot --rendering-driver opengl3 --audio-driver Dummy \
##       --resolution 1920x1080 -s tools/marketing_shots.gd
##
## Writes res://tmp/marketing/<name>.png. Prints one [SHOT] line per capture with the
## measured size, and a [SHOT] FAIL line for any scene that would not load — a scene that
## silently produced no file would otherwise read as "not in the list".

## Hint ids are read from TutorialHints.HINTS AT RUNTIME, never listed here.
##
## Two hand-maintained lists were wrong before this: a regex over the file returned 18
## (missing `spotlight_locked_intro`), and the corrected 19 was still short by 15 — the
## `spotlight_hint_<job>_<n>` set for all five jobs, which the pattern could not see and
## which are BATTLE hints, i.e. exactly the ones that would have drawn over the battle
## shot. The live dict has 34.
##
## A parallel list of something the codebase already enumerates is a second source that
## can only drift, and its drift is invisible: the capture just quietly has a panel on it.
## Reading the dict cannot go stale.

## name -> candidate resource paths, first that exists wins.
const SCENES := [
	["harmonia_village", ["res://src/maps/villages/HarmoniaVillage.tscn", "res://src/maps/villages/HarmoniaVillage.gd"]],
	["ironhaven_village", ["res://src/maps/villages/IronhavenVillage.tscn", "res://src/maps/villages/IronhavenVillage.gd"]],
	["frosthold_village", ["res://src/maps/villages/FrostholdVillage.tscn", "res://src/maps/villages/FrostholdVillage.gd"]],
	["sandrift_village", ["res://src/maps/villages/SandriftVillage.tscn", "res://src/maps/villages/SandriftVillage.gd"]],
	["eldertree_village", ["res://src/maps/villages/EldertreeVillage.tscn", "res://src/maps/villages/EldertreeVillage.gd"]],
	["grimhollow_village", ["res://src/maps/villages/GrimhollowVillage.tscn", "res://src/maps/villages/GrimhollowVillage.gd"]],
	["inn_interior", ["res://src/maps/interiors/InnInterior.tscn", "res://src/maps/interiors/InnInterior.gd"]],
	["tavern_interior", ["res://src/maps/interiors/TavernInterior.tscn", "res://src/maps/interiors/TavernInterior.gd"]],
	["shop_interior", ["res://src/maps/interiors/ShopInterior.tscn", "res://src/maps/interiors/ShopInterior.gd"]],
	["whispering_cave", ["res://src/maps/dungeons/WhisperingCave.tscn", "res://src/maps/dungeons/WhisperingCave.gd"]],
	# DragonCave is deliberately absent. It loads and captures without error but renders an
	# EMPTY GREY VOID with only the player sprite — measured 2026-08-30, a 7.7 KB file where
	# its neighbours are 50-180 KB. It builds its floor through GameLoop's dungeon setup
	# (floor index, area config), which instantiating the bare script does not trigger, so
	# there is nothing to photograph. WhisperingCave self-populates and is kept.
	# The size delta is the cheap tell: a scene an order of magnitude smaller than its peers
	# rendered nothing, and it exits 0 either way.
]

var _ok := 0
var _fail := 0


func _init() -> void:
	# Autoloads are added AFTER a -s script's _init, same as village_screenshot.gd.
	await process_frame
	await process_frame

	_suppress_furniture()

	DirAccess.make_dir_recursive_absolute("res://tmp/marketing")
	for entry in SCENES:
		await _shoot(entry[0], entry[1])

	await _shoot_battle()

	print("[SHOT] done: %d captured, %d failed" % [_ok, _fail])
	quit(0 if _fail == 0 else 1)


## The battle shot — the one a storefront actually sells on, and the one the render smoke
## could never supply: its frame carried the "Battle Controls" panel (hint `first_battle`)
## across the top half. Suppression above removes it; the rest is the smoke's own proven
## sequence, driven from here so no game code changes.
func _shoot_battle() -> void:
	var gl_res := load("res://src/GameLoop.tscn")
	if gl_res == null:
		print("[SHOT] FAIL: battle — GameLoop.tscn did not load")
		_fail += 1
		return
	var gl: Node = gl_res.instantiate()
	root.add_child(gl)
	for i in range(4):
		await process_frame

	# Same neutralisation the smoke applies: this flag force-clears is_player_trusted and
	# changes which command menu draws, so a shot taken with it true is not what a player sees.
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_all_pcs_unlocked" in gs:
		gs.debug_all_pcs_unlocked = false

	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await process_frame
	await process_frame
	if gl.has_method("_create_party"):
		gl._create_party()
	else:
		print("[SHOT] FAIL: battle — _create_party absent; GameLoop's API moved")
		_fail += 1
		return

	if not gl.has_method("_start_battle_async"):
		print("[SHOT] FAIL: battle — _start_battle_async absent; GameLoop's API moved")
		_fail += 1
		return
	await gl._start_battle_async(["goblin"], true)
	# 2.5s: the smoke's own settle time. The battle intro runs a transition and the command
	# menu builds over several frames — capturing earlier catches a half-drawn HUD.
	await create_timer(2.5).timeout

	var img := root.get_texture().get_image()
	img.save_png("res://tmp/marketing/battle.png")
	print("[SHOT] battle (%dx%d)" % [img.get_width(), img.get_height()])
	_ok += 1


func _suppress_furniture() -> void:
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		push_error("GameState autoload absent — suppression cannot be applied")
		return
	# Debug overlay: in-memory only, never written to settings.json.
	if "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	# Tutorial panels: TutorialHint.show_hint short-circuits on
	# game_constants["tutorial_" + id], so pre-marking every id keeps them off screen.
	var hints_script = load("res://src/ui/TutorialHints.gd")
	if hints_script == null or not ("HINTS" in hints_script):
		push_error("[SHOT] TutorialHints.HINTS unreadable — hints cannot be suppressed")
		_fail += 1
		return
	var ids: Array = hints_script.HINTS.keys()
	# A zero here would suppress nothing and still print a tidy line, so make it loud:
	# an empty dict and an unreadable one are the same silence otherwise.
	if ids.is_empty():
		push_error("[SHOT] TutorialHints.HINTS is EMPTY — suppression is vacuous")
		_fail += 1
		return
	if "game_constants" in gs:
		for id in ids:
			gs.game_constants["tutorial_" + str(id)] = true
	print("[SHOT] suppressed: debug overlay + %d tutorial hints (read from HINTS)" % ids.size())


func _shoot(name: String, paths: Array) -> void:
	var scene: Node = null
	var src := ""
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var res = load(path)
		if res is PackedScene:
			scene = res.instantiate()
		elif res is GDScript:
			scene = res.new()
		if scene != null:
			src = path
			break
	if scene == null:
		print("[SHOT] FAIL: %s — no loadable scene among %s" % [name, str(paths)])
		_fail += 1
		return

	root.add_child(scene)
	# 12 frames: villages stream tiles and spawn NPCs over several frames; 8 was enough for
	# the older single-village tool but caught half-populated markets here.
	for i in range(12):
		await process_frame

	var img := root.get_texture().get_image()
	var out := "res://tmp/marketing/%s.png" % name
	img.save_png(out)
	print("[SHOT] %s (%dx%d) from %s" % [name, img.get_width(), img.get_height(), src])
	_ok += 1

	scene.queue_free()
	await process_frame
