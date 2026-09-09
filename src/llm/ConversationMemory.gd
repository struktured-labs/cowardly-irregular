## ConversationMemory — what an NPC remembers you saying, between visits.
##
## Every dynamic conversation was a blank slate: the NPC could see the world
## (events, quest phase, time of day, the party's wounds and purse) but never
## that you had stood there yesterday and told them something. Recurring NPCs
## read as amnesiacs, which is the one thing a live model should never feel like.
##
## Scope is deliberately small — the player's OWN last lines to THAT NPC. Not a
## transcript, not the NPC's replies. What the player chose to say is the part
## they will recognise being remembered, and it is the cheapest thing to store.
##
## SECURITY: these lines are LLM-authored choice text. They are persisted into
## the save and injected into a LATER prompt, so this is the one place in the
## dialogue path where model output crosses into durable state and back. Every
## line is truncated and stripped of newlines before storage — an unbounded
## line is both a save-bloat vector and a way for generated text to forge
## prompt structure on its next trip through.

class_name ConversationMemory
extends RefCounted


## Persisted store lives in GameState.game_constants, so it rides the save and
## is wiped by reset_game_state() with everything else — verified, not assumed.
const STORE_KEY: String = "llm_conversation_memory"

## Lines kept per NPC. Two is enough to feel remembered without steering the model.
const MAX_LINES_PER_NPC: int = 2

## NPCs tracked before the least-recently-spoken-to is dropped. Bounds save growth.
const MAX_NPCS: int = 24

## Hard cap per stored line. LLM choice text is normally far shorter.
const MAX_LINE_CHARS: int = 120


## Lines this NPC remembers the player saying, oldest first. Empty for a stranger.
static func recall(gs: Node, npc_id: String) -> Array:
	if gs == null or npc_id == "" or not ("game_constants" in gs):
		return []
	var store: Dictionary = gs.game_constants.get(STORE_KEY, {}) as Dictionary
	var entry: Variant = store.get(npc_id, null)
	if not (entry is Dictionary):
		return []
	var lines: Variant = (entry as Dictionary).get("lines", [])
	return (lines as Array).duplicate() if lines is Array else []


## Record what the player said. Keeps the most RECENT lines — an NPC recalling
## your opening pleasantry from three visits ago is worse than recalling nothing.
static func remember(gs: Node, npc_id: String, player_lines: Array) -> void:
	if gs == null or npc_id == "" or not ("game_constants" in gs):
		return
	var kept: Array = []
	for raw in player_lines:
		var clean: String = _sanitize(str(raw))
		if clean != "":
			kept.append(clean)
	if kept.is_empty():
		return
	if kept.size() > MAX_LINES_PER_NPC:
		kept = kept.slice(kept.size() - MAX_LINES_PER_NPC)
	var store: Dictionary = (gs.game_constants.get(STORE_KEY, {}) as Dictionary).duplicate()
	store[npc_id] = {"lines": kept, "seq": _next_seq(store)}
	_evict_oldest(store)
	gs.game_constants[STORE_KEY] = store


## Monotonic recency stamp. Derived from the store rather than held in a static,
## so it survives a reload instead of restarting at zero and mis-ordering eviction.
static func _next_seq(store: Dictionary) -> int:
	var highest: int = 0
	for key in store:
		var entry: Variant = store[key]
		if entry is Dictionary:
			highest = maxi(highest, int((entry as Dictionary).get("seq", 0)))
	return highest + 1


## Drops the least-recently-spoken-to NPCs until the store fits.
static func _evict_oldest(store: Dictionary) -> void:
	while store.size() > MAX_NPCS:
		var oldest_key: String = ""
		var oldest_seq: int = -1
		for key in store:
			var entry: Variant = store[key]
			var seq: int = int((entry as Dictionary).get("seq", 0)) if entry is Dictionary else 0
			if oldest_seq < 0 or seq < oldest_seq:
				oldest_seq = seq
				oldest_key = str(key)
		if oldest_key == "":
			return
		store.erase(oldest_key)


## Newlines are stripped, not escaped — a stored line is re-injected into a
## prompt, where a bare newline lets generated text open a section of its own.
static func _sanitize(line: String) -> String:
	var flat: String = line.replace("\n", " ").replace("\r", " ").strip_edges()
	if flat.length() > MAX_LINE_CHARS:
		flat = flat.substr(0, MAX_LINE_CHARS).strip_edges() + "…"
	return flat
