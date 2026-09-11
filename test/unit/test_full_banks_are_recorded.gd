extends GutTest

## Full Bank is the top of the AP economy — five actions for four AP — and the Records page, which
## already keeps nine live-read stats with editorial quips, said nothing about it. Purely additive:
## a counter, four persistence sites mirroring `battles_won`, and one row. No combat behaviour
## changes, which is deliberate — feel is struktured's to steer and this touches none of it.
##
## The counter is PLAYER-SIDE. Enemies do not get the fifth action today, and if they ever do this
## stays a record of what the player did, not of what was done to them.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const RecordsMenuScript = preload("res://src/ui/RecordsMenu.gd")

var _saved: int = 0

func before_each() -> void:
	_saved = GameState.full_banks_unleashed

func after_each() -> void:
	GameState.full_banks_unleashed = _saved

## Quote-aware: cut at the first `#` OUTSIDE a string literal. A plain find("#") truncates real code
## on any line holding a `#` in quoted text — 3 such lines in BattleManager (cowir-controller and
## cowir-overworld, 2026-09-11). Line count preserved so substr windows stay valid.
func _strip_comments(raw: String) -> String:
	var out: Array = []
	for line in raw.split("\n"):
		var in_d := false
		var in_s := false
		var cut := -1
		for k in line.length():
			var c := line[k]
			if c == '"' and not in_s:
				in_d = not in_d
			elif c == "'" and not in_d:
				in_s = not in_s
			elif c == "#" and not in_d and not in_s:
				cut = k
				break
		out.append(line.substr(0, cut) if cut > -1 else line)
	return "\n".join(out)

func test_the_counter_exists_and_starts_at_zero_on_a_new_game() -> void:
	GameState.full_banks_unleashed = 7
	GameState.reset_game_state()
	assert_eq(GameState.full_banks_unleashed, 0,
		"a new run has banked nothing — a record that survives New Game would read as the player's")

func test_it_survives_a_save_and_load() -> void:
	GameState.full_banks_unleashed = 12
	var data: Dictionary = GameState.to_dict()
	assert_true(data.has("full_banks_unleashed"), "it must be written to the save at all")
	GameState.full_banks_unleashed = 0
	GameState.from_dict(data)
	assert_eq(GameState.full_banks_unleashed, 12, "and come back with the same count")

func test_a_save_written_before_this_shipped_loads_as_zero() -> void:
	## Every existing save lacks the key. Reading absence as anything but 0 would invent a number,
	## and a crash here would make old saves unloadable — which is worse than any missing record.
	GameState.full_banks_unleashed = 99
	var data: Dictionary = GameState.to_dict()
	data.erase("full_banks_unleashed")
	GameState.from_dict(data)
	assert_eq(GameState.full_banks_unleashed, 0, "an absent key is zero, not a carry-over or a crash")

func test_a_corrupt_value_cannot_go_negative() -> void:
	var data: Dictionary = GameState.to_dict()
	data["full_banks_unleashed"] = -5
	GameState.from_dict(data)
	assert_eq(GameState.full_banks_unleashed, 0, "clamped like every other counter in from_dict")

func test_the_unleash_path_increments_it() -> void:
	## The join. A counter nothing writes is a row that always reads zero — and the quip would sit
	## on "Bank four. Spend five. Not yet." forever while the player did it every fight.
	## ⚠️ COMMENTS BLANKED FIRST. cowir-controller 2026-09-11: a source-text pin is satisfied by the
	## COMMENT, so the arm that catches it is the tidy removal and the arm it misses is the realistic
	## one — nobody deletes a line without leaving the note that explained it. Measured on this very
	## test: replacing the increment with `pass  ## was: GameState.full_banks_unleashed += 1` left it
	## GREEN at 7/7 with the counter no longer written. Line count preserved so offsets stay valid.
	var raw := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var src: String = _strip_comments(raw)
	var i: int = src.find("full_bank_unleashed.emit(")
	assert_gt(i, -1, "CONTROL: located the unleash emit in CODE, not in a comment")
	var j: int = src.find("\nfunc ", i)
	var tail: String = src.substr(i, (j - i) if j > -1 else 400)
	assert_true(tail.contains("GameState.full_banks_unleashed += 1"),
		"the record must be written where the bank actually fires, not on a separate path")
	assert_true(tail.contains("player_party"),
		"and only for the player — this is the player's record")

func test_the_records_page_shows_it() -> void:
	var menu = RecordsMenuScript.new()
	autofree(menu)
	GameState.full_banks_unleashed = 3
	var rows: Array = menu._collect_records()
	assert_gt(rows.size(), 5, "CONTROL: the page collects its other rows")
	var found: Array = rows.filter(func(r): return str(r[0]) == "Full Banks")
	assert_eq(found.size(), 1, "exactly one Full Banks row")
	assert_eq(str(found[0][1]), "3", "and it reads the live count, not a placeholder")

func test_the_quip_changes_once_you_have_done_it() -> void:
	## The page's voice: every other row says something different at zero. A single static line
	## would read as a stat sheet rather than as the game noticing.
	var menu = RecordsMenuScript.new()
	autofree(menu)
	GameState.full_banks_unleashed = 0
	var at_zero: String = str(menu._collect_records().filter(func(r): return str(r[0]) == "Full Banks")[0][2])
	GameState.full_banks_unleashed = 1
	var after: String = str(menu._collect_records().filter(func(r): return str(r[0]) == "Full Banks")[0][2])
	assert_ne(at_zero, after, "the quip must acknowledge that the player has done it")
	assert_gt(at_zero.length(), 0, "CONTROL: both are real text")
	assert_gt(after.length(), 0, "CONTROL: both are real text")
