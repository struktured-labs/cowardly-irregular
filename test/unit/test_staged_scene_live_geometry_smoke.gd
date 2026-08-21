extends GutTest

## END-TO-END SMOKE for the two shipped staged scenes (cowir-main msg 2948).
##
## Every other cutscene ratchet I own checks STRUCTURE — is the theme
## registered, does the portrait resolve, is the coord inside the map rect.
## None of them prove the scene still LOOKS right, because none of them
## instantiate the actual village and ask where things really are.
##
## This one builds the REAL HarmoniaVillage scene and drives the REAL
## cutscene JSON against it, then asserts on live geometry:
##   • every puppet mark lands on a WALKABLE cell (not inside a building,
##     a fountain, or the perimeter wall) — the failure mode that reads as
##     "characters standing in a wall"
##   • every replace_npc target actually EXISTS in the live scene under
##     that exact name — a rename in HarmoniaVillage.gd silently degrades
##     the puppet to a spawn-at-player fallback
##   • walk paths don't cross impassable terrain — an actor tweens straight
##     through geometry, so a mark being legal isn't enough
##
## Why this exists: a lot landed under the cutscene lane in one day
## (InteractGeometry overhaul, NPC turn-to-face, wanderer sprite offset,
## sprite art regen, the Harmonia coordinate re-sync, conscript_nearby).
## The coordinate re-sync in particular was itself a latent break from a
## village resize that no structural test could have caught — the coords
## were valid, they were just valid for the OLD map. This closes that gap.

const HARMONIA_TSCN := "res://src/maps/villages/HarmoniaVillage.tscn"
const TILE_SIZE := 32

const STAGED_SCENES := [
	"res://data/cutscenes/world1_chapter1.json",
	"res://data/cutscenes/world1_harmonia_after_cave.json",
]

var _village: Node = null


## Per-test, NOT before_all: add_child_autofree frees at the end of each
## test, so a before_all-built village is already freed by test 2 (fails as
## "previously freed", with an empty NPC roster that reads like a real bug).
func before_each() -> void:
	var packed: PackedScene = load(HARMONIA_TSCN)
	assert_not_null(packed, "HarmoniaVillage.tscn must load")
	_village = packed.instantiate()
	add_child_autofree(_village)
	# NPCs + tilemap are built in _ready; give deferred children a frame.
	await get_tree().process_frame
	await get_tree().process_frame


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _scene(path: String) -> Dictionary:
	var parsed = JSON.parse_string(_read(path))
	assert_true(parsed is Dictionary, "%s must parse" % path)
	return parsed if parsed is Dictionary else {}


func _walkable(pos: Vector2) -> bool:
	# Delegates to the village's own authority so this tracks any future
	# change to what counts as impassable, rather than re-deriving it.
	if _village == null or not _village.has_method("_is_cell_walkable"):
		return true
	var cell := Vector2i(int(floor(pos.x / TILE_SIZE)), int(floor(pos.y / TILE_SIZE)))
	return _village._is_cell_walkable(cell)


func _live_npc_names() -> Dictionary:
	var out: Dictionary = {}
	_collect_npc_names(_village, out)
	return out


func _collect_npc_names(node: Node, out: Dictionary) -> void:
	for child in node.get_children():
		if "npc_name" in child:
			out[str(child.npc_name)] = child
		_collect_npc_names(child, out)


## Every position an actor is asked to OCCUPY (spawn marks + walk destinations).
func _actor_marks(scene: Dictionary) -> Array:
	var marks: Array = []
	var idx := 0
	for step in scene.get("steps", []):
		if step is Dictionary:
			var t := str(step.get("type", ""))
			if t == "spawn_actor" and step.get("at") is Array:
				var at = step["at"]
				marks.append({"i": idx, "type": t, "id": str(step.get("id", "")), "pos": Vector2(float(at[0]), float(at[1]))})
			elif t == "move_actor" and step.get("to") is Array:
				var to = step["to"]
				marks.append({"i": idx, "type": t, "id": str(step.get("id", "")), "pos": Vector2(float(to[0]), float(to[1]))})
		idx += 1
	return marks


