extends GutTest

## REVERSE orphan audit (cycle #13) — manifest keys that NOTHING plays.
##
## test_sfx_key_orphan_audit.gd covers the FORWARD direction: code asks for a
## key that doesn't exist (silent miss). This covers the reverse: a key exists
## that no code path can ever reach (dead asset). Both directions are needed —
## the forward audit was green for months while `enemy_death_industrial` sat
## unreachable because its name didn't fit the wN_<base> world-variant scheme.
##
## THE HARD PART IS AVOIDING FALSE POSITIVES, and it is the reason a naive
## version of this test would be actively harmful. A literal source grep
## reports 52 orphans; 39 of those are real consumers the grep can't see:
##
##   1. DYNAMIC KEY CONSTRUCTION — play_status() does "status_" + name, so no
##      status_* key ever appears literally in source. Same for attack_hit_*,
##      advance_*, footstep_*, formation_*, voice_*, and the wN_ world-variant
##      prefixes. NOT ability_* or strike_*: this line listed both for months
##      and both are wrong — see the DYNAMIC_PREFIXES note below.
##   2. data/ JSON CONSUMERS — cutscene and quest JSON name SFX keys directly.
##      Source-only scanning misses every one (39 keys here).
##   3. fallback_to CHAINS — a key reached only as another key's fallback.
##
## Someone "cleaning up" against a naive scan would delete live audio. Treat
## the resolver below as the deliverable and the assertion as its wrapper.

const MANIFEST_PATH := "res://data/sfx_manifest.json"

## Prefixes whose keys are built at runtime by string concatenation. If the
## GUARD pattern appears in SoundManager source, every key with that prefix is
## considered reachable. Keep GUARDs tied to the actual construction site so a
## refactor that removes the concatenation also drops the exemption.
##
## EVERY ENTRY MUST BE LOAD-BEARING — test_every_dynamic_prefix_exemption_is_load_bearing
## reds on one that exempts nothing. Three were removed 2026-09-11 for failing it, and the
## two dispositions behind that number are worth keeping apart, because "exempts 0 keys"
## does not distinguish them:
##   FALSE  `ability_` and `night_` claimed a concatenation that does not exist. Every
##          reachable ability_ cue is a literal in _ability_sounds / _ELEMENT_SFX / _TYPE_SFX
##          (_derive_ability_sounds_from_data picks from those tables, it does not build a
##          key), and night_ names a const, not a construction. Both would have exempted a
##          genuinely dead key in the largest cue family we have open questions about.
##   TRUE   `strike_` is real -- SoundManager builds "strike_" + element -- and was merely
##          redundant, every strike_ key also being a literal in EffectSystem. Removed
##          anyway, under the policy below.
##
## The policy, and why removing a TRUE-but-redundant entry is safe: an exemption that
## suppresses nothing cannot be observed to be wrong. `night_` sat here for months being
## false, and nothing could have shown that while it was also inert. Delete it and the day a
## non-literal key lands the audit REDS, loudly, naming the key -- and the entry comes back
## with the key that needs it. That is why the unreachable message below names re-adding a
## prefix as a disposition: without it, a correct new strike_ cue reads as a dead asset.
##
## ⚠️ ONE COUPLING, so the next red is not a mystery: `ambient_` is load-bearing on exactly one
## key, `ambient_village` (42 KB, no reference in src/, data/ or any .tscn — struktured's call,
## wire it or delete it). Every other ambient_ cue is also a source literal. Resolve that orphan
## either way and `ambient_` goes inert, and the arm below reds on a prefix nobody touched.
const DYNAMIC_PREFIXES := {
	"status_": "\"status_\" +",
	"attack_hit_": "attack_hit_",
	"advance_": "advance_%s",
	"footstep_": "\"footstep_\" +",
	"formation_": "formation_key",
	"voice_": "voice_",
	"w2_": "_get_world_sfx_prefix",
	"w3_": "_get_world_sfx_prefix",
	"w4_": "_get_world_sfx_prefix",
	"w5_": "_get_world_sfx_prefix",
	"w6_": "_get_world_sfx_prefix",
	"ambient_": "play_ambient(",
}

