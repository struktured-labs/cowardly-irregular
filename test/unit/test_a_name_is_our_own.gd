extends GutTest

## struktured via cowir-main 2026-11-01: summons, spell tiers and items must not wear Final Fantasy's names.
## Ids stay (saves, scripts, voice keys); only what a player READS is ours. Ratchets on 0 borrowed display names.

const ABILITIES := "res://data/abilities.json"
const ITEMS := "res://data/items.json"
const PROSE := ["res://data/abilities.json", "res://data/items.json", "res://data/lore.json", "res://data/autobattle_rule_templates.json"]

## FF spell tiers (Fira, Blizzaga, Curaja...): a classic stem plus a tier suffix. The bare words (Fire, Cure) are ours to use.
const SPELL_TIER := "(?i)\\b(fir|blizz|thund|cur|aer|wat|quak)(a|ra|ara|ga|aga|ja|aja)\\b"
## FF's item ladder (Hi-Potion, X-Potion, Mega Ether) and Megalixir.
const ITEM_LADDER := "(?i)^(hi|x|mega)[- ]|megalixir"
## Names that are FF's alone and must not appear in any player-facing prose.
## Bravely Default's battle terms; ours are Advance / Defer / AP (struktured: "should be Advance/Defer"). Case-sensitive, so prose "default" passes.
const BRAVE_DEFAULT := "\\b(BP|Brave|Default|Defaulting|Defaulted)\\b"
const BATTLE_TEXT := ["res://data/jobs.json", "res://data/abilities.json", "res://data/passives.json"]
const BORROWED := "(?i)\\b(ifrit|shiva|ramuh|bahamut|eidolons?|judgment bolt|mega flare|phoenix down)\\b"


func _table(path: String, key: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var table = data.get(key, data)
	var out := {}
	if table is Dictionary:
		out = table
	elif table is Array:
		for row in table:
			out[str(row.get("id", ""))] = row
	return out


func _matches(pattern: String, text: String) -> bool:
	var re := RegEx.new()
	re.compile(pattern)
	return re.search(text) != null


func test_the_patterns_see_the_names_they_forbid() -> void:
	for n in ["Fira", "Blizzaga", "Thundara", "Curaja"]:
		assert_true(_matches(SPELL_TIER, n), "CONTROL: the spell-tier pattern must catch '%s'" % n)
	for n in ["Fire", "Blizzard", "Thunder", "Cure", "Water", "Ignis Maximus"]:
		assert_false(_matches(SPELL_TIER, n), "the spell-tier pattern must leave '%s' alone" % n)
	for n in ["Hi-Potion", "X-Potion", "Mega Potion", "Hi-Ether", "Mega Ether", "Megalixir"]:
		assert_true(_matches(ITEM_LADDER, n), "CONTROL: the item-ladder pattern must catch '%s'" % n)
	for n in ["Potion", "Ether", "Elixir", "Remedy", "Potio Maior", "Elixir Communis"]:
		assert_false(_matches(ITEM_LADDER, n), "the item-ladder pattern must leave '%s' alone" % n)
	assert_true(_matches(BORROWED, "Summon the dragon king Bahamut"), "CONTROL: the borrowed-name pattern must catch Bahamut")
	for n in ["Brave/Default BP stacking", "banking 1 BP", "when Defaulting", "Default"]:
		assert_true(_matches(BRAVE_DEFAULT, n), "CONTROL: the Brave/Default pattern must catch '%s'" % n)
	for n in ["by default", "Defer", "Advance", "AP Recovery", "bravely"]:
		assert_false(_matches(BRAVE_DEFAULT, n), "the Brave/Default pattern must leave '%s' alone" % n)


func test_no_ability_wears_a_borrowed_name() -> void:
	var abilities := _table(ABILITIES, "abilities")
	assert_gt(abilities.size(), 100, "CONTROL: abilities.json must load")
	for id in abilities:
		var name := str(abilities[id].get("name", ""))
		assert_false(_matches(SPELL_TIER, name) or _matches(BORROWED, name), "%s displays '%s', a Final Fantasy name" % [id, name])


func test_no_item_wears_a_borrowed_name() -> void:
	var items := _table(ITEMS, "items")
	assert_gt(items.size(), 50, "CONTROL: items.json must load")
	for id in items:
		var name := str(items[id].get("name", ""))
		assert_false(_matches(ITEM_LADDER, name) or _matches(BORROWED, name), "%s displays '%s', a Final Fantasy name" % [id, name])


func test_no_prose_names_a_borrowed_summon() -> void:
	for path in PROSE:
		var text := FileAccess.get_file_as_string(path)
		assert_gt(text.length(), 1000, "CONTROL: %s must load" % path)
		var re := RegEx.new()
		re.compile(BORROWED)
		for m in re.search_all(text):
			fail_test("%s says '%s' — FF's name; the id may stay, the words a player reads may not" % [path, m.get_string()])


func test_the_renamed_ids_still_exist() -> void:
	var abilities := _table(ABILITIES, "abilities")
	for id in ["summon_ifrit", "summon_shiva", "summon_ramuh", "summon_bahamut"]:
		assert_true(abilities.has(id), "%s must keep its id; saves and rule scripts name it" % id)
	var items := _table(ITEMS, "items")
	for id in ["hi_potion", "x_potion", "mega_potion", "hi_ether", "mega_ether", "megalixir"]:
		assert_true(items.has(id), "%s must keep its id; saves and drops name it" % id)


func test_no_battle_text_says_brave_or_default() -> void:
	for path in BATTLE_TEXT:
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_not_null(data, "CONTROL: %s must parse" % path)
		var hits: Array = []
		_collect_text(data, "", hits)
		assert_gt(hits.size(), 20, "CONTROL: %s must yield names and descriptions" % path)
		for h in hits:
			assert_false(_matches(BRAVE_DEFAULT, h[1]), "%s %s says '%s' — our terms are Advance / Defer / AP" % [path, h[0], h[1]])


## Every "name" / "description" string anywhere in the tree, with its key path.
func _collect_text(node, path: String, out: Array) -> void:
	if node is Dictionary:
		for k in node:
			var v = node[k]
			if (k == "name" or k == "description") and v is String:
				out.append([path + "." + str(k), v])
			else:
				_collect_text(v, path + "." + str(k), out)
	elif node is Array:
		for i in node.size():
			_collect_text(node[i], "%s[%d]" % [path, i], out)
