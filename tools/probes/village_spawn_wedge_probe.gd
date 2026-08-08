extends SceneTree

## Does an overlapping village spawn STRAND the player, or shove them and free them?
## Every column in the fleet's thread is blocked/clear; this one is stuck/free.
##
## RESULT 2026-08-08: 0 of 7 wedged. Settle 7.8-8.3px (= radius 4.0 + safe_margin 4.0),
## 6-8 of 8 escape directions. The seven clip you and release you; they do not trap you.
##
## ⛔ IF YOU LIFT THIS INTO A PERMANENT GUARD, REPORT DISPLACEMENT PER DIRECTION, NOT A
## COUNT OVER A BAR. This version prints "6/8" and that number is not about the map: the
## FREE threshold below is an arbitrary 24.0, and chapel_exit's south travels 20.2px. Four
## rigs measured the same eight magnitudes to one decimal and DISAGREED on the boolean
## derived from them, purely because they had each picked 24. A shared arbitrary constant
## fakes independence AND hides the agreement that would have demonstrated the real thing.
##
## The verdict here is threshold-independent and that is why it stands: the clear
## directions travel 117-160px against 5px stops, and no defensible bar separates those.
##
## TWO MORE THINGS A LIFTED VERSION MUST GET RIGHT, both found by peers whose rigs differed:
##
## 1. MEASURE TRAVEL FROM THE SETTLED POSITION, NOT THE SPAWN. This probe settles first and
##    resets to `settled` before each direction, so travel excludes depenetration. A rig
##    that captures `start` before its first move_and_slide silently adds the whole ~8px
##    settle to every direction — which flips a 20.2px partial to 27.7 and the verdict with
##    it. Two rigs "disagreeing about a threshold" turned out to be measuring two different
##    quantities and calling both travel.
##
## 2. A CLEAR DIRECTION HERE MEASURES THE BUDGET, NOT THE MAP. 40 frames x 240px/s / 60 =
##    exactly 160.0, and every unobstructed direction reports precisely that. So "160.0" is
##    saturation, not a distance. Raise the budget until clear directions stop pinning to
##    it, or report time-to-clear instead.

const TS := 32
const OFFENDERS := {
	"BrasstonVillage": ["clockwork_loft_exit"],
	"HarmoniaVillage": ["bar_exit", "chapel_exit", "library_exit", "cartographer_exit"],
	"ScripturaPlaza": ["guild_exit", "bookshop_exit"],
}
## Known-CLEAR spawns in the same scenes — the control. Without them a table of
## "free" rows cannot be distinguished from a rig that never collides with anything.
const CONTROLS := {
	"BrasstonVillage": ["entrance"],
	"HarmoniaVillage": ["entrance"],
	"ScripturaPlaza": ["entrance"],
}
var DIRS := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
	Vector2(1,-1).normalized(), Vector2(-1,-1).normalized(),
	Vector2(1,1).normalized(), Vector2(-1,1).normalized()]
const DIR_NAMES := ["E","W","N","S","NE","NW","SE","SW"]


func _make_body() -> CharacterBody2D:
	var b := CharacterBody2D.new()
	b.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	b.wall_min_slide_angle = 0.0
	b.safe_margin = 4.0
	b.collision_layer = 2
	b.collision_mask = 1
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 4.0
	cs.shape = sh
	cs.position = Vector2.ZERO
	b.add_child(cs)
	return b


func _probe(scene: Node, body: CharacterBody2D, pos: Vector2) -> Dictionary:
	body.global_position = pos
	# Settle: depenetration happens DURING a move, never passively.
	for i in range(20):
		body.velocity = Vector2.ZERO
		body.move_and_slide()
		await physics_frame
	var settled: Vector2 = body.global_position
	var settle_px: float = settled.distance_to(pos)
	var free: Array = []
	for d in range(DIRS.size()):
		body.global_position = settled
		var start: Vector2 = body.global_position
		for i in range(40):
			body.velocity = DIRS[d] * 240.0   # real overworld move_speed
			body.move_and_slide()
			await physics_frame
		if body.global_position.distance_to(start) > 24.0:
			free.append(DIR_NAMES[d])
	return {"settle": settle_px, "free": free}


func _init() -> void:
	await process_frame
	print("village   spawn                    settle   free dirs")
	print("------------------------------------------------------------")
	var stuck := 0
	var total := 0
	var ctrl_ok := 0
	var ctrl_n := 0
	for vname in OFFENDERS.keys():
		var path := "res://src/maps/villages/%s.gd" % vname
		var scr = load(path)
		if scr == null:
			printerr("CANNOT LOAD ", path); continue
		var resident := 0
		for c in root.get_children():
			if c.get_script() != null and str(c.get_script().resource_path).find("/villages/") > -1:
				resident += 1
		if resident != 0:
			printerr("*** %d village(s) STILL RESIDENT before loading %s — results void" % [resident, vname])
		var scene = scr.new()
		root.add_child(scene)
		await physics_frame
		await physics_frame
		var sp = scene.get("spawn_points")
		if sp == null:
			printerr("no spawn_points on ", vname); scene.queue_free(); continue
		var body := _make_body()
		scene.add_child(body)
		await physics_frame
		for group in [[OFFENDERS[vname], false], [CONTROLS.get(vname, []), true]]:
			for sname in group[0]:
				if not sp.has(sname):
					printerr("  MISSING SPAWN ", vname, "::", sname); continue
				var r = await _probe(scene, body, sp[sname])
				var tag := "  [CONTROL]" if group[1] else ""
				print("%-10s %-24s %6.1f   %d/8 %s%s" % [vname, sname, r["settle"],
					r["free"].size(), ", ".join(r["free"]), tag])
				if group[1]:
					ctrl_n += 1
					if r["free"].size() == 8:
						ctrl_ok += 1
				else:
					total += 1
					if r["free"].size() == 0:
						stuck += 1
		root.remove_child(scene)
		scene.free()
		await physics_frame
		await physics_frame
	print("------------------------------------------------------------")
	print("CONTROL: %d/%d known-clear spawns free in all 8 dirs %s" % [ctrl_ok, ctrl_n,
		"OK" if ctrl_ok == ctrl_n and ctrl_n > 0 else "*** CONTROL FAILED — RESULTS VOID ***"])
	print("offenders: %d of %d WEDGED (0 of 8 escape directions)" % [stuck, total])
	quit(0 if (ctrl_n > 0 and ctrl_ok == ctrl_n) else 2)
