extends GutTest
## The map tools must be able to READ the palette they ship with.
##
## FOUND 2026-08-22, by me, about my own change. The per-world palette fold moved
## `terrain`/`landmarks` under `worlds.<id>` and updated the RUNTIME loader -- whose four
## tests stayed green -- while leaving all three python tools reading the v1 shape. They
## broke on main and nothing noticed, because nothing executes them.
##
## WHY THAT ASYMMETRY IS THE WHOLE POINT. `data/maps/map_palette.json` has two consumer
## families: MapImageLoader (guarded, 4 tests) and tools/*.py (guarded by nothing). A
## format change that updates one and not the other is invisible to a full suite. The tools
## are how every map is authored, so "broken and green" is the worst available state.
##
## THIS EXECUTES THE TOOLS rather than grepping them. A source check would have to assert
## that each tool spells the access some particular way -- a use-site pin, which reds on a
## correct refactor and passes on a wrong value spelled right. Running them asks the only
## question that matters: does it load?
##
## BOUND: this checks the PALETTE PATH, not that a tool produces a correct map. The map's
## correctness is covered by test_map_image_roundtrip's golden.

const TOOLS := ["compose_overworld_w1", "scale_overworld_png", "map_ascii_to_png"]


func _run_python(snippet: String) -> Array:
	var out: Array = []
	var code := OS.execute("python3", ["-c", snippet], out, true)
	return [code, "\n".join(out.map(func(x): return str(x)))]


func test_every_map_tool_can_load_the_shipped_palette() -> void:
	# CONTROL: python must be runnable at all, or every result below is meaningless
	var probe := _run_python("print('alive')")
	if int(probe[0]) != 0:
		pending("python3 unavailable in this environment -- the tools cannot be exercised")
		return
	assert_true(str(probe[1]).contains("alive"), "python control produced no output")

	# CONTROL: a deliberately broken import MUST fail, or a zero below proves nothing
	var neg := _run_python("import zzz_definitely_not_a_module")
	assert_ne(int(neg[0]), 0, "a broken import returned 0 -- this probe cannot detect failure")

	var broken: Array = []
	for tool_name in TOOLS:
		var snippet := (
			"import sys; sys.path.insert(0, 'tools')\n" +
			"import %s as T\n" % tool_name +
			# touch the palette path: module-level for some, a loader call for others
			"pal = getattr(T, 'CH2RGB', None)\n" +
			"fn  = getattr(T, 'load_palette', None)\n" +
			"if fn is not None: pal = fn()\n" +
			"assert pal is None or len(pal) > 0, 'palette decoded to nothing'\n" +
			"print('OK', len(pal) if pal else 'n/a')\n"
		)
		var r := _run_python(snippet)
		if int(r[0]) != 0:
			broken.append("%s -> %s" % [tool_name, str(r[1]).strip_edges().split("\n")[-1]])

	assert_eq(
		broken, [],
		"map tools that cannot read data/maps/map_palette.json: %s. The runtime loader and the authoring tools read the SAME file; a format change that updates only the loader leaves these broken while the suite stays green." % str(broken)
	)
