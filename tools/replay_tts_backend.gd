extends TTSBackend

## Test-only: answers with canned WAV bytes, so no test needs a server or GPU.

var next_wav: PackedByteArray = PackedByteArray()
var voices: Array[String] = []
var silent: bool = false
var fail_error: String = ""
var requests: Array = []
var cancelled: Array[String] = []


func backend_id() -> String:
	return "replay"


func is_ready() -> bool:
	return true


func server_voices() -> Array[String]:
	return voices.duplicate()


func synthesize(id: String, text: String, voice: String) -> void:
	requests.append({"id": id, "text": text, "voice": voice})
	if not silent:
		_emit.call_deferred(id)


func _emit(id: String) -> void:
	if id in cancelled:
		return
	if fail_error != "":
		synthesis_finished.emit(id, false, PackedByteArray(), fail_error)
	else:
		synthesis_finished.emit(id, true, next_wav, "")


func cancel(id: String) -> void:
	cancelled.append(id)
