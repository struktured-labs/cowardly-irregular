extends GutTest

## Spatial reachability framework (2026-07-12 — obj-detection recurred ~5x
## because every fix + test chased the interaction REACH CONSTANT, while the
## real bugs were an oversized chest collision and a door trigger buried in a
## wall. A source-pin on a number can't catch "this trigger overlaps no tile
## the player can stand on.").
##
## This loads each village for real and, for every interactable, asserts its
## trigger collision (a) overlaps at least one WALKABLE cell and (b) isn't
## oversized for a flat village. It would have failed loudly on BOTH bugs.

const TILE := 32

## All authored villages (W1-W6) — framework is village-agnostic; keep in sync
## with src/maps/villages/*.gd. Validates the interior-door fix + chest sizing
## across every village, not just W1 where the bug was reported.
const VILLAGE_SCRIPTS := [
	# W1
	"res://src/maps/villages/HarmoniaVillage.gd",
	"res://src/maps/villages/SandriftVillage.gd",
	"res://src/maps/villages/EldertreeVillage.gd",
	"res://src/maps/villages/GrimhollowVillage.gd",
	"res://src/maps/villages/IronhavenVillage.gd",
	"res://src/maps/villages/FrostholdVillage.gd",
	# W2+ (suburban / steampunk / industrial / futuristic / abstract)
	"res://src/maps/villages/MapleHeightsVillage.gd",
	"res://src/maps/villages/MapleStripMall.gd",
	"res://src/maps/villages/BrasstonVillage.gd",
	"res://src/maps/villages/ScripturaPlaza.gd",
	"res://src/maps/villages/RivetRowVillage.gd",
	"res://src/maps/villages/NodePrimeVillage.gd",
	"res://src/maps/villages/VertexVillage.gd",
]


func _first_collision(node: Node) -> CollisionShape2D:
	for c in node.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape != null:
			return c
	return null


## World-space half-extent of a collision shape (rect or circle, honoring scale).
func _half_extent(cs: CollisionShape2D) -> Vector2:
	var s := cs.shape
	if s is RectangleShape2D:
		return (s as RectangleShape2D).size * 0.5 * cs.scale.abs()
	if s is CircleShape2D:
		var r := (s as CircleShape2D).radius
		return Vector2(r * absf(cs.scale.x), r * absf(cs.scale.y))
	return Vector2.ZERO


const PLAYER_HALF := 12.0
const INTERACT_REACH := 40.0  # OverworldController._on_interaction_requested when Mode7Overlay.is_active=false

## Reachable = the player's BODY, standing centered on a walkable cell, would
## overlap the trigger. Merely touching a walkable cell's edge is NOT enough:
## the buggy library door's box touched row 5's top edge, but the player
## centered on row 5 never overlapped it → body_entered never fired. So we
## grow the trigger by the player half-extent and test walkable cell CENTERS.
func _overlaps_walkable(village, node: Node2D) -> bool:
	var cs := _first_collision(node)
	if cs == null:
		return true  # nothing to reach through — not this test's concern
	var center: Vector2 = node.global_position + cs.position
	var half := _half_extent(cs) + Vector2(PLAYER_HALF, PLAYER_HALF)
	var min_c := Vector2i(int(floor((center.x - half.x) / TILE)), int(floor((center.y - half.y) / TILE)))
	var max_c := Vector2i(int(floor((center.x + half.x) / TILE)), int(floor((center.y + half.y) / TILE)))
	for cx in range(min_c.x, max_c.x + 1):
		for cy in range(min_c.y, max_c.y + 1):
			if not village._is_cell_walkable(Vector2i(cx, cy)):
				continue
			var cc := Vector2((cx + 0.5) * TILE, (cy + 0.5) * TILE)
			if absf(cc.x - center.x) <= half.x and absf(cc.y - center.y) <= half.y:
				return true
	return false


## Reachable-via-PROBE = the player's `_on_interaction_requested` point-query
## (player_pos + facing * reach) hits the collision box from at least one
## walkable cell where they could realistically stand. This is what
## OverworldController actually runs; `_overlaps_walkable` passes when the
## body ENTERS the trigger (works for shops the player is standing INSIDE) but
## the Inn's collision box was 8px short of reach=40 from row 10 south — body
## never entered because approach was blocked by the shop sprite's implied
## wall row, and probe never hit either. Simulates all 4 facing directions.
func _reachable_via_probe(village, node: Node2D) -> bool:
	var cs := _first_collision(node)
	if cs == null:
		return true
	var center: Vector2 = node.global_position + cs.position
	var half := _half_extent(cs)
	# Scan walkable cells within (reach + half + player_half) of the box.
	var search := half + Vector2(INTERACT_REACH + PLAYER_HALF, INTERACT_REACH + PLAYER_HALF)
	var min_c := Vector2i(int(floor((center.x - search.x) / TILE)), int(floor((center.y - search.y) / TILE)))
	var max_c := Vector2i(int(floor((center.x + search.x) / TILE)), int(floor((center.y + search.y) / TILE)))
	for cx in range(min_c.x, max_c.x + 1):
		for cy in range(min_c.y, max_c.y + 1):
			if not village._is_cell_walkable(Vector2i(cx, cy)):
				continue
			var stand := Vector2((cx + 0.5) * TILE, (cy + 0.5) * TILE)
			for facing in [Vector2(0, INTERACT_REACH), Vector2(0, -INTERACT_REACH), Vector2(INTERACT_REACH, 0), Vector2(-INTERACT_REACH, 0)]:
				var probe: Vector2 = stand + facing
				if absf(probe.x - center.x) <= half.x and absf(probe.y - center.y) <= half.y:
					return true
	return false


