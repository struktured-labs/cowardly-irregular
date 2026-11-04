extends RefCounted
class_name VillageDoor

## The drawn door of a building (manifest building_art.<key>.door = {rect, open, frames, style}). struktured 2026-11-01:
## "the door is not where my char is lined up" and "the doors need an opening animation". One record drives both: entrances
## snap to it, and its strip opens before the fade and closes behind the player on the way out.

const SECONDS := 0.25


## The door's rect in WORLD pixels: the art's own rect, offset by where the building's sprite is drawn.
static func world_rect(house: Node2D, rect: Array) -> Rect2:
	var spr := house.get_node_or_null("Sprite") as Sprite2D
	var origin: Vector2 = house.global_position + (spr.position if spr else Vector2.ZERO)
	return Rect2(origin + Vector2(float(rect[0]), float(rect[1])), Vector2(float(rect[2]), float(rect[3])))


## Where an entrance belongs: the drawn door's centre x, or, with no door record, the drawn art's own centre x.
static func entrance_x(house: Node2D, door: Dictionary) -> float:
	if door.has("rect"):
		return world_rect(house, door["rect"]).get_center().x
	var spr := house.get_node_or_null("Sprite") as Sprite2D
	if spr == null or spr.texture == null:
		return house.global_position.x
	return house.global_position.x + spr.position.x + spr.texture.get_width() / 2.0


## The opening strip over the drawn door, hidden until it plays; null when the record has no strip on disk.
static func attach(house: Node2D, door: Dictionary) -> Sprite2D:
	var path := str(door.get("open", ""))
	if path == "" or not ResourceLoader.exists(path) or not door.has("rect"):
		return null
	var strip := Sprite2D.new()
	strip.name = "DoorOpen"
	strip.centered = false
	strip.texture = load(path)
	strip.hframes = maxi(int(door.get("frames", 4)), 1)
	strip.frame = 0
	strip.visible = false
	var r := world_rect(house, door["rect"])
	strip.position = r.position - house.global_position
	house.add_child(strip)
	strip.set_meta("door_style", str(door.get("style", "house")))
	return strip


## Run the strip closed -> open (or open -> closed) over SECONDS of wall clock; a closed door hides its strip again.
static func play(strip: Sprite2D, opening: bool) -> void:
	if strip == null or not is_instance_valid(strip) or not strip.is_inside_tree():
		return
	var last := strip.hframes - 1
	strip.visible = true
	strip.frame = 0 if opening else last
	var cue := "door_%s_%s" % [str(strip.get_meta("door_style", "house")), "open" if opening else "close"]
	var sm: Node = strip.get_tree().root.get_node_or_null("SoundManager")
	if sm and "_sfx_manifest" in sm:
		var key := cue if sm._sfx_manifest.has(cue) else ("door_house_open" if opening else "door_house_close")
		if sm._sfx_manifest.has(key):
			sm.play_ui(key)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(SECONDS * 1000.0):
		await strip.get_tree().process_frame
		if not is_instance_valid(strip):
			return
		var k := clampf(float(Time.get_ticks_msec() - t0) / (SECONDS * 1000.0), 0.0, 1.0)
		var step := roundi(k * last)
		strip.frame = step if opening else last - step
	strip.frame = last if opening else 0
	if not opening:
		strip.visible = false
