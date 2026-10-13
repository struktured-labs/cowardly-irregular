extends GutTest

## A PROMPT THAT SAYS A CUE IS UNWIRED MUST BE TRUE, AND ONE WAS NOT FOR ~2.5 MONTHS.
##
## `windup_swing_med` shipped 2026-07-25 as a prototype whose prompt read "INERT — no consumer until
## struktured rules". It was wired THE SAME DAY at BattleScene's EASE_IN approach tween and has
## played in every build since — deliberately, because a 0.12s anticipation cue cannot be judged
## from a brief, so shipping it to his ears IS the verdict mechanism. The wiring was right; the
## sentence describing it was never updated. @cowir-music found it 2026-10-13 by asking a different
## question of an audit they had already run clean.
##
## ⛔ WHY THIS DIRECTION AND NOT THE OTHER. test_sfx_reverse_orphan_audit already catches a cue
## NOTHING plays. The inverse — a cue that claims nothing plays it while something does — is
## invisible to it and to every other guard, because the manifest's prose is not an assertion
## anywhere. This lane's own rule is that a prompt is AUTHORITATIVE ABOUT THE ASSET and UNRELIABLE
## ABOUT THE CODE, and that is exactly the half this pins: the claim is about the code.
##
## Derived over all prompts, so it is not a pin on one cue. One entry makes the claim today and a
## future prototype written the same way is covered the day it lands.

const MANIFEST := "res://data/sfx_manifest.json"
const CLAIMS := ["INERT", "no consumer", "unwired", "nothing plays it"]


func _sfx() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "VOID: sfx_manifest.json did not parse")
	return (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}


## Every .gd under src/, concatenated. A cue "has a consumer" when its KEY appears as a quoted
## string there — which is what the claim means for a hand-played cue.
func _src_blob() -> String:
	var out := ""
	var stack: Array[String] = ["res://src"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var name_ := d.get_next()
		while name_ != "":
			var full: String = dir_path + "/" + name_
			if d.current_is_dir():
				if not name_.begins_with("."):
					stack.append(full)
			elif name_.ends_with(".gd"):
				out += FileAccess.get_file_as_string(full)
			name_ = d.get_next()
		d.list_dir_end()
	return out


func test_premise_the_src_tree_was_actually_read() -> void:
	## The corpus control. An empty blob makes every claim below "true" — the failure this lane
	## keeps finding in other guards, and the one a directory walk is most prone to.
	var blob := _src_blob()
	assert_gt(blob.length(), 200000,
		"VOID: read only %d bytes of src/*.gd, so 'no consumer' would be true of everything" % blob.length())
	assert_true(blob.contains("\"windup_swing_med\""),
		"CONTROL: the blob must contain a cue key known to be played in src/, or the search below cannot find any consumer at all")


func test_no_prompt_claims_unwired_while_something_plays_it() -> void:
	var sfx := _sfx()
	var blob := _src_blob()
	var claimed: Array[String] = []
	var lying: Array[String] = []
	for key in sfx:
		var prompt: String = str((sfx[key] as Dictionary).get("prompt", ""))
		var says_unwired := false
		for c in CLAIMS:
			if prompt.containsn(c):
				says_unwired = true
				break
		if not says_unwired:
			continue
		claimed.append(str(key))
		if blob.contains("\"%s\"" % str(key)):
			lying.append(str(key))
	## Not asserted non-empty: zero cues claiming to be unwired is a healthy state, and demanding one
	## would make this guard require a prototype to exist. The CONTROL above is what proves the search
	## works, so a zero here is a real zero rather than a broken scan.
	assert_eq(lying, [],
		"these prompts say the cue is unwired and src/ plays it by name — the wiring may be right and the SENTENCE is wrong, which is how a prototype's pending verdict becomes invisible: %s" % [lying])
	gut.p("[prompt-claims] %d prompt(s) claim unwired, %d of them falsely" % [claimed.size(), lying.size()])
