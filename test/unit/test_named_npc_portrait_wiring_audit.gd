extends GutTest

## Regression: struktured directive 2026-07-16 (cowir-main msg 2678):
## "using some other npc avatar instead or even worse proc gen... killing
## immersion." Audit (108 speakers / 12 registered PORTRAIT_SPRITES keys
## pre-fix) found named-canon characters sharing generic procedurals:
##
##   Calibrant (98 lines), Orrery (97), Mordaine (36) → mysterious
##   Elder Theron (19) → elder (shared with Herta/Anya/etc.)
##   Scholar Milo (10), Sprocket (18) → scholar
##   Bram (7), Marta (2) → shopkeeper
##   Phil the Lost (9) → mysterious
##   Cave Rat King (10) → goblin
##
## PLUS: OverworldNPC:1112 passes npc_type as portrait — 16 npc_type
## values had no PORTRAIT_SPRITES entry, causing NPC interact dialogue to
## render narrator grey blur. That's the "some other npc avatar" complaint
## most likely surface.
##
## Coordinated with cowir-sprites (thread msg 2679 → 2680) on the split:
## story-tier at portraits/ root (calibrant/orrery/mordaine), everyone
## else at portraits/npcs/. Batches A (3 story) / B (~15 named W1) /
## C (16 generic pool) land at these paths and auto-swap in via
## PORTRAIT_SPRITES lookup.
##
## Four ratchets:
##   (A) Every named-principal + generic-pool key is registered in
##       PORTRAIT_SPRITES with the agreed path.
##   (B) Every registered new key has a PORTRAIT_PROCEDURAL_FALLBACK
##       mapping to an existing procedural — interim visual is
##       intentional, not narrator blur.
##   (C) Named-canon speakers in cutscene JSON use their own portrait key
##       (Elder Theron → theron, not shared elder).
##   (D) Every npc_type declared in HarmoniaVillage._create_npc has a
##       PORTRAIT_SPRITES entry — NPC interact dialogue always resolves.

const CUTSCENE_DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"
const HARMONIA_VILLAGE := "res://src/maps/villages/HarmoniaVillage.gd"

## Named-canon speaker → own portrait key.
const NAMED_CANON_PORTRAITS := {
	"Calibrant": "calibrant",
	"Orrery": "orrery",
	"Mordaine": "mordaine",
	"Elder Theron": "theron",
	"Scholar Milo": "milo",
	"Bram": "bram",
	"Bram Smith": "bram",
	"Marta": "marta",
	"Phil the Lost": "phil",
	"Sprocket": "sprocket",
	"Herta": "herta",
	"Forest Keeper Anya": "anya",
	"Cave Rat King": "boss_rat_king",
}

## Story tier + named W1 + pre-registered post-cave + bosses + generic pool.
## Every key MUST be registered in PORTRAIT_SPRITES.
const EXPECTED_KEYS := [
	# Story tier
	"calibrant", "orrery", "mordaine",
	# Named W1 principals (in cutscenes today)
	"theron", "milo", "bram", "marta", "phil", "sprocket", "herta", "anya",
	# Named W1 (pre-registered)
	"boris", "pip", "flora", "greta", "aldwick", "rowan", "cluck",
	# Bosses
	"boss_rat_king",
	# Existing NPC portrait
	"dr_temporal",
	# Generic archetype pool
	"farmer", "traveler", "child", "blacksmith", "bartender", "maid",
	"dancer", "adventurer", "apprentice", "herbalist", "hooded_mage",
	"knight", "nervous", "pilgrim", "scholarly", "soldier",
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_all_named_and_archetype_keys_registered_in_portrait_sprites() -> void:
	var script: GDScript = load(CUTSCENE_DIALOGUE)
	assert_not_null(script, "CutsceneDialogue must load")
	var sprites: Dictionary = script.PORTRAIT_SPRITES
	var missing: Array = []
	for key in EXPECTED_KEYS:
		if not sprites.has(key):
			missing.append(key)
	assert_eq(missing.size(), 0,
		"PORTRAIT_SPRITES must register all named/archetype keys: missing %s" % str(missing))


func test_every_new_key_has_procedural_fallback() -> void:
	# Interim contract: PORTRAIT_PROCEDURAL_FALLBACK maps each new key to
	# an existing procedural, so registered-but-not-yet-delivered keys
	# render intentionally instead of falling through to narrator blur.
	var script: GDScript = load(CUTSCENE_DIALOGUE)
	assert_true("PORTRAIT_PROCEDURAL_FALLBACK" in script,
		"CutsceneDialogue must expose a PORTRAIT_PROCEDURAL_FALLBACK map")
	var fallbacks: Dictionary = script.PORTRAIT_PROCEDURAL_FALLBACK
	var missing_fallback: Array = []
	for key in EXPECTED_KEYS:
		if not fallbacks.has(key):
			missing_fallback.append(key)
	assert_eq(missing_fallback.size(), 0,
		"every registered new key needs a PORTRAIT_PROCEDURAL_FALLBACK mapping — otherwise render is narrator blur until PNG lands: missing %s" % str(missing_fallback))


func test_named_canon_speakers_use_own_portrait_key() -> void:
	var offenders: Array = []
	var dir = DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "cutscenes dir must open")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var path = "res://data/cutscenes/%s" % f
		var parsed = JSON.parse_string(_read(path))
		if not (parsed is Dictionary):
			continue
		for step in parsed.get("steps", []):
			if not (step is Dictionary) or step.get("type") != "dialogue":
				continue
			for line in step.get("lines", []):
				if not (line is Dictionary):
					continue
				var spk: String = str(line.get("speaker", ""))
				if not NAMED_CANON_PORTRAITS.has(spk):
					continue
				var expected: String = NAMED_CANON_PORTRAITS[spk]
				if str(line.get("portrait", "")) != expected:
					offenders.append("%s: '%s' portrait='%s' (expected '%s')" % [f, spk, line.get("portrait", ""), expected])
	assert_eq(offenders.size(), 0,
		"named-canon speakers must use their own portrait key (not shared generic):\n  %s" % "\n  ".join(offenders))


func test_every_harmonia_npc_type_has_portrait_entry() -> void:
	# NPC interact dialogue path: OverworldNPC:1112 passes npc_type as the
	# portrait key. Every npc_type declared in HarmoniaVillage.gd must have
	# a PORTRAIT_SPRITES entry — otherwise interact dialogue falls through
	# to narrator's grey blur.
	var village_src := _read(HARMONIA_VILLAGE)
	assert_ne(village_src, "", "HarmoniaVillage.gd must be readable")
	var script: GDScript = load(CUTSCENE_DIALOGUE)
	var sprites: Dictionary = script.PORTRAIT_SPRITES
	# Extract npc_type values from _create_npc("<name>", "<type>", ...) calls.
	var regex := RegEx.new()
	regex.compile('_create_npc\\("[^"]+",\\s*"([a-z_]+)"')
	var missing: Dictionary = {}
	for m in regex.search_all(village_src):
		var npc_type := m.get_string(1)
		if sprites.has(npc_type):
			continue
		# `mysterious` and `villager` resolve via the procedural match arm
		# (villager grouped with shopkeeper in PR #149's arm) — legitimate.
		if npc_type == "mysterious" or npc_type == "villager":
			continue
		missing[npc_type] = true
	assert_eq(missing.keys().size(), 0,
		"every HarmoniaVillage npc_type must have a PORTRAIT_SPRITES entry (else interact dialogue = grey blur): missing %s" % str(missing.keys()))
