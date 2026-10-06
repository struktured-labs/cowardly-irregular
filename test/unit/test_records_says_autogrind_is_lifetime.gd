extends GutTest

## Regression (#193): the Records page showed "Autogrind Sessions 4" on a 22-second New Game. Every other row is per-save;
## this one reads AutogrindSystem.session_history, a machine-global file nothing clears on New Game. It stays lifetime
## (the history browser depends on it) and now says so, so the page no longer reads as a per-save count.

const RecordsMenuScript := preload("res://src/ui/RecordsMenu.gd")


func _row(rows: Array, label: String) -> Array:
	for r in rows:
		if str(r[0]) == label:
			return r
	return []


func test_the_autogrind_row_says_it_spans_all_saves() -> void:
	var m = RecordsMenuScript.new()
	autofree(m)
	var row := _row(m._collect_records(), "Autogrind Sessions")
	assert_eq(row.size(), 3, "SCOPE: the Records page has an Autogrind Sessions row")
	if row.size() < 3:
		return
	assert_string_contains(str(row[2]).to_lower(), "all saves", "a lifetime count must say it is not this save's")


func test_the_row_counts_the_lifetime_history() -> void:
	var m = RecordsMenuScript.new()
	autofree(m)
	var row := _row(m._collect_records(), "Autogrind Sessions")
	assert_eq(str(row[1]) if row.size() > 1 else "", str(AutogrindSystem.session_history.size()), "CONTROL: the value is the machine-global history size")


func test_a_per_save_row_does_not_claim_all_saves() -> void:
	var m = RecordsMenuScript.new()
	autofree(m)
	var row := _row(m._collect_records(), "Battles Won")
	assert_false(str(row[2]).to_lower().contains("all saves") if row.size() > 2 else true, "CONTROL: per-save rows stay unlabelled")
