extends SceneTree
## The village elevator, photographed MID-RIDE.
##
## WHY THIS WAS OWED AND PREVIOUSLY DROPPED
## ----------------------------------------
## CAPTIONS.md has carried "Elevator mid-ride — still owed. Needs VillageElevator.interact()
## driven through an actual ride; scene instantiation cannot produce it." It is right that
## instantiating the village is not enough: the car does not exist until interact() runs. It
## is a Sprite2D created inside that method, tweened from origin to destination over
## RIDE_TIME, and freed the moment the tween finishes.
##
## RIDE_TIME IS 0.35 SECONDS. At 60fps that is ~21 frames, and `brasston_lift` was dropped
## once already for framing. A timed grab — await some seconds, screenshot — is a wall-clock
## guess about when a tween is halfway, which is the same instrument that made the web smoke
## fail 3 runs in 5 before it was changed to poll. So this does not sleep.
##
## WHAT IT DOES INSTEAD
## --------------------
## Calls interact() WITHOUT awaiting (awaiting it would return only after the car is already
## freed), then polls every frame for the car node and computes ride progress from MEASURED
## POSITIONS:
##
##     progress = distance(car, origin) / distance(origin, destination)
##
## and captures inside a window around the middle. Mid-ride is a geometric fact about where
## the car is, not a fact about elapsed time, so that is what gets measured. If the window is
## never observed the script FAILS rather than writing whatever frame it happens to hold —
## a frame with no car in it is exactly what "elevator mid-ride" must never mean.
##
##   XDG_DATA_HOME=$PWD/tmp/shot_xdg xvfb-run -a godot --rendering-driver opengl3 \
##       --audio-driver Dummy -s tools/store_shot_elevator.gd -- brasston
##
## Sandboxed XDG is mandatory: user:// is one directory shared by every cowir-* checkout.

const PROGRESS_LO := 0.30
const PROGRESS_HI := 0.70
const MAX_FRAMES := 240          ## ~4s at 60fps; the ride is 0.35s, so this is slack not budget
const VOID_BYTES := 20000

## Villages that build a VillageElevator. Named rather than discovered so an empty result is a
## failure with a cause, not a silent skip.
const VILLAGES := {
	"brasston": "res://src/maps/villages/BrasstonVillage.gd",
	"rivetrow": "res://src/maps/villages/RivetRowVillage.gd",
	"nodeprime": "res://src/maps/villages/NodePrimeVillage.gd",
}