# ── The scene builds at all ───────────────────────────────────────────

func test_village_instantiates_with_tilemap_and_npcs() -> void:
	assert_not_null(_village, "HarmoniaVillage must instantiate")
	assert_true("tile_map" in _village and _village.tile_map != null,
		"village must have built its tile_map — every geometry assertion below depends on it")
	assert_gt(_live_npc_names().size(), 5,
		"village must have populated its NPC roster")


# ── Marks land on walkable ground ─────────────────────────────────────

func test_every_actor_mark_is_on_walkable_ground() -> void:
	# THE headline check. A mark inside a building or the fountain renders
	# as a character standing in scenery — the exact class struktured
	# reported as "cutscene characters were not aligned".
	var offenders: Array = []
	for path in STAGED_SCENES:
		var scene := _scene(path)
		for m in _actor_marks(scene):
			if not _walkable(m["pos"]):
				var cell := Vector2i(int(m["pos"].x / TILE_SIZE), int(m["pos"].y / TILE_SIZE))
				offenders.append("%s[step %d] %s '%s' → %s (tile %s) is IMPASSABLE" % [
					path.get_file(), m["i"], m["type"], m["id"], m["pos"], cell])
	assert_eq(offenders.size(), 0,
		"staged actor marks must land on walkable ground:\n  %s" % "\n  ".join(offenders))


func test_walk_paths_do_not_cross_impassable_terrain() -> void:
	# A legal start and a legal end isn't enough — walk_to tweens in a
	# straight line, so an actor will glide through a building between two
	# valid marks. Samples the segment from each actor's previous known
	# position to its destination.
	var offenders: Array = []
	for path in STAGED_SCENES:
		var scene := _scene(path)
		var last_pos: Dictionary = {}   # actor id -> Vector2
		var idx := 0
		for step in scene.get("steps", []):
			if not (step is Dictionary):
				idx += 1
				continue
			var t := str(step.get("type", ""))
			var aid := str(step.get("id", ""))
			if t == "spawn_actor" and step.get("at") is Array:
				var at = step["at"]
				last_pos[aid] = Vector2(float(at[0]), float(at[1]))
			elif t == "move_actor" and step.get("to") is Array:
				var to = step["to"]
				var dest := Vector2(float(to[0]), float(to[1]))
				if last_pos.has(aid):
					var from: Vector2 = last_pos[aid]
					var blocked := _first_blocked_on_segment(from, dest)
					if blocked != Vector2.INF:
						offenders.append("%s[step %d] '%s' walks %s → %s through impassable tile %s" % [
							path.get_file(), idx, aid, from, dest,
							Vector2i(int(blocked.x / TILE_SIZE), int(blocked.y / TILE_SIZE))])
				last_pos[aid] = dest
			idx += 1
	assert_eq(offenders.size(), 0,
		"staged walk paths must stay on walkable ground end to end:\n  %s" % "\n  ".join(offenders))


func _step_ok(a: Vector2i, b: Vector2i) -> bool:
	if _village == null or not _village.has_method("_can_step"):
		return true
	return a == b or _village._can_step(a, b)


func _first_blocked_on_segment(from: Vector2, to: Vector2) -> Vector2:
	var dist := from.distance_to(to)
	if dist < 1.0:
		return Vector2.INF
	# Half-tile stepping — fine enough that a 1-tile pillar can't slip between samples.
	var steps := int(ceil(dist / (TILE_SIZE * 0.5)))
	var last := Vector2i(int(floor(from.x / TILE_SIZE)), int(floor(from.y / TILE_SIZE)))
	for i in range(steps + 1):
		var p := from.lerp(to, float(i) / float(steps))
		var cell := Vector2i(int(floor(p.x / TILE_SIZE)), int(floor(p.y / TILE_SIZE)))
		# A legal cell reached off a ledge is still a blocked walk — tiers connect only via stairs
		if not _walkable(p) or not _step_ok(last, cell):
			return p
		last = cell
	return Vector2.INF


# ── replace_npc targets resolve against the LIVE roster ───────────────

