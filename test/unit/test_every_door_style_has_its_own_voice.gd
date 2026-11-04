extends GutTest

## VillageDoor.play looks up door_<style>_open/close, falls back to door_house_*, and plays only if the manifest HAS the
## key, so a door with no cue is silent and nothing reds (2026-11-04: as composed, all 28 doors were). Styles are DERIVED
## from sprite_manifest's door records, so a new style without its own cue reds here.

const MAX_SECONDS := 1.0


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _door_records() -> Array:
	var out: Array = []
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var art: Dictionary = m.get("building_art", {})
	for key in art:
		var d = (art[key] as Dictionary).get("door", null) if art[key] is Dictionary else null
		for rec in (d if d is Array else [d]):
			if rec is Dictionary:
				out.append(rec)
	return out


func _styles() -> Array:
	var out: Array = []
	for rec in _door_records():
		var s: String = str((rec as Dictionary).get("style", "house"))
		if not out.has(s):
			out.append(s)
	return out


func test_the_door_records_are_found() -> void:
	assert_gt(_door_records().size(), 20, "FLOOR: the door records moved and every arm below would walk nothing")
	assert_true(_styles().has("shop") and _styles().has("house"), "FLOOR: both shipped styles are present, found %s" % [_styles()])


func test_every_style_has_its_own_short_open_and_close() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var bad: Array = []
	for style in _styles():
		for verb in ["open", "close"]:
			var key: String = "door_%s_%s" % [style, verb]
			var e: Dictionary = sm._sfx_manifest.get(key, {})
			var s = load(str(e.get("file", ""))) if not e.is_empty() else null
			if s == null:
				bad.append("%s (no cue, so this style borrows the house door or plays nothing)" % key)
			elif s.get_length() > MAX_SECONDS:
				bad.append("%s runs %.2fs against a %.2fs door" % [key, s.get_length(), VillageDoor.SECONDS])
	assert_eq(bad, [], "door styles without their own voice: %s" % [bad])


func _strip(style: String) -> Sprite2D:
	var strip := Sprite2D.new()
	strip.texture = PlaceholderTexture2D.new()
	strip.hframes = 4
	strip.set_meta("door_style", style)
	add_child_autofree(strip)
	return strip


func _played_by_door(style: String, opening: bool) -> String:
	var sm: Node = _sm()
	sm._sfx_cooldowns.clear()
	sm._ui_player.stream = null
	VillageDoor.play(_strip(style), opening)
	var st = sm._ui_player.stream
	return str(st.resource_path).get_file() if st != null else ""


func test_a_shop_door_rings_its_own_bell() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	var saved: bool = sm._audio_mixer_wedged
	sm._audio_mixer_wedged = false
	assert_eq(_played_by_door("house", true), "door_house_open.ogg", "CONTROL: a house door plays the house cue through the real play()")
	assert_eq(_played_by_door("shop", true), "door_shop_open.ogg", "a shop door opens with its bell, not the house creak or silence")
	assert_eq(_played_by_door("shop", false), "door_shop_close.ogg", "and closes with its own settle")
	sm._audio_mixer_wedged = saved