func _init() -> void:
	await process_frame
	await process_frame

	var village := "brasston"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		village = str(args[0])
	if not VILLAGES.has(village):
		_die("unknown village '%s' — known: %s" % [village, ", ".join(VILLAGES.keys())])
		return

	var res = load(VILLAGES[village])
	if res == null:
		_die("%s did not load" % VILLAGES[village])
		return
	var scene: Node = res.new() if res is GDScript else res.instantiate()
	root.add_child(scene)
	for i in range(20):
		await process_frame

	var elevator: Node = _find_elevator(scene)
	if elevator == null:
		_die("no VillageElevator under %s — the village builds none, or the class moved" % village)
		return
	var origin: Vector2 = elevator.bottom_position
	var destination: Vector2 = elevator.top_position
	if origin == destination:
		_die("bottom_position == top_position (%s) — there is no ride to photograph" % str(origin))
		return
	var span := origin.distance_to(destination)
	print("[SHOT] elevator: bottom=%s top=%s span=%.1fpx ride=%.2fs" % [
		str(origin), str(destination), span, float(elevator.RIDE_TIME)])

	# A stand-in rider. interact() only reads global_position to choose direction and then
	# moves it, so a bare Node2D is the whole contract. Placed at the bottom so the ride goes
	# UP, which is the direction the shot wants.
	var rider := Node2D.new()
	rider.global_position = origin
	scene.add_child(rider)

	# Camera framing is TUNED AGAINST THE RENDERED RESULT, not derived. The elevator sits near
	# the map origin, so centring on it exactly puts ~40% of the frame in off-map grey void —
	# measured on the first run. `--zoom=` and `--camy=` shift the view back onto the village.
	var zoom_f := 1.0
	var cam_dy := 0.0
	for a in args:
		if str(a).begins_with("--zoom="):
			zoom_f = float(str(a).get_slice("=", 1))
		elif str(a).begins_with("--camy="):
			cam_dy = float(str(a).get_slice("=", 1))
	if zoom_f <= 0.0:
		print("[SHOT] zoom %s is not positive — using 1.0" % str(zoom_f))
		zoom_f = 1.0
	var cam := Camera2D.new()
	cam.global_position = (origin + destination) * 0.5 + Vector2(0.0, cam_dy)
	cam.zoom = Vector2(zoom_f, zoom_f)
	scene.add_child(cam)
	cam.make_current()
	print("[SHOT] camera: pos=%s zoom=%.2fx" % [str(cam.global_position), zoom_f])
	for i in range(4):
		await process_frame

	# Snapshot the sibling set so the car — created inside interact() as a child of the
	# elevator's PARENT — can be identified by difference rather than by guessing its name.
	var before := {}
	for c in elevator.get_parent().get_children():
		before[c.get_instance_id()] = true

	elevator.interact(rider)   # deliberately NOT awaited: it returns after the car is freed

	var car: Node2D = null
	var captured := false
	var best_progress := -1.0
	var seen_car := false
	for frame in range(MAX_FRAMES):
		await process_frame
		if car == null or not is_instance_valid(car):
			car = null
			for c in elevator.get_parent().get_children():
				if not before.has(c.get_instance_id()) and c is Sprite2D:
					car = c
					seen_car = true
					break
		if car == null or not is_instance_valid(car):
			if captured:
				break
			continue
		var progress: float = car.global_position.distance_to(origin) / span
		best_progress = max(best_progress, progress)
		if progress >= PROGRESS_LO and progress <= PROGRESS_HI:
			_report_framing("elevator car", car, root)
			# WHERE IS THE RIDER? interact() tweens the CAR and only calls
			# player.teleport(destination) AFTER `await tween.finished`. If that reading is
			# right, the rider has not moved at all at this instant — so the frame shows a pad
			# sliding by itself while the player stands at the bottom. Measured, not assumed.
			print("[SHOT] rider: moved %.1fpx of %.1f (car has moved %.1fpx)" % [
				rider.global_position.distance_to(origin), span,
				car.global_position.distance_to(origin)])
			var img := root.get_texture().get_image()
			DirAccess.make_dir_recursive_absolute("res://tmp/marketing")
			var path := "res://tmp/marketing/elevator_midride_%s.png" % village
			img.save_png(path)
			var fa := FileAccess.open(path, FileAccess.READ)
			var sz := fa.get_length() if fa else 0
			if fa:
				fa.close()
			print("[SHOT] captured at progress %.2f (window %.2f-%.2f), frame %d" % [
				progress, PROGRESS_LO, PROGRESS_HI, frame])
			print("[SHOT] elevator_midride_%s %d B (%dx%d)%s" % [village, sz, img.get_width(), img.get_height(),
				"  ⚠ SUSPECT: likely an empty void" if sz < VOID_BYTES else ""])
			captured = true
			break

	if not captured:
		if not seen_car:
			_die("interact() ran but no new Sprite2D ever appeared under the elevator's parent — the car is not being created, so there was never a ride to photograph")
		else:
			_die("the car appeared but was never inside the %.2f-%.2f window (highest progress seen: %.2f). Writing the frame anyway would ship a picture of something else."
				% [PROGRESS_LO, PROGRESS_HI, best_progress])
		return
	quit(0)


func _find_elevator(n: Node) -> Node:
	for c in n.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("VillageElevator.gd"):
			return c
		var deeper := _find_elevator(c)
		if deeper != null:
			return deeper
	return null


## Is the subject inside the captured frame? The shot is what ships, so being in the viewport
## rect is the property that matters — a node can exist, be visible, be mid-ride and still be
## off-screen, and `brasston_lift` was dropped once for exactly that.
func _report_framing(label: String, node: Node, tree_root: Window) -> void:
	if node == null or not (node is CanvasItem):
		print("[SHOT] %s framing: UNKNOWN (not a CanvasItem)" % label)
		return
	var pos: Vector2 = (node as CanvasItem).get_global_transform_with_canvas().origin
	var size := Vector2(tree_root.get_texture().get_width(), tree_root.get_texture().get_height())
	var inside := pos.x >= 0.0 and pos.y >= 0.0 and pos.x <= size.x and pos.y <= size.y
	print("[SHOT] %s framing: screen=(%.0f, %.0f) frame=%dx%d -> %s" % [
		label, pos.x, pos.y, int(size.x), int(size.y),
		"IN FRAME" if inside else "⚠ OUT OF FRAME — the subject is not in the picture"])


func _die(msg: String) -> void:
	print("[SHOT] FAIL: %s" % msg)
	quit(1)
