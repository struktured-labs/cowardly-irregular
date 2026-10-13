extends GutTest

## A VARIANT MUST VARY TEXTURE, NOT LEVEL. `_try_play_sfx_from_manifest` picks uniformly from
## `[base] + variants`, so every member is equally likely on any play. If they differ in loudness the
## player hears a random level jump on one of the most repeated sounds in the game — which reads as a
## mix bug rather than as variety, and is invisible to every existing guard because they check that a
## cue RESOLVES, never what it resolves AT.
##
## Found by @cowir-music on `ability_heal` and handed over: Cure played one of three cues at random,
## 7.2 LU apart, with all three prompts authoring the same "soft" character. Repaired by re-levelling
## the two variants to the base — a flat gain on the asset, NOT a `gain_db` field, because this
## file's sibling rule says a correction over 6 dB "is a bad render rather than a level problem", and
## the gain route was justified for VOICE by struktured having approved those clips by ear. Nobody
## approved heal_v2/v3 at those levels; they are tool output against a brief all three share.
##
## GUT cannot do DSP, so tools/audit_variant_levels.py measures and pins; this asserts the pinned
## shape. Same split as tools/audit_whoop.py and its baseline.

const FIXTURE := "res://test/fixtures/sfx_variant_levels.json"
const MANIFEST := "res://data/sfx_manifest.json"
const LIMIT := 3.0

## ⛔ KNOWN WIDE AND NOT MINE TO SETTLE — a ledger with the measured value, not an allowlist. Each
## reds if its spread MOVES, so the declaration cannot outlive its fact. Why these are open rather
## than repaired: for `ability_heal` the brief settled which member was right (all three say soft,
## only the base was). For these four the reference member is ambiguous — the BASE is the loud one
## and the long-standing sound — and `buff`/`debuff` fire on every buff and debuff in the game, so
## picking a target is an audible change to the game's most-played cues and belongs to struktured.
const WIDE_PENDING := {
	"buff": 7.0,
	"debuff": 6.1,
	"ability_ice": 5.2,
	"heal": 5.2,
}


func _fixture() -> Dictionary:
	var raw := FileAccess.get_file_as_string(FIXTURE)
	assert_ne(raw, "", "variant-level fixture missing — run `tools/audit_variant_levels.py --write`")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "VOID: the fixture did not parse")
	return (parsed as Dictionary).get("families", {}) if parsed is Dictionary else {}


func _manifest_families() -> Array[String]:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var out: Array[String] = []
	if not (parsed is Dictionary):
		return out
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	for key in sfx:
		var vs: Array = (sfx[key] as Dictionary).get("variants", [])
		if vs.size() > 0:
			out.append(str(key))
	return out


func test_premise_the_fixture_covers_every_variant_family() -> void:
	## The corpus control. A fixture that silently stopped covering a family would make every
	## assertion below true about a smaller set — the failure this lane keeps finding in other guards.
	var fx := _fixture()
	var live := _manifest_families()
	assert_gt(live.size(), 5, "VOID: only %d variant families in the manifest" % live.size())
	var unmeasured: Array[String] = []
	for f in live:
		if not fx.has(f):
			unmeasured.append(f)
	assert_eq(unmeasured, [],
		"these variant families are in the manifest and NOT in the fixture, so nothing knows whether their members match in level — run `tools/audit_variant_levels.py --write`: %s" % [unmeasured])


func test_no_family_jumps_level_between_its_variants() -> void:
	var fx := _fixture()
	var wide: Array[String] = []
	var moved: Array[String] = []
	for name in fx.keys():
		var row: Dictionary = fx[name]
		if bool(row.get("unmeasurable", false)):
			continue
		var spread: float = float(row.get("spread", 0.0))
		if WIDE_PENDING.has(name):
			if absf(spread - float(WIDE_PENDING[name])) > 0.15:
				moved.append("%s declared %.1f, measured %.1f" % [name, float(WIDE_PENDING[name]), spread])
			continue
		if spread > LIMIT:
			wide.append("%s %.1f LU" % [name, spread])
	assert_eq(moved, [],
		"a declared-wide family's spread MOVED, so the ledger no longer matches the tree — re-measure and update WIDE_PENDING in the same commit: %s" % [moved])
	assert_eq(wide, [],
		"these variant families jump more than %.1f LU between members, so the cue is a random level change rather than a texture change: %s" % [LIMIT, wide])


func test_the_heal_family_is_the_repaired_one() -> void:
	## Named, because the arm above is satisfied by `ability_heal` being ABSENT. It was the defect
	## that produced this file and its repair is what the arm's threshold was chosen against.
	var fx := _fixture()
	assert_true(fx.has("ability_heal"), "ability_heal is no longer a variant family — re-point this arm")
	if not fx.has("ability_heal"):
		return
	var row: Dictionary = fx["ability_heal"]
	assert_false(bool(row.get("unmeasurable", false)), "ability_heal became unmeasurable; it was 7.2 LU apart and measurable")
	assert_lt(float(row.get("spread", 99.0)), LIMIT,
		"ability_heal is back over %.1f LU — Cure plays one of three cues at random and they no longer match" % LIMIT)
	assert_false(WIDE_PENDING.has("ability_heal"),
		"ability_heal is declared WIDE again; it was repaired, so a declaration here would hide a regression")


func test_the_unmeasurable_families_are_named_not_passed() -> void:
	## ⛔ EBU R128 is undefined below ~0.4s and FLOORS at -70, so all six footstep families read
	## -70/-70/-70. A spread computed from three floored values is 0.0 — the most confident wrong
	## answer this instrument can give, and it would read as "perfectly matched". The tool marks them
	## unmeasurable; this pins that it still does, so they can never pass as level-matched.
	var fx := _fixture()
	var floored: Array[String] = []
	for name in fx.keys():
		var row: Dictionary = fx[name]
		if bool(row.get("unmeasurable", false)):
			floored.append(str(name))
	assert_gt(floored.size(), 0,
		"no family is marked unmeasurable, but the six footstep families are all under 0.4s — either the tool stopped detecting the R128 floor, or it is now reporting a 0.0 spread for three floored values")
