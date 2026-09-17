extends GutTest

## `MasteriteEncounter._build_silhouette` cuts the FRONT-facing frame by asking the manifest which
## row `walk_down` sits on. Row 0 used to be hardcoded there; the file's own comment says a sheet
## declaring walk_down elsewhere "would show the masterite from BEHIND, with nothing failing".
##
## ⛔ NOTHING COULD FAIL, AND NOT BY OVERSIGHT: all 53 declared overworld sheets put walk_down on
## row 0 — the SAME value as the fallback — so on the shipped corpus a hardcoded 0 and a real read
## are indistinguishable. No arm over real data can separate them. Until now this consumer was held
## only by a file-scoped source ledger, which a call whose answer is discarded satisfies.
##
## 🔑 SO THE ARM SUPPLIES THE COUNTEREXAMPLE THE CORPUS DOES NOT HAVE: it declares walk_down on a
## row that is not 0 and asks where the sprite actually cut. That is the magnitude that LANDS
## rather than the presence of a lookup (cowir-autogrind's distinction, 2026-09-17).
const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const MasteriteScript := preload("res://src/exploration/MasteriteEncounter.gd")
const DONOR := "slime"


func after_each() -> void:
	Loader._manifest_loaded = false
	Loader._load_manifest()


func _silhouette_region(walk_down_row: int) -> Rect2:
	Loader._load_manifest()
	var entry: Dictionary = (Loader._overworld_monster_sheets[DONOR] as Dictionary).duplicate(true)
	((entry["animations"] as Dictionary)["walk_down"] as Dictionary)["row"] = walk_down_row
	Loader._overworld_monster_sheets[DONOR] = entry

	var trig := MasteriteScript.new()
	trig.monster_id = DONOR
	trig.archetype = "test_archetype"
	trig.display_name = "Test Masterite"
	add_child_autofree(trig)

	var art := trig.get_node_or_null("MasteriteSilhouette")
	if art == null or not (art is Sprite2D):
		return Rect2(-1, -1, -1, -1)
	if not (art as Sprite2D).region_enabled:
		return Rect2(-2, -2, -2, -2)
	return (art as Sprite2D).region_rect


func test_the_front_frame_is_cut_at_the_row_the_sheet_declares() -> void:
	var shipped := _silhouette_region(0)
	assert_eq(shipped, Rect2(0, 0, 32, 32),
		("CONTROL: with the SHIPPED declaration the masterite must cut the artist sheet at row 0. "
		+ "A (-1,-1) means no silhouette was built (procedural fallback, so nothing below is about "
		+ "the artist path); a (-2,-2) means the sprite drew the whole sheet unregioned"))

	var moved := _silhouette_region(2)
	assert_eq(moved, Rect2(0, 64, 32, 32),
		("a sheet declaring walk_down on row 2 must cut at y = 2 x 32. Hardcoding row 0 — or calling "
		+ "the owner and discarding its answer — passes on every shipped sheet, because all 53 "
		+ "declared sheets put walk_down on row 0. This is the counterexample the corpus lacks"))


## The static section is shared: a leaked probe would reach every later test in the process.
func test_the_probe_does_not_outlive_the_arm() -> void:
	Loader._load_manifest()
	var row: int = int((((Loader._overworld_monster_sheets[DONOR] as Dictionary)["animations"]
		as Dictionary)["walk_down"] as Dictionary)["row"])
	assert_eq(row, 0,
		"the donor's declared walk_down row must be back to what the manifest ships, not a probe value")
