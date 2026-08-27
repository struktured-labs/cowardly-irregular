class_name FeedbackBundle
extends RefCounted

## One keypress produces one file a tester can send back. Built for the Rat King alpha
## (struktured 2026-08-26): before this, a tester could describe a bug but could not show one,
## and the only capture in the game was a bare F12 screenshot with no state attached.
##
## Everything is best-effort. A bundle missing its log is still worth having, so no single
## absent piece may abort the write — the manifest records what was collected and what was not,
## because a silently-thin bundle is worse than a loud one.

const DEFAULT_DIR := "user://feedback"

## Files pulled in verbatim when present. Paths, not globs: each one has a known reason to exist.
const ATTACHMENTS := {
	"godot.log": "user://logs/godot.log",
	"settings.json": "user://settings.json",
	"autogrind_profiles.json": "user://autogrind/profiles.json",
}


## The state a bug report needs and a screenshot cannot show. No viewport, no filesystem —
## split out so it is testable without a running game.
static func collect_state() -> Dictionary:
	var out: Dictionary = {
		"version": _version_string(),
		"captured_at": Time.get_datetime_string_from_system(),
		"engine": Engine.get_version_info().get("string", "unknown"),
		"platform": OS.get_name(),
	}
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState") if Engine.get_main_loop() else null
	if gs:
		out["playtime_sec"] = int(gs.get("playtime")) if "playtime" in gs else -1
		out["battles_won"] = int(gs.get("battles_won")) if "battles_won" in gs else -1
		out["gold"] = int(gs.call("get_gold")) if gs.has_method("get_gold") else -1
		if "player_party" in gs:
			var party: Array = []
			for m in gs.player_party:
				if m is Dictionary:
					party.append({"name": str((m as Dictionary).get("name", "?")),
						"job": str((m as Dictionary).get("job", "?")),
						"level": int((m as Dictionary).get("job_level", 0))})
			out["party"] = party
		if "game_constants" in gs:
			## Story flags only. The full constants dict carries tuning knobs and debug state that
			## bloat the report without telling anyone where the player was.
			var story: Dictionary = {}
			for k in gs.game_constants:
				if str(k).begins_with("cutscene_flag_") or str(k).begins_with("talked_to_"):
					story[str(k)] = gs.game_constants[k]
			out["story_flags"] = story
	else:
		out["gamestate"] = "unavailable"
	return out


## Writes <out_dir>/report_<stamp>.zip and returns its ABSOLUTE path, or "" on failure.
## out_dir is a parameter so tests never touch a live user:// — the per-test override the
## player-data net exists to make unnecessary.
static func write_bundle(state: Dictionary, shot: Image, out_dir: String = DEFAULT_DIR) -> String:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var zip_path: String = "%s/report_%s.zip" % [out_dir, stamp]

	var packer := ZIPPacker.new()
	if packer.open(zip_path) != OK:
		push_warning("[FEEDBACK] could not open %s for writing" % zip_path)
		return ""

	var collected: Array = []
	var absent: Array = []

	if shot != null:
		var png: PackedByteArray = shot.save_png_to_buffer()
		if png.size() > 0:
			_put(packer, "screenshot.png", png)
			collected.append("screenshot.png")
		else:
			absent.append("screenshot.png")
	else:
		absent.append("screenshot.png")

	for name in ATTACHMENTS:
		var src: String = str(ATTACHMENTS[name])
		if FileAccess.file_exists(src):
			var f := FileAccess.open(src, FileAccess.READ)
			if f:
				_put(packer, name, f.get_buffer(f.get_length()))
				f.close()
				collected.append(name)
				continue
		absent.append(name)

	var save_bytes := _newest_save()
	if not save_bytes.is_empty():
		_put(packer, "save.json", save_bytes)
		collected.append("save.json")
	else:
		absent.append("save.json")

	## Written LAST so it can report on the rest. "absent" is the load-bearing half: a bundle
	## that quietly lacks the log looks identical to one where nothing went wrong.
	var manifest: Dictionary = state.duplicate(true)
	manifest["collected"] = collected
	manifest["absent"] = absent
	_put(packer, "report.json", JSON.stringify(manifest, "  ").to_utf8_buffer())

	packer.close()
	return ProjectSettings.globalize_path(zip_path)


static func _put(packer: ZIPPacker, name: String, data: PackedByteArray) -> void:
	packer.start_file(name)
	packer.write_file(data)
	packer.close_file()


## The save the player was most likely in. Recency, not slot order — a tester who quick-saved
## before hitting the bug wants that one, not slot 0.
static func _newest_save() -> PackedByteArray:
	var dir := DirAccess.open("user://saves")
	if dir == null:
		return PackedByteArray()
	var best := ""
	var best_time := -1
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".json"):
			var p := "user://saves/" + name
			var t := int(FileAccess.get_modified_time(p))
			if t > best_time:
				best_time = t
				best = p
		name = dir.get_next()
	dir.list_dir_end()
	if best == "":
		return PackedByteArray()
	var f := FileAccess.open(best, FileAccess.READ)
	return f.get_buffer(f.get_length()) if f else PackedByteArray()


static func _version_string() -> String:
	var v = load("res://src/meta/Version.gd")
	if v and "SEMVER" in v:
		return str(v.SEMVER)
	return "unknown"
