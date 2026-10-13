extends GutTest

## The shop and the equipment screen print an item's description next to its stat block, so a
## description that names the wrong stat sells the player the wrong thing.
##
## `mp_amulet` said "Boosts maximum magic" and granted `max_mp: 30` — no `magic` at all. The two
## sit side by side in the accessory list with `magic_ring`, which says "Enhances magical power"
## and DOES grant `magic: 100`. Nearly the same words, completely different stats, adjacent rows.
## The catalog's own convention everywhere else is "MP" (abilities.json "restores 5% max MP",
## passives.json "+30% max MP"); this was the only entry calling it "magic".
##
## 🛑 READS THE FILE, NOT `EquipmentSystem`. The autoload falls back to a hardcoded table when
## equipment.json cannot be loaded, so asserting against the autoload would compare the fallback
## with itself on exactly the broken tree this is meant to catch. The file is the authored source.

const EQUIPMENT_PATH := "res://data/equipment.json"

## Phrase -> stat, MOST SPECIFIC FIRST. A matched phrase is CONSUMED before the next is tried, or
## "magical defense" also reads as a bare "magic" claim and barrier_ring — which grants
## magic_defense and no magic — reports as a liar.
##
## ⚠️ Bare "magic"/"magical" is deliberately NOT a trigger: "a faint magical barrier" and "a magic
## crystal" are flavour, not claims. Including them produced one false positive and one
## COINCIDENTAL pass, which is worse — the arm would have been agreeing with text that happens to
## sit beside the right number.
const CLAIM_ORDER := [
	["magical defence", "magic_defense"], ["magical defense", "magic_defense"],
	["magic defense", "magic_defense"], ["magic resistance", "magic_defense"],
	["maximum mp", "max_mp"], ["max mp", "max_mp"],
	["maximum health", "max_hp"], ["max hp", "max_hp"],
	["magical power", "magic"], ["magic power", "magic"], ["magical damage", "magic"],
	["attack", "attack"],
	["protection", "defense"], ["defence", "defense"], ["defense", "defense"], ["armor", "defense"],
	["speed", "speed"],
]


var _cache: Dictionary = {}


## Every authored entry, flattened across weapons/armors/accessories. Cached: the arms below walk
## it in a loop and a re-read per entry re-parses the whole catalog 46 times.
func _entries() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var raw := FileAccess.get_file_as_string(EQUIPMENT_PATH)
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {}
	var out := {}
	for group in parsed:
		var entries = parsed[group]
		if not (entries is Dictionary):
			continue
		for id in entries:
			if entries[id] is Dictionary:
				out[str(id)] = entries[id]
	_cache = out
	return out


func _mods(entry: Dictionary) -> Dictionary:
	var m = entry.get("stat_mods", {})
	return m if m is Dictionary else {}


## CONTROL: the reader must actually parse the catalog. Without this every arm below iterates an
## empty dictionary and passes having checked nothing — the wrong-shape zero.
func test_the_catalog_reader_finds_real_equipment() -> void:
	var e := _entries()
	assert_gt(e.size(), 30, "CONTROL: equipment.json must yield entries, got %d" % e.size())
	assert_true(e.has("mp_amulet"), "CONTROL: the entry this file exists for must be present")
	assert_true(e.has("magic_ring"), "CONTROL: and its lookalike neighbour")
	assert_eq(int(_mods(e["magic_ring"]).get("magic", 0)), 100,
		"CONTROL: a known value, so a reader returning junk is caught")


## THE REGRESSION: "magic" used as the word for MP. They are separate stats and the screen shows
## both, so borrowing one name for the other is not loose phrasing — it names a stat the item does
## not touch.
func test_no_description_calls_mp_magic() -> void:
	var liars: Array[String] = []
	var applies := 0
	var all := _entries()
	for id in all:
		var entry: Dictionary = all[id]
		var text: String = str(entry.get("description", "")).to_lower()
		var mods := _mods(entry)
		if not text.contains("magic") or int(mods.get("max_mp", 0)) == 0:
			continue
		applies += 1
		if int(mods.get("magic", 0)) == 0:
			liars.append("%s: '%s' grants max_mp=%s and magic=0"
				% [id, str(entry.get("description", "")), str(mods.get("max_mp", 0))])
	assert_gt(applies, 1,
		"CONTROL: this arm must reach real entries — only %d say 'magic' AND grant max_mp, so it "
		% applies + "is not discriminating anything")
	assert_eq(liars, [] as Array[String],
		"an equipment description calls MP 'magic' — the player reads it beside a stat block that "
		+ "shows MAG unchanged: %s" % [", ".join(liars)])


## And the general form: a description that names a stat must grant that stat.
func test_every_stat_a_description_names_is_actually_granted() -> void:
	var liars: Array[String] = []
	var claims := 0
	var all := _entries()
	for id in all:
		var entry: Dictionary = all[id]
		var text: String = str(entry.get("description", "")).to_lower()
		var mods := _mods(entry)
		for pair in CLAIM_ORDER:
			var phrase: String = pair[0]
			var stat: String = pair[1]
			if not text.contains(phrase):
				continue
			text = text.replace(phrase, "")  # consumed, so a general word cannot re-match it
			claims += 1
			if int(mods.get(stat, 0)) == 0:
				liars.append("%s claims '%s' but grants no %s (%s)"
					% [id, phrase, stat, JSON.stringify(mods)])
	assert_gt(claims, 8,
		"CONTROL: CLAIM_ORDER must still match real descriptions — only %d matched, so a reworded "
		% claims + "catalog has made this arm blind")
	assert_eq(liars, [] as Array[String],
		"an equipment description names a stat the item does not grant: %s" % [", ".join(liars)])
