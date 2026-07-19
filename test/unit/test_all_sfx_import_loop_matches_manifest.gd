extends GutTest

## Full-manifest loop-agreement ratchet for SFX (cycle #11, msg 2685 finding).
##
## Shape stolen from cowir-music's test_all_music_import_loop_matches_manifest.gd.
## Rationale: SoundManager._on_ambient_finished re-plays the ambient stream on
## finish, so play_ambient() ambient loops via callback regardless of .import
## flag. BUT any future code path that plays an ambient direct via a plain
## AudioStreamPlayer (one-shot ambient stinger, direct-to-stream helper like
## the music side's _start_monster_music) makes .import authoritative — and
## silence-after-one-play regresses. Same class as cowir-music's slime/bat fix.
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
		"NEW manifest/import loop drift (%d): %s — runtime callback-loop hides this for play_ambient, but any bypass path (one-shot ambient stinger, direct AudioStreamPlayer.play) makes .import authoritative. Fix by aligning .import loop with manifest, OR add to KNOWN_LOOP_MISMATCHES with a documented reason." % [new_drift.size(), new_drift])

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
