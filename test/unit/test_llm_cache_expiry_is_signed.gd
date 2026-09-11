extends GutTest

## The response cache expired on `age > TTL`, where age is a subtraction.
##
## Third and MILDEST instance of one class found in this lane today. Stated
## plainly so nobody borrows the severity of the other two:
##
##   ConversationRewards  `since < BATTLE_COOLDOWN`   PERSISTED state
##                        every conversation reward dead until 43 battles won
##   RebalanceDaemon      `elapsed < interval`        PERSISTED state
##                        daemon dead for the whole clock offset (6h on a
##                        dual-boot RTC mismatch)
##   THIS                 `age > TTL`                 IN-MEMORY, cleared on
##                        scene change — costs FRESHNESS only
##
## A negative age means the entry's stamp is in the future: the system clock moved
## backwards mid-session (NTP correction, DST, manual change). `age > TTL` is then
## false and the entry never expires, so a stale response is served for as long as
## the lag lasts. Evicting is the safe direction — re-querying is the correct
## fallback and costs one request.
##
## Found by sweeping the lane deliberately rather than waiting for a third
## accident. ⚠️ The sweep's FIRST version was blind: it required a word character
## before the `-`, so `int(gs.battles_won) - last` did not match and the known
## ConversationRewards case was missing from its own results. It now carries that
## case as a CONTROL — if the scan cannot find the defect it was written for, its
## silence means nothing.

const LS := preload("res://src/llm/LLMService.gd")


var _svc = null


func before_each() -> void:
	_svc = LS.new()
	add_child_autofree(_svc)


func _seed(key: String, text: String, ts: float) -> void:
	_svc._cache[key] = {"text": text, "ts": ts}


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_future_stamped_entry_is_evicted_not_served_forever() -> void:
	var future: float = Time.get_unix_time_from_system() + 3600.0  # clock moved back an hour
	_seed("k", "stale line", future)
	assert_null(_svc._get_cache("k"),
		"a future-stamped entry must be evicted — `age > TTL` is false for it, so it never expired")
	assert_false(_svc._cache.has("k"),
		"and it must actually be removed, not merely refused this once")


func test_a_wildly_future_stamp_is_evicted_too() -> void:
	_seed("k", "stale", Time.get_unix_time_from_system() + 31536000.0)  # a year
	assert_null(_svc._get_cache("k"),
		"the staleness window scales with the clock error, so the guard must not depend on its size")


# ── it must still be a working cache ──────────────────────────────────────────

func test_a_fresh_entry_is_still_served() -> void:
	## CONTROL: the guard must not turn the cache off.
	_seed("k", "fresh line", Time.get_unix_time_from_system())
	assert_eq(str(_svc._get_cache("k")), "fresh line",
		"a just-written entry must still be served — this evicts impossible stamps, not valid ones")


func test_an_entry_inside_the_ttl_is_still_served() -> void:
	_seed("k", "recent", Time.get_unix_time_from_system() - (LS.CACHE_TTL_SECONDS / 2.0))
	assert_eq(str(_svc._get_cache("k")), "recent",
		"half a TTL old must still hit — otherwise the fix has disabled caching")


func test_an_entry_past_the_ttl_still_expires_normally() -> void:
	## CONTROL the other way: ordinary expiry must be untouched.
	_seed("k", "old", Time.get_unix_time_from_system() - (LS.CACHE_TTL_SECONDS + 60.0))
	assert_null(_svc._get_cache("k"),
		"past the TTL must still expire — the normal path is what the cache is for")


func test_a_missing_key_is_null_without_touching_the_cache() -> void:
	assert_null(_svc._get_cache("never_written"), "an absent key must simply miss")
	assert_eq(_svc._cache.size(), 0, "and must not create an entry")


func test_an_entry_with_no_stamp_is_treated_as_ancient() -> void:
	## `entry.get("ts", 0.0)` defaults to epoch 0, so a malformed entry reads as
	## enormously old and expires. That is the safe direction and worth pinning:
	## the alternative reading — no stamp means fresh — would cache forever.
	_svc._cache["k"] = {"text": "no stamp"}
	assert_null(_svc._get_cache("k"),
		"an entry with no timestamp must expire, not be served indefinitely")
