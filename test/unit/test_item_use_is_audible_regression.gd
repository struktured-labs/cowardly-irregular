extends GutTest

## Regression: USING AN ITEM MADE NO SOUND (2026-09-09).
##
## BattleScene's "item" arm called animator.play_item() and nothing else, so the only audio was
## whatever the EFFECT happened to emit. healing_done reaches `heal`, so HP potions sounded — and
## that masked the rest, because the item a player uses first is a Potion:
##
##   ether / hi_ether / mega_ether  SILENT. struktured ruled 2026-09-07 that MP gains get their own
##                                  popup and never healing_done's green, so nothing fired at all.
##   antidote / eye_drops / ...     SILENT. cure_status emits nothing audible.
##   smoke bomb (escape_battle)     SILENT.
##   phoenix down (revive)          played the generic `heal` cue, not the revival cue.

const EFFECT_CUE: Dictionary = {
	"revive": "ability_revive",
	"escape_battle": "ability_flee",
	"cure_status": "status_cured",
	"cure_all_status": "status_cured",
	"heal_mp": "ability_mp_restore",
	"heal_mp_percent": "ability_mp_restore",
	## Added after the first version of this file EXCLUDED these on a false premise — see
	## test_potions_are_audible_in_battle. Without them the sweep could not see the most common
	## item in the game, and only the named assert caught the regression.
	"heal_hp": "heal",
	"heal_hp_percent": "heal",
}


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _items() -> Dictionary:
	var text: String = FileAccess.get_file_as_string("res://data/items.json")
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var i: Variant = parsed.get("items", parsed)
	return i if i is Dictionary else {}


func test_derivation_ran() -> void:
	## PREMISE. Every assert below is vacuous if the derived pass no-op'd.
	var sm: Node = _sm()
	assert_not_null(sm, "SoundManager autoload must exist")
	assert_gt(sm._item_sounds.size(), 0,
		"PREMISE BROKEN: _item_sounds is empty — _derive_item_sounds_from_data() did not run, or ran before _load_sfx_manifest() so its manifest gate rejected everything. Nothing below means anything until it does.")


func test_every_item_with_an_audible_effect_resolves() -> void:
	## THE LOAD-BEARING GUARD. Derived from items.json, so a new ether or antidote is covered when
	## it is authored rather than when someone notices the silence.
	var sm: Node = _sm()
	var items: Dictionary = _items()
	assert_gt(items.size(), 50, "control: items.json parsed to %d entries — the sweep is broken" % items.size())

	var checked: int = 0
	var silent: Array[String] = []
	for iid in items.keys():
		var entry: Variant = items[iid]
		if not (entry is Dictionary):
			continue
		var effects: Variant = (entry as Dictionary).get("effects", {})
		if not (effects is Dictionary):
			continue
		for eff in EFFECT_CUE.keys():
			if not (effects as Dictionary).has(eff):
				continue
			checked += 1
			if str(sm._item_sounds.get(str(iid), "")) == "":
				silent.append("%s (%s)" % [iid, eff])
			break
	assert_gte(checked, 8,
		"control: only %d items carried an audible effect — the incident had at least 8 (3 ethers, 4 cures, revive, escape)" % checked)
	assert_eq(silent.size(), 0,
		"%d item(s) with an audible effect still play nothing when used: %s" % [silent.size(), silent])


func test_named_items_reach_the_right_cue() -> void:
	## Named, not counted — the sweep passes if items.json loses these rows.
	var sm: Node = _sm()
	var items: Dictionary = _items()
	for iid in ["ether", "hi_ether"]:
		if not items.has(iid):
			continue
		assert_eq(str(sm._item_sounds.get(iid, "")), "ability_mp_restore",
			"%s restores MP — it must not be silent" % iid)
	## And an MP item must NOT borrow the HP cue: struktured separated those popups deliberately.
	for iid in ["ether", "hi_ether"]:
		if not items.has(iid):
			continue
		assert_ne(str(sm._item_sounds.get(iid, "")), "heal",
			"%s must not reuse the HP-heal cue — the popups were separated on purpose, the audio should agree" % iid)


func test_potions_are_audible_in_battle() -> void:
	## ⛔ THIS ASSERTION USED TO SAY THE OPPOSITE, and it was wrong. It excluded potions on the
	## reasoning "healing_done already plays `heal`". _on_healing_done is FOUR lines and plays
	## nothing — the probe that "verified" it used a fixed 12-line window from the func header and
	## ran into the NEXT function, reading _on_ap_granted's cue as this one's. So the guard pinned
	## the silence it was written to prevent.
	##
	## Discriminator, and the reason the shape is worth remembering: a fixed-size window around a
	## symbol is not a scope. Bound the read at the next `func`, or count CALLERS of the cue.
	var sm: Node = _sm()
	var items: Dictionary = _items()
	assert_true(items.has("potion"), "control: potion must exist or this control is vacuous")
	var eff: Variant = (items.get("potion", {}) as Dictionary).get("effects", {})
	assert_true((eff as Dictionary).has("heal_hp"), "control: potion must still be a heal_hp item")
	assert_eq(str(sm._item_sounds.get("potion", "")), "heal",
		"the most-used item in the game is SILENT in battle — _on_healing_done plays nothing")


func test_healing_done_still_plays_nothing_so_this_cannot_double_fire() -> void:
	## The premise the mapping above depends on, asserted rather than assumed this time. If someone
	## gives _on_healing_done a cue, potions fire TWICE and this reds instead of going quietly loud.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_ne(src, "", "BattleScene.gd unreadable — this guard would pass vacuously")
	var i := src.find("func _on_healing_done(")
	assert_gt(i, -1, "control: _on_healing_done not found — the scope below is meaningless")
	var j := src.find("\nfunc ", i + 1)
	var body := src.substr(i, (j - i) if j > i else 200)
	assert_false(body.contains("SoundManager."),
		"_on_healing_done now plays a cue — potions would fire twice, once from it and once from the item map")


func test_the_call_site_exists() -> void:
	## Every assert above reads _item_sounds directly — they prove the MAP is built, never that
	## anything plays it. The map was not the bug; the missing call was.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_ne(src, "", "BattleScene.gd unreadable — this guard would pass vacuously")
	assert_true(src.contains("SoundManager.play_item("),
		"BattleScene no longer calls SoundManager.play_item — the item arm is silent again, and every other assert in this file stays green")
