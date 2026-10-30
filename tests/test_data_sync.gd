extends SceneTree

var failures: int = 0
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var feed_script = load("res://scripts/data_sync/economic_feed.gd")
	check(feed_script != null, "EconomicFeed must exist")
	if feed_script == null:
		quit(1)
		return
	var feed = feed_script.new()
	root.add_child(feed)
	var event = {"id":"rate_change","title":"Объявление","body":"Будущая ставка", "source":"https://www.cbr.ru/hd_base/KeyRate/", "published_at":"2025-01-01","effective_at":"2025-02-01","country":"RU","region":"","version":"1","verification_status":"verified","parameters":{"key_rate":0.21}}
	check(feed.validate_update(event).is_empty(), "Valid official reviewed update accepted")
	var bad = event.duplicate(true)
	bad.source = "https://www.cbr.ru.attacker.example/news"
	check(not feed.validate_update(bad).is_empty(), "Reject suffix domain impersonation")
	bad = event.duplicate(true)
	bad.source = "http://www.cbr.ru/hd_base/KeyRate/"
	check(not feed.validate_update(bad).is_empty(), "Reject plaintext HTTP")
	bad = event.duplicate(true)
	bad.effective_at = "2025-02-30"
	check(not feed.validate_update(bad).is_empty(), "Reject impossible date")
	bad = event.duplicate(true)
	bad.parameters = {"tax_rate":1.4}
	check(not feed.validate_update(bad).is_empty(), "Reject invalid rate range")
	bad = event.duplicate(true)
	bad.parameters = {"money_cheat":1000000}
	check(not feed.validate_update(bad).is_empty(), "Reject unknown parameters")
	feed.updates = [event]
	check(feed.due_updates("2025-01-31","RU").is_empty(), "Announcement does not apply before effective date")
	check(feed.due_updates("2025-02-01","RU").size() == 1, "Verified update activates on effective date")
	check(feed.due_updates("2025-03-01","US").is_empty(), "Respect selected country")
	bad = event.duplicate(true)
	bad.verification_status = "unverified"
	feed.updates = [bad]
	check(feed.due_updates("2025-03-01","RU").is_empty(), "Unverified report must never activate")
	var xml = '<?xml version="1.0"?><ValCurs Date="01.01.2025"><Valute ID="R01235"><NumCode>840</NumCode><CharCode>USD</CharCode><Nominal>1</Nominal><Name>Dollar</Name><Value>101,6797</Value></Valute><Valute ID="R01239"><CharCode>EUR</CharCode><Nominal>1</Nominal><Value>106,1028</Value></Valute></ValCurs>'
	var parsed = feed.parse_cbr_bytes(xml.to_utf8_buffer())
	check(parsed.ok and absf(parsed.data.rates.USD - 101.6797) < 0.00001, "Parse decimal comma exactly per nominal")
	check(parsed.ok and parsed.data.effective_at == "2025-01-01", "CBR effective date parsed")
	var invalid_xml = xml.replace("<Nominal>1</Nominal>","<Nominal>0</Nominal>")
	check(not feed.parse_cbr_bytes(invalid_xml.to_utf8_buffer()).ok, "Reject zero currency nominal")
	check(not feed.parse_cbr_bytes("<bad>".to_utf8_buffer()).ok, "Reject malformed XML without required currencies")
	check(not feed.parse_cbr_bytes(xml.replace("101,6797","-1").to_utf8_buffer()).ok, "Reject negative rates")
	feed.cache_path = "user://data_sync_test_%d.json" % Time.get_ticks_usec()
	var loaded = feed.load_cache()
	check(loaded.ok and feed.snapshot.get("effective_at", "") == "2024-12-29", "Offline first-run loads bundled historical CBR sample with actual source date")
	check(feed.status_text().contains("2024-12-29"), "Stale snapshot date visible")
	check(feed.snapshot.get("raw_sha256", "") == "46698b61b7025792a5a8120fa9bfe1ebeee3f21d038eb22db54aaa4c808b99be", "Provenance matches exact archived response bytes")
	check(feed.news().size() >= 1, "Offline news provides provenance")
	var original = feed.snapshot.duplicate(true)
	feed._on_request_completed(HTTPRequest.RESULT_CANT_CONNECT,0,[],PackedByteArray())
	check(feed.snapshot == original, "Network failure preserves last verified snapshot")
	feed._on_request_completed(HTTPRequest.RESULT_SUCCESS,200,[],"<bad/>".to_utf8_buffer())
	check(feed.snapshot == original, "Malformed online data preserves last verified snapshot")
	feed._on_request_completed(HTTPRequest.RESULT_SUCCESS,200,[],xml.to_utf8_buffer())
	check(feed.snapshot.effective_at == "2025-01-01", "Validated newer response becomes informational snapshot")
	check(FileAccess.file_exists(feed.cache_path), "Successful refresh creates offline cache")
	var second = feed_script.new()
	second.cache_path = feed.cache_path
	check(second.load_cache().ok and second.snapshot.effective_at == "2025-01-01", "Updated snapshot survives offline reload")
	second.free()
	var latest = feed.snapshot.duplicate(true)
	feed._on_request_completed(HTTPRequest.RESULT_SUCCESS,200,[],FileAccess.get_file_as_bytes("res://data/events/cbr_2025-01-01.xml"))
	check(feed.snapshot == latest, "Older source snapshot never rolls back latest verified data")
	bad = event.duplicate(true)
	bad.published_at = "2025-03-01"
	feed.updates = [bad]
	check(feed.due_updates("2025-02-15","RU").is_empty(), "Future publication is not eligible before news publication")
	print("DATA SYNC TESTS: %d checks, %d failures" % [checks,failures])
	feed.free()
	quit(0 if failures == 0 else 1)
