extends GutTest

## The unit suite tested the emitter's LOGIC; nothing had ever built one in a real village,
## where _ready() constructs a sprite, a collision shape and a label.

const VILLAGES := {
	"Sandrift": "res://src/maps/villages/SandriftVillage.gd",
	"Frosthold": "res://src/maps/villages/FrostholdVillage.gd",
	"Grimhollow": "res://src/maps/villages/GrimhollowVillage.gd",
	"Ironhaven": "res://src/maps/villages/IronhavenVillage.gd",
	"Eldertree": "res://src/maps/villages/EldertreeVillage.gd",
	"Brasston": "res://src/maps/villages/BrasstonVillage.gd",
}

## Emitters authored per village — the count each _setup_npcs places.
## Sandrift is 0 BY DESIGN: its only step-2 emitter is the Warden encounter, so the
## examine point that stood in for it was deleted once the encounter learned to notify.
const EXPECTED := {
	"Sandrift": 0, "Frosthold": 1, "Grimhollow": 1, "Ironhaven": 1, "Eldertree": 1,
	"Brasston": 2,
}


func _examine_points(node: Node) -> Array:
	var out: Array = []
	for n in node.find_children("*", "", true, false):
		var s = n.get_script()
		if s != null and str(s.resource_path).ends_with("QuestExaminePoint.gd"):
			out.append(n)
	return out


func test_every_authored_examine_point_builds_in_its_village() -> void:
	var built := {}
	var incomplete: Array = []
	for vname in VILLAGES:
		var scr = load(VILLAGES[vname])
		assert_not_null(scr, "%s script must load" % vname)
		if scr == null:
			continue
		var village = scr.new()
		add_child_autofree(village)
		await get_tree().process_frame

		var points := _examine_points(village)
		built[vname] = points.size()
		for p in points:
			## _ready builds these three; a construction failure leaves the node bare but present.
			if p.get_node_or_null("ExamineGlyph") == null:
				incomplete.append("%s: %s has no sprite" % [vname, p.flag])
			elif p.get_child_count() < 3:
				incomplete.append("%s: %s built %d children, expected sprite+collision+label"
					% [vname, p.flag, p.get_child_count()])
		village.queue_free()
		await get_tree().process_frame

	assert_eq(built, EXPECTED, "each village must instantiate its authored emitters. A quest step "
		+ "whose emitter never spawns is unadvanceable in play even though the data joins cleanly")
	assert_eq(incomplete, [], "an emitter spawned but did not finish _ready — it would render "
		+ "nothing and swallow the interact, stranding the quest: %s" % [incomplete])
