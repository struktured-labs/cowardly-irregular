extends GutTest

## `_try_load_archetype_sprite` has THREE refusal branches and they are not the same kind.
##
## ⛔ ABSENCE IS THE NORMAL PATH AND MUST STAY SILENT: 116 of 145 NPCs carry no archetype sheet
## and fall back to procedural by design, so a warning on `not ResourceLoader.exists` would fire
## on the majority of NPCs in the game and train everyone to ignore the channel.
##
## ✅ THE OTHER TWO MEAN SOMEBODY PUT A FILE THERE ON PURPOSE AND IT DID NOT WORK — a texture that
## will not load, or a sheet under the 128x128 floor a 4x4 grid of 32x32 frames needs. Before
## 2026-09-19 both returned bare `false`, so an artist who shipped a 96x96 sheet got a procedural
## chibi and no reason anywhere. `RoamingMonster` — a sibling consumer of the same manifest
## section — already warns on bad geometry; this file was the one that did not.
##
## 📌 LATENT WHEN FIXED, AND SAID SO: all 145 sheets on disk pass the floor today, so this
## defends the pipeline rather than repairing a live break. The asymmetry with RoamingMonster is
## what earned the change, not a rendering bug.
##
## Comments are STRIPPED before asserting — this file's own subject is push_warning calls, and a
## presence assert over raw source is satisfied by prose about the code.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const NPC_SRC := "res://src/exploration/OverworldNPC.gd"
const DECL := "func _try_load_archetype_sprite("


func _body() -> String:
	var code: String = GdSource.code_of(NPC_SRC)
	var at: int = code.find(DECL)
	if at < 0:
		return ""
	var lines: Array = code.substr(at).split("\n")
	var out: Array = []
	for i in range(1, lines.size()):
		var l: String = str(lines[i])
		if l.strip_edges() != "" and not l.begins_with("\t"):
			break
		out.append(l)
	return "\n".join(out)


func test_the_function_is_still_here() -> void:
	# CONTROL: every arm below reads this body, so a rename would make them all vacuously pass
	# on an empty string rather than fail.
	var code: String = GdSource.code_of(NPC_SRC)
	assert_ne(code, "", "OverworldNPC.gd must be readable")
	assert_true(code.contains(DECL), "the archetype loader must still be named %s" % DECL)
	assert_gt(_body().length(), 100, "its body must be non-empty — an empty body passes by construction")


func test_the_two_file_exists_refusals_each_name_a_reason() -> void:
	var body: String = _body()
	assert_eq(body.count("push_warning("), 2,
		"exactly two refusals mean a file was put there on purpose and did not work; each must say so")


func test_absence_stays_silent_because_it_is_the_normal_path() -> void:
	# The quiet branch. If a warning ever migrates above this return, 116 NPCs start warning on
	# the path they are DESIGNED to take, which is how a diagnostic channel becomes noise.
	var body: String = _body()
	var at: int = body.find("if not ResourceLoader.exists(path):")
	assert_gt(at, -1, "CONTROL: the absence branch must still exist")
	var first_warn: int = body.find("push_warning(")
	assert_gt(first_warn, at,
		"the absence branch must come BEFORE any warning — it is the designed fallback for 116 NPCs")


func test_each_reason_names_the_archetype() -> void:
	# A warning that does not say WHICH sheet is a warning you cannot act on — the artist has
	# 145 directories to check.
	var body: String = _body()
	var seen := 0
	for line in body.split("\n"):
		var l: String = str(line)
		if not l.contains("push_warning("):
			continue
		seen += 1
		assert_true(l.contains("archetype"),
			"every refusal reason must name the archetype it is about: %s" % l.strip_edges())
	# ANTI-VACUITY FLOOR. Without it, deleting both warnings empties the loop and this arm
	# asserts NOTHING — scored Risky, never [Failed]. Measured on this very file: the mutation
	# that strips both push_warnings reds two arms and made this one go silent.
	assert_eq(seen, 2, "the loop must have judged both refusal reasons, not zero")
