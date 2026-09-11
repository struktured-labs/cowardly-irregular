extends GutTest

## WORLD 5's STORY BEGAN AFTER THE PLAYER LEFT WORLD 5.
##
## 2026-09-11. `_get_pending_story_cutscene` gated `world5_prologue` and
## `world5_chapter2` on `_current_map_id == "abstract_overworld"`. That is WORLD 6's
## overworld. World 5's is `futuristic_overworld` — the id GameLoop itself instantiates
## as FuturisticOverworldScript, gives its own encounter table, and maps to terrain
## "digital"; TeleportMenu labels it "World 5: Futuristic";
## AutogrindSystem.WORLD_REGIONS lists it as world 5's region; IndustrialOverworld's
## forward portal targets it. Four independent sources, one answer.
##
## WHAT A PLAYER GOT. Finish World 4, walk the Industrial portal into World 5 — no
## prologue, because the map is futuristic_overworld. Walk into Node Prime village —
## no chapter 1 either, because that gate wants `world5_prologue_complete`. The whole
## World 5 act, and all of World 6 chained behind it, waited until the player beat the
## Root Process Arbiter and walked OUT into World 6's domain, where the prologue
## finally fired. Not a deadlock — the Futuristic forward portal opens on
## `cutscene_flag_arbiter_futuristic_defeated`, which the Root Process boss sets — but
## the act played inside out: "Boot Sequence" after the boot.
##
## 🔑 WHY 10,178 GREEN TESTS DID NOT SEE IT, and the reason this file is not a second
## copy of the spine walk. `test_story_spine_walk_regression` drives the same function
## through the same gates and is correct — but its walker does
## `for m in MAPS: gl._current_map_id = m` at every step, assigning every map in the
## game until something fires. It proves the chain CONNECTS. It cannot prove a beat is
## gated where the player actually STANDS, because the walker stands everywhere. A
## wrong map id is invisible to an omniscient reader. @cowir-music's sequence, one
## level out: the corpus was right, the query was right, the SUBJECT was connectivity.
##
## THE RULE HERE IS DERIVED, not a list. A gate may name any map it likes — villages
## and dungeons are most of them. But if it names an OVERWORLD, it must name its own
## world's, and which overworld belongs to which world is read from
## AutogrindSystem.WORLD_REGIONS rather than restated below. Nothing to keep in sync,
## and no exemption anyone can quietly widen.
##
## ⚠️ WHAT THIS DOES NOT CLAIM. It reads the dispatcher and drives it; it does not open
## the map. That the portal puts the player on a map whose id is `futuristic_overworld`
## is FuturisticOverworld's business and is checked there, not here.

const GameLoopScript := preload("res://src/GameLoop.gd")
const GAME_LOOP_SRC := "res://src/GameLoop.gd"

## Gates that must still be found by the parser, by NAME. A count floor passes while
## members quietly leave; these do not. Every one is a prologue gated on its world's
## own overworld — the exact shape the bug broke.
const PREMISE_GATES: Array[String] = [
	"world2_prologue", "world3_prologue", "world4_prologue", "world5_prologue",
]

var _cache: Dictionary = {}


## Comment-stripped source.
##
## ⚠️ MEASURED INERT TODAY, and saying so rather than implying it works. I added it
## because the repair commit put a long comment naming `futuristic_overworld` directly
## above the gates, and because my aftermath guard passed 6/6 on a commented-out gate
## an hour earlier. Then I tested it: same mutated tree (the W5 gate commented out),
## stripper on and stripper off — IDENTICAL failures. The parser below matches with
## `begins_with("if _current_map_id")` after strip_edges(), and a commented line begins
## with `#`, so it is already rejected.
##
## It stays because the aftermath guard's hollowness was a `contains()` matcher, and
## the day someone relaxes `begins_with` to `contains` for a gate shape this parser
## missed, the stripper goes from redundant to load-bearing with nothing to announce
## it. A control that is currently inert and honestly labelled is fine; one that is
## inert and described as working is how the last hollow guard got written.
func _code_only() -> String:
	if _cache.has("code"):
		return _cache["code"]
	var raw: String = FileAccess.get_file_as_string(GAME_LOOP_SRC)
	assert_ne(raw, "", "GameLoop.gd must be readable")
	var out: String = ""
	for line in raw.split("\n"):
		var idx: int = line.find("#")
		out += (line.substr(0, idx) if idx >= 0 else line) + "\n"
	_cache["code"] = out
	return out


## overworld map id -> the world that owns it, read from the autoload rather than
## restated. If this file and AutogrindSystem ever disagree, the game has two answers
## and that is the finding.
func _overworld_owner() -> Dictionary:
	var out: Dictionary = {}
	for entry in AutogrindSystem.WORLD_REGIONS:
		var region: String = str(entry.get("region", ""))
		if region.ends_with("overworld"):
			out[region] = int(entry.get("world", 0))
	return out


## cutscene id -> the map its gate requires. Pairs an `if _current_map_id == "X":`
## with the `return "Y"` immediately under it, which is the shape every gate uses.
func _gate_maps() -> Dictionary:
	if _cache.has("gates"):
		return _cache["gates"]
	var out: Dictionary = {}
	var lines: PackedStringArray = _code_only().split("\n")
	for i in range(lines.size() - 1):
		var guard: String = lines[i].strip_edges()
		if not guard.begins_with("if _current_map_id == \""):
			continue
		var map_id: String = guard.split("\"")[1]
		# The return may sit one or two lines down (a `and _cave_floor >= 1` arm keeps
		# the same shape). Take the first return within two lines, or nothing.
		for j in range(i + 1, mini(i + 3, lines.size())):
			var body: String = lines[j].strip_edges()
			if body.begins_with("return \""):
				out[body.split("\"")[1]] = map_id
				break
	_cache["gates"] = out
	return out


