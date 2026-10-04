extends GutTest

## struktured 2026-10-03: "the 2ndaries are also supposed to slightly modify the artist sprite, that never seemed to
## materialize". load_sprite_frames returned the artist sheet as soon as the primary had one, so the secondary reached
## only the procedural sprite (SnesPartySprites' palette tint) — and every starter has an artist sheet.
## Now a sheet NAMES the artist palette entries a secondary may lean (manifest "secondary_accent"), and the battle
## sprite's flash shader leans them toward the secondary's battle colour (JOB_QUIP_COLORS) at runtime. His PNGs are
## never touched and no sheet is registered. The leaned pixels are only visible on a real renderer (checked under xvfb);
## here: what the GPU is handed, per real battle sprite, and that the named entries are his and a slight share.

const SCENE := "res://src/battle/BattleScene.tscn"
const JuiceScript := preload("res://src/battle/BattleJuice.gd")
const SceneScript := preload("res://src/battle/BattleScene.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]
## Share of an idle figure's opaque pixels the named entries reach: enough to read, never most of the sprite.
const MIN_SHARE := 0.02
const MAX_SHARE := 0.25

var _guard: RefCounted = null
var _scene: Node = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()
	_scene = load(SCENE).instantiate()
	add_child_autofree(_scene)


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _sprite_for(primary: String, secondary: String) -> AnimatedSprite2D:
	var pc := Combatant.new()
	pc.combatant_name = primary.capitalize()
	pc.job = JobSystem.get_job(primary)
	pc.secondary_job_id = secondary
	pc.max_hp = 40
	pc.current_hp = 40
	pc.is_alive = true
	autofree(pc)
	# Typed Array[Combatant]: assigning a plain [pc] aborts this helper, so fill it in place
	_scene.party_members.clear()
	_scene.party_members.append(pc)
	_scene.test_enemies.clear()
	_scene._create_battle_sprites()
	return _scene.party_sprite_nodes[0] if not _scene.party_sprite_nodes.is_empty() else null


## The material's accent_count, 0 when never set: unwired, the uniform reads back null and int(null) aborts the arm.
func _count(mat: ShaderMaterial) -> int:
	var v = mat.get_shader_parameter("accent_count")
	return int(v) if v != null else 0


func _accented() -> Array:
	var out: Array = []
	for job in STARTERS:
		if not HybridSpriteLoader.secondary_accent(job).is_empty():
			out.append(job)
	return out


func test_every_artist_starter_names_an_accent() -> void:
	assert_eq(_accented(), STARTERS, "every artist starter sheet names the entries a secondary may lean")


func test_each_artist_job_wears_its_secondary() -> void:
	var bad: Array = []
	var judged := 0
	for primary in _accented():
		var want: int = HybridSpriteLoader.secondary_accent(primary).size()
		for secondary in STARTERS:
			if secondary == primary:
				continue
			var spr := _sprite_for(primary, secondary)
			var mat := spr.material as ShaderMaterial if spr else null
			judged += 1
			if mat == null:
				bad.append("%s/%s: no material" % [primary, secondary])
				continue
			if _count(mat) != want:
				bad.append("%s/%s: %s of %d entries leaned" % [primary, secondary, _count(mat), want])
			elif mat.get_shader_parameter("accent_to") != SceneScript.JOB_QUIP_COLORS[secondary]:
				bad.append("%s/%s: leaned toward %s, not the %s's colour" % [primary, secondary, mat.get_shader_parameter("accent_to"), secondary])
			elif float(mat.get_shader_parameter("accent_amount")) <= 0.0:
				bad.append("%s/%s: leaned by nothing" % [primary, secondary])
	assert_gt(judged, 15, "CONTROL: primary x secondary pairs were built (%d)" % judged)
	assert_eq(bad, [], "artist sprites that do not show their secondary: %s" % str(bad))


func test_no_secondary_or_its_own_job_leaves_the_sprite_as_drawn() -> void:
	for job in STARTERS:
		var plain := _sprite_for(job, "")
		assert_eq(_count(plain.material as ShaderMaterial), 0, "%s with no secondary is drawn as is" % job)
		var same := _sprite_for(job, job)
		assert_eq(_count(same.material as ShaderMaterial), 0, "%s/%s is drawn as is" % [job, job])


func test_the_lean_rides_the_flash_material() -> void:
	## One material per sprite, identified by its shader: a second material would cost the hit flash and death dissolve.
	var spr := _sprite_for("fighter", "mage")
	assert_true(spr.material is ShaderMaterial and (spr.material as ShaderMaterial).shader == JuiceScript.FLASH_SHADER,
		"the secondary lean is on the battle flash material, not a replacement")


func test_a_secondary_adds_no_art() -> void:
	## Artist-first: the frames a secondary draws are the frames the job draws without one — his sheet, nothing new.
	var plain := _sprite_for("bard", "")
	var leaned := _sprite_for("bard", "mage")
	var a := _sheet_paths(plain.sprite_frames)
	var b := _sheet_paths(leaned.sprite_frames)
	assert_gt(a.size(), 0, "CONTROL: the bard's frames come from sheet files")
	assert_eq(b, a, "a secondary draws the same sheet files")
	for p in b:
		assert_true(str(p).begins_with("res://assets/sprites/jobs/bard/"), "%s is the bard's own art" % p)


func _sheet_paths(sf: SpriteFrames) -> Array:
	var out: Array = []
	for anim in sf.get_animation_names():
		for i in sf.get_frame_count(anim):
			var t := sf.get_frame_texture(anim, i)
			var path := (t as AtlasTexture).atlas.resource_path if t is AtlasTexture else t.resource_path
			if not out.has(path):
				out.append(path)
	out.sort()
	return out


func _pixels(tex: Texture2D) -> Image:
	var img: Image = tex.get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _near(d: PackedByteArray, o: int, entries: PackedColorArray) -> int:
	## Index of the named entry this pixel matches under the shader's rule, else -1.
	var p := Vector3(d[o], d[o + 1], d[o + 2]) / 255.0
	for k in entries.size():
		if p.distance_to(Vector3(entries[k].r, entries[k].g, entries[k].b)) <= HybridSpriteLoader.SECONDARY_ACCENT_TOLERANCE:
			return k
	return -1


func test_the_accent_is_his_palette_and_a_slight_share_of_the_figure() -> void:
	assert_gt(_accented().size(), 0, "CONTROL: some sheet names an accent to judge")
	var bad: Array = []
	for job in _accented():
		var entries := HybridSpriteLoader.secondary_accent(job)
		var sf: SpriteFrames = HybridSpriteLoader.load_sprite_frames(null, job)
		var seen := {}
		var anims: Array = Array(sf.get_animation_names())
		anims.erase(&"idle")
		anims.push_front(&"idle")
		for anim in anims:
			if seen.size() == entries.size():
				break
			if sf.get_frame_count(anim) == 0 or sf.get_frame_texture(anim, 0) == null:
				continue
			var d := _pixels(sf.get_frame_texture(anim, 0)).get_data()
			for o in range(0, d.size(), 4):
				if d[o + 3] < 128:
					continue
				# Every entry this pixel is within tolerance of: two near shades (cleric #60a0ff/#639bff) both count
				var p := Vector3(d[o], d[o + 1], d[o + 2]) / 255.0
				for k in entries.size():
					if p.distance_to(Vector3(entries[k].r, entries[k].g, entries[k].b)) <= HybridSpriteLoader.SECONDARY_ACCENT_TOLERANCE:
						seen[k] = true
		for k in entries.size():
			if not seen.has(k):
				bad.append("%s: %s is in none of its animations' first frames" % [job, entries[k].to_html(false)])
		for i in sf.get_frame_count(&"idle"):
			var d := _pixels(sf.get_frame_texture(&"idle", i)).get_data()
			var opaque := 0
			var hit := 0
			for o in range(0, d.size(), 4):
				if d[o + 3] >= 128:
					opaque += 1
					if _near(d, o, entries) >= 0:
						hit += 1
			var share := float(hit) / maxf(1.0, float(opaque))
			if share < MIN_SHARE or share > MAX_SHARE:
				bad.append("%s idle %d: the accent is %.1f%% of the figure" % [job, i, share * 100.0])
	assert_eq(bad, [], "accent entries that are not a slight share of his art: %s" % str(bad))
