extends GutTest

## The jukebox listed "Raid!" five times.
##
## `battle_brute.ogg` is named by five manifest keys under the monster-family ruling — a troll, a
## cave troll, an ogre, a barbarian and the brute itself share one theme. Four of those keys carry
## `alias_of: "battle_brute"`, and they carry its FILE and its TITLE too, so the jukebox built five
## rows that read identically and play the same bed:
##
##     battle_barbarian · battle_brute · battle_cave_troll · battle_ogre · battle_troll
##     all titled "Raid!", all assets/audio/music/battle_brute.ogg
##
## 🔑 THE ALIAS IS FOR `play_music`, WHICH ASKS FOR `battle_ogre`. A player browsing 165 rows is
## asking for a TRACK, and there are 161 of those. Nothing becomes unreachable: the bed is still
## one row away under its own name.
##
## ⛔ THE ALTERNATIVE WAS TO LABEL THEM, NOT HIDE THEM — "Raid! (Ogre)" and so on. Rejected: that
## adds four rows to scroll past for no new audio, in the one menu whose whole problem is length.
## Stated here so the choice is visible rather than implied by the diff.
##
## 📌 This gives `alias_of` its first runtime reader. It was provenance before — the routing works
## because each alias also carries `file`, and `alias_of` recorded WHY. It now also decides.

const JUKEBOX := preload("res://src/ui/JukeboxMenu.gd")
const MANIFEST := "res://data/music_manifest.json"
const CATALOG := "res://tools/music_prompts.json"
const SIBLING_PIN := "res://test/unit/test_generic_beds_are_not_named_after_a_boss.gd"


func _tracks_map() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: the manifest read back %d chars" % raw.length())
	return (JSON.parse_string(raw) as Dictionary).get("tracks", {})


func _alias_ids() -> Array:
	var out: Array = []
	for k in _tracks_map().keys():
		var e: Variant = _tracks_map()[k]
		if e is Dictionary and str((e as Dictionary).get("alias_of", "")) != "":
			out.append(str(k))
	out.sort()
	return out


## ⛔ DELIBERATELY EMPTY, AND THE ARM BELOW KEEPS IT THAT WAY. The one entry it held —
## "The Answered Absence" on both `overworld_abstract` and `cutscene_w6_entering_nothing` — was
## retired 2026-09-16 by retitling the cutscene bed, not by declaring it forever.
##
## Which bed owned the name was a determination, not a preference. `overworld_abstract` was
## generated 2026-03-21 and its own prompt contains the phrase; the cutscene bed was generated
## three weeks later in a 25-track batch and inherited the title from `tools/music_prompts.json`,
## where one `title_template` had been copied onto two entries. The credits bed settles it —
## "The Answered Absence returns but fuller ... a single sustained piano chord" describes the
## overworld bed's piano, not the cutscene bed's near-silent drone. It is a recurring theme with
## one owner.
##
## An entry here must name WHY two beds share a name. The second assert deletes it the moment the
## collision stops being real, which is how this one left: it went red naming itself before the
## line was touched.
const KNOWN_TITLE_COLLISIONS := {}


func test_no_two_rows_read_the_same() -> void:
	var rows: Array = JUKEBOX._load_manifest_tracks()
	assert_gt(rows.size(), 100, "CONTROL: the jukebox built %d rows — it reads the live manifest" % rows.size())
	var by_title: Dictionary = {}
	for r in rows:
		var title: String = str(r[1])
		if not by_title.has(title):
			by_title[title] = []
		(by_title[title] as Array).append(str(r[0]))
	var undeclared: Array = []
	var declared_seen: Array = []
	for title in by_title.keys():
		var ids: Array = by_title[title]
		if ids.size() < 2:
			continue
		ids.sort()
		if KNOWN_TITLE_COLLISIONS.has(title) and ids == KNOWN_TITLE_COLLISIONS[title]:
			declared_seen.append(title)
			continue
		undeclared.append("%s: %s" % [title, str(ids)])
	assert_eq(undeclared.size(), 0,
		"%d jukebox rows read identically to another and are not declared: %s" % [undeclared.size(), str(undeclared)])
	## ⛔ AND THE DECLARATION MUST STILL BE TRUE. A note that outlives its fact is worse than
	## none, because the next reader trusts it (@cowir-sprites, 2026-09-16).
	assert_eq(declared_seen.size(), KNOWN_TITLE_COLLISIONS.size(),
		"%d of %d declared collisions are no longer real — delete the entry that went away" % [declared_seen.size(), KNOWN_TITLE_COLLISIONS.size()])


