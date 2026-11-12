extends SceneTree

const ShotGuard = preload("res://tools/shot_guard.gd")
const VillagePropScript = preload("res://src/exploration/VillageProp.gd")
## What a 1280x720 capture shows of a village: its camera is zoomed 2x (BaseVillage._setup_camera).
const VIEW := Vector2(640, 360)
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

## The village a shared interior is photographed AS. A room asks GameLoop which village it was entered from and draws
## that village's art; this tool builds the room alone, so with no answer every shared room fell back to its PAINTED
## look, and the store's inn was a room no player in Harmonia has seen (found 2026-11-12 on overworld's contact sheet:
## the stored frame has the painted slab table and no drawn back wall or hearth). Harmonia is the first village a
## player enters. A room with no entry here is shot as before.
const ORIGINS := {
	"inn_interior": "harmonia_village",
	"shop_interior": "harmonia_village",
	"tavern_interior": "harmonia_village",
}
## Rooms whose village HAS drawn art today: an origin that yields none is a silent fallback, and reds the shot.
const MUST_BE_DRAWN := ["inn_interior"]

var _ok := 0
var _fail := 0


## Things that MOVE in a room, held still for the capture: the recheck compares these frames pixel by pixel every
## release, so an NPC strolling or a lamp wavering reads as "the room changed" and hides a real change behind it.
## Each is a static switch its owner built for this tool (cowir-overworld 24225, 24357). A tree without the switch
## (before those tips fold) has nothing to hold and says so. SHOTS_NO_HOLD=1 leaves them moving: the control.
const HELD_STILL := [
	["res://src/exploration/OverworldNPC.gd", "strolling_enabled"],
	["res://src/maps/InteriorLighting.gd", "flicker_enabled"],
]


func _hold_still() -> void:
	if OS.get_environment("SHOTS_NO_HOLD") != "":
		print("[SHOT] held still: nothing (SHOTS_NO_HOLD)")
		return
	var held: Array = []
	var absent: Array = []
	for pair in HELD_STILL:
		var script = load(pair[0]) if ResourceLoader.exists(pair[0]) else null
		if script == null or script.get(pair[1]) == null:
			absent.append(pair[1])
			continue
		script.set(pair[1], false)
		if script.get(pair[1]) != false:
			print("[SHOT] FAIL: %s did not take false: the switch is not a static this tool can set" % pair[1])
			_fail += 1
			continue
		held.append(pair[1])
	print("[SHOT] held still: %s · not in this tree: %s" % [", ".join(held) if not held.is_empty() else "nothing", ", ".join(absent) if not absent.is_empty() else "nothing"])


## Stands in for GameLoop for the ONE question a room asks it. A room guards the call with has_method, so nothing else
## is answered and nothing else is pretended.
func _stand_in_origin(origin: String) -> Node:
	var src := GDScript.new()
	src.source_code = "extends Node\nvar origin := \"\"\nfunc get_village_origin_id() -> String:\n\treturn origin\n"
	if src.reload() != OK:
		return null
	var n: Node = src.new()
	n.name = "GameLoop"
	n.set("origin", origin)
	return n


func _init() -> void:
	# Autoloads are added AFTER a -s script's _init, same as village_screenshot.gd.
	await process_frame
	await process_frame

	_suppress_furniture()
	_hold_still()

	DirAccess.make_dir_recursive_absolute("res://tmp/marketing")
	for entry in SCENES:
		await _shoot(entry[0], entry[1])

	await _shoot_title()
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


