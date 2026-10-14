extends GutTest

## The UI channel had NO world-variant lookup, so an authored `w5_door_open` was unreachable and
## every interior door in every world opened with `door_open` — whose prompt is "Heavy wooden door
## creaking open, old iron hinges groaning, medieval dungeon door". Measured: 12 interior doors
## outside World 1 (W2x5 MapleHeights, W3x2 Brasston, W4x2 RivetRow, W5x2 NodePrime, W6x1 Vertex),
## all through GameLoop:5455 `_area_interior_transition_in`.
##
## 🔑 THE TWIN IS DOCUMENTED IN THE FILE THIS FIX COPIES. `play_battle`'s own comment: "Cycle #13:
## play_ability was the ONLY prefix-aware path, so an authored w4_enemy_death could never be reached
## from the battle side." Same defect, one channel over, found the same way — by asking which
## function resolves the key rather than whether the asset exists.
##
## ⚠️ THE CHANGE WAS A PROVABLE NO-OP WHEN IT LANDED, and that is why it ships before any asset:
## across the 49 cue keys a literal `play_ui` reaches, ZERO had a `w2_`-`w6_` variant in the
## manifest. Nothing changed audibly. What was missing was reachability.
##
## ⛔ SO THIS FILE DOES NOT ASSERT "zero variants exist" — part 2 of the item deliberately
## falsifies that, and an arm pinned to a count the next correct change breaks is the
## coincidental-value ratchet. It guards the MECHANISM, its ORDER, and the ONE NEW SILENT FAILURE
## the change creates: a `w<N>_<ui_key>` in the manifest used to be inert and now rewrites that
## cue for a whole world, so an accidental one (a `w2_menu_select` typo) would change suburban menu
## chrome with nothing saying so.

const SOUND_MANAGER := "res://src/audio/SoundManager.gd"
const SFX_MANIFEST := "res://data/sfx_manifest.json"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## Every world prefix the mechanism depends on. If `_get_world_sfx_prefix` stops returning one of
## these, every variant for that world goes silently unreachable again — the original defect, back,
## with the assets still on disk.
const WORLD_PREFIXES := ["w2_", "w3_", "w4_", "w5_", "w6_"]

## ⛔ UI CUES THAT INTENTIONALLY HAVE A WORLD VARIANT. Empty on purpose: the lookup landed before any
## asset. A row is the DELIVERABLE for authoring one — you cannot silence this arm, only explain it
## — and its absence is what catches a variant nobody meant to create.
const DECLARED_UI_VARIANTS := {}


func _play_ui_body() -> String:
	var code: String = GdSource.code_of(SOUND_MANAGER)
	assert_true(code.contains("func play_ui"),
		"VOID: SoundManager's code did not survive the comment strip — an over-strip and a correct strip are the same green")
	var start: int = code.find("func play_ui(")
	if start < 0:
		return ""
	## The NEXT `func ` after it bounds the body. Reading to end-of-file instead would let a later
	## function's variant lookup satisfy every arm below — play_battle's is 40 lines down.
	var next: int = code.find("\nfunc ", start + 1)
	return code.substr(start, (next - start) if next > start else -1)


## Every cue key a literal `play_ui` reaches, across ALL of src/ — not just SoundManager, which
## DEFINES play_ui and calls it with a literal almost nowhere. My first version scanned only
## SoundManager and derived ZERO keys; the arm's own scope control caught it and reported
## "only 0 UI cue keys derived", which is the floor doing exactly its job.
func _ui_keys() -> Array[String]:
	var out: Array[String] = []
	var rx := RegEx.create_from_string("play_ui\\(\\s*\"([a-z0-9_]+)\"")
	for path in _gd_files_under("res://src"):
		for m in rx.search_all(GdSource.code_of(path)):
			if not out.has(m.get_string(1)):
				out.append(m.get_string(1))
	return out


