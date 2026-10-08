extends Node2D
class_name DungeonAmbience
## Ambient animated dressing for dungeon floors -- flickering torches live in
## DungeonLighting; this node owns drip/crystal/steam/shimmer/sparkle/arc/mote
## props derived deterministically from a floor's ASCII rows, never from a
## per-frame random source, so a save/reload or a floor rebuild reproduces
## the same dressing. Capped effect count keeps this one cheap, allocation-
## free-at-steady-state layer (positions/colors are fixed at build time; only
## modulate/offset change in _process).

const TILE_SIZE: int = 32
const MAX_EFFECTS: int = 28

var _t: float = 0.0
var _effects: Array = []


func _process(delta: float) -> void:
	_t += delta
	for e in _effects:
		var spr: CanvasItem = e.get("node")
		if spr == null or not is_instance_valid(spr):
			continue
		var phase: float = e["phase"]
		match e["kind"]:
			"shimmer":
				spr.modulate.a = 0.45 + 0.35 * sin(_t * 4.0 + phase)
			"sparkle":
				spr.modulate.a = 0.35 + 0.5 * absf(sin(_t * 3.2 + phase))
			"arc":
				spr.visible = fmod(_t * 1.6 + phase, 1.0) < 0.10
			"mote":
				var base: Vector2 = e["base_pos"]
				spr.position = base + Vector2(sin(_t * 0.55 + phase) * 5.0, -fmod(_t * 10.0 + phase * 14.0, 26.0))
				spr.modulate.a = 0.5 + 0.3 * sin(_t * 1.2 + phase)
			"drip":
				var fall: float = fmod(_t * 16.0 + phase * 9.0, 22.0)
				spr.position.y = e["base_pos"].y + fall
				spr.modulate.a = clampf(1.0 - fall / 22.0, 0.0, 1.0)
			"crystal":
				spr.modulate.a = 0.55 + 0.3 * sin(_t * 1.8 + phase)
			"puddle":
				spr.modulate.a = 0.25 + 0.35 * maxf(0.0, sin(_t * 1.3 + phase))
			"vent":
				var rise: float = fmod(_t * 11.0 + phase * 8.0, 24.0)
				spr.position.y = e["base_pos"].y - rise
				spr.modulate.a = clampf(1.0 - rise / 24.0, 0.0, 1.0)


func clear() -> void:
	for child in get_children():
		child.queue_free()
	_effects.clear()


func _add(kind: String, pos: Vector2, color: Color, size: Vector2, phase: float) -> void:
	if _effects.size() >= MAX_EFFECTS:
		return
	var spr := ColorRect.new()
	spr.color = color
	spr.size = size
	spr.position = pos - size * 0.5
	add_child(spr)
	_effects.append({"node": spr, "kind": kind, "base_pos": spr.position, "phase": phase})


## Scans a floor's ASCII rows and seeds a bounded, deterministic set of ambient props.
## theme in {"cave","lava","frost","storm","shadow","steam","drain","castle"}. Layout-agnostic: reads
## whatever rows the floor actually has, so a redesigned floor picks this up for free.
func rebuild_for_floor(rows: Array, map_w: int, map_h: int, theme: String, seed_salt: int) -> void:
	clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_salt
	for y in range(mini(map_h, rows.size())):
		var row: String = rows[y]
		for x in range(mini(map_w, row.length())):
			if _effects.size() >= MAX_EFFECTS:
				return
			var ch := row[x]
			var cx := x * TILE_SIZE + TILE_SIZE * 0.5
			var cy := y * TILE_SIZE + TILE_SIZE * 0.5
			var phase := rng.randf() * TAU
			if ch == "l":
				_add("shimmer", Vector2(cx, cy), Color(1.0, 0.55, 0.15, 0.5), Vector2(TILE_SIZE, TILE_SIZE), phase)
			elif ch == "i":
				if (x * 13 + y * 7) % 9 == 0:
					_add("sparkle", Vector2(cx, cy), Color(0.85, 0.95, 1.0, 0.6), Vector2(6, 6), phase)
			elif ch == "M":
				var below_open: bool = y + 1 < rows.size() and x < rows[y + 1].length() and rows[y + 1][x] == "."
				if below_open and (x * 31 + y * 17) % 23 == 0:
					if theme == "storm":
						_add("arc", Vector2(cx, cy + TILE_SIZE * 0.5), Color(0.75, 0.85, 1.0, 0.9), Vector2(3, TILE_SIZE), phase)
					else:
						_add("drip", Vector2(cx, cy), Color(0.55, 0.75, 0.9, 0.7), Vector2(2, 4), phase)
			elif ch == ".":
				var h := (x * 37 + y * 19 + seed_salt) % 97
				if theme == "shadow" and h % 29 == 0:
					_add("mote", Vector2(cx, cy), Color(0.35, 0.15, 0.45, 0.6), Vector2(4, 4), phase)
				# Off-cave themes had no floor branch, so a storm drain and a factory grew cave crystals.
				elif theme == "steam" and (h % 31 == 0 or h % 37 == 0):
					_add("vent", Vector2(cx, cy), Color(0.85, 0.85, 0.85, 0.35), Vector2(5, 10), phase)
				elif theme == "drain" and (h % 31 == 0 or h % 37 == 0):
					_add("puddle", Vector2(cx, cy + 8), Color(0.45, 0.65, 0.85, 0.6), Vector2(12, 3), phase)
				elif theme == "castle" and (h % 31 == 0 or h % 37 == 0):
					_add("mote", Vector2(cx, cy), Color(0.9, 0.85, 0.7, 0.45), Vector2(3, 3), phase)
				elif theme in ["steam", "drain", "castle"]:
					pass
				elif h % 31 == 0:
					_add("crystal", Vector2(cx, cy - 6), Color(0.6, 0.8, 1.0, 0.65), Vector2(5, 5), phase)
				elif h % 37 == 0:
					_add("vent", Vector2(cx, cy), Color(0.85, 0.85, 0.85, 0.35), Vector2(5, 10), phase)
