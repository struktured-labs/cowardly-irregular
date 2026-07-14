extends RefCounted
class_name HybridSpriteLoader

## Hybrid sprite loader that checks for external artist sprite sheets first,
## then falls back to procedural SnesPartySprites generation.

const _SnesPartySprites = preload("res://src/battle/sprites/SnesPartySprites.gd")

static var _manifest: Dictionary = {}
static var _monster_manifest: Dictionary = {}
static var _battle_effects: Dictionary = {}
static var _manifest_loaded: bool = false

static func _load_manifest() -> void:
	if _manifest_loaded:
		return
	# Always set the loaded flag at the END so a failure mid-load
	# doesn't poison the cache — but mark it loaded BEFORE any
	# early-return on failure so we don't re-warn every lookup.
	var file_path = "res://data/sprite_manifest.json"
	if not FileAccess.file_exists(file_path):
		push_warning("[SPRITES] sprite_manifest.json not found at %s — all jobs/monsters will use procedural fallbacks (artist sheets invisible)" % file_path)
		_manifest_loaded = true
		return
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_warning("[SPRITES] sprite_manifest.json exists but FileAccess.open failed — artist sheets invisible")
		_manifest_loaded = true
		return
	var raw := file.get_as_text()
	file.close()
	var json = JSON.new()
	var parse_result := json.parse(raw)
	if parse_result != OK:
		push_warning("[SPRITES] sprite_manifest.json parse error: %s — artist sheets invisible" % json.get_error_message())
		_manifest_loaded = true
		return
	if not (json.data is Dictionary):
		push_warning("[SPRITES] sprite_manifest.json parsed but root is not a Dictionary — artist sheets invisible")
		_manifest_loaded = true
		return
	_manifest = json.data.get("sheets", {})
	_monster_manifest = json.data.get("monster_sheets", {})
	_battle_effects = json.data.get("battle_effects", {})
	print("[SPRITES] Loaded sprite manifest: %d sheets, %d monster sheets, %d battle effects" % [_manifest.size(), _monster_manifest.size(), _battle_effects.size()])
	_manifest_loaded = true


static func reload_manifest() -> void:
	"""Force reload the manifest (call after adding new sprite sheets)"""
	_manifest_loaded = false
	_manifest = {}
	_monster_manifest = {}
	_battle_effects = {}
	_load_manifest()


