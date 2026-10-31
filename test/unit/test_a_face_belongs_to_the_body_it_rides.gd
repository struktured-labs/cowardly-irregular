extends GutTest

## A dialogue face and the walking body under it are TWO assets, and nothing compared them.
## struktured 2026-10-30: "Willow is a merchant at mystic remedies whose portrait is cute but npc looks like
## mario with the mustache. we need like a test that asserts that portrait is somewhat related to the
## character… all sorts of broken matches." Willow (a young woman, green braid) rode the generic mustached
## merchant sheet, and so did Mortimer.
##
## Three existing guards were green through it, each asking a different question:
##   test_portrait_identity_class_regression   one NPC, two PORTRAIT keys -- never a face against a body
##   test_npc_portrait_resolution_regression    the portrait EXISTS; its regex corpus needs a literal name
##                                              and `.sprite_archetype =`, and the keeper is a variable name
##                                              with the sheet as a positional arg, so it cannot see her
##   test_a_pictured_keeper_stands_as_themselves  pinned Willow as the merchant ON PURPOSE
##
## So the corpus is the RUNNING game, not a regex: every NPC each village and interior script places, plus
## every ShopScene.PICTURED_KEEPERS entry built the way the shop builds it (a plain crawl never names her:
## the shop opens with a keeper_name the village supplies). Dungeons are out: building one can start a boss.
##
## Every (face, body) pair must have a row in npc_face_body_ledger.json naming the bytes it reviewed. A new
## pair, art changed on either side, or a row whose review said "mismatch" is RED until re-reviewed by
## tools/review_npc_face_body.py, which renders each pair side by side and has a vision model judge it.

## Mismatches that were ALREADY on main when this guard landed (2026-10-30 review, each read by eye, not only
## by the model). Pending struktured's call: redraw a side, or accept the pairing. NOT accepted by this file --
## the list exists so the guard can land without either hiding them or reding every fold. It must SHRINK:
## a listed pair that now matches, or is no longer placed, reds below until it is removed.
const PENDING_DECISION := {
	"nervous|young_woman": "Vex: a young MAN's face (sweat-drop) on the young_woman sheet -- the sex differs",
	"elder_theron|elder_theron": "Elder Theron: white hair, GREEN robe face vs a bald, ORANGE-robed sheet -- his own two assets disagree",
	"herbalist|priestess": "Gethena: an auburn-braided herbalist face on the white priestess robes",
	"hooded_mage|scholar": "Aldric: a hooded mage with glowing eyes on the old bespectacled scholar sheet",
	"adventurer|traveler": "Kael: a bearded bareheaded adventurer on the brown-hat traveler with a staff",
	"apprentice|young_man": "Jend: orange spiky hair face on the dark-haired young_man sheet",
	"pilgrim|monk": "Pilgrim Lael: a bearded old man in a grey hood on the beardless orange monk sheet",
	"knight|soldier": "Sir Reginald, Guard Henryk, Sir Corvath: a bearded knight face on the beardless soldier sheet",
	"innkeeper|innkeeper": "Mira: no mustache on the face, a mustache on the sheet (and a female name on a male innkeeper)",
	"young_man|young_man": "BORDERLINE: the sheet's mouth shading reads as a mustache at 4x; the face is clean-shaven",
}

const LEDGER := "res://data/npc_face_body_ledger.json"
const MANIFEST := "res://data/sprite_manifest.json"
const MAP_DIRS := ["res://src/maps/villages", "res://src/maps/interiors"]
const Dialogue := preload("res://src/cutscene/CutsceneDialogue.gd")
const ShopSceneScript := preload("res://src/exploration/ShopScene.gd")
const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")

var _pairs_cache: Dictionary = {}
var _walkers_seen := 0


func _names(arr: Array) -> String:
	var out := ""
	for x in arr:
		out += (", " if out != "" else "") + str(x)
	return out


func _scripts() -> Array:
	var out: Array = []
	for dir_path in MAP_DIRS:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".gd"):
				out.append("%s/%s" % [dir_path, f])
	out.sort()
	return out


## Every NPC node under `root`: face = what it speaks with, body = the sheet it actually loaded.
func _collect(root: Node, scene: String, into: Dictionary) -> void:
	for n in root.find_children("*", "Area2D", true, false):
		if n.get("is_object") == true:
			continue  ## an object (a clock, a ledger) has no face and no body; test_an_object_is_not_drawn_as_a_person judges it
		var face := ""
		var body := ""
		if n.has_method("_portrait_key"):
			face = str(n._portrait_key())
			body = str(n.get("_archetype_id"))
			if body == "":
				body = "procedural:" + str(n.get("npc_type"))
		elif n is WanderingNPC:
			## A walker speaks with dialogue_portrait over its sprite_archetype; it has no _portrait_key, so it was never judged.
			face = str(n.dialogue_portrait)
			body = str(n.sprite_archetype)
			if body == "":
				body = "procedural:walker"
			_walkers_seen += 1
		else:
			continue
		var key := "%s|%s" % [face, body]
		if not into.has(key):
			into[key] = []
		(into[key] as Array).append("%s @ %s" % [str(n.get("npc_name")), scene])


