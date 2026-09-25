extends GutTest

## An unbounded cache is the LLMService._cache defect of 2026-09-20; a recast (rev bump) must never replay stale audio.

const DIR := "user://test_voice_cache"


func before_each() -> void:
	_wipe()


func after_each() -> void:
	_wipe()


func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)


func _blob(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	b.fill(1)
	return b


func test_the_key_changes_with_voice_rev_and_text() -> void:
	var k := VoiceCache.key_for("bard.wav", 3, "Hello.")
	assert_eq(k.length(), 32)
	assert_eq(k, ("v1|bard.wav|3|Hello.").sha256_text().left(32), "the spec's key, exactly")
	assert_ne(k, VoiceCache.key_for("bard.wav", 4, "Hello."), "bumping rev must miss")
	assert_ne(k, VoiceCache.key_for("mage.wav", 3, "Hello."))
	assert_ne(k, VoiceCache.key_for("bard.wav", 3, "Hello!"))


func test_a_write_reads_back_and_survives_a_new_instance() -> void:
	var c := VoiceCache.new(DIR, 10_000)
	assert_true(c.write("k1", _blob(100)))
	assert_eq(c.read("k1").size(), 100)
	var again := VoiceCache.new(DIR, 10_000)
	assert_true(again.has("k1"), "the index is rebuilt from disk")
	assert_eq(again.total_bytes(), 100)


func test_the_directory_stays_under_the_cap_and_a_read_protects_a_line() -> void:
	var c := VoiceCache.new(DIR, 1000)
	c.write("old", _blob(400))
	c.write("mid", _blob(400))
	c.read("old")
	c.write("new", _blob(400))
	assert_true(c.total_bytes() <= 1000, "over the cap: %d" % c.total_bytes())
	assert_true(c.has("old"), "read most recently before the write, so it stays")
	assert_false(c.has("mid"), "least recently used goes first")
	assert_true(c.has("new"))
	assert_false(FileAccess.file_exists(DIR + "/mid.wav"), "evicted from disk, not just the index")


func test_constructing_a_cache_writes_nothing() -> void:
	VoiceCache.new(DIR, 1000)
	assert_false(DirAccess.dir_exists_absolute(DIR), "boot must not write user://; the dir appears on first write")
