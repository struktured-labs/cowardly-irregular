class_name TTSBackend
extends Node

## Speech backend contract; VoiceService talks only to this, so piece 5's browser backend slots in. synthesize MUST answer each id exactly once.

signal synthesis_finished(id: String, ok: bool, wav: PackedByteArray, error: String)


func backend_id() -> String:
	return "base"


func is_ready() -> bool:
	return false


## Where requests go, or "" for a backend that contacts no server (the web gating property).
func contacts_url() -> String:
	return ""


## Voice names the server reports; [] means not known yet, never "none installed".
func server_voices() -> Array[String]:
	return []


func status() -> Dictionary:
	return {"backend": backend_id(), "ready": is_ready(), "url": contacts_url()}


func synthesize(id: String, _text: String, _voice: String) -> void:
	synthesis_finished.emit(id, false, PackedByteArray(), "synthesize() not implemented")


func cancel(_id: String) -> void:
	pass


func cancel_all() -> void:
	pass
