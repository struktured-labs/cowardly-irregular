extends GutTest

## Full-manifest loop-agreement ratchet for SFX (cycle #11, msg 2685 finding).
##
## Shape stolen from cowir-music's test_all_music_import_loop_matches_manifest.gd.
##
## RATIONALE CORRECTED 2026-07-29 — the original understated why this guard is
## load-bearing, and got the mechanism backwards. It said ambient loops via the
## _on_ambient_finished callback "regardless of .import flag", treating .import as
## a hazard only for hypothetical future bypass paths. Measured: the SFX manifest
## path NEVER READS the `loop` field (SoundManager:1280 is _try_play_from_manifest,
## the MUSIC function, reading _music_manifest). `.import` is the ONLY live loop
## mechanism for SFX, today. And because all 12 ambient streams now carry
## loop=true, they never emit `finished`, so _on_ambient_finished is UNREACHABLE —
## the same effect SoundManager:1269 documents for stingers ("loop=true ... made
## them loop forever and never fire the `finished` signal").
##
## So the manifest `loop` field is DOCUMENTATION of an intent the runtime cannot
## honour on its own. An author adding an ambient key with "loop": true and no
## .import edit gets a cue that plays once and stops. THIS GUARD IS WHAT MAKES THE
## FIELD MEAN ANYTHING — it is not a nice-to-have ratchet against a future bypass.
##
## Field-level context (cowir-ai msg-3373's class, swept 2026-07-29): of 8 fields
## used across the manifest, `file`/`fallback_to`/`variants` are read;
## `prompt`/`prompt_influence`/`source`/`duration_seconds` have zero consumers and
## are legitimately inert provenance. `loop` is the only field that READS as
## behavioural while having no runtime reader — which is exactly why it needs a
## guard and they do not. Deliberately NOT adding a field-consumer ratchet: it
## would flag those four on day one, and a check whose correct case needs four
## suppression flags is rot arriving dressed as diligence.
##
## Two guarantees:
##   1. Any NEW mismatch between manifest.loop and .import loop fails the gate.
##   2. Any KNOWN_LOOP_MISMATCHES entry that now agrees fails until removed —
##      no stale allowlist rot.
##
## Only SFX entries with an EXPLICIT `loop` field in the manifest are checked;
## keys without the field are silent regarding loop-intent (probably one-shots
## by convention). Adding a `loop` field to a new key is the trigger to have
## its .import agree.


const MANIFEST_PATH := "res://data/sfx_manifest.json"

## As of cycle #11 the 12 ambient/night_crickets_wind entries are FIXED
## (loop=true both sides). Snapshot starts empty. Add here only if a real
## intentional divergence appears — with cowir-main sign-off and a comment.
const KNOWN_LOOP_MISMATCHES: Array[String] = []


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _import_loop_flag(ogg_res_path: String) -> String:
	## Read `loop=` from an .import file. Returns "true", "false", or "" if absent.
	var text: String = _read(ogg_res_path + ".import")
	for line in text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("loop="):
			return stripped.substr(len("loop=")).strip_edges().to_lower()
	return ""


func test_no_new_manifest_import_loop_drift() -> void:
	var text: String = _read(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary and parsed.has("sfx"),
		"sfx_manifest.json must parse into {sfx: {...}}")
	var sfx: Dictionary = parsed["sfx"]

	var actual_mismatches: Array[String] = []
	var checked: int = 0
	for key in sfx.keys():
		var k: String = str(key)
		var entry: Dictionary = sfx[k]
		if not entry.has("loop"):
			continue  # only entries with explicit loop-intent are checked
		var ogg_path: String = entry.get("file", "")
		if ogg_path == "":
			continue
		if not ogg_path.begins_with("res://"):
			ogg_path = "res://" + ogg_path
		var manifest_loop: bool = bool(entry["loop"])
		var import_loop_str: String = _import_loop_flag(ogg_path)
		if import_loop_str == "":
			continue
		var import_loop: bool = import_loop_str == "true"
		checked += 1
		if import_loop != manifest_loop:
			actual_mismatches.append(k)

	# Guarantee 1: no NEW drift.
	var known_set := {}
	for k in KNOWN_LOOP_MISMATCHES:
		known_set[k] = true
	var new_drift: Array[String] = []
	for k in actual_mismatches:
		if not known_set.has(k):
			new_drift.append(k)
	assert_eq(new_drift.size(), 0,
		"NEW manifest/import loop drift (%d): %s — these two must agree, and this file's header records WHICH ONE the runtime actually reads and why the disagreement is audible rather than cosmetic. Read it before choosing a side. Fix by aligning the .import loop flag with the manifest, OR add to KNOWN_LOOP_MISMATCHES with a documented reason." % [new_drift.size(), new_drift])

	# Guarantee 2: no snapshot rot.
	var actual_set := {}
	for k in actual_mismatches:
		actual_set[k] = true
	var stale_allowlist: Array[String] = []
	for k in KNOWN_LOOP_MISMATCHES:
		if not actual_set.has(k):
			stale_allowlist.append(k)
	assert_eq(stale_allowlist.size(), 0,
		"KNOWN_LOOP_MISMATCHES entries that now AGREE — remove them (%d): %s" % [stale_allowlist.size(), stale_allowlist])

	# Sanity: cycle #11 established 12 explicit-loop entries.
	assert_gt(checked, 10,
		"expected 10+ explicit-loop SFX entries checked, got %d — manifest walk broken?" % checked)


func test_all_ambient_keys_declare_loop_intent() -> void:
	## Domain rule: every ambient_*/night_* key SHOULD carry loop:true. Ambient
	## by definition loops. If someone adds an ambient_ key without the field,
	## this fires — pointing them at the cycle #11 convention.
	var text: String = _read(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	var sfx: Dictionary = parsed["sfx"]

	var missing: Array[String] = []
	for key in sfx.keys():
		var k: String = str(key)
		if not (k.begins_with("ambient_") or k.begins_with("night_")):
			continue
		var entry: Dictionary = sfx[k]
		if not entry.has("loop"):
			missing.append(k)
	assert_eq(missing.size(), 0,
		"ambient_/night_ keys without explicit loop field (%d): %s — cycle #11 established loop:true as the convention for these." % [missing.size(), missing])
