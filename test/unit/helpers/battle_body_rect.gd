extends RefCounted

## The on-screen rect a combatant actually occupies: the opaque pixels of its current frame unioned with every
## visible child (name label, HP bar, status icons). Opaque bounds are read from the source PNG, so they hold
## headless too, where a texture's get_image() can come back empty.

static var _used_cache: Dictionary = {}


static func control_rect(c: Control) -> Rect2:
	var t := c.get_global_transform()
	return Rect2(t * Vector2.ZERO, c.size * t.get_scale().abs())


static func of(n: Node) -> Rect2:
	var acc := Rect2()
	var have := false
	var stack: Array = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is CanvasItem and not (x as CanvasItem).visible:
			continue
		var r := Rect2()
		var ok := false
		if x is AnimatedSprite2D:
			var a := x as AnimatedSprite2D
			if a.sprite_frames and a.sprite_frames.has_animation(a.animation) and a.sprite_frames.get_frame_count(a.animation) > 0:
				var tex: Texture2D = a.sprite_frames.get_frame_texture(a.animation, mini(a.frame, a.sprite_frames.get_frame_count(a.animation) - 1))
				if tex:
					var base := (-tex.get_size() * 0.5 if a.centered else Vector2.ZERO) + a.offset
					var u := used_rect(tex)
					r = _xf(a.get_global_transform(), Rect2(base + u.position, u.size))
					ok = u.size.x > 0
		elif x is Sprite2D:
			var s := x as Sprite2D
			if s.texture:
				r = _xf(s.get_global_transform(), s.get_rect())
				ok = true
		elif x is Label:
			var l := x as Label
			if l.text != "" and l.modulate.a > 0.01:
				r = _xf(l.get_global_transform(), _text_rect(l))
				ok = true
		elif x is Control:
			var c := x as Control
			if c.size.x > 0 and c.size.y > 0 and c.modulate.a > 0.01:
				r = control_rect(c)
				ok = true
		if ok:
			acc = r if not have else acc.merge(r)
			have = true
		for ch in x.get_children():
			stack.append(ch)
	return acc


## A label's drawn TEXT, in its own frame: its box is often far wider than the words and draws nothing.
static func _text_rect(l: Label) -> Rect2:
	var font := l.get_theme_font(&"font")
	var px := l.get_theme_font_size(&"font_size")
	var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 2.0
	var h := l.get_minimum_size().y
	var box_w := maxf(l.size.x, w)
	var x0 := 0.0
	match l.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			x0 = (box_w - w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			x0 = box_w - w
	return Rect2(x0, 0.0, w, h)


## The opaque part of a frame, in the frame's own pixels.
static func used_rect(tex: Texture2D) -> Rect2:
	var key := "%s#%d" % [tex.resource_path, tex.get_instance_id()]
	if _used_cache.has(key):
		return _used_cache[key]
	var full := Rect2(Vector2.ZERO, tex.get_size())
	var img: Image = null
	var region := Rect2i(Vector2i.ZERO, Vector2i(tex.get_size()))
	var src: Texture2D = tex
	if tex is AtlasTexture and (tex as AtlasTexture).atlas:
		src = (tex as AtlasTexture).atlas
		region = Rect2i((tex as AtlasTexture).region)
	img = src.get_image()
	if (img == null or img.is_empty()) and src.resource_path.begins_with("res://") and FileAccess.file_exists(src.resource_path):
		img = Image.load_from_file(src.resource_path)
	var out := full
	if img and not img.is_empty():
		region = region.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		var u := img.get_region(region).get_used_rect()
		out = Rect2(Vector2(u.position), Vector2(u.size))
	_used_cache[key] = out
	return out


static func _xf(t: Transform2D, r: Rect2) -> Rect2:
	var a := t * r.position
	var b := t * r.end
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())


## Everything that stands at the screen's sides in a battle: the left column and the right column with its badges.
const WALLS := ["EnemyStatusPanel", "BattleLogPanel", "CTBTimeline", "PartyStatusPanel", "SpeedPanel", "AutoToggleButton"]


static func walls(scene: Node) -> Dictionary:
	var out := {}
	for name in WALLS:
		var c := scene.find_child(name, true, false) as Control
		if c and c.is_visible_in_tree():
			out[name] = control_rect(c)
	return out
