extends GutTest

## 14 items shipped an authoring spec in the description a player reads — 12 as quest rewards.

const ITEMS := "res://data/items.json"
const EQUIP := "res://data/equipment.json"

## The tell. An authoring-spec phrase no in-fiction text would ever use.
const SPEC_TELL := "Intended mechanics"

## Fields a player actually reads. Anything _-prefixed is a META key and is EXEMPT by design.
const PLAYER_FIELDS := ["description", "flavor", "name"]


func _load(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _entries(path: String) -> Array:
	var d := _load(path)
	var pool: Variant = d.get("items", d.get("weapons", d))
	var out: Array = []
	if pool is Dictionary:
		for k in pool:
			if pool[k] is Dictionary:
				out.append([str(k), pool[k] as Dictionary])
	return out


## FLOOR. An empty walk makes every assertion below vacuous.
func test_control_corpora_resolve() -> void:
	var items := _entries(ITEMS)
	assert_gt(items.size(), 100, "items walk must load the real corpus, else this guard is vacuous")
	var found := false
	for pair in items:
		if pair[0] == "potion":
			found = true
			assert_true(str(pair[1].get("description", "")).length() > 0,
				"a KNOWN item must carry a description — a count alone passes on a walk that "
				+ "resolved nothing")
	assert_true(found, "potion must resolve; if it does not, the walk is reading the wrong shape")


## THE RATCHET. An authoring spec in player-facing text is a developer note handed to the player.
func test_no_item_ships_an_authoring_spec() -> void:
	var offenders: Array = []
	for pair in _entries(ITEMS) + _entries(EQUIP):
		for f in PLAYER_FIELDS:
			if str(pair[1].get(f, "")).contains(SPEC_TELL):
				offenders.append("%s.%s" % [pair[0], f])
	assert_eq(offenders.size(), 0, "these ship an authoring spec in text the player reads. "
		+ "chapter_three_pages read 'Intended mechanics: passive party buff, +5% autobattle "
		+ "efficiency' as a Chapter Three quest reward. Strip the note; keep the flavor; the "
		+ "mechanic is a separate decision: %s" % [offenders])


## The tell must be able to fire — a ratchet nobody can trip is not a ratchet.
func test_the_tell_would_catch_a_planted_note() -> void:
	var sample := "A working pickaxe. Intended mechanics: two-handed weapon, ATK-focused."
	assert_true(sample.contains(SPEC_TELL), "the tell must match a real authoring note verbatim; "
		+ "if this fails the constant drifted and the ratchet above is inert")
	assert_false("A working pickaxe. Handle polished by three shifts a day.".contains(SPEC_TELL),
		"clean flavor must NOT match, else the ratchet reds on correct text")


## Deliberately NOT checked: TODO / placeholder / broken. This game's FICTION is about bugs —
## data_fragment.flavor decodes to "TODO: write description" ON PURPOSE, and a guard that
## flags it would ratchet against the writing.
func test_fiction_using_bug_words_is_not_flagged() -> void:
	var fiction := "Decoded: 'TODO: write description'"
	assert_false(fiction.contains(SPEC_TELL), "in-fiction bug words must survive this guard — "
		+ "the tell is an authoring-spec phrase, not a bug word, and that distinction is why "
		+ "this ratchet can be sharp instead of advisory")
