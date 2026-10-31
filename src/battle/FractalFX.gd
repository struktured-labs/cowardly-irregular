extends RefCounted
class_name FractalFX

## Issue #399 prototype — recursive, self-similar battle FX driven by data/vfx_sequences.json.
##
## A sequence is a list of timed PHASES. The core primitive is `emit`: N flames fly out from a
## point over an arc (360 = radial symmetry), and each flame, near the end of its flight, becomes
## the origin of a smaller copy of the same emit — so a burst fans, and each fan re-bursts. Depth
## is the escalation knob: `depth` re-runs a spec inside itself, or `child` nests a different one.
##
## A LAYER over sprites: it adds nodes to `host` and only ever reads or briefly pauses actor sprites
## (afterimages are copies), so artist frames are never edited. Not wired to abilities yet — the
## prototype is judged on clips (tools/fx_clip.sh) before anything plays it in battle.

const SEQUENCES_PATH := "res://data/vfx_sequences.json"
## One cast must not be able to allocate unbounded nodes, whatever depth the data asks for.
const FLAME_CAP := 900

const PALETTES := {
	"fire": [[0.0, Color(1.0, 1.0, 0.85, 1.0)], [0.18, Color(1.0, 0.82, 0.25, 1.0)],
		[0.5, Color(1.0, 0.42, 0.06, 0.9)], [1.0, Color(0.55, 0.06, 0.02, 0.0)]],
	"ember": [[0.0, Color(1.0, 0.75, 0.3, 0.9)], [1.0, Color(0.6, 0.1, 0.0, 0.0)]],
	"spark": [[0.0, Color(1.0, 1.0, 1.0, 1.0)], [0.3, Color(0.75, 0.95, 1.0, 1.0)],
		[1.0, Color(1.0, 0.85, 0.3, 0.0)]],
	"steel": [[0.0, Color(1.0, 1.0, 1.0, 0.95)], [0.4, Color(0.7, 0.85, 1.0, 0.7)],
		[1.0, Color(0.4, 0.5, 0.9, 0.0)]],
}

static var _tex_cache: Dictionary = {}
## A caller usually drops its FractalFX as soon as play() returns, and the delayed phases are bound
## to this instance — so play() keeps it alive here until its sequence has ended.
static var _live: Array = []
static var _add_mat: CanvasItemMaterial = null
static var _silhouette_shader: Shader = null

var host: Node2D
var actors: Dictionary = {}
var reduce_flashes: bool = false
## (intensity_px, duration_s) — the caller owns the camera.
var on_shake: Callable = Callable()
var spawned: int = 0
var rng := RandomNumberGenerator.new()
var _ramps: Dictionary = {}


func _init(p_host: Node2D, seed: int = 0) -> void:
	host = p_host
	rng.seed = seed if seed != 0 else int(Time.get_ticks_usec())


static func load_sequence(id: String) -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(SEQUENCES_PATH))
	if not (raw is Dictionary):
		return {}
	var seqs = raw.get("sequences", {})
	return seqs.get(id, {}) if seqs is Dictionary else {}


## Starts every phase at its `at` (battle seconds) and returns when the last one ends.
## `start` shifts every phase so the sequence lands on the caster's authored release frame.
func play(seq: Dictionary, from: Vector2, to: Vector2, power: float = 1.0) -> float:
	var total := 0.0
	var start := float(seq.get("start", 0.0))
	for phase in seq.get("phases", []):
		if not (phase is Dictionary):
			continue
		var at := start + float(phase.get("at", 0.0))
		total = maxf(total, at + phase_duration(phase))
		if at <= 0.0:
			_run(phase, from, to, power)
		else:
			host.get_tree().create_timer(at).timeout.connect(_run.bind(phase, from, to, power))
	_live.append(self)
	host.get_tree().create_timer(total + 0.5).timeout.connect(_release)
	return total


func _release() -> void:
	_live.erase(self)


## How long a phase occupies the timeline, recursion included.
static func phase_duration(phase: Dictionary) -> float:
	match str(phase.get("kind", "")):
		"emit":
			return _emit_duration(phase, int(phase.get("depth", 0)))
		"spin_fling":
			var tail := 0.0
			if phase.get("child") is Dictionary:
				tail = _emit_duration(phase["child"], int(phase["child"].get("depth", 0)))
			return float(phase.get("spin", 0.5)) + float(phase.get("fling", 0.35)) + tail
		_:
			return float(phase.get("dur", 0.2))


