extends RefCounted

## ONE judge of struktured's "make sure nothing ever overlaps unless we intend it" (main 23389), shared by every
## screen's guard: battle, field HUD, menus, grind, cutscenes (main 23393/23398). Nobody writes a second one.
##
## A SURFACE is a visible Control that draws its own background (Panel, PanelContainer, ColorRect, TextureRect,
## NinePatchRect, or a Control carrying a "panel" stylebox), or a text Control (Label, RichTextLabel, Button) with no
## surface above it. A surface's descendants are its content, never a collision. A surface covering most of the screen
## is a BACKDROP (a dim layer, a full-screen background) and is reported apart, since it covers everything by design.
##
## Rects are screen-space through get_global_transform_with_canvas, so a CanvasLayer's offset/scale and a Camera2D are
## applied (overworld 23399).
##
## DECLARED = {"a|b": "reason"}: an intended overlap, keyed by the two ids in either order. An id ending in "*" matches
## any id with that prefix. Every entry needs a reason, and stale() names entries that matched nothing.

const AdvanceAuraClass = preload("res://src/battle/AdvanceAura.gd")
const BACKDROP_SHARE := 0.85
const MIN_PX := 1.0


## [{"id", "rect", "node"}] for every surface under `root` (and {"backdrops": ...} via backdrops()).
static func surfaces(root: Node) -> Array:
	var out: Array = []
	var vp: Vector2 = root.get_viewport().get_visible_rect().size if root.is_inside_tree() else Vector2(1280, 720)
	_walk(root, false, out, vp, false)
	return out


static func backdrops(root: Node) -> Array:
	var out: Array = []
	var vp: Vector2 = root.get_viewport().get_visible_rect().size if root.is_inside_tree() else Vector2(1280, 720)
	_walk(root, false, out, vp, true)
	return out


## "a ∩ b at rect" for every intersecting pair not DECLARED. `used` collects the declared keys that matched, for stale().
static func collisions(surfs: Array, declared: Dictionary, used: Dictionary = {}) -> Array:
	var out: Array = []
	for i in surfs.size():
		for j in range(i + 1, surfs.size()):
			var a: Dictionary = surfs[i]
			var b: Dictionary = surfs[j]
			var hit: Rect2 = (a["rect"] as Rect2).intersection(b["rect"])
			if hit.size.x < MIN_PX or hit.size.y < MIN_PX:
				continue
			var key := _declared_key(declared, str(a["id"]), str(b["id"]))
			if key != "":
				used[key] = true
				continue
			out.append("%s ∩ %s at %s" % [a["id"], b["id"], str(hit)])
	return out


## Declared entries that matched no collision in any phase fed through `used`, or that carry no reason.
static func stale(declared: Dictionary, used: Dictionary) -> Array:
	var out: Array = []
	for k in declared:
		if str(declared[k]).strip_edges() == "":
			out.append("%s has no reason" % k)
		elif not used.has(k):
			out.append("%s matched nothing" % k)
	return out


## A stable id: the surface's own name, or its class (plus sibling index) when Godot auto-named it, under its nearest
## named ancestor, so the declared list survives a rebuild.
static func id_of(n: Node) -> String:
	var own := _name_of(n)
	var p := n.get_parent()
	while p != null and str(p.name).begins_with("@"):
		p = p.get_parent()
	return ("%s/%s" % [p.name, own]) if p != null else own


static func _name_of(n: Node) -> String:
	if not str(n.name).begins_with("@"):
		return str(n.name)
	var cls: String = n.get_script().get_global_name() if n.get_script() and n.get_script().get_global_name() != "" else n.get_class()
	var idx := 0
	if n.get_parent():
		for s in n.get_parent().get_children():
			if s == n:
				break
			if str(s.name).begins_with("@") and s.get_class() == n.get_class():
				idx += 1
	return "%s#%d" % [cls, idx]


static func _walk(n: Node, under: bool, out: Array, vp: Vector2, want_backdrops: bool) -> void:
	if n is CanvasLayer and not (n as CanvasLayer).visible:
		return
	var is_surf := false
	if n is Control:
		var c := n as Control
		if not c.is_visible_in_tree():
			return
		if c.modulate.a > 0.02 and (_draws_background(c) or (not under and _is_text(c))):
			var r := screen_rect(c)
			if r.size.x >= MIN_PX and r.size.y >= MIN_PX:
				is_surf = true
				var backdrop: bool = r.size.x * r.size.y >= BACKDROP_SHARE * vp.x * vp.y
				if backdrop == want_backdrops:
					out.append({"id": id_of(c), "rect": r, "node": c})
	for ch in n.get_children():
		_walk(ch, under or is_surf, out, vp, want_backdrops)


## A battler's FIGURE as a surface: its opaque idle body in screen space, not its texture box (main 23419: a menu over
## the monster being targeted is a finding). Node2D sprites are not Controls, so a guard adds these to surfaces() itself.
static func sprite_surface(id: String, sprite: AnimatedSprite2D) -> Dictionary:
	var fr: Rect2 = AdvanceAuraClass.figure_rect_in_sprite(sprite, &"idle")
	var s: Vector2 = sprite.scale.abs()
	var local := Rect2(fr.position / Vector2(maxf(s.x, 0.001), maxf(s.y, 0.001)), fr.size / Vector2(maxf(s.x, 0.001), maxf(s.y, 0.001)))
	var xf: Transform2D = sprite.get_global_transform_with_canvas()
	var a: Vector2 = xf * local.position
	var b: Vector2 = xf * local.end
	return {"id": id, "rect": Rect2(a, b - a).abs(), "node": sprite}


static func screen_rect(c: Control) -> Rect2:
	var xf: Transform2D = c.get_global_transform_with_canvas()
	return Rect2(xf.origin, c.size * xf.get_scale()).abs()


static func _draws_background(c: Control) -> bool:
	if c is Panel or c is PanelContainer or c is NinePatchRect:
		return true
	if c is ColorRect:
		return (c as ColorRect).color.a > 0.02
	if c is TextureRect:
		return (c as TextureRect).texture != null
	return c.has_theme_stylebox_override("panel")


static func _is_text(c: Control) -> bool:
	if c is Label:
		return (c as Label).text.strip_edges() != ""
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text().strip_edges() != ""
	return c is Button and (c as Button).text.strip_edges() != ""


static func _declared_key(declared: Dictionary, a: String, b: String) -> String:
	for k in declared:
		var parts: PackedStringArray = str(k).split("|")
		if parts.size() != 2:
			continue
		if (_match(parts[0], a) and _match(parts[1], b)) or (_match(parts[0], b) and _match(parts[1], a)):
			return str(k)
	return ""


static func _match(pat: String, id: String) -> bool:
	return id.begins_with(pat.trim_suffix("*")) if pat.ends_with("*") else id == pat
