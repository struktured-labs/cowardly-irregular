extends LLMBackend

## An LLMBackend that replays a captured reply instead of calling a model.
##
## Exists so measurement can drive the SHIPPING path — LLMService.complete_json
## and RuleComposer.compose_async — rather than re-implementing it. Every
## re-implementation of that pipeline has eventually disagreed with it: scoring a
## shape the game never sees called a correct reply a parse failure, and a scorer
## that hand-called the repair functions silently drifted from their real order.
##
## Deliberately the smallest thing that can satisfy the interface. It holds one
## string and hands it back, so there is nothing in it to drift.

var next_text: String = ""


func backend_id() -> String:
	return "replay"


func is_ready() -> bool:
	return true


func supports_json() -> bool:
	return true


func submit(id: String, _prompt: String, _opts: Dictionary = {}) -> void:
	# Deferred so the caller is awaiting before the signal lands, matching how a
	# real backend answers on a later frame.
	_emit.call_deferred(id)


func _emit(id: String) -> void:
	request_finished.emit(id, true, next_text, "")


func cancel(_id: String) -> void:
	pass


func cancel_all() -> void:
	pass
