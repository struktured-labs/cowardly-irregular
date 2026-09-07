extends GutTest

## Data-integrity guard (2026-07-05): every item id a cutscene grants via a
## give_item / grant_item step (the CutsceneDirector reads the "item" field) must
## resolve in items.json or equipment.json. A typo'd or renamed id passes the
## dispatch, adds a phantom entry to the party leader's inventory, and the player
## "receives" something that doesn't exist — the exact silent-failure class the
## grant_item/give_item dispatch fix (see CutsceneDirector) already rescued once.
## Cutscenes are authored by a separate content lane, so this cross-checks that
## the story data and the item/equipment registries stay in sync.

const CUTSCENE_DIR := "res://data/cutscenes/"


func _valid_item_ids() -> Dictionary:
	var valid := {}
	var items = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	if items is Dictionary:
		for k in items:
			valid[str(k)] = true
	var equip = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	if equip is Dictionary:
		for sec in ["weapons", "armors", "accessories"]:
			if equip.get(sec) is Dictionary:
				for k in equip[sec]:
					valid[str(k)] = true
	return valid


func test_all_cutscene_granted_items_resolve() -> void:
	var valid := _valid_item_ids()
	assert_gt(valid.size(), 0, "sanity: item/equipment registries loaded")

	var dir := DirAccess.open(CUTSCENE_DIR)
	assert_true(dir != null, "cutscene dir must be readable")
	var checked := 0
	var offenders: Array[String] = []
	for fname in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(CUTSCENE_DIR + fname))
		if not (data is Dictionary):
			continue
		for step in data.get("steps", []):
			if not (step is Dictionary):
				continue
			if str(step.get("type", "")) in ["give_item", "grant_item"]:
				var iid := str(step.get("item", ""))
				if iid != "":
					checked += 1
					if not valid.has(iid):
						offenders.append("%s → %s" % [fname, iid])

	assert_gt(checked, 0, "sanity: found cutscene item grants to check")
	assert_eq(offenders.size(), 0,
		"cutscene(s) grant an item id that resolves nowhere — player 'receives' a phantom: %s" % str(offenders))
