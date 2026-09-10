extends SceneTree
## The field-ELITE store shot: aura + the purple "It is watching you." tell.
##
## ⚠️ THE CONFIG IS OVERRIDDEN IN MEMORY. cowir-main's list said to set
## data/field_elites.json chance_per_fill 1.0 / min_seconds_between 0 for the shoot and then
## REVERT it. This does the same thing without touching the file, because a mutate-and-revert
## on a tracked data file has a failure mode the screenshot cannot show you: if this script
## dies between the edit and the revert, the repository is left with a 100%-spawn elite rate,
## and the next person to run a suite or a deploy from this tree ships or tests it. There is
## nothing to revert if nothing is written.
##
## MonsterSpawner caches the parsed JSON in `_elite_cfg` behind `_elite_cfg_loaded`, and
## GDScript Dictionaries are references — so mutating the dict returned by _elite_config()
## mutates the cache the spawner will read on its next tick. Process-local, dies with the
## process.
##
##   XDG_DATA_HOME=$PWD/tmp/shot_xdg xvfb-run -a godot --rendering-driver opengl3 \
##       --audio-driver Dummy -s tools/store_shot_elite.gd
##
## Sandboxed XDG is mandatory: user:// is one directory shared by every cowir-* checkout and
## struktured plays on it.

const ALERT_RADIUS := 150.0   ## RoamingMonster.ALERT_RADIUS — the tell's trigger distance
const VOID_BYTES := 20000
## Shifts the view down so the elite, which the ground plane's projection pushes well below
## the player, lands in frame. Measured against the rendered result, not derived.
const CAM_OFFSET := Vector2(20.0, 150.0)
## Camera magnification. 1.0 reproduces every shot taken before 2026-09-10 exactly, so this
## argument cannot silently change an existing capture — it has to be asked for.
##
## WHY IT EXISTS: field_elite_medieval.png (shot .239-era, after dark_knight finally got its
## overworld sheet) frames the elite correctly and is still a poor store image, because at
## overworld zoom the elite is roughly 20px of dark armour against dark green grass and the
## PLAYER dominates the frame. The subject of the screenshot cannot be seen in it. Position
## was never the problem and no amount of offset tuning fixes a scale problem.
const DEFAULT_ZOOM := 1.0

## Which overworld to shoot. Passed after `--`, e.g. `-s tools/store_shot_elite.gd -- steampunk`.
## The species is NOT overridden to match: field_elites.json maps world -> species, and
## swapping that mapping would photograph a monster in a world it never appears in. A store
## screenshot that advertises content the player cannot find there is a lie with a nice frame
## on it, so the world is chosen and whatever elite belongs there is what gets shot.
const WORLDS := {
	"medieval": "res://src/exploration/OverworldScene.gd",
	"steampunk": "res://src/exploration/SteampunkOverworld.gd",
	"suburban": "res://src/exploration/SuburbanOverworld.gd",
	"industrial": "res://src/exploration/IndustrialOverworld.gd",
	"futuristic": "res://src/exploration/FuturisticOverworld.gd",
	"abstract": "res://src/exploration/AbstractOverworld.gd",
}