## Clear weather + paused clock: see ShotGuard.pin_conditions for the measurement behind it.
## Called again before the battle, because _create_party resets state (reset_game_state).
func _pin_conditions(where: String) -> void:
	if not ShotGuard.pin_conditions(root, where):
		_fail += 1


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

	var origin := str(ORIGINS.get(name, ""))
	var stand_in: Node = null
	if origin != "" and OS.get_environment("SHOTS_NO_ORIGIN") == "":
		if root.get_node_or_null("GameLoop") != null:
			print("[SHOT] FAIL: %s — a GameLoop is already in the tree, so the origin cannot be stood in" % name)
			_fail += 1
			scene.free()
			return
		stand_in = _stand_in_origin(origin)
		if stand_in == null:
			print("[SHOT] FAIL: %s — the origin stand-in did not compile" % name)
			_fail += 1
			scene.free()
			return
		root.add_child(stand_in)
	root.add_child(scene)
	# 12 frames: villages stream tiles and spawn NPCs over several frames; 8 was enough for
	# the older single-village tool but caught half-populated markets here.
	for i in range(12):
		await process_frame
	if origin != "":
		var drawn := scene.find_children("Art_*", "Sprite2D", true, false).size()
		print("[SHOT] %s origin: %s · drawn pieces: %d" % [name, origin if stand_in != null else "(none: SHOTS_NO_ORIGIN)", drawn])
		if stand_in != null and name in MUST_BE_DRAWN and drawn == 0:
			print("[SHOT] FAIL: %s — shot as %s and no drawn piece stands in it: the painted fallback" % [name, origin])
			_fail += 1

	var framing := _frame_on_houses(scene)
	if framing != "":
		for i in range(6):
			await process_frame
		print("[SHOT] %s framing: %s" % [name, framing])

	## A marketing still is not the HUD (cowir-adhoc 21988): AreaTransition draws its "Enter Attic" /
	## "The Forge (rear entrance)" sign whenever the gate is drawn, not only near it, so a village frame
	## carried door labels across its facades. Hidden for the CAPTURE only; the game is untouched, and
	## CAPTIONS says the shots omit them. Counted and printed, so the log proves it ran.
	var hid := _hide_transition_labels(scene)
	await process_frame
	print("[SHOT] %s hid %d door label(s)" % [name, hid])

	var img := root.get_texture().get_image()
	var out := "res://tmp/marketing/%s.png" % name
	if not ShotGuard.save_or_refuse(img, out):
		_fail += 1
	print("[SHOT] %s (%dx%d) from %s" % [name, img.get_width(), img.get_height(), src])
	_ok += 1

	scene.queue_free()
	if stand_in != null:
		stand_in.queue_free()
	await process_frame


func _walkable_stand(scene: Node, stand: Vector2) -> Vector2:
	if not scene.has_method("_is_cell_walkable"):
		return stand
	var t := float(VillagePropScript.TILE)
	var c0 := Vector2i(floori(stand.x / t), floori(stand.y / t))
	if scene._is_cell_walkable(c0):
		print("[SHOT] stand cell %s is walkable" % str(c0))
		return stand
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var c := c0 + Vector2i(dx, dy)
			var d := Vector2(dx, dy).length()
			if d < best_d and scene._is_cell_walkable(c):
				best_d = d
				best = c
	if best_d == INF:
		print("[SHOT] stand cell %s is NOT walkable and nothing within 4 tiles is: kept as is" % str(c0))
		return stand
	print("[SHOT] stand cell %s is NOT walkable: nudged to %s" % [str(c0), str(best)])
	return Vector2((best.x + 0.5) * t, (best.y + 0.5) * t)


## Every AreaTransition's sign label (its "_indicator_label"), hidden for the capture. Returns how many
## were visible and are now hidden; one that was already hidden is not counted.
func _hide_transition_labels(n: Node) -> int:
	var hid := 0
	if "_indicator_label" in n:
		var l = n.get("_indicator_label")
		if l != null and is_instance_valid(l) and l.visible:
			l.visible = false
			hid += 1
	for c in n.get_children():
		hid += _hide_transition_labels(c)
	return hid


