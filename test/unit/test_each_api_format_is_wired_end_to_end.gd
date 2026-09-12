extends GutTest

## An unknown backend format POSTed an OpenAI body to Ollama's endpoint.
##
## `HTTPBackend` matched on `api_format` in five places, and the unknown arm of
## each made its own choice. Measured before the fix:
##
##     _probe_url       -> the bare base_url        (health-checks nothing)
##     _probe_method    -> METHOD_HEAD              (the other two formats GET)
##     _endpoint_url    -> the OLLAMA url,      warning: "defaulting to Ollama."
##     _build_body      -> an OPENAI body       ("openai", _:)
##     _extract_text    -> OPENAI parsing       ("openai", _:)
##
## Three different fallbacks across one request. And the warning was false about
## two of the three request-path sites: a developer who read "defaulting to
## Ollama" and went looking for an Ollama body would not find one.
##
## ⛔ UNREACHABLE TODAY, AND THAT IS MEASURED — this is a ratchet, not a live bug.
## Every writer of the value is constrained: `SaveSystem:1177` clamps a
## hand-edited settings.json (`fmt if fmt in ["openai", "ollama"] else "openai"`),
## `BYOKConfigPanel` writes one of two literals from a two-entry OptionButton,
## `LLMService:195` writes the literal "ollama", and no scene file sets it. So
## nothing a player can do reaches the unknown arm.
##
## It matters because of the edit that WILL come. Adding a third format is a
## five-site change where `_build_body` and `_extract_text` fail SILENTLY — their
## default arms are `"openai", _:`, so a missed site is not an error, it is an
## OpenAI request sent to the new backend.
##
## FIXED by making the unknown arm coherent rather than by documenting the split:
## every site now falls back to OpenAI, which is what `_build_body`,
## `_extract_text`, `GameState`'s default and SaveSystem's clamp already chose.
## `_probe_method` collapsed to a constant — both formats GET, and the bare HEAD
## it returned for unknown probed nothing.
##
## What this guard pins is COHERENCE PER FORMAT, not the five call sites: each
## format's probe, URL, body and parse must agree with each other. A site missed
## when the third format lands shows up as a body that does not match its
## endpoint — the thing that actually breaks — and it catches a miss at any site.

const SAVE_SYSTEM := "res://src/save/SaveSystem.gd"

## A line of SaveSystem that is unambiguously code, used as the stripper's control.
const SAVE_SYSTEM_CODE_SITE := "func save_game(slot: int = -1) -> bool:"

## The vocabulary, as HTTPBackend's own export documents it.
const FORMATS: Array[String] = ["ollama", "openai"]

## What each format must look like end to end.
const EXPECTED: Dictionary = {
	"ollama": {
		"path": "/api/generate", "probe": "/api/tags", "body_key": "prompt",
		"reply": '{"response":"R"}',
	},
	"openai": {
		"path": "/v1/chat/completions", "probe": "/v1/models", "body_key": "messages",
		"reply": '{"choices":[{"message":{"content":"C"}}]}',
	},
}

## The format an unrecognised one must behave exactly like, at every site.
const UNKNOWN_FOLLOWS := "openai"

const BASE := "https://example.invalid"


## Unparented: _ready() fires a live network probe, which a test must not do.
func _backend(fmt: String) -> HTTPBackend:
	var be := HTTPBackend.new()
	autofree(be)
	be.base_url = BASE
	be.model = "some-model"
	be.api_format = fmt
	return be


# ── each declared format is coherent end to end ───────────────────────────────

func test_every_format_posts_the_body_its_endpoint_expects() -> void:
	## THE ARM. A site missed when a third format lands shows up here as a body
	## that does not match its URL — not as a missing case label.
	var broken: Array[String] = []
	for fmt in FORMATS:
		var be: HTTPBackend = _backend(fmt)
		var url: String = be._endpoint_url(false)
		var body: String = be._build_body("a prompt", {})
		var want: Dictionary = EXPECTED[fmt] as Dictionary
		if url.find(str(want["path"])) == -1:
			broken.append("%s url is %s, wanted %s" % [fmt, url, str(want["path"])])
		if body.find("\"%s\"" % str(want["body_key"])) == -1:
			broken.append("%s body has no '%s' key" % [fmt, str(want["body_key"])])
	assert_eq(broken, ([] as Array[String]),
		("a format's request URL and body disagree: %s. Every `match api_format` in "
		+ "HTTPBackend must handle each declared format — _build_body and _extract_text "
		+ "default to OpenAI silently, so a missed arm raises no error.") % ", ".join(broken))


