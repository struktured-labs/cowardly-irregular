extends GutTest

## The free-engine voice packs were never loudness-normalised and the ElevenLabs one is. Measured
## EBU R128 integrated loudness over 654 clips, 2026-10-12:
##   fighter (ElevenLabs)  n= 50  median -18.0  p5..p95 spread 0.4 LU   <- the existence proof
##   rogue                 n=151  median -16.4  spread 3.5 LU
##   mage                  n=151  median -16.8  spread 4.4 LU
##   cleric                n=151  median -18.5  spread 4.2 LU
##   bard                  n=151  median -16.9  spread 4.6 LU
##
## Two defects in one measurement: up to 4.6 LU between two lines of the SAME voice, and a 2.1 LU
## offset between pack medians — so the Cleric is systematically quieter than the Rogue in a party
## where both speak, and a quiet line can be lost under battle SFX.
##
## Fixed by a per-line `gain_db` in the manifest rather than a re-render: struktured approved these
## clips BY EAR, so changing their level is one JSON field per clip and reverts by deleting it, where
## re-encoding 604 approved files would not. Verified INDEPENDENTLY — gain applied to the audio and
## re-measured, 43 clips stratified across packs: median -18.0, spread 0.5 LU, 0 clips more than
## 0.6 LU off target. (My first "verification" added the gain back to the number it was derived from,
## which is circular and proved only my own arithmetic.)
##
## This file cannot measure loudness — GDScript has no meter — so it guards the MECHANISM and the
## invariants a wrong write would break. The loudness claim is `tools/voice_level_trim.py --selftest`
## and the measurement above.

const MANIFEST := "res://data/sfx_manifest.json"
const SM := "res://src/audio/SoundManager.gd"
const TOOL := "res://tools/voice_level_trim.py"
const MAX_ABS_GAIN := 6.0


func _sfx() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary and (parsed as Dictionary).has("sfx"), "VOID: manifest did not parse")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


func test_the_player_actually_reads_the_per_line_gain() -> void:
	## Without this the 613 gains are inert data and every arm below still passes — the manifest
	## would describe a level nothing applies, which is worse than no gain at all because it reads
	## as solved.
	var src := FileAccess.get_file_as_string(SM)
	assert_gt(src.length(), 0, "VOID: SoundManager.gd read empty")
	assert_true(src.contains("get(\"gain_db\", 0.0)"),
		"play_voice no longer reads gain_db off the manifest entry, so every per-line level in the manifest is inert")
	assert_true(src.contains("VOICE_PLAYER_BASE_DB + gain"),
		"the gain is read but not APPLIED to the voice player's level — it must offset the channel base, or the manifest describes a level nothing performs")


func test_the_gains_are_in_a_plausible_range() -> void:
	## A gain outside +/-6 dB is a bad render rather than a level problem, and the tool caps there.
	## A wrong write (a stray unit, a sign flip) lands outside this band.
	var sfx := _sfx()
	var gained := 0
	var wild: Array[String] = []
	for key in sfx:
		var e: Dictionary = sfx[key]
		if not e.has("gain_db"):
			continue
		gained += 1
		var g: float = float(e["gain_db"])
		if absf(g) > MAX_ABS_GAIN + 0.01:
			wild.append("%s %+.1f" % [key, g])
	assert_gt(gained, 500,
		"VOID: only %d entries carry a gain_db — 613 were written, so either the write was lost or this arm is checking almost nothing" % gained)
	assert_eq(wild, [],
		"these gains are outside +/-%.1f dB, which is a bad render rather than a level problem: %s" % [MAX_ABS_GAIN, wild])


func test_only_voice_lines_carry_a_gain() -> void:
	## The field is read ONLY by play_voice. A gain_db on a battle or UI cue would be silently
	## ignored, which is the "data describing a level nothing applies" failure one surface over.
	var sfx := _sfx()
	var strays: Array[String] = []
	for key in sfx:
		if (sfx[key] as Dictionary).has("gain_db") and not str(key).begins_with("voice_"):
			strays.append(str(key))
	assert_eq(strays, [],
		"these non-voice cues carry a gain_db that nothing reads — only play_voice applies it: %s" % strays)


