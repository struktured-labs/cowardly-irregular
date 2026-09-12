extends GutTest

## `Mode7Overlay.is_active` is a STATIC, and the map you walk into inherits whatever the last one
## left on it. Every dungeon inherited `true`.
##
## The overworld clears it in `_exit_tree` (`_mode7.cleanup()`), but `MapSystem.load_map` calls
## `unload_current_map()` -> `queue_free()`, which is DEFERRED, and then `add_child`s the new map
## immediately. So the new map's `_ready` runs a full frame BEFORE the old one's `_exit_tree`.
## `BaseVillage` and `BaseInterior` already defend against this in their first two statements, with
## a playtest citation — "stale true gave VILLAGES the 2x horizontal boost after visiting the
## overworld — movement overshoot made doors near-impossible to hit" (2026-07-11). Dungeons never
## got that line, and neither did the three interiors that extend Node2D instead of BaseInterior.
##
## ⚠️ THE MOVEMENT HALF SELF-HEALS AND THE GEOMETRY HALF DOES NOT, which is why this outlived the
## village fix. One frame later `cleanup()` finally runs and the 2x boost goes away — but every
## interactable sized itself in `_ready`, reading `InteractGeometry.is_mode7()` while it was still
## true, and a CollisionShape2D built once is not rebuilt. Measured on the Whispering Cave, the
## tutorial dungeon, whose only entrance is the W1 overworld:
##
##     entered from a village     TreasureChest circle r=40
##     entered from the OVERWORLD TreasureChest circle r=128, scale (1.0, 1.67)
##
## 128px with the billboard Y-stretch is 4 cells wide and 6.7 tall in a 32px-cell dungeon. It does
## not merely make the chest easy to press; it makes the chest win presses meant for the stairs,
## the boss trigger and its neighbours, which is the same press-theft class as the chest that was
## sitting in the Ironhaven doorway.
##
## 🔑 The corpus is DERIVED from the two directories, not listed — a dungeon added next month is
## covered without anyone remembering this file exists.

## ⛔ THE CORPUS IS DERIVED FROM THE MAP CONTRACT, not from a directory listing and not from a
## hand list. A map is what GameLoop can drop a player into, and the method it calls to do that is
## `spawn_player_at`. Measured: 59 scripts across the three map directories implement it; exactly
## one does not — `BossTrigger`, an Area2D COMPONENT that lives inside a dungeon and has no
## business clearing a global. A directory listing hands you that component and demands it clear
## the static, which is a false positive whose natural repair is an allowlist.
##
## I tried GameLoop's own preload constants first and its control caught them out: 54 paths, and
## the Whispering Cave is not among them, because that one routes through MapSystem as a .tscn.
## Two loaders, one contract — so key on the contract.
##
## Villages are in the corpus on purpose. They already clear the static, so they are the sweep's
## proof that a map CAN come back clean rather than the sweep being unable to see a pass.
const MAP_DIRS := ["res://src/maps/dungeons/", "res://src/maps/interiors/", "res://src/maps/villages/"]


func _map_scripts() -> Array:
	var out: Array = []
	for d in MAP_DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		dir.list_dir_begin()
		var e: String = dir.get_next()
		while e != "":
			if e.ends_with(".gd"):
				var probe = load(d + e).new()
				if probe is Object and (probe as Object).has_method("spawn_player_at"):
					out.append(d + e)
				if probe is Node:
					(probe as Node).free()
			e = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out


## Arrive with the statics hot, exactly as walking in from a Mode 7 overworld leaves them.
func _enter_from_the_overworld(path: String) -> Dictionary:
	Mode7Overlay.is_active = true
	Mode7Overlay.camera_angle = 0.7
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var m = load(path).new()
	if not (m is Node2D):
		if m is Node:
			(m as Node).free()
		return {"skipped": true}
	vp.add_child(m)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var r := {
		"skipped": false,
		"active": Mode7Overlay.is_active,
		"angle": Mode7Overlay.camera_angle,
		"node": m,
		"vp": vp,
	}
	return r


