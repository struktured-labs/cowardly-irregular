extends GutTest

## `max()`/`min()`/`abs()`/`clamp()` and friends return Variant. Binding one with `:=`
## infers Variant, and this project treats that warning as an error — so the file is
## REJECTED by `--check-only` and by a cold `--import`, printing "Failed to load script".
##
## The GUT runtime loader accepts it anyway, so the tests still run and the suite stays
## green. That gap is why this went unnoticed: the only instruments that reject are ones
## nobody runs before a fold. Measured 2026-08-15 on test_byok_settings_ui_regression.gd:49,
## the single instance tree-wide against 108 files already using the typed siblings.
##
## Use the typed forms: maxi/mini/absi/clampi (int) or maxf/minf/absf/clampf (float).

const UNTYPED := "max|min|abs|clamp|round|floor|ceil|sign|pow|sqrt"
const TYPED := "maxi|mini|absi|clampi|maxf|minf|absf|clampf"
## A file known to use the typed forms — the control names a member instead of a count.
const CONTROL_FILE := "res://src/battle/BattleManager.gd"


func _gd_files_under(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir() and not name.begins_with("."):
			out.append_array(_gd_files_under(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
	return out


func _corpus() -> Array[String]:
	var out: Array[String] = []
	out.append_array(_gd_files_under("res://src"))
	out.append_array(_gd_files_under("res://test"))
	return out


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


## Only the WALRUS binding is a defect — a bare max() call as an argument is fine.
func _walrus_hits(src: String, alternation: String) -> int:
	var re := RegEx.new()
	re.compile(":=\\s*(%s)\\s*\\(" % alternation)
	return re.search_all(src).size()


## The control counts ANY call of the typed form, not just walrus-bound ones — most
## real uses are arguments inside expressions, and an earlier version measured 0 here.
func _call_hits(src: String, alternation: String) -> int:
	var re := RegEx.new()
	re.compile("\\b(%s)\\s*\\(" % alternation)
	return re.search_all(src).size()


func test_no_variant_returning_builtin_is_bound_with_walrus() -> void:
	var offenders: Array[String] = []
	for path in _corpus():
		if _walrus_hits(_read(path), UNTYPED) > 0:
			offenders.append(path.get_file())
	assert_eq(offenders.size(), 0,
		"%d file(s) bind a Variant-returning builtin with `:=`, which this project rejects "
		% offenders.size()
		+ "at --check-only/--import time — use the typed form (maxi/maxf/...): "
		+ ", ".join(offenders))


func test_the_scan_finds_the_typed_form_in_a_named_file() -> void:
	# A count control tests plumbing; this names a member that must be found.
	var hits := _call_hits(_read(CONTROL_FILE), TYPED)
	assert_gt(hits, 0,
		"the scanner found ZERO typed-sibling calls in %s — a broken pattern " % CONTROL_FILE
		+ "would report zero offenders forever, so this proves the regex can match at all")


func test_the_corpus_is_a_real_population() -> void:
	# Guards against a corpus walker that silently returns nothing.
	var with_typed := 0
	for path in _corpus():
		if _call_hits(_read(path), TYPED) > 0:
			with_typed += 1
	assert_gt(with_typed, 40,
		"only %d file(s) use the typed siblings — measured 108 on 2026-08-15, so a " % with_typed
		+ "collapse to near-zero means the walker stopped reaching the tree")
