extends GutTest

## A derived roamer went STALE when its battle idle moved. tools/derive_overworld_roamer_sheets.py cuts each overworld
## sheet from the battle idle frames and never revisits it, so when the Cursed Armor's idle moved off a crouch the field
## still showed the crouch, and when 16 legacy monsters' idles moved off a slash arc the field still showed the arc.
## The tool now records, on the roamer's overworld_monster_sheets entry, WHICH idle it was cut from; that record must
## still equal the battle sheet's idle. A pixel comparison was tried first and could not separate fresh from stale:
## re-deriving in-engine (BILINEAR or TRILINEAR) scored correct roamers 0.52-0.95 against the tool's BOX filter.

## Roamers derived by the tool as of 2026-10-14; the floor keeps an emptied record from passing.
const MIN_DERIVED := 20


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))


func stale_reason(id: String, field: Dictionary, battle: Dictionary) -> String:
	## "" when the roamer's recorded source idle is the battle sheet's current idle; otherwise why not.
	var rec = field.get("derived_from_idle", null)
	if not (rec is Dictionary):
		return ""
	var idle = battle.get("animations", {}).get("idle", null)
	if not (idle is Dictionary):
		return "%s: roamer was derived from a battle idle, and the battle sheet no longer declares one" % id
	var now := [int(idle.get("start", 0)), int(idle.get("end", idle.get("start", 0)))]
	var was := [int(rec.get("start", -1)), int(rec.get("end", -1))]
	if now != was:
		return "%s: roamer cut from battle idle %s but the battle idle is now %s" % [id, str(was), str(now)]
	return ""


func test_every_derived_roamer_is_cut_from_its_current_battle_idle() -> void:
	var m := _manifest()
	var battle: Dictionary = m.get("monster_sheets", {})
	var field: Dictionary = m.get("overworld_monster_sheets", {})
	var derived := 0
	var stale: Array = []
	for id in field:
		var f: Dictionary = field[id]
		if not f.has("derived_from_idle"):
			continue
		derived += 1
		assert_true(FileAccess.file_exists("res://assets/sprites/monsters/overworld/%s.png" % id), "%s: derived roamer sheet exists" % id)
		var why := stale_reason(str(id), f, battle.get(id, {}))
		if why != "":
			stale.append(why)
	assert_true(derived >= MIN_DERIVED,"CONTROL: the derived roamers carry their provenance (%d)" % derived)
	assert_eq(stale, [], "roamers showing an idle their monster no longer uses (re-derive with --refresh <id>): %s" % str(stale))


func test_the_check_sees_a_moved_idle() -> void:
	var field := {"derived_from_idle": {"start": 0, "end": 1}}
	assert_eq(stale_reason("x", field, {"animations": {"idle": {"start": 0, "end": 1}}}), "", "same idle is fresh")
	assert_ne(stale_reason("x", field, {"animations": {"idle": {"start": 3, "end": 4}}}), "", "a moved idle is stale")
	assert_ne(stale_reason("x", field, {"animations": {"idle": {"start": 0, "end": 0}}}), "", "a shortened idle is stale")
	assert_ne(stale_reason("x", field, {"animations": {}}), "", "a vanished idle is stale")
	assert_eq(stale_reason("x", {}, {"animations": {"idle": {"start": 3, "end": 4}}}), "", "a hand-drawn roamer is not judged")