static func _emit_duration(spec: Dictionary, depth_left: int) -> float:
	var life := float(spec.get("life", 0.35))
	var child_at := float(spec.get("child_at", 0.8))
	if depth_left > 0:
		return life * child_at + _emit_duration(spec, depth_left - 1) * float(spec.get("time_decay", 0.8))
	if spec.get("child") is Dictionary:
		return life * child_at + _emit_duration(spec["child"], int(spec["child"].get("depth", 0)))
	return life


func _run(phase: Dictionary, from: Vector2, to: Vector2, power: float) -> void:
	if not is_instance_valid(host):
		return
	var at_pos: Vector2 = from if str(phase.get("origin", "target")) == "caster" else to
	at_pos += _vec(phase.get("offset", [0, 0]))
	match str(phase.get("kind", "")):
		"bolt":
			_bolt(from, to, phase, power)
		"emit":
			var heading := deg_to_rad(float(phase.get("heading", 0.0)))
			if bool(phase.get("aim", false)):
				heading = (to - from).angle()
			_emit(at_pos, phase, heading, power, int(phase.get("depth", 0)))
		"spin_fling":
			_spin_fling(at_pos, phase, power)
		"ring":
			_ring(at_pos, phase, power)
		"flash":
			_flash(at_pos, phase, power)
		"shake":
			if on_shake.is_valid():
				on_shake.call(float(phase.get("intensity", 8.0)) * power, float(phase.get("dur", 0.25)))
		"lunge":
			_lunge(phase)
		"impact_frame":
			_impact_frame(phase)
		"hitstop":
			_hitstop(phase)
		"knockback":
			_knockback(phase)
		"slash":
			_slash(at_pos, phase, power)
		_:
			push_warning("[FractalFX] unknown phase kind '%s'" % str(phase.get("kind", "")))


# ── the recursive emitter ───────────────────────────────────────────

func _emit(origin: Vector2, spec: Dictionary, heading: float, k: float, depth_left: int) -> void:
	var count := int(spec.get("count", 8))
	var arc := deg_to_rad(float(spec.get("arc", 360.0)))
	var radius := float(spec.get("radius", 60.0)) * k
	var life := float(spec.get("life", 0.35))
	var size := float(spec.get("size", 1.0)) * k
	var jitter := deg_to_rad(float(spec.get("jitter", 6.0)))
	var stretch := float(spec.get("stretch", 1.6))
	var child_at := float(spec.get("child_at", 0.8))
	var ramp := _ramp(str(spec.get("palette", "fire")))
	var base := heading + deg_to_rad(float(spec.get("twist", 0.0)))
	var radial := arc >= TAU - 0.001
	if bool(spec.get("bloom", true)):
		_bloom(origin, size * 1.6, life * 0.7, ramp)
	var next: Dictionary = {}
	var next_depth := 0
	var next_k := k * float(spec.get("decay", 0.55))
	if depth_left > 0:
		next = spec.duplicate()
		next["life"] = life * float(spec.get("time_decay", 0.8))
		next["bloom"] = spec.get("child_bloom", spec.get("bloom", true))
		next_depth = depth_left - 1
	elif spec.get("child") is Dictionary:
		next = spec["child"]
		next_depth = int(next.get("depth", 0))
	for i in count:
		if spawned >= FLAME_CAP:
			return
		var a: float
		if radial:
			a = base + TAU * float(i) / float(count)
		elif count > 1:
			a = base - arc * 0.5 + arc * float(i) / float(count - 1)
		else:
			a = base
		a += rng.randf_range(-jitter, jitter)
		var end := origin + Vector2.from_angle(a) * radius * rng.randf_range(0.85, 1.15)
		var s := _flame(origin, size * 0.5, ramp)
		var then := Callable()
		if not next.is_empty():
			var child_heading := a
			then = func() -> void:
				if is_instance_valid(s):
					_emit(s.position, next, child_heading, next_k, next_depth)
		_fly(s, origin, end, life, size, stretch, ramp, then, child_at)


func _fly(s: Sprite2D, start: Vector2, end: Vector2, life: float, size: float, stretch: float,
		ramp: Gradient, then: Callable, child_at: float) -> void:
	s.rotation = (end - start).angle()
	var tw := host.create_tween().set_parallel(true)
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(s):
			return
		var e := 1.0 - pow(1.0 - t, 3.0)
		s.position = start.lerp(end, e)
		var swell := minf(t * 5.0, 1.0)
		var body := size * lerpf(1.0, 0.35, t) * (0.5 + 0.5 * swell)
		## Long while fast, round as it slows: the speed reads as a streak without a trail node.
		var streak := 1.0 + stretch * pow(1.0 - t, 2.0)
		s.scale = Vector2(body * streak, body)
		s.modulate = ramp.sample(t), 0.0, 1.0, life)
	if then.is_valid():
		tw.tween_callback(then).set_delay(life * child_at)
	tw.chain().tween_callback(s.queue_free)


