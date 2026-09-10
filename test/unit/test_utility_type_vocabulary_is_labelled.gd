extends GutTest

## Three hand-written copies of the same ability-type list, two of the tokens naming types that do
## not exist. That is the shape that hid the debuffer archetype for years.
##
## _ai_healer, _ai_tank and the shared utility slot each carried their own literal
## ["buff", "support", "defensive", …]. No ability in the game authors `buff` or `defensive` — the
## ten authored types are escape, healing, magic, meta, mp_restore, physical, revival, song, summon,
## support. The dead tokens are harmless in themselves; what is not harmless is that they READ as
## live vocabulary, which is exactly how ["debuff", "status"] survived in the classifier and in
## _ai_debuffer's body until today.
##
## So they are LABELLED, not deleted: one shared constant, dead entries named in its comment. This
## file is the ratchet that keeps the label honest in both directions — a NEW dead token reds, and a
## dead one becoming live reds too, because then it belongs in the live half and the comment is
## stale.
##
## Unifying the tank's copy with the shared list added `song` to it. Zero monsters author a song
## ability (all four belong to the Bard), so that is a provable no-op for the current roster — and
## that is measured below rather than asserted, because "no monster has one" is exactly the kind of
## premise that quietly stops being true.

const SRC := "res://src/battle/BattleManager.gd"
const KNOWN_DEAD := ["buff", "defensive"]

func _abilities() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return (parsed as Dictionary).get("abilities", parsed)

func _authored_types() -> Dictionary:
	var out: Dictionary = {}
	var ab: Dictionary = _abilities()
	for aid in ab:
		out[str((ab[aid] as Dictionary).get("type", ""))] = true
	assert_gt(out.size(), 5, "CONTROL: the type vocabulary read non-empty (%d)" % out.size())
	return out

func _constant_tokens() -> Array:
	var src := FileAccess.get_file_as_string(SRC)
	var i: int = src.find("const UTILITY_ABILITY_TYPES")
	assert_gt(i, -1, "CONTROL: located the shared constant")
	var line: String = src.substr(i, src.find("\n", i) - i)
	var out: Array = []
	var re := RegEx.new()
	re.compile("\"([a-z_]+)\"")
	for m in re.search_all(line):
		out.append(m.get_string(1))
	assert_gt(out.size(), 2, "CONTROL: parsed tokens out of the constant (%s)" % str(out))
	return out

func test_the_live_utility_types_are_all_present() -> void:
	## The half that matters mechanically: an archetype must be able to reach every ability type a
	## monster can actually carry as utility.
	var tokens := _constant_tokens()
	for t in ["support", "song", "summon"]:
		assert_true(t in tokens, "'%s' is an authored type and must be selectable as utility" % t)

func test_the_dead_tokens_are_exactly_the_labelled_ones() -> void:
	## Bidirectional. A new token naming a type nothing authors reds here, and so does one of these
	## becoming live — at which point the constant's comment is wrong and should be rewritten.
	var authored := _authored_types()
	var dead: Array = []
	for t in _constant_tokens():
		if not authored.has(t):
			dead.append(t)
	dead.sort()
	var expected: Array = KNOWN_DEAD.duplicate()
	expected.sort()
	assert_eq(dead, expected,
		"the constant's dead tokens changed — update its comment and this list together: found %s, labelled %s" % [str(dead), str(expected)])

func test_no_filter_kept_its_own_copy() -> void:
	## The anti-drift half. Three literal copies is how two of them ended up naming a vocabulary the
	## third had already outgrown.
	var src := FileAccess.get_file_as_string(SRC)
	assert_gt(src.length(), 1000, "CONTROL: read BattleManager")
	assert_eq(src.count("\"buff\", \"support\", \"defensive\""), 0,
		"a hand-written copy of the utility list is back — point it at UTILITY_ABILITY_TYPES")
	assert_gte(src.count("in UTILITY_ABILITY_TYPES"), 2,
		"CONTROL: the constant is actually the thing being filtered on")

func test_adding_song_to_the_tank_list_is_a_no_op_for_this_roster() -> void:
	## The premise behind unifying the lists, measured rather than trusted. If a monster ever gains
	## a song, this reds and someone re-checks whether a tank should be able to sing.
	var ab: Dictionary = _abilities()
	var songs: Dictionary = {}
	for aid in ab:
		if str((ab[aid] as Dictionary).get("type", "")) == "song":
			songs[aid] = true
	assert_gt(songs.size(), 2, "CONTROL: song abilities exist at all (%d)" % songs.size())
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var mons: Dictionary = (parsed as Dictionary).get("monsters", parsed)
	assert_gt(mons.size(), 50, "CONTROL: the roster read non-empty (%d)" % mons.size())
	var singers: Array = []
	for mid in mons:
		for aid in ((mons[mid] as Dictionary).get("abilities", []) as Array):
			if songs.has(str(aid)):
				singers.append("%s/%s" % [mid, aid])
	assert_eq(singers.size(), 0,
		"a monster now carries a song, so unifying the tank list is no longer a no-op: " + str(singers))
