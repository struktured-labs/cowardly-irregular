extends GutTest

## Wave F regression coverage for two related DynamicConversation bugs:
##
##  B10  — empty NPC reply renders a blank dialogue panel
##         (DynamicConversation.gd _do_npc_reply used to assign and display
##         even when the LLM returned reply == "")
##
##  R3   — authored `openings` from npc_showcase_personas.json were dead data
##         (DynamicConversation.setup() took no openings; the LLM-off opening
##         turn cycled through the flatter `fallbacks` list instead)
##
## Both fixes use the deterministic fallback path so we don't need a live
## backend to exercise them.


var _dc: DynamicConversation


func before_each() -> void:
	_dc = DynamicConversation.new()
	_dc.name = "TestDC"
	add_child_autofree(_dc)


# ── R3: authored openings flow through to the LLM-off opening turn ──────────

func test_setup_accepts_optional_openings_argument() -> void:
	# Backward-compatible: setup() must accept omitted openings_lines.
	_dc.setup("Test NPC", "wise sage", "Village", null, ["Fallback line."])
	assert_eq(_dc._opening_lines.size(), 0,
		"openings default to empty when caller omits the param")


func test_setup_stores_openings_when_supplied() -> void:
	var openings: Array = ["Bespoke opening A.", "Bespoke opening B."]
	_dc.setup("Test NPC", "wise sage", "Village", null, ["Plain fallback."], openings)
	assert_eq(_dc._opening_lines.size(), 2)
	assert_eq(str(_dc._opening_lines[0]), "Bespoke opening A.")


func test_fallback_opening_line_uses_openings_when_available() -> void:
	# When openings are non-empty, _fallback_opening_line MUST return one
	# of them — not a line from the flatter fallbacks list.
	var openings: Array = ["Only opening."]
	_dc.setup("Test NPC", "wise sage", "Village", null, ["Plain fallback."], openings)
	var line: String = _dc._fallback_opening_line()
	assert_eq(line, "Only opening.",
		"openings list must be preferred over fallbacks when present")


func test_fallback_opening_line_falls_through_when_openings_empty() -> void:
	# Backward-compatible: if no openings were authored, fall through to the
	# legacy per-turn fallback line. This keeps non-showcase NPCs intact.
	_dc.setup("Test NPC", "wise sage", "Village", null, ["Legacy fallback."])
	var line: String = _dc._fallback_opening_line()
	assert_eq(line, "Legacy fallback.")


# ── B10: empty NPC reply must never render as a blank panel ─────────────────

func test_dialogue_prompts_fallback_reply_line_never_empty() -> void:
	# The B10 fix relies on _fallback_reply_line returning a non-empty
	# string for any exchange_count value. Pin that contract.
	for i in range(0, 10):
		var line: String = DialoguePrompts._fallback_reply_line(i)
		assert_true(line.strip_edges() != "",
			"_fallback_reply_line(%d) returned empty string" % i)


# ── Source-level guard so the empty-reply check isn't accidentally removed ──

func test_do_npc_reply_guards_against_empty_string() -> void:
	# Read DynamicConversation.gd from disk and verify the guard text the
	# B10 fix introduced is still present. This is a belt-and-braces check
	# so a future refactor can't silently re-introduce blank dialogue.
	var src := FileAccess.get_file_as_string("res://src/llm/DynamicConversation.gd")
	assert_true(src != "", "DynamicConversation.gd must be readable")
	assert_true(src.find("reply.strip_edges() == \"\"") != -1,
		"DynamicConversation._do_npc_reply must guard against empty replies " +
		"(Wave F B10 fix). Look for: 'if reply.strip_edges() == \"\":'")
	assert_true(src.find("_fallback_reply_line(_exchange_count)") != -1,
		"empty-reply guard must fall back to DialoguePrompts._fallback_reply_line")


# ── EventLog B13: JSON-safe coercion drops Object refs ──────────────────────

func test_eventlog_drops_object_refs_from_data() -> void:
	var log := EventLog.new()
	# Object refs (Node, RefCounted) are not JSON-safe.
	var node := Node.new()
	add_child_autofree(node)
	log.record("custom", "node ref event", {"safe_key": 42, "object_ref": node})
	# Result should still record the event, but with the object_ref scrubbed.
	var entries := log.recent(1)
	assert_eq(entries.size(), 1)
	var data: Dictionary = entries[0].get("data", {})
	assert_eq(int(data.get("safe_key", -1)), 42, "primitives must survive")
	assert_false(data.has("object_ref"),
		"non-JSON-safe Object ref must be dropped before storage")


func test_eventlog_data_roundtrips_through_json() -> void:
	# Belt-and-braces: the scrubbed entry MUST stringify cleanly through
	# JSON, which is what GameState.to_dict() ultimately does.
	var log := EventLog.new()
	log.record("custom", "nested data", {
		"flat": "value",
		"nested": {"inner": [1, 2, 3]},
	})
	var raw_text: String = JSON.stringify(log.serialize())
	assert_true(raw_text != "", "serialize result must be JSON-stringifiable")
	var parsed: Variant = JSON.parse_string(raw_text)
	assert_true(parsed is Array, "round-trip parses back to Array")