func test_every_format_parses_its_own_backends_reply() -> void:
	var broken: Array[String] = []
	for fmt in FORMATS:
		var be: HTTPBackend = _backend(fmt)
		var res: Array = be._extract_text(200, str((EXPECTED[fmt] as Dictionary)["reply"]).to_utf8_buffer())
		if not bool(res[0]):
			broken.append("%s: %s" % [fmt, str(res[2])])
	assert_eq(broken, ([] as Array[String]),
		"these formats cannot read their own backend's reply: %s" % ", ".join(broken))


func test_every_format_probes_its_own_health_endpoint() -> void:
	var broken: Array[String] = []
	for fmt in FORMATS:
		var be: HTTPBackend = _backend(fmt)
		var probe: String = be._probe_url()
		if probe.find(str((EXPECTED[fmt] as Dictionary)["probe"])) == -1:
			broken.append("%s probes %s" % [fmt, probe])
	assert_eq(broken, ([] as Array[String]),
		"these formats probe the wrong endpoint: %s" % ", ".join(broken))


# ── the unknown arm follows ONE format, not three ─────────────────────────────

func test_an_unrecognised_format_behaves_like_exactly_one_real_one() -> void:
	## THE REGRESSION. Not "unknown is handled" — unknown was handled at all five
	## sites before, by three different formats. What was wrong is that they
	## disagreed, so no single backend could serve the request.
	var unknown: HTTPBackend = _backend("some_future_format")
	var like: HTTPBackend = _backend(UNKNOWN_FOLLOWS)
	var split: Array[String] = []
	if unknown._endpoint_url(false) != like._endpoint_url(false):
		split.append("endpoint (%s vs %s)" % [unknown._endpoint_url(false), like._endpoint_url(false)])
	if unknown._build_body("p", {}) != like._build_body("p", {}):
		split.append("body")
	if unknown._probe_url() != like._probe_url():
		split.append("probe url (%s vs %s)" % [unknown._probe_url(), like._probe_url()])
	if unknown._probe_method() != like._probe_method():
		split.append("probe method")
	var reply: String = str((EXPECTED[UNKNOWN_FOLLOWS] as Dictionary)["reply"])
	if bool(unknown._extract_text(200, reply.to_utf8_buffer())[0]) \
			!= bool(like._extract_text(200, reply.to_utf8_buffer())[0]):
		split.append("parse")
	assert_eq(split, ([] as Array[String]),
		("an unrecognised api_format no longer follows '%s' at every site — it splits at: %s. "
		+ "A request built this way cannot be served by any one backend.")
		% [UNKNOWN_FOLLOWS, ", ".join(split)])


func test_the_warning_names_the_format_the_code_actually_uses() -> void:
	## The half that had no test and was therefore free to go stale. The old text
	## said "defaulting to Ollama" while the body and the parse were OpenAI's.
	var src: String = FileAccess.get_file_as_string("res://src/llm/HTTPBackend.gd")
	assert_false(src.is_empty(), "CONTROL: source must load")
	var at: int = src.find("Unknown api_format")
	assert_true(at != -1, "CONTROL: the unknown-format warning must still exist")
	var line: String = src.substr(at, 160)
	assert_true(line.to_lower().find(UNKNOWN_FOLLOWS) != -1,
		("the warning must name '%s', the format the unknown arm actually follows. It said "
		+ "'defaulting to Ollama' while two of the three request sites used OpenAI: %s")
		% [UNKNOWN_FOLLOWS, line.split("\n")[0]])


# ── the vocabulary must agree wherever it is declared ─────────────────────────

func test_the_clamp_admits_exactly_the_formats_this_file_covers() -> void:
	## SaveSystem clamps a hand-edited settings.json to a hardcoded pair. If it
	## ever admits a third, this file's coverage is silently one short and the new
	## format reaches HTTPBackend through a door no arm above tested.
	var src: String = _code_only(FileAccess.get_file_as_string(SAVE_SYSTEM))
	assert_false(src.is_empty(), "CONTROL: SaveSystem must load")
	for fmt in FORMATS:
		assert_true(src.find("\"%s\"" % fmt) != -1,
			("SaveSystem's api_format clamp no longer names '%s'. If the clamp list changed, add "
			+ "the format to FORMATS and EXPECTED here — otherwise it reaches HTTPBackend "
			+ "untested, and _build_body/_extract_text treat it as OpenAI without erroring.") % fmt)


