extends RefCounted
## The CODE of a .gd file, with `#` comments and `"""` docstrings removed — for any guard whose
## assertion is satisfied by the mere presence of a token.
##
## ⛔ A PRESENCE ASSERT OVER RAW SOURCE IS SATISFIED BY PROSE ABOUT THE CODE. Measured
## 2026-09-12 on this lane's own guards: delete `"boss_" + _current_world_suffix` from
## SoundManager, name it in `_start_boss_music`'s docstring, and the arm excusing ~119 composed
## track ids stayed GREEN with the composition gone. Delete the boss path's
## `_declared_music_track(boss_type)` call, name it in an EARLIER docstring, and the boss-routing
## guard went fully green — its two passes before that were positional luck, not detection.
##
## 🔑 TWO HALVES, AND WHICH YOU NEED IS DECIDED BY WHAT YOUR ASSERTION IS SATISFIED BY
## (cowir-overworld's split, 2026-09-12): `#` comments are line-addressable, so a stateless
## line pass handles them; a `"""` region is not, so it needs a region split. A `#`-only strip
## cannot touch a docstring — that is this lane's `.325` defect verbatim.
##
## ⚠️ THE SPLIT IS PARITY, NOT A STATE MACHINE. cowir-adhoc lost five verdicts to a stripper
## whose docstring toggle parsed as `A or (B and C)`; the state desynced and swallowed whole
## files as prose. Nothing here carries state across a delimiter.
##
## ⛔ BUT "NOTHING TO DESYNC" WAS TRUE OF THE SPLIT AND FALSE OF THE PIPELINE, and the first
## version of this header said it flatly. Running the `#` pass SECOND was itself the state
## dependency I claimed not to have: a fence hidden in a comment flipped parity for the rest of
## the file. Fixed in split() below, where the order is now the whole point.
##
## ⚠️ AND A STRIPPER IS AN INSTRUMENT TOO: over-stripping and a correct strip are the same green.
## Every caller MUST assert a known code site survives — `split()` returns both halves so the
## caller can also floor the doc side, because an empty doc side passes by construction.
##
## 📌 test_every_authored_bed_has_a_consumer.gd keeps its OWN quote-aware stripper and its own
## case table. Not folded in here: that one is pinned by a six-costume table earned across four
## lanes, and rewiring a load-bearing guard to a new helper is a bigger change than the exposure
## it would close. If a third consumer appears, move that table here and delete the copy.


## {"code": <outside every docstring, comments stripped>, "doc": <inside them>}
static func split(body: String) -> Dictionary:
	## ⛔ ORDER IS LOAD-BEARING, AND THIS SHIPPED THE WRONG WAY ROUND. A `"""` inside a `#`
	## comment flips parity for the whole rest of the file, so splitting first loses real code
	## from the code half AND leaks prose into it — both directions from one flip. Measured on
	## this helper (cowir-sprites, 2026-09-12): `var x` and `var y` both absent, the docstring
	## text present. Stripping comments first removes the false fence before parity ever sees it.
	##
	## ⚠️ THE COST, measured rather than waved past: `strip_comments` then also runs inside
	## docstring regions, so a `#` there truncates that line in the `doc` half. Four such lines
	## exist in src/ today — two prose ("principle #7", "Cadence #14") and two hex colours, which
	## are inside string literals and therefore survive the quote-aware pass anyway. None carries
	## a token any consumer asserts. A parity flip is the worse failure and the only one with two
	## directions, so this is the right trade — but it IS a trade.
	var parts: PackedStringArray = strip_comments(body).split("\"\"\"")
	var code: PackedStringArray = []
	var doc: PackedStringArray = []
	for i in parts.size():
		if i % 2 == 0:
			code.append(parts[i])
		else:
			doc.append(parts[i])
	return {"code": "\n".join(code), "doc": "\n".join(doc)}


static func code_of(path: String) -> String:
	return str(split(FileAccess.get_file_as_string(path))["code"])


## Quote-aware and escape-aware: a `#` inside a string is not a comment, and `\"` does not
## close one. Both costumes exist in src/ today.
static func strip_comments(src: String) -> String:
	var out: PackedStringArray = []
	for line in src.split("\n"):
		var l: String = str(line)
		var quote: String = ""
		var kept: String = ""
		var i: int = 0
		## ⛔ BOUNDED, AND THE BOUND IS THE REAL ONE: every branch below consumes at least one
		## character, so a correct scan can never reach l.length() + 1 iterations. A mutation that
		## drops an advance would otherwise SPIN — measured 2026-09-12 on this file: EC=124, killed
		## by an external timeout after 90 s, with `run_tests.sh` carrying no timeout of its own.
		## A hang is not a red: it reads as infrastructure, it outlives its own sweep (12 minutes,
		## measured by cowir-controller) and a second sweep then collides with it on git index.lock.
		## Truncating the line instead makes the consumers' surviving-code controls fire, which is
		## EC=1 and names the defect. @cowir-sprites bound their private copy in 6affd8ee; the bound
		## does not travel with a helper, and this one now has three consumers.
		var budget: int = l.length() + 1
		while i < l.length():
			budget -= 1
			if budget < 0:
				break
			var ch: String = l[i]
			if quote != "":
				kept += ch
				if ch == "\\" and i + 1 < l.length():
					kept += l[i + 1]
					i += 2
					continue
				if ch == quote:
					quote = ""
			elif ch == "\"" or ch == "'":
				quote = ch
				kept += ch
			elif ch == "#":
				break
			else:
				kept += ch
			i += 1
		out.append(kept)
	return "\n".join(out)