## PREMISE. Both sources real, by named member — either one going empty makes every
## arm below pass on nothing.
func test_premise_the_gates_and_the_region_table_both_parse() -> void:
	var owner := _overworld_owner()
	# gte, not eq: a seventh world is ordinary growth and must not red this file.
	# @cowir-overworld's PLUS-ONE magnitude — the eq form taxes correct work.
	assert_gte(owner.size(), 5,
		"WORLD_REGIONS yielded %d overworlds; the cross-check has nothing to check against" % owner.size())
	assert_eq(int(owner.get("futuristic_overworld", -1)), 5,
		"AutogrindSystem no longer says futuristic_overworld is world 5's — this whole file is built on that mapping, so re-derive it before trusting anything below")
	assert_eq(int(owner.get("abstract_overworld", -1)), 6,
		"AutogrindSystem no longer says abstract_overworld is world 6's — same")

	# THE CONTROL MUST NOT BE DRAINABLE. `for g in PREMISE_GATES` runs zero times at
	# [] and the named-member check below passes on nothing — the silent control I put
	# in my own bestiary guard an hour before writing this one. Pinned to a literal.
	assert_gte(PREMISE_GATES.size(), 4,
		"PREMISE_GATES holds %d, fewer than the 4 this guard names — the membership check below is going vacuous. Adding a gate is free; losing one is not." % PREMISE_GATES.size())
	var gates := _gate_maps()
	var missing: Array[String] = []
	for g in PREMISE_GATES:
		if not gates.has(g):
			missing.append(g)
	assert_eq(missing.size(), 0,
		"the parser lost a gate it must see: %s — if the dispatcher's shape changed, fix the parse; a silent 0 here reads as 'no defects'" % ", ".join(missing))


## CONTROL, both directions. A reader that cannot return a positive is not a reader.
func test_the_check_answers_both_ways() -> void:
	var owner := _overworld_owner()
	var gates := _gate_maps()
	assert_eq(str(gates.get("world4_prologue", "")), "industrial_overworld",
		"CONTROL: W4's prologue is gated on its own overworld and must read as correct")
	assert_false(gates.has("world7_prologue"),
		"CONTROL: a gate that does not exist must not be reported — the parser is inventing pairs")
	# The rule must be capable of FAILING: feed it the bug as it shipped.
	var world_of_gate: int = 5
	assert_ne(int(owner.get("abstract_overworld", -1)), world_of_gate,
		"CONTROL: the shipped bug (world5_* gated on abstract_overworld) must be judged wrong by this rule, or the rule cannot catch it")


## THE RATCHET. Any worldN gate that names an overworld must name world N's.
func test_no_world_gate_names_another_worlds_overworld() -> void:
	var owner := _overworld_owner()
	var wrong: Array[String] = []
	var checked: int = 0
	for cutscene in _gate_maps().keys():
		var cid: String = str(cutscene)
		if not cid.begins_with("world"):
			continue
		var digits: String = cid.substr(5, 1)
		if not digits.is_valid_int():
			continue
		var map_id: String = str(_gate_maps()[cutscene])
		if not owner.has(map_id):
			continue  # a village or dungeon — this rule says nothing about those
		checked += 1
		var declared: int = int(digits)
		var actual: int = int(owner[map_id])
		if declared != actual:
			wrong.append("%s is world %d's beat but is gated on %s, which is world %d's" % [cid, declared, map_id, actual])
	wrong.sort()

	assert_gte(checked, 4,
		"only %d overworld-gated beats examined; the rule is going vacuous and would report clean on anything" % checked)
	assert_eq(wrong.size(), 0,
		"a world's story beat is gated on a DIFFERENT world's overworld, so it cannot fire where the player stands: %s" % ", ".join(wrong))


## BEHAVIOURAL. Stands where the player stands and asks the shipped dispatcher. This
## is the arm the spine walk cannot have: it never moves off the one map.
func test_a_player_entering_world5_gets_the_world5_prologue_there() -> void:
	var saved: Dictionary = GameState.game_constants.duplicate(true)
	for k in GameState.game_constants.keys():
		if str(k).begins_with("cutscene_flag_"):
			GameState.game_constants.erase(k)

	var gl = GameLoopScript.new()
	GameState.game_constants["cutscene_flag_world4_complete"] = true

	# 2026-09-11: world4_transition was wired (cowir-story), and like W2/W3's it precedes the
	# next world's prologue on arrival. Assert that ordering, then clear it — this test's
	# subject is WHICH overworld the prologue fires on, not that nothing precedes it.
	gl._current_map_id = "futuristic_overworld"
	assert_eq(gl._get_pending_story_cutscene(), "world4_transition",
		"the industrial->digital dissolve goes first, the same shape as world2_transition before the W3 prologue")
	GameState.game_constants["cutscene_flag_world4_transition_complete"] = true

	gl._current_map_id = "futuristic_overworld"
	assert_eq(gl._get_pending_story_cutscene(), "world5_prologue",
		"a player who just walked the Industrial portal into World 5 is standing on futuristic_overworld with world4_complete set. That is the whole trigger for world5_portal_entry — Boot Sequence — and nothing else fires here")

	# ...and the next beat waits for the village, as its authored world5_village_entry says.
	GameState.game_constants["cutscene_flag_world5_prologue_complete"] = true
	assert_eq(gl._get_pending_story_cutscene(), "",
		"chapter 1 is world5_village_entry; it must NOT fire out on the overworld")
	gl._current_map_id = "node_prime_village"
	assert_eq(gl._get_pending_story_cutscene(), "world5_chapter1",
		"walking into Node Prime is world5_village_entry — the beat the broken prologue gate was holding hostage")

	gl.free()
	GameState.game_constants = saved