func _init() -> void:
	await process_frame
	await process_frame
	_suppress_furniture()
	DirAccess.make_dir_recursive_absolute("res://tmp/marketing")

	var world := "medieval"
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		world = str(user_args[0])
	if not WORLDS.has(world):
		_die("unknown world '%s' — known: %s" % [world, ", ".join(WORLDS.keys())])
		return
	var ow_script := load(WORLDS[world])
	if ow_script == null:
		_die("%s did not load" % WORLDS[world])
		return
	print("[SHOT] world: %s (%s)" % [world, WORLDS[world]])
	var ow = ow_script.new()
	root.add_child(ow)
	# The overworld builds tiles, the player and the spawner across several frames.
	for i in range(30):
		await process_frame

	if not ("monster_spawner" in ow) or ow.monster_spawner == null:
		_die("overworld has no monster_spawner — its API moved")
		return
	if not ("player" in ow) or ow.player == null:
		_die("overworld has no player — the tell is distance-gated and cannot fire")
		return
	var sp = ow.monster_spawner

	# ── force the spawn, in memory ──────────────────────────────────────────
	if not sp.has_method("_elite_config"):
		_die("MonsterSpawner._elite_config absent — cannot override spawn odds")
		return
	var cfg: Dictionary = sp._elite_config()
	if cfg.is_empty() or not cfg.has("spawn"):
		_die("field_elites.json produced an empty config — nothing to override")
		return
	var spawn: Dictionary = cfg["spawn"]
	var was_chance = spawn.get("chance_per_fill")
	spawn["chance_per_fill"] = 1.0
	spawn["min_seconds_between"] = 0.0
	# Prove the override actually landed on the dict the spawner reads. Re-fetching through
	# the accessor (not reusing `spawn`) is the point: if the cache were copied rather than
	# referenced, this reads the old value and says so instead of silently spawning nothing.
	var readback: Dictionary = sp._elite_config().get("spawn", {})
	if float(readback.get("chance_per_fill", 0.0)) != 1.0:
		_die("override did not reach the spawner's cache (read back %s, was %s) — the config is copied, not referenced"
			% [str(readback.get("chance_per_fill")), str(was_chance)])
		return
	print("[SHOT] elite spawn odds overridden in memory: %s -> 1.0 (file untouched)" % str(was_chance))

	if not sp.has_method("_try_spawn_elite"):
		_die("MonsterSpawner._try_spawn_elite absent")
		return

	var elite: Node = null
	for attempt in range(60):
		sp._try_spawn_elite()
		await process_frame
		elite = _find_elite(sp)
		if elite != null:
			break
	if elite == null:
		_die("no elite spawned in 60 attempts at chance_per_fill=1.0 — _find_spawn_position likely returned ZERO (no valid tile near the player)")
		return
	print("[SHOT] elite spawned: %s" % str(elite.get("monster_id")))

	# ── put it inside ALERT_RADIUS so the tell fires ────────────────────────
	# 0.6 * radius: comfortably inside the gate, far enough that the sprite and the label do
	# not overlap the player.
	# HOLD the position every frame. Setting it once and waiting is what produced the first
	# unusable frame: RoamingMonster keeps walking, so by capture time it had drifted to the
	# screen edge and was half-cropped. Re-asserting each frame lets _tick_elite_watch run
	# (the tell is distance-gated, so the monster must stay near) while pinning it in shot.
	var off := Vector2(ALERT_RADIUS * 0.6, -20.0)
	if user_args.size() > 2:
		off = Vector2(float(user_args[1]), float(user_args[2]))
	# `-- <world> [offx offy] [zoom]`. A bad or absent value falls back to DEFAULT_ZOOM rather
	# than to 0, which would collapse the viewport and render nothing while still exiting 0.
	var zoom_f := DEFAULT_ZOOM
	if user_args.size() > 3:
		zoom_f = float(user_args[3])
	elif user_args.size() == 2:
		zoom_f = float(user_args[1])
	if zoom_f <= 0.0:
		print("[SHOT] zoom %s is not positive — falling back to %s" % [str(zoom_f), str(DEFAULT_ZOOM)])
		zoom_f = DEFAULT_ZOOM
	print("[SHOT] camera zoom: %sx" % str(zoom_f))
	var target: Vector2 = ow.player.global_position + off
	# Screen position is what matters and the overworld does not map world->screen linearly
	# (the ground is drawn on a skewed plane), so report both and let the offset be tuned
	# against the measurement rather than against a guess.
	var cam: Camera2D = ow.get_viewport().get_camera_2d()
	print("[SHOT] player world=%s  elite target=%s  offset=%s  camera=%s" % [
		str(ow.player.global_position), str(target), str(off),
		str(cam.global_position) if cam else "<none>"])
	# FRAME THE ELITE BY MOVING THE CAMERA, not by solving the projection. The overworld
	# draws its ground on a skewed plane, so a world-space offset from the player does not
	# map linearly to a screen offset — measured: a (90,-20) world delta put the elite ~340px
	# down-screen, not 20px up. Rather than model that, pin the camera between the two: the
	# elite is then centre-frame by construction whatever the projection does, and the player
	# stays in shot because the tell is distance-gated and they must be close anyway.
	var cam2: Camera2D = ow.get_viewport().get_camera_2d()
	for i in range(30):
		elite.global_position = target
		# Camera2D.offset, NOT global_position: the camera follows the player (it is driven
		# every frame), so an assigned position is overwritten before the next draw — measured,
		# the frame did not move. offset is not recomputed by the follow logic, so it sticks.
		if cam2:
			cam2.offset = CAM_OFFSET
			cam2.zoom = Vector2(zoom_f, zoom_f)
		await process_frame
	elite.global_position = target
	if cam2:
		cam2.offset = CAM_OFFSET
		cam2.zoom = Vector2(zoom_f, zoom_f)

	var tell = elite.get_node_or_null("MoodTell")
	if tell == null:
		print("[SHOT] ⚠ no MoodTell node — capturing anyway, but the prompt will be absent")
	elif not tell.visible:
		print("[SHOT] ⚠ MoodTell is HIDDEN (dist=%.1f, ALERT_RADIUS=%.1f) — the shot will not show the prompt"
			% [elite.global_position.distance_to(ow.player.global_position), ALERT_RADIUS])
	else:
		# `tell.visible` is a NODE PROPERTY. It says the distance gate fired, NOT that the
		# label lands inside the captured frame — and the old line printed "tell visible"
		# either way. Demonstrated 2026-09-10: a 2.0x zoom run printed "tell visible" on an
		# image with no tell in it at all. The reader takes that line as "the prompt is in
		# the shot", which is the one thing it never measured.
		print("[SHOT] tell node visible (distance gate fired): \"%s\"" % str(tell.text))
	_report_framing("tell", tell, root)
	_report_framing("elite", elite, root)

	var img := root.get_texture().get_image()
	var path := "res://tmp/marketing/field_elite_%s.png" % world
	img.save_png(path)
	var fa := FileAccess.open(path, FileAccess.READ)
	var sz := fa.get_length() if fa else 0
	if fa:
		fa.close()
	print("[SHOT] field_elite_%s %d B (%dx%d)%s" % [world, sz, img.get_width(), img.get_height(),
		"  ⚠ SUSPECT: likely an empty void" if sz < VOID_BYTES else ""])
	quit(0)