func test_no_dungeon_or_interior_inherits_mode7() -> void:
	var leaked: Array = []
	var checked := 0
	var corpus: Array = _map_scripts()
	assert_true(corpus.has("res://src/maps/dungeons/WhisperingCave.gd"),
		"CONTROL: the corpus must contain the Whispering Cave — the tutorial dungeon, whose only " +
		"entrance is the Mode 7 overworld. %d maps found" % corpus.size())
	assert_false(corpus.has("res://src/maps/dungeons/BossTrigger.gd"),
		"CONTROL: and must NOT contain BossTrigger — a component inside a dungeon, not a map")
	for path in corpus:
		var r: Dictionary = await _enter_from_the_overworld(path)
		if bool(r.get("skipped", true)):
			continue
		checked += 1
		if bool(r["active"]) or absf(float(r["angle"])) > 0.001:
			leaked.append("%s — after _ready: is_active=%s camera_angle=%.2f. Add the two BaseVillage lines to its _ready: Mode7Overlay.is_active = false and camera_angle = 0.0" % [
				str(path).get_file(), str(r["active"]), float(r["angle"])])
		(r["node"] as Node).queue_free()
		await get_tree().physics_frame
	Mode7Overlay.is_active = false
	Mode7Overlay.camera_angle = 0.0

	assert_gt(checked, 20,
		"CONTROL: only %d maps instantiated from two directories — with a thin corpus the [] below is free" % checked)
	leaked.sort()
	assert_eq(leaked, [],
		"a map that is never Mode 7 inherited the overworld's static: its player gets the 2x " +
		"horizontal boost and its interactables size themselves as billboards: %s" % ", ".join(leaked))


## The half that does not self-heal: a shape built under the leak is never rebuilt.
func test_a_dungeon_chest_is_not_a_billboard() -> void:
	var r: Dictionary = await _enter_from_the_overworld("res://src/maps/dungeons/WhisperingCave.gd")
	assert_false(bool(r.get("skipped", true)), "PRECONDITION: the Whispering Cave instantiates")
	if bool(r.get("skipped", true)):
		return
	var fat: Array = []
	var chests := 0
	var stack: Array = [r["node"]]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is Node2D and n.has_method("interact")):
			continue
		for c in n.get_children():
			if not (c is CollisionShape2D) or c.shape == null:
				continue
			chests += 1
			var radius := -1.0
			if c.shape is CircleShape2D:
				radius = (c.shape as CircleShape2D).radius
			if radius >= InteractGeometry.SIGNPOST_RADIUS_MODE7 or absf(c.scale.y - InteractGeometry.MODE7_Y_STRETCH) < 0.01:
				var cls := str(n.get_script().resource_path).get_file().get_basename() if n.get_script() else "?"
				fat.append("%s radius %.0f scale %s" % [cls, radius, str(c.scale)])
	(r["node"] as Node).queue_free()
	await get_tree().physics_frame
	Mode7Overlay.is_active = false
	Mode7Overlay.camera_angle = 0.0

	assert_gt(chests, 0, "CONTROL: the cave carries interactables with shapes, or the [] is free")
	fat.sort()
	assert_eq(fat, [],
		"a Whispering Cave interactable built itself with Mode 7 geometry because the static was " +
		"still hot in _ready. cleanup() fixes movement a frame later; a CollisionShape2D built " +
		"once is never rebuilt, so this lasts the whole visit: %s" % ", ".join(fat))


## CONTROL: the probe must be able to SEE the leak, or both [] above are decoration. A bare Node2D
## clears nothing, which is exactly what every dungeon was before this branch.
func test_the_probe_can_see_a_map_that_clears_nothing() -> void:
	Mode7Overlay.is_active = true
	Mode7Overlay.camera_angle = 0.7
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var bare := Node2D.new()
	vp.add_child(bare)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var still_active: bool = Mode7Overlay.is_active
	var still_angled: float = Mode7Overlay.camera_angle
	bare.queue_free()
	await get_tree().physics_frame
	Mode7Overlay.is_active = false
	Mode7Overlay.camera_angle = 0.0
	assert_true(still_active,
		"a map with no clear must leave is_active TRUE — if the static resets itself, the sweep " +
		"above passes no matter what any dungeon does")
	assert_almost_eq(still_angled, 0.7, 0.001, "and must leave camera_angle where the overworld left it")