## Load a battle-effect texture registered under manifest.battle_effects — returns null if the key is absent or the texture load fails so callers can fall back gracefully. cowir-main's norm: HybridSpriteLoader is the single source, no direct load() bypass (msg 4ec21a07 commit note).
static func load_battle_effect_texture(key: String) -> Texture2D:
	_load_manifest()
	if not _battle_effects.has(key):
		return null
	var entry: Dictionary = _battle_effects[key]
	var path: String = str(entry.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		push_warning("[SPRITES] battle_effect '%s' path missing or unloadable: %s" % [key, path])
		return null
	var tex: Resource = load(path)
	return tex if tex is Texture2D else null


static func has_artist_sheet(job_id: String) -> bool:
	"""Check if a job has an artist sprite sheet in the manifest."""
	_load_manifest()
	return _manifest.has(job_id)


static func load_sprite_frames(customization, primary_job_id: String, secondary_job_id: String = "", weapon_id: String = "", armor_id: String = "", accessory_id: String = "") -> SpriteFrames:
	_load_manifest()

	# Check manifest for external sprite sheet
	if _manifest.has(primary_job_id):
		var sheet_data = _manifest[primary_job_id]
		var frames = _load_external_sheet(sheet_data, primary_job_id)
		if frames:
			print("[SPRITES] Using artist sheet for '%s'" % primary_job_id)
			return frames
		else:
			print("[SPRITES] Artist sheet for '%s' failed to load, using procedural" % primary_job_id)
	else:
		print("[SPRITES] No manifest entry for '%s', using procedural" % primary_job_id)

	# Fall back to procedural generation
	return _SnesPartySprites.create_sprite_frames(customization, primary_job_id, secondary_job_id, weapon_id, armor_id, accessory_id)


## Load monster sprite frames from manifest. Returns null if no entry exists,
## allowing the caller to fall back to procedural generation.
## Monster sheet schema (in manifest under "monster_sheets"):
##   monster_id: {
##     "path": "res://assets/sprites/monsters/monster_id.png",
##     "frame_width": 256, "frame_height": 256, "fps": 8,
##     "animations": {
##       "idle":   {"start": 0, "end": 1},
##       "attack": {"start": 2, "end": 3},
##       ...
##     }
##   }
## Sheets are horizontal strips: frame_width * num_frames wide, frame_height tall.
static func load_monster_sprite_frames(monster_id: String) -> SpriteFrames:
	_load_manifest()

	if not _monster_manifest.has(monster_id):
		return null

	var sheet_data = _monster_manifest[monster_id]
	var sheet_path = sheet_data.get("path", "res://assets/sprites/monsters/%s.png" % monster_id)
	if not ResourceLoader.exists(sheet_path):
		push_warning("[SPRITES] Monster sheet not found: %s" % sheet_path)
		return null

	var texture = load(sheet_path) as Texture2D
	if not texture:
		push_warning("[SPRITES] Failed to load monster texture: %s" % sheet_path)
		return null

	var frame_width: int = sheet_data.get("frame_width", 256)
	var frame_height: int = sheet_data.get("frame_height", 256)
	var fps: float = sheet_data.get("fps", 8)
	var animations = sheet_data.get("animations", {})

	var sprite_frames = SpriteFrames.new()
	var cols_per_row: int = texture.get_width() / frame_width

	for anim_name in animations:
		var anim_data = animations[anim_name]
		var start_frame: int = anim_data.get("start", 0)
		var end_frame: int = anim_data.get("end", start_frame)

		sprite_frames.add_animation(anim_name)
		sprite_frames.set_animation_speed(anim_name, fps)
		sprite_frames.set_animation_loop(anim_name, anim_name == "idle")

		for frame_idx in range(start_frame, end_frame + 1):
			var col: int = frame_idx % cols_per_row
			var row: int = frame_idx / cols_per_row
			var atlas = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * frame_width, row * frame_height, frame_width, frame_height)
			sprite_frames.add_frame(anim_name, atlas)

	if sprite_frames.get_animation_names().size() == 0:
		return null

	print("[SPRITES] Loaded monster sheet for '%s' (%d animations)" % [monster_id, sprite_frames.get_animation_names().size()])
	return sprite_frames


static func _load_external_sheet(sheet_data: Dictionary, job_id: String) -> SpriteFrames:
	var base_path = sheet_data.get("path", "res://assets/sprites/jobs/%s" % job_id)
	var frame_width = sheet_data.get("frame_width", 32)
	var frame_height = sheet_data.get("frame_height", 32)
	var animations = sheet_data.get("animations", ["idle", "walk", "attack", "cast", "hit", "dead"])

	var sprite_frames = SpriteFrames.new()
	var loaded_any = false

	for anim_name in animations:
		var sheet_path = "%s/%s.png" % [base_path, anim_name]
		if not ResourceLoader.exists(sheet_path):
			continue

		var texture = load(sheet_path) as Texture2D
		if not texture:
			continue

		sprite_frames.add_animation(anim_name)
		sprite_frames.set_animation_speed(anim_name, sheet_data.get("fps", 8))
		# Only idle and victory loop; all others play once so animation_finished fires
		sprite_frames.set_animation_loop(anim_name, anim_name in ["idle", "victory"])

		var frame_count = texture.get_width() / frame_width
		for i in range(frame_count):
			var atlas = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * frame_width, 0, frame_width, frame_height)
			sprite_frames.add_frame(anim_name, atlas)

		loaded_any = true

	return sprite_frames if loaded_any else null
