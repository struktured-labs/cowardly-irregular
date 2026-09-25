class_name NullTTSBackend
extends TTSBackend

## Never ready and contacts nothing: live voice off, and web until piece 5.

func backend_id() -> String:
	return "null"


func synthesize(id: String, _text: String, _voice: String) -> void:
	synthesis_finished.emit(id, false, PackedByteArray(), "live voice is off")
