extends GutTest

## 2026-07-02: the title-screen version label was LYING — Version.SEMVER
## sat at "3.26.0-alpha" while the deployed build was v3.31.0-alpha and
## main was 165 commits past the tag. Three of tonight's playtest bug
## reports arrived with no way to tell which build produced them.
## display() now embeds the git short-hash in dev runs; semver() stays
## clean for save-file persistence.


func test_semver_matches_deployed_release_line() -> void:
	# Ratchet vs the stale-const failure mode: the const must at least
	# be on the currently-deployed release line (bump at deploy time).
	assert_true(Version.SEMVER.begins_with("3.31."),
		"Version.SEMVER (%s) is behind the deployed v3.31.0-alpha — bump it at deploy time" % Version.SEMVER)


func test_display_embeds_dev_hash_in_source_checkouts() -> void:
	# This test runs from a source checkout, so git must resolve.
	var h: String = Version._git_short_hash()
	assert_true(h.length() >= 7 and h.is_valid_hex_number(),
		"dev runs must resolve a git short-hash (got '%s')" % h)
	assert_true(Version.display().contains("(" + h + ")"),
		"display() must embed the dev hash so F12 caps self-document the build")


func test_semver_never_carries_the_dev_hash() -> void:
	# SaveSystem persists semver() — tooling parses it; a "(hash)" suffix
	# would break every downstream parse.
	assert_false(Version.semver().contains("("))
	assert_eq(Version.semver(), Version.SEMVER)


func test_hash_is_cached_static() -> void:
	# One subprocess per session, not one per display() call.
	var a: String = Version._git_short_hash()
	assert_true(Version._dev_hash_cached)
	assert_eq(Version._git_short_hash(), a)
