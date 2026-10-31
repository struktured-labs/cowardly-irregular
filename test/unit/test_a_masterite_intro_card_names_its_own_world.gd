extends GutTest

## A Masterite intro is WIRED in one file (a village's _place_masterites, a dungeon's _init) and
## AUTHORED in another, and nothing checked that the two agree. Measured 2026-10-25, before this
## guard: NINE boss-intro cards named the wrong world, each exactly one world behind — Rivet Row's
## three (industrial) announced "Masterite — Steampunk", Node Prime's three (digital) announced
## "Masterite — Industrial", and Vertex's three (abstract) announced "Masterite — Digital". Six of
## those also announced the PREVIOUS world's boss by name: the player walked up to the Warden of the
## Firewall and the card said "Warden of the Assembly Line". The scenes themselves were right — right
## trigger, right world field, right dialogue — so every check that read the scene in isolation
## passed. Only the wiring says which monster a scene is introducing.
##
## Derived from the wiring, never listed, so a village added tomorrow is covered the day it lands.

const MAPS_ROOT := "res://src/maps"
const WORLD_MAP := "res://src/ui/WorldMapMenu.gd"
const MONSTERS := "res://data/monsters.json"

## The world ladder itself — the suffix order IS the world order, which is canon rather than data.
## The player-facing THEME WORD is not here on purpose: it is read off WorldMapMenu.WORLDS below,
## because "futuristic" ships as "Digital" and a hardcoded word would have agreed with the bug.
const SUFFIX_WORLD := {
	"medieval": 1, "suburban": 2, "steampunk": 3,
	"industrial": 4, "futuristic": 5, "abstract": 6,
}

## Three populations wire intros and only one of them follows the roster conventions, so the checks
## below are scoped by what a scene CLAIMS rather than by a list. Measured: 12 scenes carry a
## "Masterite — <theme>" card and all 12 trigger `boss_<archetype>_<suffix>`; 3 dungeon bosses carry
## "Dungeon Boss — <place>" and trigger `boss_<place>_<archetype>`, because a dungeon boss is a NAMED
## VARIANT of a roster Masterite ("a Warden variant built from salvaged line parts") whose name is
## SUPPOSED to differ; 3 W1 village encounters carry no card at all and trigger
## `world1_<archetype>_pre_fight`. A rule written for the first and applied to all three would red
## six correct scenes, and one relaxed to fit all three would permit the bug this file is about.
const ROSTER_CARD_PREFIX := "Masterite"
const VARIANT_CARD_PREFIX := "Dungeon Boss"


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read(path))
	return parsed if parsed is Dictionary else {}


func _monsters() -> Dictionary:
	var root: Dictionary = _json(MONSTERS)
	var inner: Variant = root.get("monsters", root)
	return inner if inner is Dictionary else {}


## world id -> player-facing theme word, off the table the world map actually draws.
func _world_themes() -> Dictionary:
	var out := {}
	var rx := RegEx.new()
	rx.compile('"id"\\s*:\\s*(\\d+).*?"theme"\\s*:\\s*"([^"]+)"')
	for m in rx.search_all(_read(WORLD_MAP)):
		out[int(m.get_string(1))] = m.get_string(2)
	return out