## Frame a village on its HOUSES, not its entrance (2026-10-31). The camera follows the player, who
## spawns at the entrance, so every village shot was an entrance plaza and .747's facades (roofs,
## walls, doors on their fronts) sat at the edge of the frame or out of it. This finds the densest
## cluster of HOUSE props a single view can hold, stands the player just below the nearest door in
## it (so the party is in shot too), and offsets the camera onto the cluster. DERIVED from the
## scene, never a per-village coordinate list: a village that gains or moves houses re-frames
## itself. A scene with fewer than 2 houses (Eldertree builds none; interiors; the cave) returns ""
## and is captured exactly as before.
func _frame_on_houses(scene: Node) -> String:
	if not ("player" in scene and "camera" in scene) or scene.player == null or scene.camera == null:
		return ""
	var centers: Array[Vector2] = []
	var doors: Array[Vector2] = []
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n.get_script() == VillagePropScript and n.kind == VillagePropScript.Kind.HOUSE:
			## position is the facade's base cell, bottom-centre of its first column (VillageProp.create).
			var half := VillagePropScript.TILE * 0.5
			centers.append(n.global_position + Vector2((n.size_tiles.x - 1) * half, -n.size_tiles.y * half))
		## The OTHER way a building stands up: every child of "Buildings" — shops, inns and doors that
		## carry their own art, which are Area2D themselves. _spawn_house_facades never faces a block that
		## art already claims, so Frosthold, Sandrift and Grimhollow have ZERO HOUSE props (measured) and
		## 5-6 buildings here each; counting facades alone, or excluding Area2D, left them unframed.
		if n is Node2D and n.get_parent() != null and n.get_parent().name == "Buildings":
			centers.append(n.global_position)
		if n is Area2D and "require_interaction" in n and n.require_interaction and "target_map" in n:
			doors.append(n.global_position)
	var reach := VIEW * 0.5 - Vector2(32, 32)
	var best := -1
	var best_n := 0
	for i in centers.size():
		var k := 0
		for c in centers:
			if absf(c.x - centers[i].x) <= reach.x and absf(c.y - centers[i].y) <= reach.y:
				k += 1
		if k > best_n:
			best_n = k
			best = i
	if best_n < 2:
		## Said out loud: a village that SHOULD re-frame and silently didn't reads exactly like one
		## that has nothing to frame.
		print("[SHOT] framing skipped: %d building(s) found (facades + building art), densest view holds %d (need 2)" % [centers.size(), best_n])
		return ""
	var target := Vector2.ZERO
	for c in centers:
		if absf(c.x - centers[best].x) <= reach.x and absf(c.y - centers[best].y) <= reach.y:
			target += c
	target /= best_n
	## Stand at a door's foot when the cluster has one in view, else on the street below it.
	var stand := target + Vector2(0, VillagePropScript.TILE * 3)
	var used_door := false
	var nearest := INF
	for d in doors:
		if absf(d.x - target.x) <= reach.x and absf(d.y - target.y) <= reach.y and d.distance_to(target) < nearest:
			nearest = d.distance_to(target)
			## 2.5 tiles, not 1.25: at 1.25 the player stood INSIDE the door's trigger and an "Enter …"
			## prompt drew over the frame (measured on Harmonia and Frosthold).
			stand = d + Vector2(0, VillagePropScript.TILE * 2.5)
			used_door = true
	## Smoothing OFF for the shot: with it on, the camera was still easing toward the new spot when the
	## frame was taken, so two identical runs differed by a 2-3 px pan (45% of pixels on Frosthold).
	scene.camera.position_smoothing_enabled = false
	## Stand somewhere a player CAN stand (cowir-overworld 21994): the door-foot point is synthetic and once
	## landed on Harmonia's river/wall seam. Ask the village itself (BaseVillage._is_cell_walkable), and step
	## to the nearest walkable cell within 4 tiles. Nothing walkable in reach keeps the point and SAYS so.
	stand = _walkable_stand(scene, stand)
	scene.player.global_position = stand
	## Where the tool stood the player, in world px (cowir-overworld 21992 asks whether a seam is a spawn or framing).
	print("[SHOT] player stood at world px (%d, %d), door=%s" % [int(stand.x), int(stand.y), str(used_door)])
	## Keep the player inside the frame: the offset never pushes them past the view's edge.
	var keep := VIEW * 0.5 - Vector2(48, 72)
	scene.camera.offset = (target - stand).clamp(-keep, keep)
	scene.camera.reset_smoothing()
	scene.camera.force_update_scroll()
	return "%d of %d buildings in view · player at %s (%s)" % [best_n, centers.size(), str(stand.round()), "a door" if used_door else "the street below them"]


