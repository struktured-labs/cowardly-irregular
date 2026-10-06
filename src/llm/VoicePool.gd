extends Node

## The ready pool (spec 2b.2): one LLM-written, synthesized line per speaker + trigger, filled one at a time while nothing else uses the GPU.

const TRIGGER_ORDER := ["turn_start", "big_hit_taken", "low_hp", "used_signature_ability", "victory"]
const SYNTH_TIMEOUT_SEC := 20.0
const FAIL_COOLDOWN_MSEC := 5000
const STASH_CAP := 8

var store: VoicePoolStore
var discarded: int = 0
var _filling := false
var _retry_after_msec := 0
var _stash: Dictionary = {}
var _stash_order: Array[String] = []
var _next_token := 0
var _recent: Dictionary = {}


func _ready() -> void:
	store = VoicePoolStore.new()
	store.load_from_disk()
	var vs := get_node_or_null("/root/VoiceService")
	if vs != null and store.drop_stale(vs._cast) > 0:
		store.save()


func _process(_delta: float) -> void:
	if can_fill():
		var slot := next_empty_slot()
		if not slot.is_empty():
			fill_slot(slot[0], slot[1])


## The player opted into both LLM party lines and live voice, on desktop.
func is_enabled() -> bool:
	var vs := get_node_or_null("/root/VoiceService")
	var gs := get_node_or_null("/root/GameState")
	if vs == null or gs == null or vs.is_web:
		return false
	return bool(gs.get("tts_live_enabled")) and bool(gs.get("party_llm_dialogue_enabled"))


func can_fill() -> bool:
	if _filling or Time.get_ticks_msec() < _retry_after_msec or not is_enabled():
		return false
	var vs := get_node_or_null("/root/VoiceService")
	var llm := get_node_or_null("/root/LLMService")
	if llm == null or not llm.is_available() or not llm.is_idle():
		return false
	return vs.is_live_ready() and not vs.is_busy()


func _speakers() -> Array[String]:
	var vs := get_node_or_null("/root/VoiceService")
	var gs := get_node_or_null("/root/GameState")
	var out: Array[String] = []
	if vs == null or gs == null:
		return out
	for m in gs.player_party:
		var job := str((m as Dictionary).get("job_id", ""))
		if job != "" and not vs.voice_for(job).is_empty() and not out.has(job):
			out.append(job)
	return out


## Most frequent trigger first, so the lines a battle needs soonest are ready soonest.
func next_empty_slot() -> Array:
	for trigger in TRIGGER_ORDER:
		for speaker in _speakers():
			if not store.has_line(speaker, trigger):
				return [speaker, trigger]
	return []


## Jobs, party members and every monster: a line written before its battle cannot know who is in it.
func forbidden_names() -> Array[String]:
	var out: Array[String] = []
	var js := get_node_or_null("/root/JobSystem")
	if js != null and "jobs" in js:
		for j in js.jobs.keys():
			out.append(str(j).replace("_", " "))
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		for m in gs.player_party:
			out.append(str((m as Dictionary).get("name", "")))
	var es := get_node_or_null("/root/EncounterSystem")
	if es != null and "monster_database" in es:
		for id in es.monster_database:
			out.append(str(id).replace("_", " "))
			out.append(str((es.monster_database[id] as Dictionary).get("name", "")))
	return out


func fill_slot(speaker: String, trigger: String) -> bool:
	_filling = true
	var ok := await _fill(speaker, trigger)
	_filling = false
	if not ok:
		_retry_after_msec = Time.get_ticks_msec() + FAIL_COOLDOWN_MSEC
	return ok


func _fill(speaker: String, trigger: String) -> bool:
	var pp := get_node_or_null("/root/PartyPersonas")
	var llm := get_node_or_null("/root/LLMService")
	var vs := get_node_or_null("/root/VoiceService")
	if pp == null or llm == null or vs == null:
		return false
	var key := VoicePoolStore.slot_key(speaker, trigger)
	var prompt := DialoguePrompts.build_pooled_party_line(str(pp.get_persona(speaker)), pp.get_signature_phrases(speaker), speaker, trigger, _recent.get(key, []))
	var raw: Variant = await llm.complete_json(prompt, DialoguePrompts.SCHEMA_PARTY_LINE, DialoguePrompts.FALLBACK_PARTY_LINE, {"cache": false})
	var line := str(DialoguePrompts.validate_party_line(raw).get("line", ""))
	if line == "" or not is_enabled():
		return false
	if VoicePoolStore.names_anyone(line, forbidden_names()):
		discarded += 1
		return false
	var stream: AudioStream = await vs.synthesize(speaker, line, SYNTH_TIMEOUT_SEC)
	if stream == null:
		return false
	var v: Dictionary = vs.voice_for(speaker)
	store.put(speaker, trigger, line, str(v.get("voice", "")), int(v.get("rev", 0)))
	store.save()
	var recent: Array = _recent.get(key, [])
	recent.append(line)
	_recent[key] = recent.slice(-5)
	return true


## A ready line and a one-shot token for its audio. {} when the pool has nothing playable.
func take_line(speaker: String, trigger: String) -> Dictionary:
	if not is_enabled() or not store.has_line(speaker, trigger):
		return {}
	var slot := store.take(speaker, trigger)
	store.save()
	var vs := get_node_or_null("/root/VoiceService")
	var stream: AudioStream = vs.get_cached(speaker, str(slot["line"])) if vs != null else null
	if stream == null:
		return {}
	_next_token += 1
	var token := "pool:%d" % _next_token
	_stash[token] = stream
	_stash_order.append(token)
	while _stash_order.size() > STASH_CAP:
		_stash.erase(_stash_order.pop_front())
	return {"line": str(slot["line"]), "token": token}


func claim_stream(token: String) -> AudioStream:
	var s: AudioStream = _stash.get(token, null)
	_stash.erase(token)
	_stash_order.erase(token)
	return s
