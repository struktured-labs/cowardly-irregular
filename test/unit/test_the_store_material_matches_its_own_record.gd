extends GutTest

## The store material had NO guard at all. `tools/pre_ready_guards.sh` said so honestly on 2026-10-24:
## a fold touching only `itch-assets/` derived nothing from any leg, and the sweep reported that a
## green there said nothing about those 26 paths (gate712 red). The tool was right; this is the
## missing guard rather than a relaxation of the arm that caught it.
##
## It drives the real `tools/check_store_assets.sh --verify`: every MANIFEST row describes a file that
## is on disk, every file on disk is listed, and the authored docs match what THIS commit records
## (the tool's default ref is HEAD since 2026-10-24 — `origin/store-assets` stopped being canonical
## when itch-assets/ landed on main on 09-24, and the old refusal printed an overwrite as its remedy).
##
## ⚠️ `res://itch-assets` below is load-bearing beyond readability: pre_ready_guards' TREE leg finds
## a tree's guards by grepping them for that exact literal, so this constant is what makes a store
## change derive this file. Renaming it to a plain string silently returns itch-assets to having no
## guard, and the sweep goes back to reporting a hole.

const STORE_DIR := "res://itch-assets"
const TOOL := "tools/check_store_assets.sh"


func _root() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/")


func _run(flag: String) -> Array:
	var out: Array = []
	## TMPDIR into the repo's own tmp/: the checker's fixtures are mktemp -d, and the suite should not
	## write them under /usr's temp root.
	var cmd := "cd %s && TMPDIR=%s/tmp bash %s %s 2>&1" % [_root(), _root(), TOOL, flag]
	var ec := OS.execute("bash", ["-c", cmd], out, true)
	return [ec, "\n".join(out)]


func test_the_store_material_matches_its_own_record() -> void:
	var r := _run("--verify")
	assert_eq(r[0], 0, "tools/check_store_assets.sh --verify refused:\n%s" % r[1])


func test_the_checker_is_pointed_at_a_real_directory() -> void:
	## CONTROL: a clean verdict from a checker aimed at an absent or EMPTY directory is a green about
	## nothing, and "exists" alone cannot tell those apart — so enumerate and require real frames.
	## Walking is also what makes this file reachable: pre_ready_guards' TREE leg scans for guards
	## that ENUMERATE a directory (DirAccess.get_files_at / list_dir_begin / …) and then greps those
	## for "res://<tree>". A guard that only asks dir_exists_absolute is not a walker, derives for no
	## tree, and leaves itch-assets uncovered however well it checks.
	var dir := ProjectSettings.globalize_path(STORE_DIR)
	assert_true(DirAccess.dir_exists_absolute(dir), "%s is absent; the verdict above is about nothing" % STORE_DIR)
	assert_true(FileAccess.file_exists(dir + "/MANIFEST.txt"), "%s holds no MANIFEST.txt to check against" % STORE_DIR)
	var pngs := 0
	for f in DirAccess.get_files_at(dir + "/screenshots"):
		if str(f).ends_with(".png"):
			pngs += 1
	assert_gt(pngs, 0, "no .png under %s/screenshots — an empty tree satisfies 'exists' and checks nothing" % STORE_DIR)


func test_the_checker_can_refuse() -> void:
	## And a check that cannot fail is not a check: the tool's own arms plant drift, an unlisted file
	## and an uncommitted doc edit, and require each to be caught. Without this, the arm above is a
	## green whose discriminating power was never measured.
	var r := _run("--selftest")
	assert_eq(r[0], 0, "the checker's own arms did not all flip:\n%s" % r[1])
	assert_true(str(r[1]).contains("0 failed"), "selftest did not report 0 failed:\n%s" % r[1])