## Keys with no consumer TODAY that are deliberately staged ahead of a named
## owner. Every entry needs the owner and what they're waiting on — an entry
## with no owner is just a dead asset wearing a costume.
const KNOWN_PENDING_CONSUMER := {
	# cowir-battle: contact-frame seam (their cycle, confirmed msg 2910)
	"thump_light": "cowir-battle contact-frame seam",
	"thump_med": "cowir-battle contact-frame seam",
	"thump_heavy": "cowir-battle contact-frame seam",
	"thump_crit": "cowir-battle contact-frame seam",
	# pre-staged before ON_HIT_STATUSES grows (cowir-battle ratchet, msg 2797)
	"status_burn": "pre-staged for future burn_chance weapon proc",
	"status_freeze": "pre-staged for future freeze_chance weapon proc",
	# cowir-battle: W6 Arbiter-duel win-condition arms (msg 3223/3226) — spec
	# still moving; shipped inert so the cues exist when the signal lands.
	"duel_answer_dodge": "cowir-battle W6 Arbiter duel arms",
	"duel_answer_block": "cowir-battle W6 Arbiter duel arms",
	"duel_answer_strike": "cowir-battle W6 Arbiter duel arms",
	# The EXP-bar ramp is the ONE part of the victory kit still unwired. The voice-topology
	# ruling (cowir-main 2026-08-19) resolved the other four and they have left this list.
	# The ramp's blocker is different and was never the voice: wiring it replaces the flat
	# exp_tick at VictoryOverlay._animate_card_content with tier selection across the
	# roll-up, which changes how the EXP fill SOUNDS on a surface struktured locked on
	# 2026-08-18. Needs his call, not a routing decision.
	"exp_bar_tick_ramp_lo": "struktured — EXP fill feel, locked surface 2026-08-18",
	"exp_bar_tick_ramp_mid": "struktured — EXP fill feel, locked surface 2026-08-18",
	"exp_bar_tick_ramp_hi": "struktured — EXP fill feel, locked surface 2026-08-18",
}


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "should be readable: %s" % path)
	var t := f.get_as_text()
	f.close()
	return t


## Files that DEFINE the audio key space rather than consume it. Both must be excluded from the
## consumer corpus: a definer in the corpus certifies its own keys as reachable. sfx_manifest is
## obvious; music_manifest is NOT, and it is the one four lanes tripped on 2026-09-09 — audio keys
## have TWO definers, and 4 keys (ambient_cave/forest/village, victory) exist in both stores with
## DIFFERENT files. Today this changes nothing (the ambient_ dynamic prefix covers the only
## affected key), so it is preventive: the day an SFX key coincides with a new track name, the
## audit would silently certify it against a file that can never play it.
const KEY_SPACE_DEFINERS: Array[String] = ["sfx_manifest.json", "music_manifest.json"]


func _slurp_dir(root: String, ext: String, skip_file: String = "") -> String:
	## Concatenate every file under root with the given extension.
	var out := ""
	var dirs: Array[String] = [root]
	while not dirs.is_empty():
		var cur: String = dirs.pop_back()
		var d := DirAccess.open(cur)
		if d == null:
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			var full := cur.path_join(name)
			if d.current_is_dir():
				if not name.begins_with("."):
					dirs.append(full)
			elif name.ends_with(ext) and name != skip_file and not KEY_SPACE_DEFINERS.has(name):
				## A key named ONLY in a comment is not a consumer, and this audit fails toward
				## SILENCE — a phantom consumer suppresses a real orphan. MEASURED 2026-09-12:
				## src/ is 22.8% comment and 0 of 338 keys flip when stripped, so this is
				## preventive today, exactly like KEY_SPACE_DEFINERS above. JSON has no comments,
				## so only .gd is stripped.
				out += _code_only(_read(full), "") if ext == ".gd" else _read(full)
			name = d.get_next()
		d.list_dir_end()
	return out