## The title screen (2026-10-31): the source of the store COVER, and the last shipped frame no tool reached —
## it came from the exported .483 binary, and its corner still read "v3.33.483-alpha". GameLoop opens on it.
## Stars are placed with randf(), so the RNG is seeded first; the logo float and the star twinkle run on the
## wall clock (Time.get_ticks_msec), so two runs still differ by a few px. Judge this one by eye.
func _shoot_title() -> void:
	seed(748)
	var gl_res := load("res://src/GameLoop.tscn")
	if gl_res == null:
		print("[SHOT] FAIL: title_screen — GameLoop.tscn did not load")
		_fail += 1
		return
	var gl: Node = gl_res.instantiate()
	root.add_child(gl)
	## TitleScreen enables input after a 0.5s timer; 1.5s also lets the background and logo settle.
	await create_timer(1.5).timeout
	var ts = gl.get("_title_screen")
	## Refuse rather than photograph whatever is on screen: a GameLoop that skipped its title would
	## otherwise ship as the store cover.
	if ts == null or not is_instance_valid(ts) or not ts.visible:
		print("[SHOT] FAIL: title_screen — GameLoop did not open on its title screen")
		_fail += 1
		gl.queue_free()
		await process_frame
		return
	## Show what a PLAYER sees. Version.display() appends the git short-hash on every editor-build source
	## run (src/meta/Version.gd _should_ask_git), so a capture from any checkout — even one at the tag —
	## reads "vX (hash)", while the exported builds on the store read plain "vX". The store frame shows
	## the exported string, from Version.semver(), the same source display() uses.
	if "_version_label" in ts and ts._version_label != null:
		ts._version_label.text = "v" + load("res://src/meta/Version.gd").semver()
		await process_frame
	var img := root.get_texture().get_image()
	if not ShotGuard.save_or_refuse(img, "res://tmp/marketing/title_screen.png"):
		_fail += 1
	var ver := "?"
	if "_version_label" in ts and ts._version_label != null:
		ver = ts._version_label.text
	print("[SHOT] title_screen (%dx%d) version=%s" % [img.get_width(), img.get_height(), ver])
	_ok += 1

	## The COVER SOURCE: the same frame with TitleScreen._add_vignette's BOTTOM strip hidden (black,
	## alpha 0.45, from 70% of the height down). Measured 2026-10-31: the shipped cover_630x500 is this
	## title cropped (300,0,1056,600) -> LANCZOS 630x500, from a frame WITHOUT that strip (luma ratio 1.00
	## above it, 0.57 below it) and WITH the top one. The crop itself is done offline from this file, so
	## the recipe stays in one script. Found by its colour and place, not its child index.
	var vp_h: float = ts.get_viewport_rect().size.y
	var hid := 0
	for c in ts.get_children():
		if c is ColorRect and is_equal_approx(c.color.a, 0.45) and c.position.y >= vp_h * 0.6:
			c.visible = false
			hid += 1
	if hid != 1:
		print("[SHOT] FAIL: title_cover_source — expected exactly 1 bottom vignette strip, found %d" % hid)
		_fail += 1
	else:
		await process_frame
		await process_frame
		var img2 := root.get_texture().get_image()
		if not ShotGuard.save_or_refuse(img2, "res://tmp/marketing/title_cover_source.png"):
			_fail += 1
		print("[SHOT] title_cover_source (%dx%d), bottom strip hidden" % [img2.get_width(), img2.get_height()])
		_ok += 1
	gl.queue_free()
	await process_frame