func _bloom(pos: Vector2, size: float, life: float, ramp: Gradient) -> void:
	var g := _flame(pos, size * 0.4, ramp)
	g.texture = _tex("soft")
	var tw := host.create_tween().set_parallel(true)
	tw.tween_property(g, "scale", Vector2.ONE * size, life * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(g):
			g.modulate = ramp.sample(t), 0.0, 1.0, life)
	tw.chain().tween_callback(g.queue_free)


# ── phases ──────────────────────────────────────────────────────────

func _bolt(from: Vector2, to: Vector2, p: Dictionary, k: float) -> void:
	var dur := float(p.get("dur", 0.4))
	var lift := float(p.get("arc_height", 40.0))
	var size := float(p.get("size", 1.4)) * k
	var spacing := float(p.get("trail_spacing", 10.0))
	var ramp := _ramp(str(p.get("palette", "fire")))
	var ember := _ramp("ember")
	var head := _flame(from, size, ramp)
	head.modulate = ramp.sample(0.05)
	var mid := (from + to) * 0.5 + Vector2(0, -lift)
	var last := [from]
	var tw := host.create_tween()
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(head):
			return
		var pos := from.lerp(mid, t).lerp(mid.lerp(to, t), t)
		var step: Vector2 = pos - last[0]
		if step.length() > 0.01:
			head.rotation = step.angle()
		head.scale = Vector2(size * 1.8, size)
		while (pos - last[0]).length() >= spacing:
			last[0] = last[0] + (pos - last[0]).normalized() * spacing
			_trail_ember(last[0], size * 0.55, ember), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(head.queue_free)


func _trail_ember(pos: Vector2, size: float, ramp: Gradient) -> void:
	var e := _flame(pos, size, ramp)
	var drift := pos + Vector2(rng.randf_range(-6, 6), rng.randf_range(-22, -10))
	var life := rng.randf_range(0.18, 0.3)
	var tw := host.create_tween().set_parallel(true)
	tw.tween_property(e, "position", drift, life)
	tw.tween_property(e, "scale", Vector2.ONE * size * 0.2, life)
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(e):
			e.modulate = ramp.sample(t), 0.0, 1.0, life)
	tw.chain().tween_callback(e.queue_free)


## A ring of flames winds up around the target, then every one is flung out along a spiral.
func _spin_fling(center: Vector2, p: Dictionary, k: float) -> void:
	var n := int(p.get("count", 10))
	var r0 := float(p.get("radius", 70.0)) * k
	var r1 := float(p.get("inner", 26.0)) * k
	var turns := float(p.get("turns", 1.25))
	var spin := float(p.get("spin", 0.5))
	var fling := float(p.get("fling", 0.35))
	var out := float(p.get("distance", 150.0)) * k
	var size := float(p.get("size", 1.1)) * k
	var ramp := _ramp(str(p.get("palette", "fire")))
	var child = p.get("child", null)
	for i in n:
		if spawned >= FLAME_CAP:
			return
		var a0 := TAU * float(i) / float(n)
		var s := _flame(center + Vector2.from_angle(a0) * r0, size, ramp)
		s.modulate = ramp.sample(0.1)
		var tw := host.create_tween()
		tw.tween_method(func(t: float) -> void:
			if not is_instance_valid(s):
				return
			var a := a0 + turns * TAU * (t * t)
			s.position = center + Vector2.from_angle(a) * lerpf(r0, r1, t)
			s.rotation = a + PI * 0.5
			s.scale = Vector2(size * (1.0 + 1.4 * t), size), 0.0, 1.0, spin)
		var a_end := a0 + turns * TAU
		## Tangent plus outward: the fling leaves along the spin, which is what reads as a spiral.
		var dir := Vector2.from_angle(a_end + PI * 0.3)
		var start := center + Vector2.from_angle(a_end) * r1
		tw.tween_callback(func() -> void:
			if not is_instance_valid(s):
				return
			var then := Callable()
			if child is Dictionary:
				var cd: Dictionary = child
				var h := dir.angle()
				then = func() -> void:
					if is_instance_valid(s):
						_emit(s.position, cd, h, k * float(cd.get("scale", 0.6)), int(cd.get("depth", 0)))
			_fly(s, start, start + dir * out, fling, size * 1.2, 2.4, ramp, then, 0.85))


