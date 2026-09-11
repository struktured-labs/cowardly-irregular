extends GutTest

## `test_overworld_secrets_are_reachable` proves no CHEST is sealed inside terrain. It says nothing
## about the door in front of it, and a HiddenPassage is the only thing that makes a chest a secret
## rather than a chest.
##
## ⛔ THE GAP. A HiddenPassage is an Area2D on layer 4 with mask 2 — it carries no terrain collision
## of its own, so it can sit anywhere at all, including the middle of a mountain, and nothing errors.
## Put one there and: the sprite draws, the "secrets" group registers it, the content radar counts
## it, `secret_<id>` never gets set because `body_entered` never fires, and the chest behind it
## passes the chest sweep because the chest is in open ground. **Every instrument in the suite
## reports a healthy secret that no player can ever discover.**
##
## 🔑 The property that matters is the same one the chest sweep asks, moved one object earlier: can a
## real body, with its real radius, occupy a point inside the trigger box. This is a physics query
## for the reason that file gives at length — the Mode 7 collider clone is displaced +140.6 px, so
## reading the shipped PNG answers a different question and disagrees with the engine in both
## directions.

const WORLDS := {
	"medieval": "res://src/exploration/OverworldScene.gd",
	"suburban": "res://src/exploration/SuburbanOverworld.gd",
	"steampunk": "res://src/exploration/SteampunkOverworld.gd",
	"industrial": "res://src/exploration/IndustrialOverworld.gd",
	"futuristic": "res://src/exploration/FuturisticOverworld.gd",
	"abstract": "res://src/exploration/AbstractOverworld.gd",
}
## OverworldPlayer's own radius plus its solver margin — the clearance a real body needs.
const BODY_RADIUS := 8.0
## A point the engine has already reported as blocked; the control the chest sweep uses.
const KNOWN_SOLID := Vector2(4 * 2 * 32 + 16, 40 * 2 * 32 + 16)


func _body_fits(space: PhysicsDirectSpaceState2D, at: Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = BODY_RADIUS
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	q.collide_with_bodies = true
	return space.intersect_shape(q, 1).is_empty()


func _trigger_half_extent(passage: Node2D) -> Vector2:
	for c in passage.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
			var cs := c as CollisionShape2D
			return ((cs.shape as RectangleShape2D).size * 0.5) * cs.scale.abs()
	return Vector2.ZERO


## Can a body stand anywhere inside the door's own trigger box?
func _touchable(space: PhysicsDirectSpaceState2D, passage: Node2D) -> bool:
	var half := _trigger_half_extent(passage)
	if half == Vector2.ZERO:
		return false
	var centre := passage.global_position
	var steps := 5
	for ix in range(steps):
		for iy in range(steps):
			var fx: float = -1.0 + 2.0 * float(ix) / float(steps - 1)
			var fy: float = -1.0 + 2.0 * float(iy) / float(steps - 1)
			if _body_fits(space, centre + Vector2(half.x * fx, half.y * fy)):
				return true
	return false


func test_every_hidden_passage_can_be_walked_into() -> void:
	var unreachable: Array = []
	var worlds_built := 0
	var probed := 0

	for label in WORLDS:
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()   # own space: every overworld sits at (0,0) otherwise
		add_child_autofree(vp)
		var w = load(WORLDS[label]).new()
		vp.add_child(w)
		await get_tree().physics_frame
		await get_tree().physics_frame
		worlds_built += 1

		var space := vp.world_2d.direct_space_state
		for n in w.get_children():
			if not (n is Node2D) or not ("passage_id" in n):
				continue
			probed += 1
			if not _touchable(space, n as Node2D):
				unreachable.append("%s/%s at %s" % [label, str(n.passage_id), str((n as Node2D).global_position)])
	unreachable.sort()

	assert_eq(worlds_built, WORLDS.size(), "built %d of %d overworlds" % [worlds_built, WORLDS.size()])
	# Pinned to the MEASURED corpus, not to a floor low enough to survive a drain: seven passages are
	# authored — W1 x2, and one each in suburban, steampunk, industrial, futuristic and abstract.
	# gte, so adding a secret is free and losing one — or a collector that stops seeing them — is not.
	assert_gte(probed, 7,
		"only %d hidden passages were probed across every overworld; 7 are authored. A collector " % probed +
		"that has gone blind looks exactly like a clean sweep from the outside.")
	assert_eq(unreachable, [],
		"a hidden passage sits where no body can reach its trigger — it draws, it registers in the " +
		"\"secrets\" group, the radar counts it, and body_entered never fires: %s" % str(unreachable))


## CONTROL for the probe itself. Without this, `_body_fits` returning true for everything would make
## every clear result above free — which is exactly how the chest sweep's first control failed.
func test_the_probe_reports_solid_rock_as_solid() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var w = load(WORLDS["medieval"]).new()
	vp.add_child(w)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := vp.world_2d.direct_space_state
	assert_false(_body_fits(space, KNOWN_SOLID),
		"CONTROL: a point the engine already reports as terrain must NOT fit a body")
	# And the paired positive: the Frozen Alcove's own cell, chosen by this same query.
	assert_true(_body_fits(space, Vector2(5 * 2 * 32 + 16, 5 * 2 * 32 + 16)),
		"CONTROL: cell (5,5) — the alcove the frozen-alcove chest sits in — must fit a body, or the " +
		"probe says no to everything and the sweep above is vacuous")