func test_the_aliased_ids_are_not_rows() -> void:
	## Derived from the manifest, never a hardcoded list of four: a fifth alias must be excluded
	## too, and a hardcoded list would silently let it through.
	var aliases: Array = _alias_ids()
	assert_gt(aliases.size(), 0,
		"CONTROL: the manifest declares %d aliases — with none, this arm has no subject" % aliases.size())
	var ids: Array = []
	for r in JUKEBOX._load_manifest_tracks():
		ids.append(str(r[0]))
	for a in aliases:
		assert_false(ids.has(a), "%s is a routing alias and must not be its own jukebox row" % a)


func test_the_track_the_aliases_point_at_is_still_listed() -> void:
	## Hiding the aliases must not hide the bed. Every alias target is itself a row.
	var ids: Array = []
	for r in JUKEBOX._load_manifest_tracks():
		ids.append(str(r[0]))
	var m: Dictionary = _tracks_map()
	var checked: int = 0
	for a in _alias_ids():
		var target: String = str((m[a] as Dictionary).get("alias_of", ""))
		assert_true(ids.has(target),
			"%s aliases %s, which is not a row — the bed became unreachable from the jukebox" % [a, target])
		checked += 1
	assert_gt(checked, 0, "SCOPE control: walked %d aliases" % checked)


func test_every_other_authored_track_is_still_a_row() -> void:
	## ⛔ THE DANGEROUS DIRECTION. A filter that is too broad empties the menu, and "fewer rows" is
	## what this change looks like when it works — so the count alone cannot tell the two apart.
	## Require the row set to be EXACTLY the non-alias keys.
	var m: Dictionary = _tracks_map()
	var expected: Array = []
	for k in m.keys():
		var e: Variant = m[k]
		if e is Dictionary and str((e as Dictionary).get("alias_of", "")) == "":
			expected.append(str(k))
	expected.sort()
	var ids: Array = []
	for r in JUKEBOX._load_manifest_tracks():
		ids.append(str(r[0]))
	ids.sort()
	assert_eq(ids.size(), expected.size(),
		"the jukebox lists %d rows against %d non-alias tracks" % [ids.size(), expected.size()])
	var missing: Array = []
	for k in expected:
		if not ids.has(k):
			missing.append(k)
	assert_eq(missing.size(), 0, "these authored tracks lost their row: %s" % str(missing.slice(0, 8)))


func test_the_list_is_still_sorted_and_well_formed() -> void:
	## The skip runs inside the build loop; dropping an entry must not disturb the rest.
	var rows: Array = JUKEBOX._load_manifest_tracks()
	var prev: String = ""
	for r in rows:
		assert_gte(r.size(), 3, "each row stays [id, display, duration]")
		assert_true(str(r[1]).length() > 0, "%s has no display name" % str(r[0]))
		if prev != "":
			assert_true(str(r[0]) >= prev, "rows must stay sorted by id (saw %s after %s)" % [str(r[0]), prev])
		prev = str(r[0])

func test_the_prompt_catalog_never_hands_two_beds_one_name() -> void:
	## ⛔ THE COLLISION WAS BORN HERE, NOT IN THE MANIFEST. `tools/music_prompts.json` carried
	## one `title_template` on two entries — `/worlds/6/tracks/overworld` and
	## `/shared_tracks/cutscene_w6_entering_nothing` — and the manifest inherited it at generation.
	## Fixing only the manifest leaves the next run free to write it back.
	##
	## The template count is derived and printed by the CONTROL below, not restated here — nine
	## staged prompts are waiting on a Suno login, so this figure is one login from wrong.
	var raw: String = FileAccess.get_file_as_string(CATALOG)
	assert_gt(raw.length(), 1000, "CONTROL: the prompt catalog read back %d chars" % raw.length())
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "CONTROL: the catalog parsed as a Dictionary")
	var seen := {}
	var dupes: Array = []
	var stack: Array = [parsed]
	while not stack.is_empty():
		var node: Variant = stack.pop_back()
		if node is Dictionary:
			if node.has("title_template"):
				var t: String = str(node["title_template"])
				if seen.has(t):
					dupes.append(t)
				seen[t] = true
			for v in (node as Dictionary).values():
				stack.push_back(v)
		elif node is Array:
			for v in (node as Array):
				stack.push_back(v)
	assert_gt(seen.size(), 100, "CONTROL: walked %d title templates — a shallow walk would measure nothing" % seen.size())
	assert_eq(dupes.size(), 0,
		"%d title templates are authored on more than one catalog entry, so a regeneration writes two beds one name: %s" % [dupes.size(), str(dupes)])