func _gd_files(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := "%s/%s" % [dir_path, name]
		if d.current_is_dir():
			if not name.begins_with("."):
				_gd_files(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()


## Every (monster_id, cutscene_id, source file) the maps wire. Two shapes: a village builds
## MasteriteEncounter instances and assigns `<var>.monster_id` / `<var>.cutscene_id`; a dungeon sets
## its own `boss_id` / `boss_cutscene_id`. Both are read — a scan that knew only one found 3 of 12.
func _wiring() -> Array:
	var files: Array = []
	_gd_files(MAPS_ROOT, files)
	var pairs: Array = []
	var rx_mid := RegEx.new()
	rx_mid.compile('(\\w+)\\.monster_id\\s*=\\s*"([^"]+)"')
	var rx_cid := RegEx.new()
	rx_cid.compile('(\\w+)\\.cutscene_id\\s*=\\s*"([^"]+)"')
	var rx_bid := RegEx.new()
	rx_bid.compile('(?m)^\\tboss_id\\s*=\\s*"([^"]+)"')
	var rx_bcs := RegEx.new()
	rx_bcs.compile('(?m)^\\tboss_cutscene_id\\s*=\\s*"([^"]+)"')
	for f in files:
		var src := _read(f)
		if src == "":
			continue
		var cids := {}
		for m in rx_cid.search_all(src):
			cids[m.get_string(1)] = m.get_string(2)
		for m in rx_mid.search_all(src):
			var mid: String = m.get_string(2)
			if mid.begins_with("masterite_"):
				pairs.append({"file": f, "monster": mid, "cutscene": str(cids.get(m.get_string(1), ""))})
		var bid := rx_bid.search(src)
		if bid != null and bid.get_string(1).begins_with("masterite_"):
			var bcs := rx_bcs.search(src)
			pairs.append({"file": f, "monster": bid.get_string(1), "cutscene": bcs.get_string(1) if bcs != null else ""})
	return pairs


## "" when the scene opens without a card — the W1 encounters do, which is a shape and not a gap.
func _card_title(scene: Dictionary) -> String:
	for s in (scene.get("steps", []) as Array):
		if s is Dictionary and str((s as Dictionary).get("type", "")) == "boss_intro":
			return str((s as Dictionary).get("title", ""))
	return ""


func _suffix(monster_id: String) -> String:
	var parts := monster_id.split("_")
	return str(parts[parts.size() - 1]) if parts.size() > 0 else ""


func _archetype(monster_id: String) -> String:
	var parts := monster_id.split("_")
	return str(parts[1]) if parts.size() > 2 else ""


func test_the_derivation_sees_the_real_roster() -> void:
	## CONTROL. Every arm below is a loop over this, so an empty or one-world scan would pass them
	## all in silence — which is the failure mode the bug this file exists for already survived.
	var pairs := _wiring()
	assert_gt(pairs.size(), 10, "the maps must wire more than a handful of Masterites (found %d)" % pairs.size())
	var worlds := {}
	var wired := 0
	for p in pairs:
		worlds[SUFFIX_WORLD.get(_suffix(str(p["monster"])), 0)] = true
		if str(p["cutscene"]) != "":
			wired += 1
	assert_gt(worlds.size(), 2, "the scan must span several worlds, or a one-world corpus cannot see an off-by-one-world bug")
	assert_gt(wired, 5, "most of those must actually name an intro scene (found %d)" % wired)
	var themes := _world_themes()
	assert_gt(themes.size(), 5, "the world map's theme table must parse (got %s)" % str(themes))


func test_every_wired_masterite_intro_exists_and_claims_its_own_world() -> void:
	var missing: Array = []
	var wrong_world: Array = []
	var wrong_trigger: Array = []
	for p in _wiring():
		var cid: String = str(p["cutscene"])
		if cid == "":
			continue
		var mid: String = str(p["monster"])
		var path := "res://data/cutscenes/%s.json" % cid
		if not FileAccess.file_exists(path):
			missing.append("%s -> %s" % [mid, cid])
			continue
		var scene := _json(path)
		var want_world: int = int(SUFFIX_WORLD.get(_suffix(mid), 0))
		if int(scene.get("world", -1)) != want_world:
			wrong_world.append("%s: %s says world %s, the monster is world %d" % [cid, cid, str(scene.get("world")), want_world])
		if not _card_title(scene).begins_with(ROSTER_CARD_PREFIX):
			continue
		var want_trigger := "boss_%s_%s" % [_archetype(mid), _suffix(mid)]
		if str(scene.get("trigger", "")) != want_trigger:
			wrong_trigger.append("%s: trigger '%s', expected '%s'" % [cid, str(scene.get("trigger", "")), want_trigger])
	assert_eq(missing.size(), 0, "a wired cutscene_id with no file goes straight to the fight with a push_warning nobody reads: " + str(missing))
	assert_eq(wrong_world.size(), 0, "a scene's world must be the world of the monster it introduces: " + str(wrong_world))
	assert_eq(wrong_trigger.size(), 0, "a scene presenting a roster Masterite must trigger the roster fight: " + str(wrong_trigger))


func test_a_masterite_card_names_the_masterite_it_introduces() -> void:
	var mon := _monsters()
	var themes := _world_themes()
	var wrong_name: Array = []
	var wrong_theme: Array = []
	var cards := 0
	for p in _wiring():
		var cid: String = str(p["cutscene"])
		if cid == "":
			continue
		var path := "res://data/cutscenes/%s.json" % cid
		if not FileAccess.file_exists(path):
			continue
		var scene := _json(path)
		var card := {}
		for s in (scene.get("steps", []) as Array):
			if s is Dictionary and str((s as Dictionary).get("type", "")) == "boss_intro":
				card = s
				break
		if card.is_empty():
			continue  ## The W1 village encounters open on dialogue with no card at all — a shape, not a gap.
		var title: String = str(card.get("title", ""))
		if not title.begins_with(ROSTER_CARD_PREFIX):
			continue
		cards += 1
		var mid: String = str(p["monster"])
		var real: String = str((mon.get(mid, {}) as Dictionary).get("name", ""))
		if str(card.get("name", "")) != real:
			wrong_name.append("%s announces '%s'; the monster the player is about to fight is '%s'" % [cid, str(card.get("name", "")), real])
		var want_theme: String = str(themes.get(int(SUFFIX_WORLD.get(_suffix(mid), 0)), ""))
		if want_theme != "" and not title.contains(want_theme):
			wrong_theme.append("%s says '%s'; this is the %s world" % [cid, title, want_theme])
	assert_gt(cards, 5, "CONTROL: the loop must reach real Masterite cards, not skip them all (%d)" % cards)
	assert_eq(wrong_name.size(), 0, "a card claiming to present a Masterite must name THAT Masterite: " + str(wrong_name))
	assert_eq(wrong_theme.size(), 0, "and must name its own world — every one of these was exactly one world behind: " + str(wrong_theme))


func test_the_dungeon_variant_exemption_is_load_bearing() -> void:
	## The skip above is only honest while variant cards really exist and really differ. If they
	## stopped differing, the exemption would be dead code quietly widening the guard's blind spot.
	var mon := _monsters()
	var variants := 0
	var differing := 0
	for p in _wiring():
		var cid: String = str(p["cutscene"])
		if cid == "":
			continue
		var path := "res://data/cutscenes/%s.json" % cid
		if not FileAccess.file_exists(path):
			continue
		for s in (_json(path).get("steps", []) as Array):
			if not (s is Dictionary) or str((s as Dictionary).get("type", "")) != "boss_intro":
				continue
			if not str((s as Dictionary).get("title", "")).begins_with(VARIANT_CARD_PREFIX):
				continue
			variants += 1
			var real: String = str((mon.get(str(p["monster"]), {}) as Dictionary).get("name", ""))
			if str((s as Dictionary).get("name", "")) != real:
				differing += 1
	assert_gt(variants, 0, "no '%s' card exists any more — delete the exemption rather than leaving it to widen" % VARIANT_CARD_PREFIX)
	assert_gt(differing, 0, "every variant card now matches its roster monster, so the exemption buys nothing and hides the check")
