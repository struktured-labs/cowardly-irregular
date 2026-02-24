extends RefCounted
class_name HybridSpriteLoader

## Hybrid sprite loader that checks for external artist sprite sheets first,
## then falls back to procedural SnesPartySprites generation.

const _SnesPartySprites = preload("res://src/battle/sprites/SnesPartySprites.gd")

static var _manifest: Dictionary = {}
static var _manifest_loaded: bool = false

static func _load_manifest() -> void:
	if _manifest_loaded:
		return
	var file_path = "res://data/sprite_manifest.json"
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				_manifest = json.data.get("sheets", {})
			file.close()
	_manifest_loaded = true


static func load_sprite_frames(customization, primary_job_id: String, secondary_job_id: String = "", weapon_id: String = "", armor_id: String = "", accessory_id: String = "") -> SpriteFrames:
	_load_manifest()

	# Check manifest for external sprite sheet
	if _manifest.has(primary_job_id):
		var sheet_data = _manifest[primary_job_id]
		var frames = _load_external_sheet(sheet_data, primary_job_id)
		if frames:
			return frames

	# Fall back to procedural generation
	return _SnesPartySprites.create_sprite_frames(customization, primary_job_id, secondary_job_id, weapon_id, armor_id, accessory_id)


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

		var frame_count = texture.get_width() / frame_width
		for i in range(frame_count):
			var atlas = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * frame_width, 0, frame_width, frame_height)
			sprite_frames.add_frame(anim_name, atlas)

		loaded_any = true

	return sprite_frames if loaded_any else null