## Auto-trigger transitions (require_interaction=false) that overlap a walkable
## cell wedged BETWEEN two other walkable cells (east-west or north-south) sit
## in a CORRIDOR — a player walking through gets auto-warped instead of just
## walking past. Village Exits at map edges are fine (adjacent cells are
## walls/edges); mid-map interior doors on a promenade are the hazard class.
func _blocks_walkable_corridor(village, node: Node2D) -> bool:
	var cs := _first_collision(node)
	if cs == null:
		return false
	var center: Vector2 = node.global_position + cs.position
	var half := _half_extent(cs)
	var min_c := Vector2i(int(floor((center.x - half.x) / TILE)), int(floor((center.y - half.y) / TILE)))
	var max_c := Vector2i(int(floor((center.x + half.x) / TILE)), int(floor((center.y + half.y) / TILE)))
	for cx in range(min_c.x, max_c.x + 1):
		for cy in range(min_c.y, max_c.y + 1):
			var here := Vector2i(cx, cy)
			if not village._is_cell_walkable(here):
				continue
			var ew: bool = village._is_cell_walkable(Vector2i(cx - 1, cy)) and village._is_cell_walkable(Vector2i(cx + 1, cy))
			var ns: bool = village._is_cell_walkable(Vector2i(cx, cy - 1)) and village._is_cell_walkable(Vector2i(cx, cy + 1))
			if ew or ns:
				return true
	return false


func test_every_village_interactable_is_reachable_and_sane() -> void:
	for path in VILLAGE_SCRIPTS:
		if not ResourceLoader.exists(path):
			continue
		var v = load(path).new()
		add_child(v)
		await get_tree().process_frame
		await get_tree().process_frame
		var vid: String = v._get_area_id() if v.has_method("_get_area_id") else path.get_file()

		# Interior doors (AreaTransitions live under `buildings`).
		if "buildings" in v and v.buildings:
			for door in v.buildings.get_children():
				if "target_map" in door:
					assert_true(_overlaps_walkable(v, door),
						"%s: door '%s' trigger overlaps NO walkable cell — buried in a wall, body_entered can't fire" % [vid, door.name])
					# Auto-warp doors in a walkable corridor eat traffic. Fine for map-edge exits; hazard mid-map.
					if not door.require_interaction:
						assert_false(_blocks_walkable_corridor(v, door),
							"%s: auto-warp door '%s' overlaps a walkable corridor cell — walking past auto-warps player away from downstream interactables" % [vid, door.name])

			# Shops + inns + village bars — have `interact()` method but do NOT
			# join the `interactables` group, so the group-fallback in
			# OverworldController misses them. Must be reachable via probe.
			for kid in v.buildings.get_children():
				if kid.has_method("interact") and kid != null and not ("target_map" in kid):
					assert_true(_reachable_via_probe(v, kid),
						"%s: interactable '%s' can't be probe-reached from any walkable cell (ui_accept press won't hit it) — collision too shallow or misaligned" % [vid, kid.name])

		# Non-door AreaTransitions live under `transitions` (forge_entrance, world portal, etc.).
		if "transitions" in v and v.transitions:
			for t in v.transitions.get_children():
				if not ("target_map" in t):
					continue
				if t.require_interaction:
					assert_true(_reachable_via_probe(v, t),
						"%s: transition '%s' (press-A) can't be probe-reached from any walkable cell" % [vid, t.name])
				else:
					# Auto-warp is BY DESIGN for village exits (walk off south → overworld) — exempt overworld-targeting exits AND transitions named "Exit". Hazard class is mid-map auto-warps on a promenade.
					var target: String = str(t.target_map) if "target_map" in t else ""
					if target == "overworld" or str(t.name) == "Exit":
						continue
					assert_false(_blocks_walkable_corridor(v, t),
						"%s: auto-warp transition '%s' (target=%s) overlaps a walkable corridor cell — walking past auto-warps the player" % [vid, t.name, target])

		# Treasure chests (self-register to group 'treasure').
		for chest in get_tree().get_nodes_in_group("treasure"):
			if not is_instance_valid(chest) or not v.is_ancestor_of(chest):
				continue
			assert_true(_overlaps_walkable(v, chest),
				"%s: chest '%s' trigger overlaps NO walkable cell" % [vid, chest.name])
			var cs := _first_collision(chest)
			if cs and cs.shape is CircleShape2D:
				var eff_r: float = (cs.shape as CircleShape2D).radius * maxf(absf(cs.scale.x), absf(cs.scale.y))
				assert_lte(eff_r, float(TILE) * 2.0,
					"%s: chest '%s' grab zone %.0fpx is a >2-tile grabber-arm in a flat village" % [vid, chest.name, eff_r])

		v.free()
		await get_tree().process_frame
