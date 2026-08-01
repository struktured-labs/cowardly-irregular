extends GutTest

## Bidirectional reachability audit for portrait art (2026-07-25).
##
## Prompted by @cowir-story's layer-six class — "two data sources feed one
## surface, one silently wins." The portrait surface has exactly that shape:
## PORTRAIT_SPRITES (art) and PORTRAIT_PROCEDURAL_FALLBACK (drawn) both feed
## _create_portrait, and the fallback is DESIGNED to look reasonable. So a
## key whose PNG never arrived is visually indistinguishable from one whose
## PNG arrived and works. Nothing fails; the art is just never seen.
##
## Found on the first run: villager_m.png, villager_f.png and elder_f.png —
## 256x256 portraits from cowir-sprites' Batch C — shipped with ZERO
## consumers anywhere in src/ or data/.
##
## The audit direction that matters is B (art on disk that nothing points
## at), because that's the one no other check covers: A is expected state
## (keys are deliberately pre-registered before art lands — the masterite
## W2-W5 variants and dr_temporal all sit that way on purpose).
##
## METHOD NOTE, learned the hard way while writing this: my first pass
## reported the four keepers/*.png shopkeeper portraits as orphans. They
## are not — ShopScene.gd consumes them directly by path. I had checked
## ONE source (PORTRAIT_SPRITES) and concluded "nothing points at it",
## which is the exact failure this audit exists to catch. Any consumer
## check here must sweep the whole of src/ + data/, not one registry.

const CUTSCENE_DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"
const PORTRAIT_ROOT := "res://assets/sprites/portraits"

## Subdirectories owned by a DIFFERENT consumer than CutsceneDialogue.
## keepers/ belongs to ShopScene (by direct path, not via a registry).
const NON_DIALOGUE_DIRS := ["keepers"]


func _registry() -> Dictionary:
	var script: GDScript = load(CUTSCENE_DIALOGUE)
	assert_not_null(script, "CutsceneDialogue must load")
	return script.PORTRAIT_SPRITES


func _all_portrait_pngs(dir_path: String, out: Array) -> void:
	var d = DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".png"):
			out.append("%s/%s" % [dir_path, f])
	for sub in d.get_directories():
		if sub in NON_DIALOGUE_DIRS:
			continue
		_all_portrait_pngs("%s/%s" % [dir_path, sub], out)


## True when ANY file under src/ or data/ mentions this basename. Deliberately
## broad — a portrait can legitimately be consumed by direct path (ShopScene),
## by registry key, or by a key built at runtime.
func _has_any_consumer(basename: String) -> bool:
	return _grep_tree("res://src", basename) or _grep_tree("res://data", basename)


func _grep_tree(root: String, needle: String) -> bool:
	var d = DirAccess.open(root)
	if d == null:
		return false
	for f in d.get_files():
		if not (f.ends_with(".gd") or f.ends_with(".json")):
			continue
		var text := FileAccess.get_file_as_string("%s/%s" % [root, f])
		if text.find(needle) > -1:
			return true
	for sub in d.get_directories():
		if _grep_tree("%s/%s" % [root, sub], needle):
			return true
	return false


func test_no_portrait_art_ships_without_a_consumer() -> void:
	# Direction B — the one that matters. Art that landed but nothing reads
	# renders as "the procedural still shows", which looks fine and wastes
	# whatever it cost to make.
	var pngs: Array = []
	_all_portrait_pngs(PORTRAIT_ROOT, pngs)
	assert_gt(pngs.size(), 10, "sanity: portrait art should exist to audit")
	var orphans: Array = []
	for p in pngs:
		var base: String = str(p).get_file().get_basename()
		if not _has_any_consumer(base):
			orphans.append(p.replace(PORTRAIT_ROOT + "/", ""))
	assert_eq(orphans.size(), 0,
		"portrait art with no consumer in src/ or data/ — it will never render, and the procedural fallback hides that:\n  %s" % "\n  ".join(orphans))


func test_registered_keys_without_art_still_resolve_intentionally() -> void:
	# Direction A is EXPECTED state, not a defect — keys are deliberately
	# pre-registered so cowir-sprites' art auto-swaps in on arrival (the
	# masterite W2-W5 variants, dr_temporal). What must hold is that each
	# one still renders something chosen rather than the narrator blur.
	var script: GDScript = load(CUTSCENE_DIALOGUE)
	var reg: Dictionary = script.PORTRAIT_SPRITES
	var fallbacks: Dictionary = script.PORTRAIT_PROCEDURAL_FALLBACK
	var src := FileAccess.get_file_as_string(CUTSCENE_DIALOGUE)
	var unresolved: Array = []
	for key in reg:
		if ResourceLoader.exists(str(reg[key])):
			continue
		# No art yet — needs either a procedural fallback mapping or a
		# prefix arm (masterite_* is handled by prefix).
		if fallbacks.has(key):
			continue
		if str(key).begins_with("masterite_") and src.find('begins_with("masterite_")') > -1:
			continue
		unresolved.append("%s → %s" % [key, reg[key]])
	assert_eq(unresolved.size(), 0,
		"a registered key whose art hasn't landed must still resolve via PORTRAIT_PROCEDURAL_FALLBACK or a prefix arm, else it renders narrator-blur:\n  %s" % "\n  ".join(unresolved))


func test_gendered_generics_are_registered() -> void:
	# Direct pin for the find. These three shipped 256x256 and sat unused.
	var reg := _registry()
	for key in ["villager_m", "villager_f", "elder_f"]:
		assert_true(reg.has(key),
			"'%s' art exists on disk — register it or it renders never" % key)
		assert_true(ResourceLoader.exists(str(reg[key])),
			"'%s' must point at art that actually exists" % key)


func test_generic_villager_and_elder_keys_unchanged() -> void:
	# The restraint was "don't change what struktured has already seen without
	# him asking". He asked, 2026-07-31: "phil the lost: no portrait … PLEASE
	# MAKE PORTRAITS FOR ALL SPRITES". `villager` is the npc_type of 55 placed
	# NPCs and had no art, so every one of them shared one procedural face.
	# The invariant this test was really protecting SURVIVES: the generic keys
	# must not be silently repointed at the GENDERED variants.
	var reg := _registry()
	assert_eq(str(reg.get("elder", "")), "res://assets/sprites/portraits/npcs/elder.png",
		"generic 'elder' must keep its existing art — repointing it to elder_f is a visible change nobody asked for")
	assert_eq(str(reg.get("villager", "")), "res://assets/sprites/portraits/npcs/villager.png",
		"generic 'villager' must have its OWN art — never villager_m, and no longer left procedural (55 NPCs share this key)")
	assert_true(ResourceLoader.exists(str(reg.get("villager", ""))),
		"the villager portrait must exist on disk or 55 NPCs fall back to the generic procedural face")
