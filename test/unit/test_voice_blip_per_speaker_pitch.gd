extends GutTest

## tick 72 regression: voice blip pitch_base must hash on the speaker
## NAME (Sister Concord, Cantor Vell, Greenleaf, ...), not the
## resolved alias key ("scholar"). Otherwise every NPC sharing the
## same npc_type sounds identical.
##
## Original silent gap (caught in tick 72 audit): _load_voice_blip
## set pitch_base = 1.0 by default and only hash-derived a per-
## speaker pitch when the blip FILE was missing. Even worse, the hash
## was on the resolved alias key — so all 8 interior scholar NPCs
## would hash to pitch(hash("scholar")), identical voice.
##
## Fix: pitch_base ALWAYS derives from speaker name (or speaker_key
## when name omitted, for back-compat). The blip file lookup still
## uses the resolved alias key — Sister Concord and Cantor Vell share
## the same scholar.ogg (when it ever exists) but at distinct pitches.

const CUTSCENE_DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_load_voice_blip_accepts_speaker_name_param() -> void:
	# Signature pin: _load_voice_blip MUST take speaker_name as an
	# optional second arg. Anyone removing the param breaks per-NPC
	# voice variety silently.
	var src := _read(CUTSCENE_DIALOGUE)
	assert_true(src.contains("func _load_voice_blip(speaker_key: String, speaker_name: String = \"\")"),
		"_load_voice_blip must accept (speaker_key, speaker_name='') — otherwise scholars/guards/merchants sharing a blip family all sound identical")


func test_pitch_always_derives_from_speaker_name_when_present() -> void:
	# Pin: pitch_source = speaker_name if non-empty, else speaker_key.
	# pitch_base = _hash_pitch(pitch_source) BEFORE the cache-bypass
	# return — so updating just the speaker name on a cached blip
	# still re-pitches.
	var src := _read(CUTSCENE_DIALOGUE)
	var idx: int = src.find("func _load_voice_blip")
	assert_gt(idx, -1, "_load_voice_blip must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("var pitch_source: String = speaker_name if speaker_name != \"\" else speaker_key"),
		"_load_voice_blip body must derive pitch_source from speaker_name first, falling back to speaker_key")
	assert_true(body.contains("_voice_blip_pitch_base = _hash_pitch(pitch_source)"),
		"pitch_base must be assigned from _hash_pitch(pitch_source) on every call — not gated on file-missing fallback")


func test_pitch_assignment_precedes_cache_bypass_return() -> void:
	# Critical ordering: pitch must update EVEN when the blip key
	# matches the cached one. Otherwise consecutive scholars after
	# the first would never re-pitch (same key, early return).
	var src := _read(CUTSCENE_DIALOGUE)
	var idx: int = src.find("func _load_voice_blip")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	var pitch_pos: int = body.find("_voice_blip_pitch_base = _hash_pitch(pitch_source)")
	var return_pos: int = body.find("return")
	assert_gt(pitch_pos, -1, "pitch_base assignment must appear in body")
	assert_gt(return_pos, -1, "cache-bypass return must appear in body")
	assert_lt(pitch_pos, return_pos,
		"pitch_base assignment MUST precede the cache-bypass return — otherwise the second scholar in a row uses the FIRST scholar's pitch")


func test_call_site_threads_entry_speaker_through() -> void:
	# Pin: the call site at _show_current_line must pass
	# entry.get("speaker", "") so the speaker name reaches _load_voice_blip.
	var src := _read(CUTSCENE_DIALOGUE)
	assert_true(src.contains("_load_voice_blip(_resolve_voice_blip_key(portrait_type, theme_name), entry.get(\"speaker\", \"\"))"),
		"_show_current_line must pass entry.get('speaker', '') as the second arg to _load_voice_blip — otherwise per-NPC pitch variety never activates")


func test_voice_blip_aliases_cover_every_interior_npc_type() -> void:
	# Pin: VOICE_BLIP_ALIASES must map every interior npc_type to
	# SOMETHING — even if the target .ogg doesn't exist yet,
	# the alias makes intent explicit and reachable when sfx ships.
	var src := _read(CUTSCENE_DIALOGUE)
	for npc_type in ["scholar", "merchant", "guard"]:
		var key: String = "\"" + npc_type + "\":"
		# Scope to the const block.
		var const_idx: int = src.find("const VOICE_BLIP_ALIASES")
		assert_gt(const_idx, -1, "VOICE_BLIP_ALIASES const must exist")
		var const_end: int = src.find("}", const_idx)
		var const_body: String = src.substr(const_idx, const_end - const_idx)
		assert_true(const_body.contains(key),
			"VOICE_BLIP_ALIASES must define '%s' — otherwise interior NPCs of this type use raw type as blip key, which has no .ogg" % npc_type)


func test_back_compat_speaker_key_hash_when_name_omitted() -> void:
	# Existing callers that don't pass speaker_name MUST still get
	# deterministic per-speaker_key pitch (the old behavior).
	# Pinned by the conditional structure of pitch_source.
	var src := _read(CUTSCENE_DIALOGUE)
	assert_true(src.contains("if speaker_name != \"\" else speaker_key"),
		"pitch_source must fall back to speaker_key when speaker_name is empty — preserves legacy caller behavior")
