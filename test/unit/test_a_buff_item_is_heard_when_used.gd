extends GutTest

## A buff item made NO sound when used (2026-10-13).
##
## `play_item` looks its id up in `_item_sounds` and RETURNS EARLY when the id is unmapped.
## `_item_sounds` is derived from `_ITEM_EFFECT_SFX`, which mapped eight effect keys — none of them
## `add_buff`. So power_drink / speed_tonic / defense_tonic / magic_tonic were silent: they are shop
## stock (`VillageShop:43`), power_drink and speed_tonic are the BRAVE and QUICK starting kit, and
## they deal no damage, so unlike an attack item nothing else on the frame makes a sound either.
## The `buff` cue was authored the whole time — the ABILITY path plays exactly it, `play_battle("buff")`,
## for the same effect. An authored cue, an unreachable key, and the player's own shop stock.
##
## Evidence it is reachable, not theoretical: `ItemSystem.is_usable_in_battle` is true for every one
## (category BUFF, not META) and `ineffective_use_reason(..., in_battle = true)` returns "" for
## `add_buff` by its own arm — "In battle the buff still lands, including at full HP."
##
## ⚠️ REPORTED, NOT FIXED: `repel` (`repel_steps`) is the one other battle-usable, damage-free,
## unmapped item, so it is still silent. Not mapped here because no authored cue fits a field-only
## effect and inventing one is cowir-sfx's call, not this guard's. It is named in arm 4 so the
## number cannot drift quietly, rather than allowlisted — a guard whose correct case needs a skip
## flag is not a guard.

const ITEMS: String = "res://data/items.json"
const BUFF_ITEMS: Array[String] = ["power_drink", "speed_tonic", "defense_tonic", "magic_tonic"]

var _sm = null


func before_each() -> void:
	_sm = SoundManager
	if _sm != null:
		_sm._sfx_cooldowns.clear()


func after_each() -> void:
	if _sm != null:
		_sm._sfx_cooldowns.clear()


## Every member this file drives, so a rename reds by name instead of aborting an arm that has
## already asserted (which scores Passing, not Risky).
func test_the_members_this_file_drives_exist() -> void:
	assert_not_null(_sm, "SoundManager autoload missing")
	for m in ["play_item", "play_battle"]:
		assert_true(_sm.has_method(m), "SoundManager.%s is gone" % m)
	assert_true("_item_sounds" in _sm, "the _item_sounds map is gone")
	assert_true("_sfx_cooldowns" in _sm, "the _sfx_cooldowns seam is gone")
	assert_true(_sm._sfx_manifest.has("buff"), "the authored buff cue this maps onto is gone")
	assert_not_null(ItemSystem, "ItemSystem autoload missing")
	assert_true(ItemSystem.has_method("is_usable_in_battle"), "the usability predicate this derives from is gone")


## THE DEFECT, behaviourally: using each buff item is HEARD. A stamp in _sfx_cooldowns means the
## key was actually served — _try_play_sfx_from_manifest returns false BEFORE stamping when a key
## is absent, and the early return in play_item stamps nothing at all.
func test_each_buff_item_is_heard_when_used() -> void:
	for item_id in BUFF_ITEMS:
		_sm._sfx_cooldowns.clear()   # 80ms cooldown is per key; all four map to `buff`
		_sm.play_item(item_id)
		assert_true(_sm._sfx_cooldowns.has("buff"),
			"%s made no sound — play_item returned early on an unmapped id, and a buff item deals no damage so nothing else sounds" % item_id)


## DERIVED, not a hand-list: no battle-usable item carrying add_buff may be silent. Reds if the
## mapping is dropped, or if a new buff item arrives spelling its effect some other way.
func test_no_buff_item_is_silent() -> void:
	var corpus: Array = _battle_usable_items()
	## CORPUS FLOOR: an empty or buff-less derivation would pass this arm vacuously. Assert it
	## could have contained the defect before asserting it does not.
	assert_gt(corpus.size(), 20, "the battle-usable derivation collapsed — the arm below would pass on nothing")
	var seen: Array[String] = []
	for row in corpus:
		seen.append(str(row[0]))
	for want in BUFF_ITEMS:
		assert_true(seen.has(want), "%s is absent from the derived corpus, so this arm cannot see it" % want)
	var silent: Array[String] = []
	for row in corpus:
		var effects: Dictionary = row[1]
		if not effects.has("add_buff"):
			continue
		if str(_sm._item_sounds.get(str(row[0]), "")) == "":
			silent.append(str(row[0]))
	silent.sort()
	assert_eq(silent.size(), 0,
		"%d battle-usable buff item(s) resolve to no cue and deal no damage, so using them is silent: %s"
		% [silent.size(), ", ".join(silent)])


## The cue it maps onto must be AUTHORED — "mapped" must not mean "mapped to another miss".
func test_the_buff_items_map_onto_an_authored_cue() -> void:
	for item_id in BUFF_ITEMS:
		var cue: String = str(_sm._item_sounds.get(item_id, ""))
		assert_ne(cue, "", "%s is unmapped" % item_id)
		assert_true(_sm._sfx_manifest.has(cue),
			"%s maps to \"%s\", which is not an authored cue" % [item_id, cue])


## The REST of the silent set, named so it cannot grow quietly. `repel` is the known member and is
## reported rather than mapped; a SECOND member means something new went silent and wants a look.
func test_the_rest_of_the_silent_set_is_only_repel() -> void:
	var silent: Array[String] = []
	for row in _battle_usable_items():
		var effects: Dictionary = row[1]
		if effects.has("damage"):
			continue           # the hit path sounds for an attack item
		if str(_sm._item_sounds.get(str(row[0]), "")) != "":
			continue
		silent.append(str(row[0]))
	silent.sort()
	assert_eq(silent, ["repel"] as Array[String],
		"the silent battle-usable set changed — expected only `repel` (field-only effect, no authored cue fits it; cowir-sfx's call), got: %s" % ", ".join(silent))


## id -> effects, for every item ItemSystem will let a player use in a battle.
func _battle_usable_items() -> Array:
	var out: Array = []
	var txt: String = FileAccess.get_file_as_string(ITEMS)
	if txt == "":
		return out
	var parsed = JSON.parse_string(txt)
	if parsed == null:
		return out
	var rows = parsed["items"] if (parsed is Dictionary and parsed.has("items")) else parsed
	if not (rows is Dictionary):
		return out
	for k in rows.keys():
		var v = rows[k]
		if not (v is Dictionary):
			continue
		var effects = v.get("effects", {})
		if not (effects is Dictionary) or effects.is_empty():
			continue
		if not ItemSystem.is_usable_in_battle(str(k)):
			continue
		out.append([str(k), effects])
	return out
