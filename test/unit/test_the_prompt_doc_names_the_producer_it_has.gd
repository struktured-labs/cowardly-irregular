extends GutTest

## DialoguePrompts' parameter docs said `recent_events` comes from `EventLog.recent()`.
## The real producer is `EventLog.recent_varied()` — DynamicConversation calls it for every
## NPC prompt. The two are NOT interchangeable and EventLog records why: recent(5) on a walk
## to town returns five `area_entered` rows and the boss the player just beat is gone, which
## is the defect recent_varied was written to fix.
##
## A doc naming the wrong producer is how that fix gets undone: the next reader "simplifies"
## the caller to match the documentation. This pins the two together so either side moving
## alone is a red, and it derives the producer from the CALLER rather than hard-coding it.
##
## The doc side must be read RAW (the claim IS a comment); the caller side must be read with
## comments STRIPPED, or a docstring mentioning recent() would satisfy the call detection.

const PROMPTS := "res://src/llm/DialoguePrompts.gd"
const CALLER := "res://src/llm/DynamicConversation.gd"
const LOG := "res://src/llm/EventLog.gd"


func _raw(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _stripped(path: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line in _raw(path).split("\n"):
		out.append(str(line).split("#")[0])
	return "\n".join(out)


func test_floor_the_sources_this_file_reads() -> void:
	for p in [PROMPTS, CALLER, LOG]:
		assert_gt(_raw(p).length(), 2000, "CONTROL: %s must actually be read" % p)


## Which EventLog reader does the dialogue path really use? Derived, not assumed.
func _producer_used_by_caller() -> String:
	var code: String = _stripped(CALLER)
	for m in ["recent_varied", "recent_entries", "recent"]:
		if code.contains("_event_log.%s(" % m):
			return m
	return ""


func test_the_caller_uses_a_real_eventlog_reader() -> void:
	var used: String = _producer_used_by_caller()
	assert_ne(used, "", "CONTROL: the dialogue path must call some EventLog reader")
	assert_true(_stripped(LOG).contains("func %s(" % used),
		"CONTROL: EventLog must declare the reader the caller uses")


## The claim under test: the parameter doc must name the producer the caller actually uses.
func test_the_doc_names_the_producer_the_caller_uses() -> void:
	var used: String = _producer_used_by_caller()
	var doc: String = _raw(PROMPTS)
	var mentions: int = doc.count("recent_events  — Array[Dictionary] from EventLog.%s()" % used)
	assert_gt(mentions, 0,
		"DialoguePrompts documents recent_events as coming from something other than %s(), " % used
		+ "which is what DynamicConversation calls — the next reader will change the caller to match")


## Without this the arm above passes if the two readers are the same function.
func test_control_the_two_readers_are_genuinely_different() -> void:
	var log: String = _stripped(LOG)
	assert_true(log.contains("func recent_varied("), "CONTROL: recent_varied must exist")
	assert_true(log.contains("func recent("), "CONTROL: recent must exist")
	var at: int = log.find("func recent_varied(")
	var body: String = log.substr(at, log.find("\nfunc ", at + 1) - at)
	assert_true(body.contains("while") or body.contains("type"),
		"CONTROL: recent_varied must actually collapse runs, or naming it buys nothing")


## No doc anywhere in the file may still name the reader the caller does NOT use.
func test_no_stale_producer_is_named_anywhere_in_the_doc() -> void:
	var used: String = _producer_used_by_caller()
	var stale: String = "recent" if used == "recent_varied" else "recent_varied"
	var doc: String = _raw(PROMPTS)
	assert_eq(doc.count("recent_events  — Array[Dictionary] from EventLog.%s()" % stale), 0,
		"a recent_events parameter doc still names EventLog.%s(), which is not the producer" % stale)
