extends SceneTree

const ShotGuard = preload("res://tools/shot_guard.gd")
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
##   XDG_DATA_HOME=$PWD/tmp/shot_xdg xvfb-run -a godot --rendering-driver opengl3 \
##       --audio-driver Dummy --resolution 1920x1080 -s tools/marketing_shots.gd
##
## ⛔ THE XDG PREFIX IS NOT OPTIONAL AND THIS SCRIPT CANNOT SUPPLY IT. Line 11 promises the
## suppression "lands in a sandboxed XDG profile" — that is a statement about the CALLER, not
## about anything here: nothing in this file sets XDG_DATA_HOME, and godot resolves user:// by
## APPLICATION NAME, so an unprefixed run lands in struktured's live save directory whatever
## worktree you are in. The command above used to omit it while the prose above promised it,
## which is the worst arrangement of the two: a reader who copies the line gets the behaviour
## the paragraph says they are protected from. Its sibling tools/store_shots_225.gd documented
## the prefix correctly the whole time.
##
## Measured 2026-09-12 on tools/village_screenshot.sh, the same shape: one sandboxed run
## created app_userdata/Cowardly Irregular/{autobattle,autogrind,debug_atlas.png,logs,saves,
## shader_cache}. saves/ and autobattle/ are the two directories run_tests.sh's net exists to
## restore, and no screenshot run invokes that net.
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
	_pin_conditions("battle")
	await gl._start_battle_async(["goblin"], true)
	# 2.5s: the smoke's own settle time. The battle intro runs a transition and the command
	# menu builds over several frames — capturing earlier catches a half-drawn HUD.
	await create_timer(2.5).timeout

	var img := root.get_texture().get_image()
	if not ShotGuard.save_or_refuse(img, "res://tmp/marketing/battle.png"):
		_fail += 1
	print("[SHOT] battle (%dx%d)" % [img.get_width(), img.get_height()])
	_ok += 1

	# The store had no picture of ADVANCE, the mechanic shipped in v3.33.346-350: queue up to
	# four actions, five at a full bank, and the acting PC's aura grows a layer per press. The
	# plain battle frame above is taken before anything is queued, so the aura is never in it.
	# Driven through the scene's OWN queue_changed handler -- the same entry point the menu
	# uses -- so this is the real rendered aura at 5/5, not a mock-up.
	var scene := _find_battle_scene(root)
	if scene == null:
		print("[SHOT] FAIL: battle_advance — no node with _on_advance_queue_changed; the aura API moved")
		_fail += 1
		return
	scene._on_advance_queue_changed(5, 5)
	await process_frame
	await process_frame
	# The aura settles (disc, orbit, gold rim) over a few frames; the kick decays.
	await create_timer(0.35).timeout
	var img_adv := root.get_texture().get_image()
	# A FRAME THAT DID NOT CHANGE IS A FRAME WITHOUT THE AURA. Saving it would put a picture of
	# nothing on the store page under a name that promises the mechanic -- the exact shape of
	# the "battle" shot this one exists to supplement.
	if img_adv.get_data() == img.get_data():
		print("[SHOT] FAIL: battle_advance — identical to the un-queued frame; the aura did not draw")
		_fail += 1
		return
	if not ShotGuard.save_or_refuse(img_adv, "res://tmp/marketing/battle_advance.png"):
		_fail += 1
	print("[SHOT] battle_advance (%dx%d) — full bank 5/5, aura drew" % [img_adv.get_width(), img_adv.get_height()])
	_ok += 1


## The BattleScene by CAPABILITY, not by path: the node that answers the queue signal is the one
## that owns the aura, whatever the scene tree is called this month.
func _find_battle_scene(n: Node) -> Node:
	if n.has_method("_on_advance_queue_changed"):
		return n
	for c in n.get_children():
		var found := _find_battle_scene(c)
		if found != null:
			return found
	return null


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
	_pin_conditions("setup")


## ⛔ THE WEATHER WAS A DICE ROLL IN EVERY STORE FRAME. GameState._process advances the clock and
## rolls weather from WEATHER_VOCAB (world 1: "clear" is 55 of 100), and _weather_world starts at 0,
## so the very first frame -- before this script's setup -- already rolls. Measured 2026-10-24 at
## .710: two runs minutes apart differed on 45-97% of pixels in every outdoor frame and the battle
## (interiors 0.00%), sandrift's mean RGB moved by 17, and one battle frame read "~ RAIN ~" under a
## caption that says the weather is off. So a re-shoot was partly random and the run-to-run floor
## swamped every real change. Pausing playtime stops both the clock and the re-roll; "clear" and the
## new-game phase (0.15, inside the untinted 0.10-0.50 band) are what a player starting fresh sees.
## Called again before each capture, because _create_party resets state (reset_game_state).
func _pin_conditions(where: String) -> void:
	var gs = root.get_node_or_null("GameState")
	if gs == null or not ("weather_condition" in gs) or not ("playtime_paused" in gs):
		push_error("[SHOT] GameState has no weather/pause fields -- conditions cannot be pinned")
		_fail += 1
		return
	gs.playtime_paused = true
	var consts: Dictionary = gs.get_script().get_script_constant_map()
	if not consts.has("DAY_PHASE_NEW_GAME") or not ("day_phase" in gs):
		push_error("[SHOT] GameState.DAY_PHASE_NEW_GAME / day_phase absent -- the clock cannot be pinned")
		_fail += 1
		return
	gs.day_phase = float(consts["DAY_PHASE_NEW_GAME"])
	if gs.weather_condition != "clear":
		gs.weather_condition = "clear"
		if gs.has_signal("weather_changed"):
			gs.weather_changed.emit("clear")
	print("[SHOT] conditions (%s): weather=%s day_phase=%.2f paused=%s" % [where, gs.weather_condition, float(gs.day_phase), str(gs.playtime_paused)])


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
	if not ShotGuard.save_or_refuse(img, out):
		_fail += 1
	print("[SHOT] %s (%dx%d) from %s" % [name, img.get_width(), img.get_height(), src])
	_ok += 1

	scene.queue_free()
	await process_frame