func _fallback_targets(sfx: Dictionary) -> Dictionary:
	var targets := {}
	for k in sfx:
		var ft: String = str(sfx[k].get("fallback_to", ""))
		if ft != "":
			targets[ft] = true
		var vars_v: Variant = sfx[k].get("variants", [])
		if vars_v is Array:
			for v in (vars_v as Array):
				targets[str(v)] = true
	return targets


func _unreachable(sfx: Dictionary, fallback_targets: Dictionary, all_text: String,
		src_text: String, active_prefixes: Array) -> Array[String]:
	## The resolver, parameterised by WHICH dynamic prefixes are in play. The backward arm
	## re-runs it with one prefix withheld; sharing the function is the point, because a
	## second copy would drift and then measure a resolver nobody ships.
	var out: Array[String] = []
	for key_variant in sfx.keys():
		var key: String = str(key_variant)
		if fallback_targets.has(key):
			continue
		# literal reference anywhere in src/ or data/
		if all_text.contains("\"%s\"" % key) or all_text.contains("'%s'" % key):
			continue
		# runtime-constructed via a live concatenation site
		var dynamic := false
		for prefix in active_prefixes:
			if key.begins_with(prefix) and src_text.contains(DYNAMIC_PREFIXES[prefix]):
				dynamic = true
				break
		if dynamic:
			continue
		if KNOWN_PENDING_CONSUMER.has(key):
			continue
		out.append(key)
	return out


func test_no_unreachable_sfx_keys() -> void:
	var parsed: Variant = JSON.parse_string(_read(MANIFEST_PATH))
	assert_true(parsed is Dictionary and parsed.has("sfx"), "manifest must parse to {sfx:{...}}")
	var sfx: Dictionary = parsed["sfx"]

	var src_text := _slurp_dir("res://src", ".gd")
	var data_text := _slurp_dir("res://data", ".json", "sfx_manifest.json")
	var all_text := src_text + data_text

	## fallback_to targets are reachable via the fallback chain, and VARIANTS are a second
	## live mechanism this audit did not model: _try_play_sfx_from_manifest picks randomly from
	## [base] + base.variants, so a variant is played whenever its BASE is played. Six of them
	## (buff/debuff/heal _v2/_v3) were carried in KNOWN_PENDING_CONSUMER instead, described as
	## "unwired alternate take" — which was FALSE. They are wired, by rotation. An allowlist
	## entry whose stated reason is untrue is worse than no entry: it reads as a decision and it
	## cannot expire, because the condition it names never held. Modelling the mechanism also
	## covers every FUTURE variant with no list to maintain.
	var fallback_targets := _fallback_targets(sfx)

	var unreachable := _unreachable(sfx, fallback_targets, all_text, src_text, DYNAMIC_PREFIXES.keys())

	assert_eq(unreachable.size(), 0,
		("UNREACHABLE SFX keys — %d asset(s) nothing can ever play: %s\n" +
		"FOUR dispositions, and the fourth is the one this message used to omit:\n" +
		"  1. wire a consumer;\n" +
		"  2. if the key is BUILT at runtime, add its prefix to DYNAMIC_PREFIXES with the " +
		"construction site as the guard — a correct new cue in a concatenated family lands " +
		"here, and reads exactly like a dead asset if you do not know to look;\n" +
		"  3. add to KNOWN_PENDING_CONSUMER with the owner and what they're waiting on;\n" +
		"  4. delete the asset.\n" +
		"Do NOT add an entry without a named owner — that just hides a dead asset.") % [unreachable.size(), unreachable])


