extends GutTest

## Every village's exit trigger sat 2-2.5 tiles LEFT of its exit tiles. The map loops set spawn_points["exit"] to the
## FIRST 'X' (the block's top-left) and the village centred a 4-6-tile trigger on it: Harmonia's exit is X cols 15..20,
## its trigger covered cols 12.5..18.5. So the right third of the exit did not take you out, the path beside it did,
## and the gate (the AreaTransition's posts, banner and "Exit" board) drew on the market stall — seen in a render.
## BaseVillage.exit_centre_of now centres it on the block. Derived: every village whose map has an exit block,
## stood up for real, judged by its live "Exit" trigger's collision.

const GS := preload("res://test/unit/helpers/village_grid_source.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const DIR := "res://src/maps/villages/"
const TILE := 32.0


func after_all() -> void:
	SoundState.restore()


func _villages() -> Dictionary:
	## path -> map rows, for every village script whose map carries an exit block.
	var out := {}
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string(DIR + f)
		if not src.contains("exit_trans"):
			continue
		var rows := GS.rows(src)
		for r in rows:
			if str(r).contains("X"):
				out[DIR + f] = rows
				break
	return out


func _top_row_exit_cols(rows: Array) -> Array:
	for y in rows.size():
		var cols: Array = []
		var row := str(rows[y])
		for x in row.length():
			if row[x] == "X":
				cols.append(x)
		if not cols.is_empty():
			return cols
	return []


func test_every_village_exit_trigger_covers_its_exit_tiles() -> void:
	var villages := _villages()
	assert_gt(villages.size(), 8, "CONTROL: the villages with an exit block were found (%d)" % villages.size())
	var bad: Array = []
	for path in villages:
		var vp := SubViewport.new()
		vp.world_2d = World2D.new()
		vp.size = Vector2i(640, 480)
		add_child_autofree(vp)
		var village: Node = load(path).new()
		vp.add_child(village)
		await get_tree().process_frame
		await get_tree().process_frame
		var exit := village.find_child("Exit", true, false) as Area2D
		if exit == null:
			bad.append("%s: no Exit transition" % path.get_file())
			continue
		var shape: CollisionShape2D = null
		for c in exit.get_children():
			if c is CollisionShape2D:
				shape = c
				break
		if shape == null or not (shape.shape is RectangleShape2D):
			bad.append("%s: Exit has no rectangle trigger" % path.get_file())
			continue
		var half := (shape.shape as RectangleShape2D).size.x / 2.0
		var cx: float = exit.position.x + shape.position.x
		var left := (cx - half) / TILE
		var right := (cx + half) / TILE
		var cols := _top_row_exit_cols(villages[path])
		var lo: float = float(cols.min())
		var hi: float = float(cols.max()) + 1.0
		if left > lo + 0.01 or right < hi - 0.01:
			bad.append("%s: trigger covers cols %.1f..%.1f, the exit is %d..%d" % [path.get_file(), left, right, int(lo), int(hi) - 1])
		elif absf((left + right) / 2.0 - (lo + hi) / 2.0) > 0.51:
			bad.append("%s: trigger centred %.1f tiles off the exit" % [path.get_file(), (left + right) / 2.0 - (lo + hi) / 2.0])
		vp.queue_free()
	assert_eq(bad, [], "exit triggers that miss their exit tiles: %s" % str(bad))


func _all(n: Node, out: Array) -> void:
	out.append(n)
	for c in n.get_children():
		_all(c, out)


## Centring the exits moved every gate, and Frosthold's Guard Ingrid had been authored beside the OLD, off-road one:
## the gate landed on her and her name sat on the "Exit" board. Nothing a player bumps into or reads may stand in
## the gate's drawing (48px arch + pillars, 56px tall) or its board at (-40, -72).
func test_nothing_stands_in_a_village_gate() -> void:
	var villages := _villages()
	var bad: Array = []
	var judged := 0
	for path in villages:
		var vp := SubViewport.new()
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var village: Node = load(path).new()
		vp.add_child(village)
		await get_tree().process_frame
		await get_tree().process_frame
		var exit := village.find_child("Exit", true, false) as Node2D
		if exit == null:
			continue
		judged += 1
		var p := exit.global_position
		var zone := Rect2(p.x - 44.0, p.y - 76.0, 88.0, 80.0)
		var nodes: Array = []
		_all(village, nodes)
		for n in nodes:
			if n == exit or not (n is Node2D) or exit.is_ancestor_of(n) or n.get_script() == null:
				continue
			var scr: String = n.get_script().resource_path.get_file()
			if not (scr.contains("NPC") or scr.contains("VillageProp") or scr.contains("Chicken") or scr.contains("Signpost") or scr.contains("Lamp")):
				continue
			if zone.has_point((n as Node2D).global_position):
				bad.append("%s: %s (%s) stands in the gate" % [path.get_file(), n.name, scr])
		vp.queue_free()
	assert_gt(judged, 8, "CONTROL: the village gates were judged (%d)" % judged)
	assert_eq(bad, [], "things standing in a village gate: %s" % str(bad))


## Props are drawn up from their base cell, so a stall can cover a door its origin never touches: Brasston's stall at
## (7,12) drew its awning and counter across the Clockwork Loft door at (9,12), and before the exits were centred
## Harmonia's covered its own gate. Every village, every drawn door (exit and interior), every prop's drawn sprite.
func test_no_prop_is_drawn_across_a_door() -> void:
	var villages := _villages()
	var bad: Array = []
	var doors_judged := 0
	for path in villages:
		var vp := SubViewport.new()
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var village: Node = load(path).new()
		vp.add_child(village)
		await get_tree().process_frame
		await get_tree().process_frame
		var nodes: Array = []
		_all(village, nodes)
		var doors: Array = []
		var props: Array = []
		for n in nodes:
			if n.get_script() == null:
				continue
			var rp: String = n.get_script().resource_path
			if rp.ends_with("AreaTransition.gd") and bool(n.get("show_gate_visual")):
				doors.append(n)
			elif rp.ends_with("VillageProp.gd"):
				props.append(n)
		for d in doors:
			doors_judged += 1
			var p: Vector2 = (d as Node2D).global_position
			# The arch and pillars as AreaTransition draws them. The sign label draws ON TOP of props, so it is not judged.
			var shapes: Array = [Rect2(p.x - 30.0, p.y - 60.0, 60.0, 60.0).grow(-2.0)]
			for prop in props:
				for c in prop.get_children():
					if c is Sprite2D and (c as Sprite2D).texture:
						var spr := c as Sprite2D
						var drawn := Rect2((prop as Node2D).global_position + spr.position, spr.texture.get_size())
						if shapes.any(func(r: Rect2) -> bool: return drawn.intersects(r)):
							bad.append("%s: a %s prop at %s is drawn across %s" % [path.get_file(), VillageProp.Kind.keys()[int(prop.get("kind"))] if prop.get("kind") != null else "?", (prop as Node2D).global_position, d.name])
		vp.queue_free()
	assert_gt(doors_judged, 20, "CONTROL: the village doors were judged (%d)" % doors_judged)
	assert_eq(bad, [], "props drawn across a door: %s" % str(bad))
