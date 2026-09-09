extends GutTest

## A masterite drew its ENTIRE walk sheet — sixteen little soldiers standing in a 4x4 block.
##
## FOUND 2026-09-09 from a cowir-deploy store shot of Eldertree. MasteriteEncounter._build_silhouette
## assigned the artist sheet straight to a Sprite2D: `texture = load(art)`, no region. The sheets are
## 128x128 grids of sixteen 32x32 frames, so Godot drew all sixteen at once. Nothing errored. It read
## as a squad of guards drilling on the green, which is why it survived: a training-ground-looking
## thing in a village called the Training Hollow looks authored, not broken. Three people described
## it as "12 identical armed NPCs" before anyone measured it.
##
## The comment above the branch claimed "Same path convention RoamingMonster._setup_sprite consumes,
## so masterite art drops in without a code change." RoamingMonster's convention is the PATH *and*
## `region_enabled` + a region rect; only the first half was copied. Half a convention reads as the
## whole one in a diff.
##
## WHAT IS ASSERTED: the drawn rectangle, not the presence of a setter. Sheet-backed masterites must
## draw ONE frame, and the drawn figure must match its own 2x2 trigger box — a touch-triggered
## encounter where the art is smaller or larger than the hitbox is a different bug wearing this fix.

const MASTERITE := "res://src/exploration/MasteriteEncounter.gd"
const OVERWORLD_ART := "res://assets/sprites/monsters/overworld/%s.png"
const VILLAGE_DIR := "res://src/maps/villages"


## The CONSUMER corpus: every monster_id actually handed to a MasteriteEncounter. Scanned rather
## than listed so a fifth masterite is covered the day it is placed, not the day someone remembers.
func _placed_masterite_ids() -> Array:
	var ids: Array = []
	var dir := DirAccess.open(VILLAGE_DIR)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".gd"):
			var src := FileAccess.get_file_as_string("%s/%s" % [VILLAGE_DIR, f])
			if src.contains("MasteriteEncounter"):
				var rx := RegEx.new()
				rx.compile('monster_id = "([a-z_0-9]+)"')
				for m in rx.search_all(src):
					var id := m.get_string(1)
					if not (id in ids):
						ids.append(id)
		f = dir.get_next()
	ids.sort()
	return ids


func _build(monster_id: String) -> Node:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var m = load(MASTERITE).new()
	m.archetype = "probe"
	m.monster_id = monster_id
	vp.add_child(m)
	await get_tree().physics_frame
	return m


func test_every_placed_masterite_draws_a_single_frame() -> void:
	var ids := _placed_masterite_ids()
	assert_gt(ids.size(), 2, "CONTROL: only %d masterites found by scanning the villages -- the scan is broken and every count below is free" % ids.size())

	var whole_sheet: Array = []
	var checked := 0
	for id in ids:
		# A masterite with no art takes the procedural branch and has no sheet to mis-draw.
		if not FileAccess.file_exists(OVERWORLD_ART % id):
			continue
		var m = await _build(id)
		var spr = m.get_node_or_null("MasteriteSilhouette")
		assert_not_null(spr, "%s built no silhouette at all" % id)
		if spr == null:
			continue
		var sheet: Vector2 = spr.texture.get_size()
		# CONTROL: if the sheet were a single frame, a missing region would be harmless and this
		# test would pass while proving nothing about the defect.
		assert_gt(sheet.x * sheet.y, 32.0 * 32.0,
			"CONTROL: %s's sheet is %s -- one frame, so the region below is not what keeps it honest" % [id, str(sheet)])
		checked += 1
		var drawn: Vector2 = spr.get_rect().size
		if drawn.x > 32.0 or drawn.y > 32.0:
			whole_sheet.append("%s draws %s of a %s sheet" % [id, str(drawn), str(sheet)])

	assert_gt(checked, 2, "only %d masterites had art on disk -- too few to certify the class" % checked)
	assert_eq(whole_sheet, [],
		"a masterite is drawing more than one frame -- the extra frames render as a crowd of identical figures standing in the village: %s" % str(whole_sheet))


func test_the_silhouette_fills_its_own_trigger_box() -> void:
	var ids := _placed_masterite_ids()
	var mismatched: Array = []
	var checked := 0
	for id in ids:
		if not FileAccess.file_exists(OVERWORLD_ART % id):
			continue
		var m = await _build(id)
		var spr = m.get_node_or_null("MasteriteSilhouette")
		var cs = null
		for c in m.get_children():
			if c is CollisionShape2D and c.shape is RectangleShape2D:
				cs = c
		assert_not_null(cs, "%s has no trigger box" % id)
		if spr == null or cs == null:
			continue
		checked += 1
		var drawn: Vector2 = spr.get_rect().size * spr.scale
		var box: Vector2 = (cs.shape as RectangleShape2D).size
		if not drawn.is_equal_approx(box):
			mismatched.append("%s draws %s inside a %s trigger" % [id, str(drawn), str(box)])

	assert_gt(checked, 2, "only %d masterites measured" % checked)
	assert_eq(mismatched, [],
		"a touch-triggered encounter whose art and hitbox disagree fires early or late for reasons the player cannot see: %s" % str(mismatched))


func test_the_probe_can_tell_the_two_branches_apart() -> void:
	# Without art the procedural silhouette is built instead, and it must NOT claim a region --
	# otherwise the assertions above would pass on a masterite that never loaded a sheet at all.
	var m = await _build("zzz_no_such_masterite")
	var spr = m.get_node_or_null("MasteriteSilhouette")
	assert_not_null(spr, "CONTROL: the procedural fallback must still build a silhouette")
	if spr != null:
		assert_false(spr.region_enabled,
			"CONTROL: the procedural branch draws a whole generated image; if it reports a region the probe cannot distinguish the branches")
