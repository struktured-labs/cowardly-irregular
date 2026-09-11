extends GutTest

## Ask Elder Theron about the Chancellor and he calls her "he".
##
## Measured against live llama3 on the shipped conversation prompts, 8 samples
## per call site, scored on the text a player would read:
##
##     21 replies mentioned Mordaine or "the Chancellor"
##      9 of them used he/his/him and never she/her
##
## "The Chancellor? Ah, yes. A figure of great power and little mercy. HIS
## ambitions are many, HIS methods..." — Elder Theron, about the woman whose
## throne-room prose, scripted lines and own boss dialogue all use she/her.
##
## Nothing in the conversation prompt said otherwise, so the model guessed from
## the title. After adding a one-line pronoun note: 0 of 19.
##
## ⚠️ THE NOTE HAS TO MATCH HOW PLAYERS SPEAK. A name-only match fired on NONE of
## the misgendering samples — every one of them says "the Chancellor", not
## "Mordaine". That is why CHARACTER_PRONOUNS carries `refs`.
##
## DECLARED, NOT INFERRED. A pronoun is a fact about a character; deriving it from
## prose statistics would carry a future misgendering bug straight into the
## prompt. The derivation lives HERE instead, as the guard that the declaration
## still matches canon.

const DP := preload("res://src/llm/DialoguePrompts.gd")

const PERSONA := "Elder Theron, keeper of Harmonia's records."
const EVENTS: Array = [{"type": "battle", "summary": "The party defeated the Cave Rat King."}]


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_reply_about_the_chancellor_carries_her_pronoun() -> void:
	var p: String = DP.build_npc_reply("Elder Theron", PERSONA, "Harmonia", EVENTS,
		"You came back.", "What do you know about the Chancellor?")
	assert_true(p.find("Chancellor Mordaine uses she/her") != -1,
		"the prompt must state her pronoun when the player asks about her — 9 of 21 replies said 'he'")


func test_the_title_is_enough_not_just_the_name() -> void:
	## THE DISCRIMINATOR. Every misgendering sample said "the Chancellor". A
	## name-only match would have fired on none of them and measured as a fix.
	var by_title: String = DP.build_npc_reply("Elder Theron", PERSONA, "Harmonia", EVENTS,
		"Sit down.", "Tell me about the Chancellor.")
	var by_name: String = DP.build_npc_reply("Elder Theron", PERSONA, "Harmonia", EVENTS,
		"Sit down.", "Tell me about Mordaine.")
	assert_true(by_title.find("she/her") != -1, "the TITLE alone must trigger the note")
	assert_true(by_name.find("she/her") != -1, "and so must the name")


func test_the_combined_reply_carries_it_too() -> void:
	var p: String = DP.build_combined_reply("Elder Theron", PERSONA, "Harmonia", EVENTS,
		"You came back.", "What do you know about the Chancellor?", 3)
	assert_true(p.find("she/her") != -1, "combined_reply is the busiest path and had 5 of the 9")


func test_the_opening_line_carries_it_when_events_name_her() -> void:
	## The opening is the FIRST thing a player hears on walking up, and its context
	## is recent_events rather than anything said yet. Found by mutation: dropping
	## the note from this builder alone was SILENT — I threaded three call sites and
	## had tested two.
	var p: String = DP.build_npc_opening("Elder Theron", PERSONA, "Harmonia",
		[{"type": "story", "summary": "Mordaine's banners went up over the castle."}],
		[], "evening", {}, [])
	assert_true(p.find("Chancellor Mordaine uses she/her") != -1,
		"an opening whose events name her must carry her pronoun too")


func test_an_opening_about_nothing_relevant_stays_clean() -> void:
	## CORRECT-WORK, opening side: no figure in the events, no note.
	var p: String = DP.build_npc_opening("Elder Theron", PERSONA, "Harmonia",
		EVENTS, [], "evening", {}, [])
	assert_eq(p.find("uses she/her"), -1, "no figure in the events means no pronoun line")