## ⚠️ Six play_ui sites pass a VARIABLE key (two Rebalance panels, CutsceneDirector's play_sfx step,
## VillageElevator, play_pickup's fallback, play_ui's own recursion), so a literal scan under-counts
## the population by construction. It is still the right corpus for the arm below, which asks
## whether a MANIFEST variant rewrites a cue: an undeclared variant of a variable-passed key is
## caught by the same missing row. Said rather than implied — a literal cue-key grep is the corpus
## error that put a chest cue on a floor pickup.
func _gd_files_under(root: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var dir: String = pending.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for sub in d.get_directories():
			pending.append("%s/%s" % [dir, sub])
		for f in d.get_files():
			if f.ends_with(".gd"):
				out.append("%s/%s" % [dir, f])
	return out


func test_play_ui_resolves_a_world_variant_at_all() -> void:
	var body: String = _play_ui_body()
	assert_gt(body.length(), 100, "VOID: could not isolate play_ui's body (%d chars)" % body.length())
	assert_true(body.contains("_get_world_sfx_prefix()"),
		"play_ui no longer resolves a world prefix, so every authored w2_-w6_ UI variant is unreachable and the cue falls back to its World 1 asset in all six worlds — the exact defect this fix closed, and it fails SILENTLY because the fallback still plays something")


func test_the_variant_is_tried_BEFORE_the_default() -> void:
	## ⛔ ORDER IS THE FIX. A variant attempted after the default can never win: the default always
	## resolves, returns true, and the variant is dead code. Same shape as the format assertion that
	## had to precede the masking decode in the sample-rate guard.
	var body: String = _play_ui_body()
	assert_gt(body.length(), 100, "VOID: could not isolate play_ui's body")
	var variant_at: int = body.find("world_key, SFX_UI_BASE_DB")
	var default_at: int = body.find("sound_key, SFX_UI_BASE_DB")
	assert_gt(variant_at, -1, "play_ui no longer attempts the world key through the manifest")
	assert_gt(default_at, -1, "play_ui no longer attempts the base key — SCOPE: this arm no longer describes the function it guards")
	assert_lt(variant_at, default_at,
		"the world variant is tried AFTER the base key (variant at %d, base at %d). The base always resolves and returns, so the variant is unreachable — the lookup would be present and inert, which reads as fixed" % [variant_at, default_at])


func test_the_variant_inherits_the_base_cues_trim() -> void:
	## The trim is read off the BASE key, matching play_battle's _battle_level. Read it off the world
	## key instead and a variant silently loses its correction: `chest_open` carries +7.0 because it
	## measured the quietest world event in the game, and a `w4_chest_open` would play 7 dB under
	## with nothing in the manifest explaining why.
	var body: String = _play_ui_body()
	assert_gt(body.length(), 100, "VOID: could not isolate play_ui's body")
	assert_true(body.contains("_UI_VOLUME_TRIM_DB.get(sound_key"),
		"play_ui's trim lookup no longer uses the BASE key — a world variant would stop inheriting its cue's level correction, and the trims are measured per ROLE, not per asset")
	assert_false(body.contains("_UI_VOLUME_TRIM_DB.get(world_key"),
		"the trim is being read off the WORLD key, so every variant starts untrimmed: chest_open's +7.0 would not reach w4_chest_open")


func test_the_prefix_function_still_covers_every_world() -> void:
	## A world dropped from this match arm makes its variants unreachable while the assets sit on
	## disk — the original defect restored for one world, and invisible because the fallback plays.
	var code: String = GdSource.code_of(SOUND_MANAGER)
	var missing: Array[String] = []
	for p in WORLD_PREFIXES:
		if not code.contains("return \"%s\"" % p):
			missing.append(p)
	assert_eq(missing, [],
		"_get_world_sfx_prefix no longer returns these prefixes, so their variants are unreachable: %s" % [missing])


func test_no_undeclared_world_variant_rewrites_a_ui_cue() -> void:
	## ⛔ THE ONE NEW SILENT FAILURE THIS CHANGE CREATES. Before the lookup, a `w2_menu_select` in
	## the manifest was inert data. Now it REPLACES menu_select for every suburban-world player, and
	## nothing announces it. So any world variant of a UI cue must be declared above with its
	## reason; an undeclared one is either a typo or an undocumented decision.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SFX_MANIFEST))
	assert_true(parsed is Dictionary and (parsed as Dictionary).has("sfx"),
		"VOID: the sfx manifest did not parse, so this arm is about nothing")
	if not (parsed is Dictionary):
		return
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	var ui: Array[String] = _ui_keys()
	assert_gt(ui.size(), 30,
		"VOID: only %d UI cue keys derived from play_ui call sites — a short population here would read as full coverage" % ui.size())
	var undeclared: Array[String] = []
	for key in sfx:
		var k: String = str(key)
		for p in WORLD_PREFIXES:
			if not k.begins_with(p):
				continue
			var base: String = k.substr(p.length())
			if ui.has(base) and not DECLARED_UI_VARIANTS.has(k):
				undeclared.append("%s (rewrites %s in world %s)" % [k, base, p.substr(1, 1)])
	assert_eq(undeclared, [],
		"these world variants of UI cues are not declared, and since play_ui became prefix-aware each one REPLACES its base cue for a whole world: %s" % [undeclared])
