extends GutTest

## A VARIANT MUST VARY TEXTURE, NOT LEVEL. `_try_play_sfx_from_manifest` picks uniformly from
## `[base] + variants`, so every member is equally likely on any play. If they differ in loudness the
## player hears a random level jump on one of the most repeated sounds in the game — which reads as a
## mix bug rather than as variety, and is invisible to every existing guard because they check that a
## cue RESOLVES, never what it resolves AT.
##
## Found by @cowir-music on `ability_heal` and handed over: Cure plays one of three cues at random,
## 7.2 LU apart, with all three prompts authoring the same "soft" character.
##
## ⛔ THIS FILE MEASURES AND DECLARES. IT REPAIRS NOTHING, AND THAT IS A RULING RATHER THAN CAUTION.
## I built the repair — pull v2/v3 down to the base — and @cowir-main held it: the quiet member as
## the target makes Cure ~7 dB quieter on two casts in three, a change to one of the most-heard cues
## in a family struktured has ruled on by ear more than once. **The brief saying "soft" settles
## CHARACTER, not which of three levels he has been hearing and accepting.** That is the same call I
## correctly declined to make for buff/debuff/ice/heal, and I then made it for the fifth family —
## the inconsistency was mine. Four options are with him: pull the variants down, raise the base,
## meet in the middle, or leave it. Until then every wide family is declared, none is repaired.
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
## ⛔ TWO NUMBERS PER FAMILY, BECAUSE THE WEB BUILD SHIPS MONO. make_web_audio.sh:121 transcodes
## every master with `-ac 1`, so wherever a family mixes channel counts its spread DIFFERS BY
## PLATFORM — and NO FLAT GAIN FIXES BOTH TIERS. Matching ability_heal on desktop (-7.2 on the
## variants) leaves the web build mismatched ~5.5 dB the other way.
##   [desktop LUFS as-is, web LUFS mono-downmixed]
const WIDE_PENDING := {
	## @cowir-music's find. Repair held at 415e433fc; a fifth option exists that none of
	## @cowir-main's four covers — make the channel counts consistent, which is a content change.
	"ability_heal": [7.2, 3.4],
	"buff": [7.0, 3.9],
	## wide on DESKTOP only; the mono tier is inside the limit
	"debuff": [6.1, 3.0],
	## all-mono, so the two tiers agree — a flat gain WOULD fix this one on both
	"ability_ice": [5.2, 5.2],
	## ⛔ THE ONE THAT GETS WORSE ON WEB: 5.2 desktop, 9.9 MONO. All-stereo members with different
	## stereo widths, so the downmix pushes them APART. Nobody had seen this; it is the largest
	## variant mismatch in the bank and it only exists in the shipped web build.
	"heal": [5.2, 9.9],
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
		var spread_mono: float = float(row.get("spread_mono", -1.0))
		if WIDE_PENDING.has(name):
			var want: Array = WIDE_PENDING[name]
			if absf(spread - float(want[0])) > 0.15:
				moved.append("%s desktop declared %.1f, measured %.1f" % [name, float(want[0]), spread])
			if spread_mono >= 0.0 and absf(spread_mono - float(want[1])) > 0.15:
				moved.append("%s WEB declared %.1f, measured %.1f" % [name, float(want[1]), spread_mono])
			continue
		if spread > LIMIT:
			wide.append("%s %.1f LU" % [name, spread])
	assert_eq(moved, [],
		"a declared-wide family's spread MOVED, so the ledger no longer matches the tree — re-measure and update WIDE_PENDING in the same commit: %s" % [moved])
	assert_eq(wide, [],
		"these variant families jump more than %.1f LU between members, so the cue is a random level change rather than a texture change: %s" % [LIMIT, wide])


func test_the_heal_family_is_the_open_case_and_still_measures_what_was_reported() -> void:
	## Named rather than left to the ledger loop, because this is the family that produced the file
	## and the one a decision is pending on. It pins the REPORTED number: if the assets change — by a
	## ruling, or by a regeneration nobody announced — this arm reds and names the new spread, which
	## is what makes the held branch and this ledger stay in step.
	var fx := _fixture()
	assert_true(fx.has("ability_heal"), "ability_heal is no longer a variant family — re-point this arm")
	if not fx.has("ability_heal"):
		return
	var row: Dictionary = fx["ability_heal"]
	assert_false(bool(row.get("unmeasurable", false)),
		"ability_heal became unmeasurable; it was 7.2 LU apart and measurable, so the instrument changed rather than the assets")
	assert_almost_eq(float(row.get("spread_mono", -1.0)), 3.4, 0.15,
		"ability_heal's WEB spread moved off 3.4 LU. The web build ships mono, so this is the number a browser player hears and it is tracked separately from desktop's 7.2")
	assert_almost_eq(float(row.get("spread", -1.0)), 7.2, 0.15,
		"ability_heal's spread moved off the 7.2 LU that was reported to struktured. If this is his ruling landing, update WIDE_PENDING (or remove the family from it) in the same commit as the assets")
	assert_true(WIDE_PENDING.has("ability_heal"),
		"ability_heal left the ledger while its spread is still wide, which is how an open decision becomes an unguarded one")


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


## ⛔ THE CONTROL ON THE DOWNMIX ITSELF, guarding the bug that cost @cowir-music two retracted
## numbers on 2026-10-13: `pan=mono|c0=0.5*c0+0.5*c1` on a MONO input references a channel that does
## not exist and silently halves amplitude — a flat -6.02 dB that looks like a real measurement.
##
## ⚠️ COMPARED PER MEMBER, NOT PER SPREAD, AND THAT CORRECTION CAME FROM A SURVIVING MUTATION. My
## first version compared the family's as-is spread against its downmixed spread — and a UNIFORM
## -6.02 dB on every member leaves the spread IDENTICAL, so the arm could not see the very bug its
## comment claimed to guard. It passed the mutation; the ledger arms caught it instead, via the
## mixed-channel families where the per-member shifts differ. A spread is a difference, and a
## difference is blind to anything applied equally to both sides.
func test_the_downmix_is_a_no_op_on_every_mono_member() -> void:
	var fx := _fixture()
	var checked := 0
	var broken: Array[String] = []
	for name in fx.keys():
		var row: Dictionary = fx[name]
		if bool(row.get("unmeasurable", false)):
			continue
		var members: Dictionary = row.get("members", {})
		for m in members.keys():
			var mem: Dictionary = members[m]
			if int(mem.get("ch", 0)) != 1:
				continue
			var a: float = float(mem.get("lufs", -999.0))
			var b: float = float(mem.get("lufs_mono", -998.0))
			checked += 1
			if absf(a - b) > 0.05:
				broken.append("%s %.1f -> %.1f" % [m, a, b])
	assert_gt(checked, 5,
		"CONTROL: only %d mono members checked, so this arm cannot see a downmix regression" % checked)
	assert_eq(broken, [],
		"the downmix is NOT a no-op on these MONO members, so the tool is running pan=mono on a mono input and halving amplitude by ~6 dB — every web figure it reports is wrong by that much: %s" % [broken])