func _ring(pos: Vector2, p: Dictionary, k: float) -> void:
	var r := Sprite2D.new()
	r.texture = _tex("ring")
	r.material = _additive()
	r.position = pos
	r.scale = Vector2.ONE * 0.2
	r.modulate = _ramp(str(p.get("palette", "fire"))).sample(0.15)
	host.add_child(r)
	var dur := float(p.get("dur", 0.3))
	var tw := host.create_tween().set_parallel(true)
	tw.tween_property(r, "scale", Vector2.ONE * float(p.get("scale", 3.5)) * k, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(r.queue_free)


func _flash(pos: Vector2, p: Dictionary, k: float) -> void:
	## Reduce Flashes keeps the beat but drops it to a local glow nobody has to look away from.
	var size := float(p.get("size", 9.0)) * k * (0.35 if reduce_flashes else 1.0)
	var peak := float(p.get("alpha", 0.85)) * (0.4 if reduce_flashes else 1.0)
	var g := _flame(pos, size * 0.6, _ramp("fire"))
	g.texture = _tex("soft")
	g.modulate = Color(1.0, 0.95, 0.8, 0.0)
	var dur := float(p.get("dur", 0.2))
	var tw := host.create_tween()
	tw.tween_property(g, "modulate:a", peak, dur * 0.15)
	tw.parallel().tween_property(g, "scale", Vector2.ONE * size, dur * 0.15)
	tw.tween_property(g, "modulate:a", 0.0, dur * 0.85).set_ease(Tween.EASE_IN)
	tw.tween_callback(g.queue_free)


func _slash(center: Vector2, p: Dictionary, k: float) -> void:
	## A crescent swept in order, so the arc reads as one motion rather than a shape that appears.
	var n := int(p.get("count", 14))
	var radius := float(p.get("radius", 64.0)) * k
	var a0 := deg_to_rad(float(p.get("from", -120.0)))
	var a1 := deg_to_rad(float(p.get("to", 40.0)))
	var sweep := float(p.get("dur", 0.12))
	var ramp := _ramp(str(p.get("palette", "steel")))
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		var a := lerpf(a0, a1, t)
		var pos := center + Vector2.from_angle(a) * radius
		var thick := sin(PI * t) * float(p.get("size", 1.3)) * k
		host.get_tree().create_timer(sweep * t).timeout.connect(func() -> void:
			if not is_instance_valid(host):
				return
			var s := _flame(pos, thick, ramp)
			s.rotation = a + PI * 0.5
			s.scale = Vector2(thick * 2.6, thick * 0.6)
			var tw := host.create_tween()
			tw.tween_method(func(u: float) -> void:
				if is_instance_valid(s):
					s.modulate = ramp.sample(u), 0.0, 1.0, float(p.get("life", 0.22)))
			tw.tween_callback(s.queue_free))


func _lunge(p: Dictionary) -> void:
	var who: Node2D = actors.get(str(p.get("actor", "caster")))
	var toward: Node2D = actors.get(str(p.get("toward", "target")))
	if not is_instance_valid(who) or not is_instance_valid(toward):
		return
	var home := who.position
	var reach := float(p.get("distance", 0.7))
	var dest := home.lerp(toward.position, reach)
	var dur := float(p.get("dur", 0.14))
	var hold := float(p.get("hold", 0.12))
	var back := float(p.get("back", 0.2))
	var every := float(p.get("ghost_every", 0.025))
	var tw := host.create_tween()
	tw.tween_property(who, "position", dest, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_interval(hold)
	tw.tween_property(who, "position", home, back).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	## `ghost_from` skips frames the artist already drew a smear on, so the trail never doubles it.
	var from_t := float(p.get("ghost_from", 0.0))
	var ghosts := int(ceil((dur - from_t) / maxf(every, 0.005)))
	for i in ghosts:
		var t := from_t + every * i
		if t <= 0.0:
			_afterimage(who, p)
		else:
			host.get_tree().create_timer(t).timeout.connect(_afterimage.bind(who, p))


## A COPY of the sprite's current frame, tinted and faded; the original is never touched.
func _afterimage(src: Node2D, p: Dictionary) -> void:
	if not is_instance_valid(src) or not is_instance_valid(host):
		return
	var g := Sprite2D.new()
	if src is AnimatedSprite2D:
		var a := src as AnimatedSprite2D
		if a.sprite_frames == null:
			return
		g.texture = a.sprite_frames.get_frame_texture(a.animation, a.frame)
		g.flip_h = a.flip_h
	elif src is Sprite2D:
		g.texture = (src as Sprite2D).texture
		g.flip_h = (src as Sprite2D).flip_h
	else:
		return
	g.position = src.position
	g.scale = src.scale
	g.z_index = src.z_index - 1
	g.material = _additive()
	g.modulate = _color(p.get("ghost_color", [0.55, 0.75, 1.0, 0.55]))
	host.add_child(g)
	var tw := host.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, float(p.get("ghost_fade", 0.2)))
	tw.tween_callback(g.queue_free)


## Classic impact frames: a dark silhouette, then a white one, each held a few frames.
func _impact_frame(p: Dictionary) -> void:
	var who: Node2D = actors.get(str(p.get("actor", "target")))
	if not is_instance_valid(who):
		return
	var frame := float(p.get("frame", 0.035))
	var mat := ShaderMaterial.new()
	mat.shader = _silhouette()
	mat.set_shader_parameter("tint", Color(0.05, 0.0, 0.1, 1.0))
	var was: Material = who.material
	who.material = mat
	var tw := host.create_tween()
	tw.tween_interval(frame)
	tw.tween_callback(func() -> void: mat.set_shader_parameter("tint", Color(1, 1, 1, 1)))
	tw.tween_interval(frame * 1.5)
	tw.tween_callback(func() -> void:
		if is_instance_valid(who):
			who.material = was)


func _hitstop(p: Dictionary) -> void:
	var dur := float(p.get("dur", 0.09))
	for key in p.get("actors", ["caster", "target"]):
		var a = actors.get(str(key))
		if a is AnimatedSprite2D and is_instance_valid(a):
			var sprite: AnimatedSprite2D = a
			var was := sprite.speed_scale
			sprite.speed_scale = 0.0
			host.get_tree().create_timer(dur).timeout.connect(func() -> void:
				if is_instance_valid(sprite):
					sprite.speed_scale = was)


func _knockback(p: Dictionary) -> void:
	var who: Node2D = actors.get(str(p.get("actor", "target")))
	if not is_instance_valid(who):
		return
	var home := who.position
	var base := who.scale
	var push := Vector2(float(p.get("distance", 18.0)), 0.0)
	var dur := float(p.get("dur", 0.24))
	var tw := host.create_tween().set_parallel(true)
	tw.tween_property(who, "position", home + push, dur * 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(who, "scale", base * Vector2(0.86, 1.12), dur * 0.2)
	tw.chain().tween_property(who, "position", home, dur * 0.75).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(who, "scale", base, dur * 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# ── nodes, textures, colours ────────────────────────────────────────

func _flame(pos: Vector2, size: float, ramp: Gradient) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _tex("flame")
	s.material = _additive()
	s.position = pos
	s.scale = Vector2.ONE * size
	s.modulate = ramp.sample(0.0)
	host.add_child(s)
	spawned += 1
	return s


func _ramp(name: String) -> Gradient:
	if _ramps.has(name):
		return _ramps[name]
	var g := Gradient.new()
	var stops: Array = PALETTES.get(name, PALETTES["fire"])
	g.offsets = PackedFloat32Array(stops.map(func(s): return float(s[0])))
	g.colors = PackedColorArray(stops.map(func(s): return s[1]))
	_ramps[name] = g
	return g


static func _additive() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


static func _silhouette() -> Shader:
	if _silhouette_shader == null:
		_silhouette_shader = Shader.new()
		_silhouette_shader.code = "shader_type canvas_item;\nuniform vec4 tint : source_color = vec4(1.0);\nvoid fragment() { COLOR = vec4(tint.rgb, texture(TEXTURE, UV).a * tint.a); }\n"
	return _silhouette_shader


static func _tex(kind: String) -> Texture2D:
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var d := (Vector2(x, y) + Vector2(0.5, 0.5) - c) / (n * 0.5)
			var a := 0.0
			match kind:
				"flame":
					## Hot core, soft falloff, brighter toward the leading edge.
					var r := Vector2(d.x * 0.85 - 0.08, d.y).length()
					a = clampf(1.0 - r, 0.0, 1.0)
					a = a * a * (1.0 + 0.6 * clampf(1.0 - r * 2.5, 0.0, 1.0))
				"soft":
					a = pow(clampf(1.0 - d.length(), 0.0, 1.0), 2.2)
				"ring":
					a = clampf(1.0 - absf(d.length() - 0.8) * 9.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var t := ImageTexture.create_from_image(img)
	_tex_cache[kind] = t
	return t


static func _vec(v) -> Vector2:
	return Vector2(float(v[0]), float(v[1])) if v is Array and v.size() >= 2 else Vector2.ZERO


static func _color(v) -> Color:
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return Color.WHITE