func test_the_consumer_corpus_excludes_every_definer() -> void:
	## @cowir-story's precondition, applied to this file: name every DEFINER of the key space —
	## plural — and assert it is disjoint from the CONSUMER corpus. A definer inside the corpus
	## makes its own keys look consumed, which is guaranteed-zero rather than measured-zero.
	##
	## The arm that matters is music_manifest: it is a definer of the SAME key space and reads as
	## an ordinary data file. Excluding only the obvious one is the mistake this catches.
	## ⛔ DELIBERATELY NOT KEY_SPACE_DEFINERS. Looping the constant that drives the exclusion makes
	## this guard move WITH the bug: delete music_manifest from that list and the loop stops
	## checking it, so the arm scores green. Measured — that is exactly what happened on the first
	## attempt. The subject list has to be independent of the mechanism under test.
	const DEFINERS_ON_DISK: Array[String] = ["sfx_manifest.json", "music_manifest.json"]
	var corpus := _slurp_dir("res://data", ".json", "sfx_manifest.json")
	for definer in DEFINERS_ON_DISK:
		var text := _read("res://data/" + definer)
		assert_ne(text, "", "control: %s unreadable — the check below cannot fail honestly" % definer)
		if text == "":
			continue
		## A long, distinctive slice: if the definer leaked into the corpus this is present verbatim.
		var probe := text.substr(0, 240)
		assert_false(corpus.contains(probe),
			"%s is a DEFINER of the audio key space and is inside the consumer corpus — every key it names reads as consumed" % definer)
	## CONTROL: the corpus must still hold a real consumer, or the assertions above pass by being empty.
	assert_gt(corpus.length(), 5000,
		"control: the consumer corpus is only %d chars — the exclusion took the whole directory with it" % corpus.length())


func test_the_definer_list_is_actually_exhaustive() -> void:
	## ⛔ THE PREDICATE ABOVE SAYS "EVERY DEFINER" AND THE INSTRUMENT CHECKS A TWO-ITEM LITERAL.
	## That is the shape cowir-main named on 2026-09-09 after publishing a sweep predicate ("orphaned
	## = unreachable by ANY path") phrased more broadly than the scanner under it: broad wording
	## READS AS A SAFETY MARGIN and deters anyone from interrogating the code, so it conceals the gap
	## instead of merely failing to describe it.
	##
	## So this DISCOVERS definers rather than trusting the list. A definer is a data/*.json holding a
	## dict whose entries carry a `file` pointing into assets/audio/ — the manifest shape. Add a
	## third audio manifest and this reds until it is listed, which is what makes "every" true.
	var found: Array[String] = []
	var dir := DirAccess.open("res://data")
	assert_not_null(dir, "res://data unreadable — this guard would pass by finding nothing")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var parsed: Variant = JSON.parse_string(_read("res://data/" + fname))
			if parsed is Dictionary:
				for top in (parsed as Dictionary).keys():
					var section: Variant = (parsed as Dictionary)[top]
					if not (section is Dictionary) or (section as Dictionary).size() < 20:
						continue
					var audio_entries := 0
					for k in (section as Dictionary).keys():
						var e: Variant = (section as Dictionary)[k]
						if e is Dictionary and str((e as Dictionary).get("file", "")).begins_with("assets/audio/"):
							audio_entries += 1
					if audio_entries >= 20 and not found.has(fname):
						found.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()

	found.sort()
	assert_gte(found.size(), 2,
		"control: discovered %d audio-key definers — expected at least sfx_manifest.json and music_manifest.json, so the scan is broken and the comparison below is vacuous" % found.size())
	for f in found:
		assert_true(KEY_SPACE_DEFINERS.has(f),
			"%s DEFINES audio keys and is not in KEY_SPACE_DEFINERS — it is sitting in the consumer corpus, so every key it names reads as consumed. Add it to that list." % f)


