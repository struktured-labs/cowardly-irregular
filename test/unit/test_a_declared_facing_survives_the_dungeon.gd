extends GutTest

## A monster that DECLARES its facing must face the same way in a dungeon marker as in battle.
##
## `monster_faces_party(id, convention_default)` returns the declared `flip_h` when the manifest
## carries one and `convention_default` otherwise — so a declaration BYPASSES the argument.
## Both dungeon markers called it as `not monster_faces_party(id, h > 128.0)`: a DOUBLE inversion.
##
##   undeclared sheet   conv flips, then `not` flips back        -> agrees with battle
##   DECLARED sheet     conv is ignored, only the `not` applies  -> OPPOSITE of battle
##
## So the bug was invisible for 113 of 114 monsters and hit exactly the one whose facing somebody
## cared enough to declare — `cave_rat_king`, which `WhisperingCave` names as a literal. It faced
## the party correctly in battle and backwards on the cave marker.
##
## Triggers: SCOPE (nothing declares, so the behavioural arm proves nothing) ·
## INVERSION (the two call shapes disagree for a declarer — the defect itself) ·
## SHAPE (a dungeon marker goes back to the double negative).

const LOADER := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const MANIFEST := "res://data/sprite_manifest.json"
const DUNGEONS := ["res://src/maps/dungeons/WhisperingCave.gd", "res://src/maps/dungeons/DragonCave.gd"]


func _declarers() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var out: Array = []
	if parsed is Dictionary:
		var ms = (parsed as Dictionary).get("monster_sheets", {})
		if ms is Dictionary:
			for k in ms:
				var e = (ms as Dictionary)[k]
				if e is Dictionary and (e as Dictionary).has("flip_h"):
					out.append(str(k))
	out.sort()
	return out


## The floor. Every behavioural arm below reads this set; if nothing declares, they are all
## vacuously green and the defect they describe cannot occur OR be detected.
func test_the_corpus_of_declared_facings_is_not_empty() -> void:
	var d := _declarers()
	assert_gt(d.size(), 0,
		"SCOPE: no monster_sheets entry declares flip_h, so the inversion arm below proves nothing. Either the manifest lost its declarations or _declarers() no longer matches its shape.")


## The defect, as arithmetic rather than as source text: for a monster that DECLARES, the two
## call shapes return opposite answers. This is what made the old dungeon form wrong.
func test_the_two_call_shapes_disagree_for_a_declared_facing() -> void:
	var d := _declarers()
	if d.is_empty():
		return
	for mid in d:
		var battle_form: bool = LOADER.monster_faces_party(mid, false)
		var old_dungeon_form: bool = not LOADER.monster_faces_party(mid, true)
		assert_ne(battle_form, old_dungeon_form,
			"INVERSION: '%s' declares flip_h, so both call shapes should have differed — if they now agree, monster_faces_party stopped honouring the declaration and the dungeon fix is papering over a deeper change" % mid)


## An UNDECLARED monster is unaffected either way — which is exactly why this survived.
func test_an_undeclared_facing_is_unchanged_by_the_fix() -> void:
	var declared := _declarers()
	for conv in [true, false]:
		var old_form: bool = not LOADER.monster_faces_party("__no_such_monster__", not conv)
		var new_form: bool = LOADER.monster_faces_party("__no_such_monster__", conv)
		assert_eq(old_form, new_form,
			"the two shapes must agree for an undeclared sheet (conv=%s); if they diverge, the fix changes 113 monsters instead of 1" % conv)


func test_no_dungeon_marker_uses_the_double_negative() -> void:
	for path in DUNGEONS:
		var src := FileAccess.get_file_as_string(path)
		assert_gt(src.length(), 200, "SCOPE: %s is missing or empty" % path)
		assert_false(src.contains("not HybridSpriteLoader.monster_faces_party("),
			"SHAPE: %s is back to `not monster_faces_party(...)`. That cancels for the size convention and INVERTS a declared flip_h — the exact defect this file exists for." % path)
		assert_true(src.contains("HybridSpriteLoader.monster_faces_party("),
			"WIRING: %s no longer asks the loader for facing at all" % path)
		assert_false(src.contains("monster_faces_party(boss_id, tex.region.size.y > 128.0)") or src.contains("monster_faces_party(\"cave_rat_king\", tex.region.size.y > 128.0)"),
			"SHAPE: %s passes the INVERTED size test (> 128). Battle passes `<= 128`; the two must match or the convention fallback disagrees between surfaces." % path)