func _find_elite(sp) -> Node:
	if not ("_monsters" in sp):
		return null
	for m in sp._monsters:
		if is_instance_valid(m) and m.get("elite") == true:
			return m
	return null


## Is a node actually inside the captured frame? The shot is what ships, so "in the viewport
## rect" is the property that matters and node.visible is not it. Reports rather than dies:
## a badly framed shot is still worth writing to disk so a human can look at it — but the log
## must not call it good.
func _report_framing(label: String, node: Node, tree_root: Window) -> void:
	if node == null or not (node is CanvasItem):
		print("[SHOT] %s framing: UNKNOWN (not a CanvasItem)" % label)
		return
	var ci := node as CanvasItem
	var pos: Vector2 = ci.get_global_transform_with_canvas().origin
	var size: Vector2 = Vector2(tree_root.get_texture().get_width(), tree_root.get_texture().get_height())
	var inside := pos.x >= 0.0 and pos.y >= 0.0 and pos.x <= size.x and pos.y <= size.y
	print("[SHOT] %s framing: screen=(%.0f, %.0f) frame=%dx%d -> %s" % [
		label, pos.x, pos.y, int(size.x), int(size.y),
		"IN FRAME" if inside else "⚠ OUT OF FRAME — the subject is not in the picture"])


func _die(msg: String) -> void:
	print("[SHOT] FAIL: %s" % msg)
	quit(1)


func _suppress_furniture() -> void:
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		push_error("[SHOT] GameState absent — suppression cannot be applied")
		return
	# In-memory only; this flag also gates the only in-game escape past a broken world
	# transition, so it must never ship false.
	if "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	var hints_script = load("res://src/ui/TutorialHints.gd")
	if hints_script == null or not ("HINTS" in hints_script):
		push_error("[SHOT] TutorialHints.HINTS unreadable")
		return
	var ids: Array = hints_script.HINTS.keys()
	if ids.is_empty():
		push_error("[SHOT] TutorialHints.HINTS is EMPTY — suppression is vacuous")
		return
	if "game_constants" in gs:
		for id in ids:
			gs.game_constants["tutorial_" + str(id)] = true
	print("[SHOT] suppressed: debug overlay + %d tutorial hints" % ids.size())