func test_pending_consumer_allowlist_has_not_rotted() -> void:
	## Guarantee 2: once something IS wired, it must leave the allowlist —
	## otherwise the list silently becomes a graveyard nobody rereads.
	var parsed: Variant = JSON.parse_string(_read(MANIFEST_PATH))
	var sfx: Dictionary = parsed["sfx"]
	var src_text := _slurp_dir("res://src", ".gd")
	var data_text := _slurp_dir("res://data", ".json", "sfx_manifest.json")
	var all_text := src_text + data_text

	var now_wired: Array[String] = []
	var vanished: Array[String] = []
	for key in KNOWN_PENDING_CONSUMER:
		if not sfx.has(key):
			vanished.append(key)
			continue
		if all_text.contains("\"%s\"" % key) or all_text.contains("'%s'" % key):
			now_wired.append(key)

	assert_eq(now_wired.size(), 0,
		"KNOWN_PENDING_CONSUMER entries that now HAVE a consumer — remove them (%d): %s" % [now_wired.size(), now_wired])
	assert_eq(vanished.size(), 0,
		"KNOWN_PENDING_CONSUMER entries no longer in the manifest — remove them (%d): %s" % [vanished.size(), vanished])


func test_world_variant_keys_use_the_prefix_shape() -> void:
	## Cycle #13 root cause: enemy_death_industrial used base_<world> while the
	## resolver builds wN_<base>, so it was unreachable from the day it landed.
	## Pin the shape — a suffix-named world variant is a silent dead asset.
	const WORLD_WORDS := ["medieval", "suburban", "steampunk", "industrial", "digital", "abstract"]
	var parsed: Variant = JSON.parse_string(_read(MANIFEST_PATH))
	var sfx: Dictionary = parsed["sfx"]

	var wrong_shape: Array[String] = []
	for key_variant in sfx.keys():
		var key: String = str(key_variant)
		for w in WORLD_WORDS:
			if key.ends_with("_" + w):
				wrong_shape.append(key)
				break

	assert_eq(wrong_shape.size(), 0,
		("World-variant SFX keys using base_<world> instead of wN_<base> (%d): %s\n" +
		"_get_world_sfx_prefix() builds wN_<base>, so a suffix-shaped key can never " +
		"be resolved — it will never play. Rename to the wN_ form.") % [wrong_shape.size(), wrong_shape])

func test_dynamic_prefix_exemptions_are_backed_by_live_behaviour() -> void:
	## cowir-ai msg-3319: a source-text pin is a claim about the code's SPELLING,
	## written where we meant its BEHAVIOUR. test_no_unreachable_sfx_keys exempts
	## every status_/ability_/footstep_ key on the strength of a construction
	## string appearing in SoundManager. Mutation-tested 2026-07-29: neutering
	## play_status with an early return, while leaving `"status_" +` in the file,
	## left that guard GREEN — it cannot tell reachable from unreachable.
	##
	## This does not prove reachability in general (that wants a call graph).
	## It proves the exemption's PREMISE for the largest prefix families: the
	## dispatcher actually resolves a real manifest key when called.
	var sm: Node = get_node_or_null("/root/SoundManager")
	assert_true(sm != null, "SoundManager autoload present")

	## PREMISE, asserted rather than trusted (cowir-story msg-3384 class): every
	## resolution assert below reads "the cooldown got stamped" as "the key resolved".
	## That inference holds ONLY because the stamp sits AFTER the manifest-presence
	## check in _try_play_sfx_from_manifest. Move it earlier — a plausible refactor,
	## "stamp regardless so we don't retry a missing key every frame" — and EVERY key
	## stamps, including ones the manifest has never heard of. The asserts below would
	## then pass for an unresolvable key and this guard would go on printing green
	## while proving nothing. That is an INVERSION, not staleness: it does not rot
	## into a false claim, it rots into no claim at all.
	var phantom: String = "definitely_not_a_real_status_key"
	sm._sfx_cooldowns.erase("status_" + phantom)
	assert_false(sm._sfx_manifest.has("status_" + phantom),
		"control: the phantom key must genuinely be absent for this premise test to mean anything")
	sm.play_status(phantom)
	assert_false(sm._sfx_cooldowns.has("status_" + phantom),
		"PREMISE BROKEN: a manifest MISS stamped a cooldown. The stamp no longer implies resolution, so every assert below this line is vacuous — fix the ordering in _try_play_sfx_from_manifest, or replace the resolution asserts with a different instrument.")

	## _sfx_cooldowns lives on the AUTOLOAD and persists for the whole GUT run, so
	## an earlier test that played these keys would satisfy the asserts below
	## whether or not THIS call resolved anything. Erasing first is what makes the
	## stamp evidence of this call. Found 2026-07-29 while auditing my own assert
	## messages: this guard replaced a spelling pin and had a latent vacuity of its
	## own, differing only in what it would have passed for.
	sm._sfx_cooldowns.erase("status_poison")
	for k in sm._sfx_cooldowns.keys():
		if str(k).ends_with("ability_fire"):
			sm._sfx_cooldowns.erase(k)

	# status_: play_status must reach a manifest key, not merely contain the string.
	sm.stop_ambient()
	var before: String = sm._current_ambient_key
	assert_true(sm._sfx_manifest.has("status_poison"), "control: status_poison exists to be found")
	assert_false(sm._sfx_cooldowns.has("status_poison"),
		"control: cooldown cleared, so a stamp below can only come from this call")
	sm.play_status("poison")
	assert_true(sm._sfx_cooldowns.has("status_poison"),
		"play_status('poison') must RESOLVE status_poison — cooldown is stamped only on a manifest hit")

	# ability_: play_ability resolves through _ability_sounds to a real key.
	assert_true(sm._sfx_manifest.has("ability_fire"), "control: ability_fire exists")
	sm.play_ability("fire")
	# World-agnostic: play_ability prefixes by CURRENT world, so a prior test
	# leaving the world at W3-W6 resolves w3_/w4_/w5_/w6_ability_fire. Naming
	# only the W1/W2 forms made this pass alone and fail in the full suite.
	var hit_fire := false
	for k in sm._sfx_cooldowns:
		if str(k).ends_with("ability_fire"):
			hit_fire = true
			break
	assert_true(hit_fire, "play_ability('fire') must RESOLVE some ability_fire variant (any world prefix)")

	assert_eq(before, "", "ambient state untouched by this test")


