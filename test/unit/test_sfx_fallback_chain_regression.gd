extends GutTest

## A manifest entry whose `file` is missing on disk used to push a warning
## on every play() call (menu_error fires from inn-deny / shop-deny /
## item-deny / overworld-menu paths — easily 5+ times per minute of play).
## The fallback_to field lets the manifest declare "if my file is missing,
## route to this other key" — silencing the warning AND giving the user a
## coherent SFX instead of nothing.

const SFX_MANIFEST := "res://data/sfx_manifest.json"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"


func _manifest() -> Dictionary:
	var f := FileAccess.open(SFX_MANIFEST, FileAccess.READ)
	assert_not_null(f, "sfx_manifest.json must be readable")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary and (parsed as Dictionary).has("sfx"),
		"sfx_manifest.json must have a top-level 'sfx' Dictionary")
	return (parsed as Dictionary)["sfx"]


func _source() -> String:
	return FileAccess.get_file_as_string(SOUND_MANAGER)


func test_known_missing_sfx_have_fallback_or_exist() -> void:
	# Every manifest entry either has a real file on disk OR declares a
	# fallback_to that exists in the manifest. Anything else WILL warn.
	var sfx := _manifest()
	for key in sfx.keys():
		var entry: Dictionary = sfx[key]
		var path: String = str(entry.get("file", ""))
		if path == "":
			continue
		if not path.begins_with("res://"):
			path = "res://" + path
		if FileAccess.file_exists(path):
			continue
		var fallback: String = str(entry.get("fallback_to", ""))
		assert_ne(fallback, "", "%s has missing file %s — declare fallback_to" % [key, path])
		assert_true(sfx.has(fallback), "%s.fallback_to='%s' must exist in manifest" % [key, fallback])


func test_menu_error_falls_back_to_menu_cancel() -> void:
	var sfx := _manifest()
	assert_true(sfx.has("menu_error"), "menu_error entry must exist")
	var entry: Dictionary = sfx["menu_error"]
	assert_eq(str(entry.get("fallback_to", "")), "menu_cancel",
		"menu_error must fall back to menu_cancel until a real menu_error.ogg lands")


func test_sound_manager_honors_fallback_to() -> void:
	var src := _source()
	assert_ne(src, "", "SoundManager.gd must be readable")
	var idx := src.find("func _try_play_sfx_from_manifest")
	assert_gt(idx, -1, "_try_play_sfx_from_manifest must exist")
	var rest := src.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("fallback_to"),
		"_try_play_sfx_from_manifest must read the 'fallback_to' field when load() returns null")
	# Must guard against self-loops — fallback_to: <self> would recurse forever.
	assert_true(body.contains("fallback_key != sound_key") or body.contains("fallback_key != resolved_key"),
		"fallback chain must skip self-references to avoid infinite recursion")


## ⛔ A FALLBACK CYCLE IS BOUNDED BY ONE LINE'S POSITION, AND NOTHING PINNED THAT THE DATA STAYS
## ACYCLIC. `_try_play_sfx_from_manifest` recurses into `fallback_to`, and its own comment says the
## bound is the cooldown stamp rather than the guard above it:
##   "the `fallback_key != sound_key` checks catch self-loops ONLY, so an a->b->a cycle would
##    recurse forever (the cached-null branch recurses too) — except the second visit to any key
##    hits its own fresh stamp and returns here. Do NOT move the stamp after the load."
## So a two-step cycle in the DATA is survivable only because of where that one statement sits. The
## arms above pin specific chains (menu_error -> menu_cancel) and that the engine honours the field;
## none of them says the manifest as a whole is acyclic, or that a fallback names a key that exists.
## Audited clean at 28 fallbacks / 26 variant refs / 25 hand-mapped cues, which is what earns this
## guard its scope rather than a suppression list.
func test_every_cue_indirection_lands_somewhere_real() -> void:
	var sfx := _manifest()
	assert_gt(sfx.size(), 500, "PREMISE: only %d manifest entries parsed" % sfx.size())

	var fallbacks: Array[String] = []
	var dangling: Array[String] = []
	var selfref: Array[String] = []
	for key in sfx:
		var target: String = str((sfx[key] as Dictionary).get("fallback_to", ""))
		if target.is_empty():
			continue
		fallbacks.append(str(key))
		if target == str(key):
			selfref.append(str(key))
		elif not sfx.has(target):
			dangling.append("%s -> %s" % [key, target])
	assert_gt(fallbacks.size(), 10,
		"CONTROL: only %d entries declare fallback_to, so the walk below covers almost nothing" % fallbacks.size())
	assert_eq(dangling, [],
		"these fallbacks name a key that is not in the manifest, so the cue goes nowhere and the warning the field exists to silence comes back: %s" % [dangling])
	assert_eq(selfref, [],
		"these entries fall back to THEMSELVES — the engine's self-loop guard catches it, but it is never what anyone meant: %s" % [selfref])

	## The walk. A cycle would recurse until the cooldown stamp stopped it, which is a bound on the
	## CODE rather than a statement about the data, so the data gets its own assertion.
	var cycles: Array[String] = []
	for key in fallbacks:
		var seen: Array[String] = [key]
		var at: String = key
		for _step in range(32):
			at = str((sfx.get(at, {}) as Dictionary).get("fallback_to", ""))
			if at.is_empty() or not sfx.has(at):
				break
			if at in seen:
				cycles.append(" -> ".join(seen) + " -> " + at)
				break
			seen.append(at)
	assert_eq(cycles, [],
		"these fallback chains CYCLE. _try_play_sfx_from_manifest recurses into fallback_to and only the cooldown stamp's position stops it, so this is a latent unbounded recursion that one refactor of that function turns real: %s" % [cycles])

	var bad_variants: Array[String] = []
	var variant_refs: int = 0
	for key in sfx:
		for v in (sfx[key] as Dictionary).get("variants", []):
			variant_refs += 1
			if not sfx.has(str(v)):
				bad_variants.append("%s -> %s" % [key, str(v)])
	assert_gt(variant_refs, 10,
		"CONTROL: only %d variant refs found, so the check below covers almost nothing" % variant_refs)
	assert_eq(bad_variants, [],
		"these variant lists name a key that is not in the manifest — the randomiser picks it, the lookup misses, and the cue is silent for that draw: %s" % [bad_variants])


func test_every_hand_mapped_ability_cue_names_a_real_key() -> void:
	## The documented instance, in SoundManager's own words: "this key read constant_modification
	## from 2026-07-11, matched nothing, and left the authored cue unreachable while the
	## Scriptweaver's signature act played a sword." A hand-mapped target that does not exist falls
	## through to ability_physical, which is AUDIBLE and plausible, so nothing reports it.
	var sfx := _manifest()
	var src := _source()
	var rx := RegEx.create_from_string("_ability_sounds\\[\"([a-z_0-9]+)\"\\]\\s*=\\s*\"([a-z_0-9]+)\"")
	var mapped: int = 0
	var dangling: Array[String] = []
	for m in rx.search_all(src):
		mapped += 1
		var cue: String = m.get_string(2)
		if not sfx.has(cue) and not src.contains("\"%s\":" % cue):
			dangling.append("%s -> %s" % [m.get_string(1), cue])
	assert_gt(mapped, 10,
		"CONTROL: matched only %d hand-mapped ability cues, so this arm is reading almost nothing" % mapped)
	assert_eq(dangling, [],
		"these hand-mapped ability cues name a manifest key that does not exist, so the ability falls back to ability_physical — a sword thump, audible and plausible, which is why it went unnoticed for months last time: %s" % [dangling])