func _pairs() -> Dictionary:
	if not _pairs_cache.is_empty():
		return _pairs_cache
	var out := {}
	for path in _scripts():
		var script = load(path)
		if script == null or not script.can_instantiate():
			continue
		var vp := SubViewport.new()
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		## Untyped on purpose: some scripts under these dirs are RefCounted helpers, and a typed `Node`
		## assignment ABORTS this function (the crawl then reads 0 NPCs). Check, then skip.
		var made = script.new()
		if not (made is Node):
			continue
		var scene: Node = made
		vp.add_child(scene)
		await get_tree().process_frame
		await get_tree().process_frame
		_collect(scene, path.get_file(), out)
	for t in ShopSceneScript.PICTURED_KEEPERS:
		var shop = ShopInteriorScript.new()
		shop.shop_type = t
		shop.keeper_name = str(ShopSceneScript.PICTURED_KEEPERS[t][0])
		var vp := SubViewport.new()
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		vp.add_child(shop)
		await get_tree().process_frame
		await get_tree().process_frame
		_collect(shop, "ShopInterior.gd [%s]" % shop.keeper_name, out)
	for k in out:
		gut.p("[face-body] %s|%s" % [k, _names(out[k])])
	_pairs_cache = out
	return out


func _ledger() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEDGER))
	return parsed if parsed is Dictionary else {}


## The bytes a face key draws: its PORTRAIT_SPRITES file, or "procedural" when it has none.
func _face_sha(face: String) -> String:
	var p := str(Dialogue.PORTRAIT_SPRITES.get(face, ""))
	return FileAccess.get_sha256(p) if p != "" and FileAccess.file_exists(p) else "procedural"


func _body_sha(body: String) -> String:
	if body.begins_with("procedural:"):
		return "procedural"
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var e: Variant = ((m as Dictionary).get("overworld_npc_sheets", {}) as Dictionary).get(body, {}) if m is Dictionary else {}
	var p := str((e as Dictionary).get("path", "")) if e is Dictionary else ""
	return FileAccess.get_sha256(p) if p != "" and FileAccess.file_exists(p) else "missing"


## "match" is a reviewed pair. "procedural" is allowed ONLY where a side really has no art -- otherwise it
## would be a way to wave through a pair nobody looked at.
func _verdict_ok(key: String, row: Dictionary) -> bool:
	var v := str(row.get("verdict", ""))
	if v == "match":
		return true
	if v == "procedural":
		return _face_sha(key.get_slice("|", 0)) == "procedural" or _body_sha(key.get_slice("|", 1)) == "procedural"
	return false


func test_the_corpus_reaches_the_villages_and_every_pictured_keeper() -> void:
	var pairs: Dictionary = await _pairs()
	var npcs := 0
	for k in pairs:
		npcs += (pairs[k] as Array).size()
	assert_gt(_scripts().size(), 20, "FLOOR: the map scripts must be found, or the crawl judged a fraction")
	assert_gt(npcs, 50, "FLOOR: the crawl must reach the placed NPCs (%d found)" % npcs)
	assert_gt(_walkers_seen, 0, "CONTROL: the crawl must reach the WanderingNPC walkers too -- they speak with a face over a body")
	var seen := ""
	for k in pairs:
		seen += _names(pairs[k]) + " ; "
	for t in ShopSceneScript.PICTURED_KEEPERS:
		var who := str(ShopSceneScript.PICTURED_KEEPERS[t][0])
		assert_true(seen.contains(who + " @ ShopInterior"), "CONTROL: pictured keeper %s must be in the corpus -- the keepers are the case this guard exists for" % who)


func test_every_face_and_body_pair_has_been_reviewed() -> void:
	var pairs: Dictionary = await _pairs()
	var ledger := _ledger()
	assert_gt(ledger.size(), 0, "CONTROL: the ledger must parse, or every pair below reads as unreviewed")
	var unreviewed: Array = []
	for k in pairs:
		if not ledger.has(k):
			unreviewed.append("%s (%s)" % [k, _names(pairs[k])])
	unreviewed.sort()
	assert_eq(unreviewed, [], "a face that has never been compared with the body under it -- run tools/review_npc_face_body.py: %s" % [unreviewed])


func test_no_reviewed_pair_has_changed_art_since() -> void:
	var pairs: Dictionary = await _pairs()
	var ledger := _ledger()
	var changed: Array = []
	for k in pairs:
		if not ledger.has(k):
			continue
		var row: Dictionary = ledger[k]
		var face := str(k).get_slice("|", 0)
		var body := str(k).get_slice("|", 1)
		if str(row.get("face_sha256", "")) != _face_sha(face) or str(row.get("body_sha256", "")) != _body_sha(body):
			changed.append(str(k))
	changed.sort()
	assert_eq(changed, [], "the art on one side changed after its review; the verdict is about other pixels: %s" % [changed])


func test_no_pair_the_review_found_broken_ships() -> void:
	var pairs: Dictionary = await _pairs()
	var ledger := _ledger()
	var broken: Array = []
	for k in pairs:
		var row: Variant = ledger.get(k, null)
		if row is Dictionary and not _verdict_ok(str(k), row as Dictionary) and not PENDING_DECISION.has(str(k)):
			broken.append("%s -- %s (%s)" % [k, str((row as Dictionary).get("reason", "")), _names(pairs[k])])
	broken.sort()
	assert_eq(broken, [], "the face and the body under it are different people: %s" % [broken])


func test_the_pending_list_only_shrinks() -> void:
	var pairs: Dictionary = await _pairs()
	var ledger := _ledger()
	var stale: Array = []
	for k in PENDING_DECISION:
		if not pairs.has(k):
			stale.append("%s is no longer placed" % k)
		elif str((ledger.get(k, {}) as Dictionary).get("verdict", "")) == "match":
			stale.append("%s now MATCHES" % k)
	stale.sort()
	assert_eq(stale, [], "fixed or retired -- remove it from PENDING_DECISION so the list keeps meaning 'still broken': %s" % [stale])