## ⛔ `voice_blip_*` SHARES THE PREFIX AND IS A DIFFERENT ASSET CLASS. The arm above excludes
## non-`voice_` cues and would pass if a future levelling pass gained the blips — @cowir-deploy
## censused the shipped tree and found the partition exact: 654 mono LINE entries (613 gained + 41
## at target) and 6 STEREO blips, consumed by CutsceneDialogue._voice_blip_player per speaker.
##
## The mono premise the 613 gains rest on holds for the 654 and NOT for the 6, and @cowir-music
## measured why that matters: on a stereo asset, all-samples RMS and channel-averaged RMS diverge by
## ~0 dB where the channels are correlated and ~6 dB where they are not. So a pass that widened from
## "voice_ LINE entries" to "the voice_ PREFIX" would silently measure 6 files with an instrument
## whose assumption no longer applies — and the widening is the easy mistake, because the prefix is
## the obvious way to name the set.
func test_the_stereo_blips_are_not_in_the_levelled_set() -> void:
	var sfx := _sfx()
	var gained_blips: Array[String] = []
	var blips := 0
	for key in sfx:
		if not str(key).begins_with("voice_blip_"):
			continue
		blips += 1
		if (sfx[key] as Dictionary).has("gain_db"):
			gained_blips.append(str(key))
	assert_gt(blips, 0,
		"VOID: no voice_blip_* entries found, so this arm is not guarding the boundary it describes")
	assert_eq(gained_blips, [],
		"these text-advance blips carry a gain_db: they are STEREO and a different asset class, so the mono premise the 613 line gains were measured under does not hold for them. If blips are to be levelled, meter them channel-averaged and say so: %s" % gained_blips)


func test_the_tool_and_the_engine_agree_on_the_channel_base() -> void:
	## ⛔ THE CROSS-FILE INVARIANT, and the one a future edit will break: every gain was computed
	## against the voice player's base level, because the headroom for a positive gain is
	## `peak + BASE`. Change VOICE_PLAYER_BASE_DB and all 613 gains are computed against a base
	## that no longer exists — quiet lines stay quiet, and a loud one can clip. Two files, one
	## number, and nothing else would notice.
	var src := FileAccess.get_file_as_string(SM)
	var tool_src := FileAccess.get_file_as_string(TOOL)
	assert_gt(tool_src.length(), 0, "VOID: voice_level_trim.py is gone — the gains have no derivation")
	var m := RegEx.create_from_string("VOICE_PLAYER_BASE_DB:\\s*float\\s*=\\s*(-?[0-9.]+)")
	var e := m.search(src)
	assert_not_null(e, "VOID: could not read VOICE_PLAYER_BASE_DB from SoundManager")
	if e == null:
		return
	var t := RegEx.create_from_string("BASE_DB\\s*=\\s*(-?[0-9.]+)")
	var te := t.search(tool_src)
	assert_not_null(te, "VOID: could not read BASE_DB from the tool")
	if te == null:
		return
	assert_eq(float(e.get_string(1)), float(te.get_string(1)),
		"SoundManager's VOICE_PLAYER_BASE_DB (%s) and the tool's BASE_DB (%s) disagree — every gain in the manifest was computed against the tool's value, so the peak headroom they assume is wrong. Re-run `tools/voice_level_trim.py --apply` after changing either." % [e.get_string(1), te.get_string(1)])


func test_the_fighter_pack_is_the_reference_and_barely_moves() -> void:
	## The argument for the whole change: the ElevenLabs pack already sat in a 0.4 LU band, so its
	## gains are near zero while the free packs needed real correction. If the Fighter's gains ever
	## grow large, either the target moved or that pack stopped being the reference — both worth a
	## look, and neither visible from the range arm above.
	var sfx := _sfx()
	var big: Array[String] = []
	var n := 0
	for key in sfx:
		if not str(key).begins_with("voice_fighter_"):
			continue
		var g: float = float((sfx[key] as Dictionary).get("gain_db", 0.0))
		n += 1
		if absf(g) > 2.0:
			big.append("%s %+.1f" % [key, g])
	assert_gt(n, 40, "VOID: only %d fighter clips found; the pack was 50" % n)
	assert_eq(big, [],
		"the ElevenLabs pack needs gains over 2 dB, so it is no longer the 0.4 LU reference the target was taken from: %s" % big)