func test_the_other_pin_of_this_fact_agrees_with_this_one() -> void:
	## ⛔ TWO FILES PIN TITLE COLLISIONS AND NEITHER KNEW ABOUT THE OTHER. Resolving the one
	## real entry here left `test_generic_beds_are_not_named_after_a_boss.gd` still declaring it;
	## that file is self-retiring too, so it went red naming itself — which found the second pin
	## by luck of it being a good guard, not by anything connecting them.
	##
	## A self-retiring pin protects the FACT. It does not tell you how many pins the fact has.
	## This arm is the link, as an assert rather than a comment, because "do the two dicts agree"
	## is checkable: add an entry to either file alone and this reds.
	##
	## ⛔ THE CONTROL IS THE LOAD-BEARING HALF. Rename or move the sibling and the regex below
	## finds nothing, both sets read empty, and the arm passes while connecting nothing.
	var sibling: String = FileAccess.get_file_as_string(SIBLING_PIN)
	assert_gt(sibling.length(), 1000, "CONTROL: the sibling guard read back %d chars" % sibling.length())
	var decl: int = sibling.find("const KNOWN_TITLE_COLLISIONS")
	assert_gt(decl, 0, "CONTROL: %s no longer declares KNOWN_TITLE_COLLISIONS — this arm would agree with nothing" % SIBLING_PIN)
	var body: String = sibling.substr(decl, sibling.find("}", decl) - decl)
	var theirs := {}
	var re := RegEx.create_from_string("\"([^\"]+)\"\\s*:")
	for m in re.search_all(body):
		theirs[m.get_string(1).to_lower()] = true
	var mine := {}
	for k in KNOWN_TITLE_COLLISIONS:
		mine[str(k).to_lower()] = true
	var only_here: Array = []
	var only_there: Array = []
	for k in mine:
		if not theirs.has(k): only_here.append(k)
	for k in theirs:
		if not mine.has(k): only_there.append(k)
	assert_eq(only_here.size() + only_there.size(), 0,
		"the two title-collision pins disagree — declared only here: %s; only in the sibling: %s. Both files must name the same collisions or one will outlive the other" % [str(only_here), str(only_there)])


func test_the_rows_a_player_actually_sees_are_unique() -> void:
	## ⛔ EVERY OTHER ARM HERE CALLS THE STATIC. `JUKEBOX._load_manifest_tracks()` is the list
	## BUILDER; what a player reads is `TRACKS`, assigned from it in `_ready` at JukeboxMenu:64 and
	## then indexed by the draw loop. Today that is a bare assignment, so the two are the same list
	## — and "today it is a bare assignment" is a precondition no arm stated.
	##
	## @cowir-autogrind hit this an hour ago from the other side: seven arms calling their helper
	## directly, and the path that actually reaches the grind building its dict elsewhere. The
	## split @cowir-controller named is the general form — the helper owns the PROPERTY, an
	## instance owns the CONSEQUENCE — and the consequence is the half a player experiences.
	##
	## So this arm stands the menu up and reads the field the draw loop reads. Add a filter to
	## _ready and the static arms above stay green while this one follows the rows.
	##
	## ⛔ ROUTE COUNT, measured rather than assumed (@cowir-autogrind: a consequence arm is
	## scoped to a ROUTE, not to a feature). `TRACKS` has exactly ONE write — JukeboxMenu:64 —
	## so there is one way the list comes to exist and this arm covers it. Their case was two:
	## the single-action and Advance paths both reach the sort, and their first consequence arm
	## drove one.
	##
	## ⚠️ AND THIS CHECKS TITLES, WHICH IS STRICTER THAN WHAT RENDERS. The row a player reads is
	## `title   ·   duration` (:291), so two beds sharing a title but differing in length are
	## visually distinguishable and this arm would still flag them. Deliberate: the Jukebox is a
	## browsing surface and two rows reading "Raid!" are confusing whatever follows the dot. It
	## cannot MISS a collision, only over-report one — and the real instance could not be
	## distinguished anyway, since all five alias rows named ONE file and therefore one duration.
	var jb: Node = JUKEBOX.new()
	add_child_autofree(jb)
	await get_tree().process_frame
	assert_gt(jb.TRACKS.size(), 100,
		"CONTROL: the live menu built %d rows — a small list would make the duplicate check vacuous" % jb.TRACKS.size())
	var seen: Dictionary = {}
	var dupes: Array = []
	for row in jb.TRACKS:
		var title: String = str(row[1])
		if seen.has(title):
			dupes.append(title)
		seen[title] = true
	assert_eq(dupes.size(), 0,
		"%d rows in the LIVE menu read identically to another: %s — the static builder may still be clean, so look at _ready before looking at _load_manifest_tracks" % [dupes.size(), str(dupes)])
