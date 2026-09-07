extends GutTest

## struktured 2026-08-20: "mordaine needs her own avatar." She HAD one — the severe
## circlet-and-hood Chancellor under the `chancellor_mordaine` key — but her four
## cutscenes ask for `mordaine`, which pointed at the Batch-A knight placeholder (a
## purple-eyed armored MAN). Two keys, one character, the wrong face on screen. The
## art ruling forbids any hooded/obscured variant ("plainly visible, all three surfaces
## read as one character"), so both keys must resolve to the SAME file, forever.

const CD := "res://src/cutscene/CutsceneDialogue.gd"
const KNIGHT_PLACEHOLDER := "res://assets/sprites/portraits/mordaine.png"


func _portrait_path(key: String) -> String:
	var src := FileAccess.get_file_as_string(CD)
	var i := src.find('"%s": "res://' % key)
	assert_gt(i, -1, "PORTRAIT_SPRITES must have key %s" % key)
	var start := src.find('"res://', i)
	var end := src.find('"', start + 1)
	return src.substr(start + 1, end - start - 1)


func test_both_mordaine_keys_resolve_to_one_face() -> void:
	var a := _portrait_path("mordaine")
	var b := _portrait_path("chancellor_mordaine")
	assert_eq(a, b, "cutscene key and NPC key must show the SAME Mordaine — one character, one face")
	assert_true(ResourceLoader.exists(a), "the shared portrait file must exist: %s" % a)


func test_cutscene_key_no_longer_wears_the_knight() -> void:
	assert_ne(_portrait_path("mordaine"), KNIGHT_PLACEHOLDER,
		"`mordaine` must not point at the Batch-A knight placeholder — that is not her")


func test_every_mordaine_cutscene_uses_a_wired_key() -> void:
	# The four cutscenes ask for `mordaine`; if one is ever changed to a key nobody wired, she'd silently fall to a generic face
	var src := FileAccess.get_file_as_string(CD)
	var files := ["world1_mordaine_intro", "world1_mordaine_defeat", "world1_mordaine_procedure", "world1_mordaine_speaks"]
	var checked := 0
	for f in files:
		var txt := FileAccess.get_file_as_string("res://data/cutscenes/%s.json" % f)
		if txt == "":
			continue
		checked += 1
		var j = JSON.parse_string(txt)
		var keys := _collect_portrait_keys(j)
		for k in keys:
			if "mordaine" in k:
				assert_true(('"%s": "res://' % k) in src, "%s uses portrait key '%s' which must be wired in PORTRAIT_SPRITES" % [f, k])
	assert_gt(checked, 2, "CONTROL: read the real cutscene files (%d)" % checked)


func _collect_portrait_keys(o, out: Array = []) -> Array:
	if o is Dictionary:
		if o.has("portrait"):
			out.append(str(o["portrait"]))
		for v in o.values():
			_collect_portrait_keys(v, out)
	elif o is Array:
		for v in o:
			_collect_portrait_keys(v, out)
	return out
