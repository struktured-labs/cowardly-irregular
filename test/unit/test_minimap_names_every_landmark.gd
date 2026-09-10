extends GutTest

## Five of the six overworld minimaps had ZERO named markers.
##
## OverworldMinimap.SHORT_NAMES was entirely W1 keys, and every other world drew its villages,
## portals and landmarks as anonymous coloured squares — Maple Heights, Brasston, Rivet Row, Node
## Prime and Vertex included. The labelling feature worked the whole time; it was simply never
## extended past the world it was written in. Found 2026-09-10 by cropping the minimap out of a
## rendered frame, because a dot with no name looks exactly like a dot.
##
## ⚠️ THE FIX INTRODUCED A NEW FAILURE MODE AND THIS TEST IS THE PRICE OF IT. The minimap now SKIPS
## keys it cannot name, so the anonymous dots beside every dragon cave (arrival points, not places)
## are gone. That trades a visible wrong dot for an INVISIBLE MISSING one: a POI added without a
## label no longer shows up at all. So the guard is not optional decoration on the change, it is what
## makes the change safe.
##
## POI-ness is DERIVED, not listed: a spawn point that some transition or objective READS is a place
## the player travels to; one that is only WRITTEN is where he lands coming back. That distinction
## comes from the code rather than from the key's name, which matters because `suburban_portal` reads
## like a destination and is an arrival point, while `the_question` reads like neither and is a POI.

const MINIMAP := "res://src/exploration/OverworldMinimap.gd"
const WORLDS := {
	"medieval": "res://src/exploration/OverworldScene.gd",
	"suburban": "res://src/exploration/SuburbanOverworld.gd",
	"steampunk": "res://src/exploration/SteampunkOverworld.gd",
	"industrial": "res://src/exploration/IndustrialOverworld.gd",
	"futuristic": "res://src/exploration/FuturisticOverworld.gd",
	"abstract": "res://src/exploration/AbstractOverworld.gd",
}
## Read by the scene for its own bookkeeping, never a marker.
const NOT_LANDMARKS := ["default", "entrance"]


func _keys_read_and_written(src: String) -> Array:
	var writes := {}
	var reads := {}
	var rx_w := RegEx.new()
	rx_w.compile("spawn_points\\[\\s*\"([a-z0-9_]+)\"\\s*\\]\\s*=")
	for m in rx_w.search_all(src):
		writes[m.get_string(1)] = true
	var rx_g := RegEx.new()
	rx_g.compile("spawn_points\\.get\\(\\s*\"([a-z0-9_]+)\"")
	for m in rx_g.search_all(src):
		reads[m.get_string(1)] = true
	var rx_i := RegEx.new()
	rx_i.compile("spawn_points\\[\\s*\"([a-z0-9_]+)\"\\s*\\](?!\\s*=)")
	for m in rx_i.search_all(src):
		reads[m.get_string(1)] = true
	return [writes, reads]


func test_every_landmark_a_world_travels_to_has_a_name() -> void:
	var names: Dictionary = load(MINIMAP).SHORT_NAMES
	assert_gt(names.size(), 15, "CONTROL: only %d short names loaded" % names.size())

	var nameless: Array = []
	var worlds_scanned := 0
	var pois_seen := 0
	for label in WORLDS:
		var src := FileAccess.get_file_as_string(WORLDS[label])
		assert_gt(src.length(), 500, "CONTROL: %s read as %d chars" % [label, src.length()])
		var pair := _keys_read_and_written(src)
		var writes: Dictionary = pair[0]
		var reads: Dictionary = pair[1]
		assert_gt(writes.size(), 2, "CONTROL: %s declares only %d spawn points -- the scan is broken" % [label, writes.size()])
		worlds_scanned += 1
		for k in writes:
			if k in NOT_LANDMARKS or not reads.has(k):
				continue
			pois_seen += 1
			if not names.has(k):
				nameless.append("%s/%s" % [label, k])
	nameless.sort()

	assert_eq(worlds_scanned, WORLDS.size(), "scanned %d of %d worlds" % [worlds_scanned, WORLDS.size()])
	assert_gt(pois_seen, 20, "CONTROL: only %d landmarks found across six worlds -- any zero below is free" % pois_seen)
	assert_eq(nameless, [],
		"a landmark the player travels to has no minimap name, and the minimap now SKIPS what it cannot name, so it does not appear on the map at all: %s" % str(nameless))


func test_the_scan_can_tell_a_landmark_from_an_arrival_point() -> void:
	# CONTROL: suburban_portal is written by W1 and never read there — an arrival point that reads
	# like a destination. If the discriminator ever calls it a landmark, the sweep above is measuring
	# key names rather than use.
	var src := FileAccess.get_file_as_string(WORLDS["medieval"])
	var pair := _keys_read_and_written(src)
	assert_true((pair[0] as Dictionary).has("suburban_portal"), "CONTROL: W1 must declare suburban_portal")
	assert_false((pair[1] as Dictionary).has("suburban_portal"), "CONTROL: W1 must never READ suburban_portal; if it does, this control is stale rather than the code being wrong")
	assert_true((pair[1] as Dictionary).has("cave_entrance"), "CONTROL: a real landmark must read as READ")


## A name sitting on top of a marker is as unreadable as two names on top of each other — and the
## marker is the thing the name belongs to. W4 shipped with "Rivet" underneath the gold objective
## dot, because labels were placed in the same pass that drew the dots (so a label could not avoid a
## marker that did not exist yet) and the objective marker is added later still.
func test_no_minimap_label_sits_on_a_marker() -> void:
	var overlaps: Array = []
	var worlds_built := 0
	var labels_seen := 0
	var markers_seen := 0

	for label in WORLDS:
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var w = load(WORLDS[label]).new()
		vp.add_child(w)
		await get_tree().physics_frame
		await get_tree().process_frame
		var mm = w.get("_minimap")
		if mm == null:
			continue
		worlds_built += 1
		var rects: Array = mm.get("_label_rects")
		var markers: Array = mm.get("_marker_rects")
		var texts: Array = mm.get("_labels")
		labels_seen += rects.size()
		markers_seen += markers.size()
		var obj = mm.get("_objective_dot")
		var all_markers: Array = markers.duplicate()
		if obj != null:
			all_markers.append(Rect2(obj.position, obj.size))
		for i in range(rects.size()):
			for m in all_markers:
				if (rects[i] as Rect2).intersects(m):
					var t: String = str(texts[i].text) if i < texts.size() else "?"
					overlaps.append("%s/%s" % [label, t])
	overlaps.sort()

	assert_eq(worlds_built, WORLDS.size(), "built %d of %d minimaps" % [worlds_built, WORLDS.size()])
	assert_gt(labels_seen, 15, "CONTROL: only %d labels placed across six worlds -- any zero below is free" % labels_seen)
	assert_gt(markers_seen, 15, "CONTROL: only %d markers reserved -- the overlap test has nothing to hit" % markers_seen)
	assert_eq(overlaps, [], "a minimap name is drawn on top of a marker: %s" % str(overlaps))
