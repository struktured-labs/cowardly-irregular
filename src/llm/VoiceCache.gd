class_name VoiceCache
extends RefCounted

## Synthesized WAV bytes on disk, bounded: past the cap the least-recently-used line goes first.

const DEFAULT_DIR := "user://voice_cache"
const DEFAULT_CAP_BYTES := 200 * 1024 * 1024

var dir: String
var cap_bytes: int
var _sizes: Dictionary = {}
var _used: Dictionary = {}
var _total: int = 0
var _last_stamp: float = 0.0


func _init(cache_dir: String = DEFAULT_DIR, cap: int = DEFAULT_CAP_BYTES) -> void:
	dir = cache_dir
	cap_bytes = cap
	_scan()


static func key_for(voice: String, rev: int, text: String) -> String:
	return ("v1|%s|%d|%s" % [voice, rev, text]).sha256_text().left(32)


func path_for(key: String) -> String:
	return "%s/%s.wav" % [dir, key]


func has(key: String) -> bool:
	return _sizes.has(key)


func total_bytes() -> int:
	return _total


## The cached bytes, or empty on a miss; a hit counts as a use.
func read(key: String) -> PackedByteArray:
	if not _sizes.has(key):
		return PackedByteArray()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path_for(key))
	if bytes.is_empty():
		_forget(key)
		return bytes
	_used[key] = _stamp()
	return bytes


func write(key: String, bytes: PackedByteArray) -> bool:
	if bytes.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path_for(key), FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	_total += bytes.size() - int(_sizes.get(key, 0))
	_sizes[key] = bytes.size()
	_used[key] = _stamp()
	_evict()
	return true


func remove(key: String) -> void:
	if _sizes.has(key):
		DirAccess.remove_absolute(path_for(key))
		_forget(key)


func _forget(key: String) -> void:
	_total -= int(_sizes.get(key, 0))
	_sizes.erase(key)
	_used.erase(key)


func _evict() -> void:
	if _total <= cap_bytes:
		return
	var keys: Array = _sizes.keys()
	keys.sort_custom(func(a, b): return float(_used[a]) < float(_used[b]))
	for k in keys:
		if _total <= cap_bytes:
			break
		remove(k)


func _stamp() -> float:
	_last_stamp = maxf(Time.get_unix_time_from_system(), _last_stamp + 0.001)
	return _last_stamp


func _scan() -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for name in d.get_files():
		if not name.ends_with(".wav"):
			continue
		var key: String = name.get_basename()
		var f := FileAccess.open(path_for(key), FileAccess.READ)
		if f == null:
			continue
		_sizes[key] = f.get_length()
		f.close()
		_total += int(_sizes[key])
		_used[key] = float(FileAccess.get_modified_time(path_for(key)))
		_last_stamp = maxf(_last_stamp, float(_used[key]))