func test_every_dynamic_prefix_exemption_is_load_bearing() -> void:
	## THE BACKWARD ARM. KNOWN_PENDING_CONSUMER has had one since it was written
	## (test_pending_consumer_allowlist_has_not_rotted): once a key is wired, it must
	## LEAVE the list. DYNAMIC_PREFIXES — the other exemption table in this file, and
	## the broader one, since each entry exempts a whole family — had only the forward
	## question, "is this explained?" An exemption table needs BOTH directions, and the
	## missing one is what let `night_` sit here claiming a concatenation that never
	## existed: nothing can observe an exemption being wrong while it is also inert.
	##
	## The instrument is delete-the-entry, per prefix: withhold it and re-run the real
	## resolver. If the unreachable set does not grow, the entry suppressed nothing.
	var parsed: Variant = JSON.parse_string(_read(MANIFEST_PATH))
	assert_true(parsed is Dictionary and parsed.has("sfx"), "manifest must parse to {sfx:{...}}")
	var sfx: Dictionary = parsed["sfx"]
	var src_text := _slurp_dir("res://src", ".gd")
	var data_text := _slurp_dir("res://data", ".json", "sfx_manifest.json")
	var all_text := src_text + data_text
	var fallback_targets := _fallback_targets(sfx)
	var all_prefixes: Array = DYNAMIC_PREFIXES.keys()

	## CONTROLS, in the order they can lie. The corpus first: an empty src_text makes every
	## guard string absent, so no prefix exempts anything and EVERY entry reads as inert —
	## a wrong-shape unanimous verdict rather than a finding.
	assert_gt(src_text.length(), 100000,
		"control: src corpus is %d chars — too small to have read src/, so inertness below is an artifact" % src_text.length())
	assert_gt(sfx.size(), 100, "control: manifest holds %d keys" % sfx.size())
	var baseline := _unreachable(sfx, fallback_targets, all_text, src_text, all_prefixes)
	assert_eq(baseline.size(), 0,
		"control: the audit is already RED (%s) — this arm's deltas are not interpretable until test_no_unreachable_sfx_keys is green" % [baseline])

	## And the instrument itself: a prefix that is known load-bearing MUST come back non-empty,
	## or the delta machinery is broken and the whole table would score green by measuring nothing.
	var probe := all_prefixes.duplicate()
	probe.erase("voice_")
	var probe_delta := _unreachable(sfx, fallback_targets, all_text, src_text, probe).size() - baseline.size()
	assert_gt(probe_delta, 0,
		"control: withholding voice_ (30 keys, none literal) exposed %d new unreachable keys — the delta instrument is broken, so every 'load-bearing' verdict below is vacuous" % probe_delta)

	var inert: Array[String] = []
	for prefix in all_prefixes:
		var without := all_prefixes.duplicate()
		without.erase(prefix)
		if _unreachable(sfx, fallback_targets, all_text, src_text, without).size() == baseline.size():
			inert.append(str(prefix))

	assert_eq(inert.size(), 0,
		("DYNAMIC_PREFIXES entries that exempt nothing (%d): %s\n" +
		"Delete them. Either the concatenation they claim does not exist (the entry is FALSE " +
		"and would one day exempt a genuinely dead key), or every key in the family is also a " +
		"source literal (the entry is TRUE but redundant). The two are indistinguishable from " +
		"here, which is exactly why neither may stay: an inert exemption cannot be observed to " +
		"be wrong. If the family really is built at runtime, the entry comes back the day a " +
		"non-literal key lands — test_no_unreachable_sfx_keys names that key and that " +
		"disposition.") % [inert.size(), inert])