func test_an_unrelated_conversation_carries_no_note() -> void:
	## CORRECT-WORK: the prompt must not grow a roster the model reads past every
	## turn. No figure named, no note.
	var p: String = DP.build_npc_reply("Elder Theron", PERSONA, "Harmonia", EVENTS,
		"Fine weather.", "Where can I buy rope?")
	assert_eq(p.find("uses she/her"), -1, "no figure mentioned means no pronoun line")


func test_the_fixture_is_the_shape_production_supplies() -> void:
	## CONTROL, and it caught a real hole in this file: recent_events is
	## Array[Dictionary] from EventLog.recent(). Passing Array[String] is a
	## GDScript error inside _format_events, which ABORTS it — so the whole events
	## block vanishes and every test above still passes, on a shape no caller
	## produces. Assert the block RENDERS, so a wrong-shaped fixture reds.
	var p: String = DP.build_npc_opening("Elder Theron", PERSONA, "Harmonia",
		EVENTS, [], "evening", {}, [])
	assert_true(p.find("Recent events:") != -1,
		"the events block must render — if it does not, the fixture is not the production shape")
	assert_true(p.find("Cave Rat King") != -1,
		"and carry the summary text, not merely the heading")


# ── the declaration must still match canon ────────────────────────────────────

func test_every_declared_pronoun_matches_the_authored_prose() -> void:
	## Derives the same answer from data/cutscenes and asserts the DECLARATION
	## agrees. Guards against canon drift without the prompt being computed from
	## prose — a misgendering bug in a future cutscene must not silently become
	## the prompt's instruction.
	##
	## Proximity-windowed on purpose: counting pronouns file-wide gives Mordaine
	## he=46 she=139 they=205, because the party's they/them swamps the signal.
	var checked: int = 0
	for who in DP.CHARACTER_PRONOUNS:
		var entry: Dictionary = DP.CHARACTER_PRONOUNS[who]
		var short: String = str(who).split(" ")[-1].to_lower()
		var he: int = 0
		var she: int = 0
		for f in _cutscene_files():
			var txt: String = FileAccess.get_file_as_string(f).to_lower()
			var at: int = txt.find(short)
			while at != -1:
				var seg: String = txt.substr(at + short.length(), 110)
				he += _count_words(seg, ["he", "his", "him", "himself"])
				she += _count_words(seg, ["she", "her", "hers", "herself"])
				at = txt.find(short, at + 1)
		var total: int = he + she
		assert_gte(total, 5,
			"CONTROL: only %d pronouns found near '%s' — too little canon to check against" % [total, short])
		if total < 5:
			continue
		checked += 1
		var declared: String = str(entry.get("pronoun", ""))
		var dominant: String = "she/her" if she > he else "he/him"
		assert_eq(declared, dominant,
			"%s is declared %s but the authored prose says %s (he=%d she=%d)"
				% [who, declared, dominant, he, she])
	assert_gte(checked, 1, "CONTROL: no declaration was checked — the derivation is broken")


func test_the_table_has_not_been_drained() -> void:
	## Draining it empties the loop above, which would assert nothing. gte with a
	## literal, because the table may legitimately GROW as canon settles.
	assert_gte(DP.CHARACTER_PRONOUNS.size(), 1,
		"CHARACTER_PRONOUNS is empty — every check that walks it becomes vacuous")


func _cutscene_files() -> PackedStringArray:
	var out: PackedStringArray = []
	var d := DirAccess.open("res://data/cutscenes")
	if d == null:
		return out
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		if n.ends_with(".json"):
			out.append("res://data/cutscenes/" + n)
		n = d.get_next()
	d.list_dir_end()
	return out


func _count_words(seg: String, words: Array) -> int:
	var n: int = 0
	for w in seg.split(" "):
		var t: String = w.strip_edges().trim_suffix(",").trim_suffix(".").trim_suffix('"')
		if t in words:
			n += 1
	return n