func test_the_clamp_is_still_what_keeps_the_unknown_arm_off_the_player_path() -> void:
	## THE PREMISE. This is a ratchet only because no writer can produce an unknown
	## format. If the clamp goes, the unknown arm becomes live — it is coherent now,
	## but it would be pointing a real player at an OpenAI endpoint they did not pick.
	var src: String = _code_only(FileAccess.get_file_as_string(SAVE_SYSTEM))
	assert_true(src.find("llm_custom_api_format") != -1,
		"CONTROL: SaveSystem must still load the field")
	assert_true(src.find("else \"openai\"") != -1,
		("SaveSystem no longer coerces an unrecognised api_format, so a hand-edited "
		+ "settings.json now reaches HTTPBackend's unknown arm. Re-read this file's header: "
		+ "the arm is coherent but it is a guess, not the player's choice."))


# ── controls ──────────────────────────────────────────────────────────────────

func test_the_two_formats_are_actually_distinguishable() -> void:
	## CONTROL. Every arm above compares one format's output to another's. If the
	## two produced identical URLs and bodies, the coherence arm would pass for a
	## backend that ignored api_format entirely.
	var a: HTTPBackend = _backend("ollama")
	var b: HTTPBackend = _backend("openai")
	assert_ne(a._endpoint_url(false), b._endpoint_url(false), "the two endpoints must differ")
	assert_ne(a._build_body("p", {}), b._build_body("p", {}), "the two bodies must differ")
	assert_ne(a._probe_url(), b._probe_url(), "the two probes must differ")


func test_a_reply_in_the_wrong_shape_is_rejected_rather_than_emptied() -> void:
	## CONTROL on the parse arm: it asserts `res[0]` is true for the matching
	## shape. If _extract_text returned true for everything, that proves nothing.
	var be: HTTPBackend = _backend("ollama")
	var res: Array = be._extract_text(200, str((EXPECTED["openai"] as Dictionary)["reply"]).to_utf8_buffer())
	assert_false(bool(res[0]),
		"an Ollama backend must reject an OpenAI-shaped reply, or the parse arm is vacuous")


func test_the_backend_really_built() -> void:
	## CONTROL: every arm reads methods off a constructed backend. One that failed
	## to build would make them all vacuous in the same direction.
	var be: HTTPBackend = _backend("ollama")
	assert_eq(be.api_format, "ollama", "the fixture must carry the format under test")
	assert_true(be._endpoint_url(false).begins_with(BASE), "and the base url it was given")


## Strip BOTH comment forms before any presence assert on this file.
##
## Every arm below asks whether a token IS PRESENT, and a presence assert is
## exactly what prose satisfies. `#` comments need a line-based stateless pass;
## `"""` regions are not line-addressable and need a parity pass — SaveSystem
## carries 36 of them, so the `#` half alone would not have been enough.
##
## `must_survive` is a KNOWN CODE SITE that over-stripping deletes. Without it an
## over-aggressive stripper and a correct one are the same green, and the arms
## would red on correct code with no way to tell which happened.
func _code_only(src: String, must_survive: String = SAVE_SYSTEM_CODE_SITE) -> String:
	var out: PackedStringArray = PackedStringArray()
	var in_doc: bool = false
	for line in src.split("\n"):
		var hash_at: int = line.find("#")
		var code: String = line if hash_at == -1 else line.substr(0, hash_at)
		var trimmed: String = code.strip_edges()
		if in_doc:
			if trimmed.ends_with("\"\"\""):
				in_doc = false
			continue
		if trimmed.begins_with("\"\"\""):
			# A single-line """…""" opens and closes; only an odd count toggles.
			if trimmed.count("\"\"\"") % 2 == 1:
				in_doc = true
			continue
		out.append(code)
	var stripped: String = "\n".join(out)
	assert_true(stripped.find(must_survive) != -1,
		("STRIPPER CONTROL: '%s' is a known code site in SaveSystem and must survive "
		+ "stripping. It did not, so the stripper is eating code and every presence "
		+ "assert above is measuring the wrong text.") % must_survive)
	return stripped