func test_every_replace_npc_target_exists_in_the_live_village() -> void:
	# replace_npc looks the NPC up BY DISPLAY NAME at runtime. A rename in
	# HarmoniaVillage.gd doesn't break any structural test — the puppet just
	# silently stops inheriting the NPC's position and spawns on the player
	# instead, and the real NPC stays visible next to its own double.
	var live := _live_npc_names()
	var offenders: Array = []
	for path in STAGED_SCENES:
		var scene := _scene(path)
		var idx := 0
		for step in scene.get("steps", []):
			if step is Dictionary and step.get("type") == "spawn_actor":
				var target := str(step.get("replace_npc", ""))
				if target != "" and not live.has(target):
					offenders.append("%s[step %d] replace_npc '%s' — no NPC by that name in the live village" % [
						path.get_file(), idx, target])
			idx += 1
	assert_eq(offenders.size(), 0,
		"replace_npc targets must exist in HarmoniaVillage:\n  %s\n  live roster: %s" % [
			"\n  ".join(offenders), str(live.keys())])


func test_replaced_npcs_stand_on_walkable_ground() -> void:
	# The puppet inherits the live NPC's position, so if the NPC itself was
	# placed in scenery the puppet lands there too. Covers the marks that
	# DON'T appear in the JSON because they're inherited at runtime.
	var live := _live_npc_names()
	var offenders: Array = []
	for path in STAGED_SCENES:
		var scene := _scene(path)
		for step in scene.get("steps", []):
			if not (step is Dictionary) or step.get("type") != "spawn_actor":
				continue
			var target := str(step.get("replace_npc", ""))
			if target == "" or not live.has(target):
				continue
			var npc = live[target]
			if not _walkable(npc.global_position):
				offenders.append("'%s' stands at %s which is impassable — its puppet inherits that" % [
					target, npc.global_position])
	assert_eq(offenders.size(), 0,
		"replace_npc targets must themselves stand on walkable ground:\n  %s" % "\n  ".join(offenders))


# ── Camera framing ────────────────────────────────────────────────────

func test_camera_targets_show_authored_scenery() -> void:
	# WAS test_camera_targets_are_inside_the_map, which checked bounds only.
	# That was the wrong invariant and it hid a real bug: the after_cave
	# "tell me what you see" pan was in-bounds and showed a blank wall,
	# because the castle it aimed at was occluded by the tilemap (2026-07-25).
	# In-bounds does not mean there is anything to see.
	#
	# The map rect is no longer the whole authored area — CastleVista draws a
	# sky/treeline/castle band ABOVE the top edge, deliberately outside the
	# rect, so it can never be painted over. So: a target must be inside the
	# map OR inside a band some scenery node actually draws in.
	var w: int = _village.MAP_WIDTH * TILE_SIZE
	var h: int = _village.MAP_HEIGHT * TILE_SIZE
	var vista: Node2D = _village.find_child("CastleVista", true, false)
	var offenders: Array = []
	for path in STAGED_SCENES:
		var scene := _scene(path)
		var idx := 0
		for step in scene.get("steps", []):
			if step is Dictionary and step.get("type") == "camera_focus" and step.get("target") is Array:
				var t = step["target"]
				var p := Vector2(float(t[0]), float(t[1]))
				var in_map: bool = p.x >= 0 and p.y >= 0 and p.x <= w and p.y <= h
				if not (in_map or _inside_vista_band(vista, p)):
					offenders.append("%s[step %d] camera_focus %s is outside the map (0,0)-(%d,%d) AND outside any scenery band — the pan shows engine void" % [
						path.get_file(), idx, p, w, h])
			idx += 1
	assert_eq(offenders.size(), 0,
		"camera targets must land on something authored:\n  %s" % "\n  ".join(offenders))


## The CastleVista backdrop above the map's top edge — sky, ridge, treeline, castle.
func _inside_vista_band(vista: Node2D, p: Vector2) -> bool:
	if vista == null:
		return false
	var s: GDScript = load("res://src/exploration/CastleVista.gd")
	var o: Vector2 = vista.global_position
	return absf(p.x - o.x) <= s.SPAN_X * 0.5 and p.y >= o.y - s.SKY_HEIGHT and p.y <= o.y