## TWO halves: `#` comments are line-based and stateless; `"""` docstrings need a REGION strip.
## Which a guard needs is decided by what its assertion is SATISFIED BY (@cowir-overworld) — these
## are PRESENCE asserts, so a docstring naming the call satisfies them. My .325 fix closed only the
## `#` half. `must_survive` is REQUIRED so no call site reads prose by accident (@cowir-adhoc).
func _code_only(text: String, must_survive: String) -> String:
	var out: PackedStringArray = []
	var in_doc := false
	for raw_line in text.split("\n"):
		var line: String = raw_line
		var fences := line.count("\"\"\"")
		if in_doc:
			if fences % 2 == 1:
				in_doc = false
			continue
		if fences >= 2:
			line = line.substr(0, line.find("\"\"\"")) + line.substr(line.rfind("\"\"\"") + 3)
		elif fences == 1:
			line = line.substr(0, line.find("\"\"\""))
			in_doc = true
		var quote := ""
		var cut := -1
		var i := 0
		while i < line.length():
			var c := line[i]
			if quote != "":
				if c == "\\":
					i += 2
					continue
				if c == quote:
					quote = ""
			elif c == "\"" or c == "'":
				quote = c
			elif c == "#":
				cut = i
				break
			i += 1
		out.append(line.substr(0, cut) if cut > -1 else line)
	var result: String = "\n".join(out)
	if must_survive != "":
		assert_true(result.contains(must_survive),
			"OVER-STRIPPED: %s did not survive — an over-eager stripper and a correct one are the same green" % must_survive)
	return result


