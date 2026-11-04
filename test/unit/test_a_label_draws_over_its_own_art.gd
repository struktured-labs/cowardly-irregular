extends GutTest
## struktured 2026-11-01 (via cowir-main 20977): "Harmony Fountain" was hidden under the fountain's canopy.
## These props y-sort their own children, so a label placed ABOVE the art (smaller y) sorts BEHIND it.

const SUBJECTS := [
	"res://src/exploration/VillageFountain.gd",
	"res://src/exploration/VillageShop.gd",
	"res://src/exploration/VillageInn.gd",
	"res://src/exploration/VillageBar.gd",
]


## Draw order inside one parent: z first, then (when y-sorted) the sort y, then tree order.
func _drawn_after(a: CanvasItem, b: CanvasItem) -> bool:
	if a.z_index != b.z_index:
		return a.z_index > b.z_index
	var parent := a.get_parent() as Node2D
	if parent != null and parent.y_sort_enabled:
		var ay: float = (a as Node2D).position.y if a is Node2D else (a as Control).position.y
		var by: float = (b as Node2D).position.y if b is Node2D else (b as Control).position.y
		if ay != by:
			return ay > by
	return a.get_index() > b.get_index()


func test_every_label_draws_over_its_own_art() -> void:
	var checked := 0
	for path in SUBJECTS:
		var node: Node2D = load(path).new()
		add_child_autofree(node)
		await get_tree().process_frame
		var art: Sprite2D = node.get("sprite")
		assert_not_null(art, "%s has no sprite to draw over" % path)
		if art == null:
			continue
		for kid in node.get_children():
			if kid is Label:
				checked += 1
				assert_true(_drawn_after(kid, art), "%s: label '%s' sorts under its own art" % [path.get_file(), (kid as Label).text])
	## Floor: one name label per subject (the bar adds a second), so a lost label cannot pass this vacuously.
	assert_gte(checked, SUBJECTS.size(), "found %d labels across %d props" % [checked, SUBJECTS.size()])


## Control for the order rule itself: unraised, the fountain's label (y -50) sorts under its art (y +48).
func test_an_unraised_label_would_sort_under_the_art() -> void:
	var node: Node2D = load(SUBJECTS[0]).new()
	add_child_autofree(node)
	await get_tree().process_frame
	var label: Label = node.get("name_label")
	label.z_index = 0
	assert_false(_drawn_after(label, node.get("sprite")), "the rule must red the label the canopy used to hide")
