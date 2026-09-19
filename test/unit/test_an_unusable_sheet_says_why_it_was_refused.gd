extends GutTest

## The archetype loaders have THREE refusal branches and they are not the same kind.
##
## ⛔ ABSENCE STAYS SILENT, AND MY FIRST VERSION OF THIS HEADER GOT THE REASON WRONG. It said
## "116 of 145 NPCs carry no archetype sheet" — that figure is from another guard entirely and
## counts sheets DECLARING NO ROW ORDER, a different fact about a different thing. Measured:
## both loaders are guarded by a non-empty archetype at the call site, and every resolvable
## archetype has art on disk (27 of 27 derived, 7 of 7 explicit overrides), so the absence
## branch is currently UNREACHABLE. It stays silent because it can only fire for an archetype
## whose sheet has not landed yet — a legitimate work-in-progress state, not a busy path.
##
## ✅ THE OTHER TWO MEAN SOMEBODY PUT A FILE THERE ON PURPOSE AND IT DID NOT WORK — a texture that
## will not load, or a sheet under the 128x128 floor a 4x4 grid of 32x32 frames needs. Before
## 2026-09-19 both returned bare `false`, so an artist who shipped a 96x96 sheet got a procedural
## chibi and no reason anywhere. `RoamingMonster` — a sibling consumer of the same manifest
## section — already warned on bad geometry; these two did not.
##
## 🔑 BOTH LOADERS ARE PINNED AS ONE CONTRACT BECAUSE THEY ARE THE SAME SHAPE AND DRIFTED ONCE
## ALREADY: OverworldNPC was fixed first, and WanderingNPC — a near-verbatim copy — was found
## only by asking whether the first instance was the only one. A per-file guard would have let
## them diverge again silently.
##
## 📌 LATENT WHEN FIXED, AND SAID SO: every sheet on disk passes the floor today, so this defends
## the pipeline rather than repairing a live break. The asymmetry with RoamingMonster earned it.
##
## Comments are STRIPPED before asserting — this file's own subject is push_warning calls, and a
## presence assert over raw source is satisfied by prose about the code.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## {source: declaration}
const LOADERS := {
	"res://src/exploration/OverworldNPC.gd": "func _try_load_archetype_sprite(",
	"res://src/exploration/WanderingNPC.gd": "func _try_load_archetype(",
}


func _body_of(src: String, decl: String) -> String:
	var code: String = GdSource.code_of(src)
	var at: int = code.find(decl)
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


func test_both_loaders_are_still_here() -> void:
	# CONTROL: every arm below reads these bodies, so a rename would make them all pass
	# vacuously on an empty string rather than fail.
	assert_eq(LOADERS.size(), 2, "the contract covers both loaders")
	for src in LOADERS:
		assert_gt(_body_of(str(src), str(LOADERS[src])).length(), 100,
			"%s: %s must exist with a non-empty body" % [src, LOADERS[src]])


func test_the_two_file_exists_refusals_each_name_a_reason() -> void:
	var checked := 0
	for src in LOADERS:
		checked += 1
		assert_eq(_body_of(str(src), str(LOADERS[src])).count("push_warning("), 2,
			"%s: exactly two refusals mean a file was put there on purpose and did not work" % src)
	assert_eq(checked, 2, "both loaders must have been judged, not zero")


func test_absence_stays_silent_because_it_is_the_designed_gap() -> void:
	# The quiet branch. If a warning ever migrates above this return it starts firing for every
	# archetype whose art has not landed yet, which is how a channel becomes noise.
	var checked := 0
	for src in LOADERS:
		var body: String = _body_of(str(src), str(LOADERS[src]))
		var at: int = body.find("if not ResourceLoader.exists(path):")
		assert_gt(at, -1, "%s: CONTROL: the absence branch must still exist" % src)
		var first_warn: int = body.find("push_warning(")
		assert_gt(first_warn, at, "%s: absence must come BEFORE any warning" % src)
		checked += 1
	assert_eq(checked, 2, "both loaders must have been judged")


func test_each_reason_names_the_archetype() -> void:
	# A warning that does not say WHICH sheet is one you cannot act on — 145 directories.
	var seen := 0
	for src in LOADERS:
		for line in _body_of(str(src), str(LOADERS[src])).split("\n"):
			var l: String = str(line)
			if not l.contains("push_warning("):
				continue
			seen += 1
			assert_true(l.contains("archetype"),
				"%s: every reason must name the archetype: %s" % [src, l.strip_edges()])
	# ANTI-VACUITY FLOOR. Without it, deleting the warnings empties the loop and this arm
	# asserts NOTHING — scored [Risky], never [Failed]. Measured on this file's first draft.
	assert_eq(seen, 4, "two reasons per loader must have been judged, not zero")