func test_the_stripper_this_audit_now_depends_on_actually_strips() -> void:
	## MEASURED 2026-09-12: with _code_only neutered to a pass-through, this file was EC=0 ·
	## Passing 7 — the whole consumer corpus reverted to raw source and NOTHING here noticed.
	## The sibling guards caught their own neuter on a length control; this one had none, and it
	## is the file where the failure direction is SILENCE (a key named only in a comment reads as
	## a live consumer, and a phantom consumer suppresses a real orphan). @cowir-music `da523860`.
	var raw := _read("res://src/audio/SoundManager.gd")
	var code := _code_only(raw, "func play_ui")
	assert_gt(raw.length(), 10000, "CONTROL: SoundManager read back %d chars" % raw.length())
	assert_true(raw.contains("\n#") or raw.contains("\t#"),
		"ANTI-VACUITY: SoundManager holds no comment line, so 'comments are stripped' proves nothing here")
	assert_lt(code.length(), raw.length(),
		"the stripper removed nothing from %d chars — it is a pass-through and this audit reads prose as code" % raw.length())
	## STRUCTURAL, not a phrase: a reworded comment must not change the verdict.
	assert_false(_code_only("\tvar x := 1  # play_sfx(\"ghost_key\")", "").contains("ghost_key"),
		"a key named only in a trailing comment still counts as a consumer")
	## Two asserts, not one: "the call survived" is ALSO true of a last-# cut, so the single
	## assert this replaces was green under that mutation while its message claimed otherwise.
	var trailing := _code_only('\tplay_sfx("real_key")  # see ghost_key #3', "")
	assert_true(trailing.contains('"real_key"'), "a real consumer was dropped")
	assert_false(trailing.contains("ghost_key"),
		"cut at the LAST # — a key named in the middle of a comment survived as a consumer")
	assert_true(_code_only('\tvar s := "has #hash"  # gone', "").contains('"has #hash"'),
		"a # inside a string literal is not a comment")
	## `##` — GDScript's doc-comment form and the one most of src/ uses — was in NO case here, in
	## either position. Mutation-tested 2026-09-12 (skip a run of 2+ `#`): the sibling guards RED
	## because their negatives assert ABSENCE and blindness makes the output LARGER, but this table
	## never mentioned `##` so it stayed green. Latent today (0 of 338 keys are named only in a
	## comment) and it fails toward SILENCE: a key inside a `##` comment would read as a consumer.
	var doc_tail := _code_only('\tplay_sfx("real_key")  ## mentions ghost_key in prose', "")
	assert_true(doc_tail.contains('"real_key"'), "the stripper ate a real consumer before a ##")
	assert_false(doc_tail.contains("ghost_key"),
		"a `##` doc comment survived — a key named in one would read as a live consumer")
	## JSON has no comments and is NOT stripped; the data half of the corpus must survive intact.
	var data_raw := _read("res://data/sfx_manifest.json")
	assert_gt(data_raw.length(), 1000, "CONTROL: the manifest is %d chars" % data_raw.length())

## An exemption you can add without saying WHY is permission to skip, and CLAUDE.md is explicit:
## require the DELIVERABLE, never the permission — "you can't silence it green, only explain it
## green". Both audits TELL a lane to record a reason ("add to KNOWN_PENDING_CONSUMER with the
## owner and what they're waiting on") and until 2026-09-12 neither CHECKED one: only keys were
## ever read, so `"my_key": ""` would have passed. @cowir-autogrind's reason-length arm, adopted.
## FLOOR of 20 is derived, not picked: the twelve live reasons run 31-53 chars and the shortest
## real one ("cowir-battle contact-frame seam") is 31, so 20 cannot fail honest work today while
## still rejecting "", "todo" and "wip".
func test_every_exemption_states_a_reason_a_reader_can_disagree_with() -> void:
	var thin: Array[String] = []
	for key in KNOWN_PENDING_CONSUMER:
		var reason: String = str(KNOWN_PENDING_CONSUMER[key]).strip_edges()
		if reason.length() < 20:
			thin.append("%s -> %s" % [key, "(empty)" if reason.is_empty() else reason])
	if KNOWN_PENDING_CONSUMER.is_empty():
		# An empty table is the GOOD state — every key reached a consumer and no escape hatch is
		# left to police. This used to assert_gt(size, 0), which redded on exactly that outcome
		# and told the reader to delete the arm: a red whose instruction destroys coverage.
		pass_test("no exemptions remain — nothing to police, and that is the finished state")
		return
	assert_eq(thin, [],
		("exemptions with no usable reason (%d): %s\n" +
		"FIX: say who owns it and what they are waiting on — \"cowir-battle contact-frame seam\" " +
		"is the shape. An entry a reader cannot disagree with cannot be reviewed, and it never " +
		"expires because the condition it names was never stated.") % [thin.size(), thin])
