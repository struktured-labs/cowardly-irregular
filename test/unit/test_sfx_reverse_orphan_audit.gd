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
##      status_* key ever appears literally in source. Same for ability_*,
##      attack_hit_*, strike_*, advance_*, footstep_*, formation_*, voice_*,
##      and the wN_ world-variant prefixes.
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
const DYNAMIC_PREFIXES := {
	"status_": "\"status_\" +",
	"ability_": "_ability_sounds",
	"attack_hit_": "attack_hit_",
	"strike_": "\"strike_\" +",
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
	"night_": "NIGHT_AMBIENCE_KEY",
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
	# cowir-overworld: ShopScene purchase wire (their msg 2775 item 1)
	"purchase_complete": "cowir-overworld shop UX package",
	# struktured verdict pending — inert prototype (cowir-main msg 2914/2928)
	"windup_swing_med": "struktured hitstop-feel verdict",
	# pre-staged before ON_HIT_STATUSES grows (cowir-battle ratchet, msg 2797)
	"status_burn": "pre-staged for future burn_chance weapon proc",
	"status_freeze": "pre-staged for future freeze_chance weapon proc",
	# authored alternates never wired; harmless, kept as design options
	"buff_v2": "unwired alternate take",
	"buff_v3": "unwired alternate take",
	"debuff_v2": "unwired alternate take",
	"debuff_v3": "unwired alternate take",
	"heal_v2": "unwired alternate take",
	"heal_v3": "unwired alternate take",
}


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "should be readable: %s" % path)
	var t := f.get_as_text()
	f.close()
	return t


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
			elif name.ends_with(ext) and name != skip_file:
				out += _read(full)
			name = d.get_next()
		d.list_dir_end()
	return out


func test_no_unreachable_sfx_keys() -> void:
	var parsed: Variant = JSON.parse_string(_read(MANIFEST_PATH))
	assert_true(parsed is Dictionary and parsed.has("sfx"), "manifest must parse to {sfx:{...}}")
	var sfx: Dictionary = parsed["sfx"]

	var src_text := _slurp_dir("res://src", ".gd")
	var data_text := _slurp_dir("res://data", ".json", "sfx_manifest.json")
	var all_text := src_text + data_text

	# fallback_to targets are reachable via the fallback chain.
	var fallback_targets := {}
	for k in sfx:
		var ft: String = str(sfx[k].get("fallback_to", ""))
		if ft != "":
			fallback_targets[ft] = true

	var unreachable: Array[String] = []
	for key_variant in sfx.keys():
		var key: String = str(key_variant)
		if fallback_targets.has(key):
			continue
		# literal reference anywhere in src/ or data/
		if all_text.contains("\"%s\"" % key) or all_text.contains("'%s'" % key):
			continue
		# runtime-constructed via a live concatenation site
		var dynamic := false
		for prefix in DYNAMIC_PREFIXES:
			if key.begins_with(prefix) and src_text.contains(DYNAMIC_PREFIXES[prefix]):
				dynamic = true
				break
		if dynamic:
			continue
		if KNOWN_PENDING_CONSUMER.has(key):
			continue
		unreachable.append(key)

	assert_eq(unreachable.size(), 0,
		("UNREACHABLE SFX keys — %d asset(s) nothing can ever play: %s\n" +
		"Either wire a consumer, or add to KNOWN_PENDING_CONSUMER with the owner " +
		"and what they're waiting on, or delete the asset. Do NOT add an entry " +
		"without a named owner — that just hides a dead asset.") % [unreachable.size(), unreachable])


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
