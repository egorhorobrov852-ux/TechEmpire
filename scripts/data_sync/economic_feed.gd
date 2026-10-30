extends Node
## Reviewed metadata and informational CBR exchange rates. Never changes game rules.

signal sync_finished(ok: bool, message: String)

const CBR_URL = "https://www.cbr.ru/scripts/XML_daily.asp"
const BUNDLED_RAW = "res://data/events/cbr_2025-01-01.xml"
const BUNDLED_META = "res://data/events/cbr_provenance.json"
const MAX_BODY_BYTES = 2 * 1024 * 1024
const OFFICIAL_HOSTS = ["cbr.ru", "www.cbr.ru", "nalog.gov.ru", "www.nalog.gov.ru", "irs.gov", "www.irs.gov", "federalreserve.gov", "www.federalreserve.gov"]
const PARAMETER_RANGES = {"key_rate":[0.0,1.0],"tax_rate":[0.0,1.0],"inflation":[-0.5,2.0],"usd_rub":[0.01,1000000.0],"eur_rub":[0.01,1000000.0]}

var snapshot: Dictionary = {}
var updates: Array = []
var cache_path: String = "user://economic_snapshot.json"
var request_node: HTTPRequest
var busy: bool = false
var last_message: String = ""

func _ready() -> void:
	request_node = HTTPRequest.new()
	request_node.timeout = 20.0
	request_node.max_redirects = 0
	request_node.body_size_limit = MAX_BODY_BYTES
	add_child(request_node)
	request_node.request_completed.connect(_on_request_completed)

func _valid_date(value: String) -> bool:
	if value.length() != 10 or value.substr(4,1) != "-" or value.substr(7,1) != "-":
		return false
	var parts = value.split("-")
	if parts.size() != 3 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return false
	var year = int(parts[0])
	var month = int(parts[1])
	var day = int(parts[2])
	if year < 1900 or year > 2200 or month < 1 or month > 12:
		return false
	var days = [31,28,31,30,31,30,31,31,30,31,30,31]
	if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0):
		days[1] = 29
	return day >= 1 and day <= days[month-1]

func _official_source(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	var host = url.substr(8).get_slice("/",0).to_lower()
	return host in OFFICIAL_HOSTS

func validate_update(record: Dictionary) -> String:
	for field in ["id","title","body","source","published_at","effective_at","country","region","version","verification_status"]:
		if not record.get(field) is String:
			return "Отсутствует строковое поле: " + field
	if record.id.is_empty() or record.title.is_empty() or record.version.is_empty():
		return "Пустой идентификатор, заголовок или версия."
	if not _official_source(record.source):
		return "Источник не входит в список официальных HTTPS-источников."
	if not _valid_date(record.published_at) or not _valid_date(record.effective_at):
		return "Некорректная дата публикации или вступления в силу."
	if record.country not in ["RU","US"]:
		return "Неизвестный профиль страны."
	if record.verification_status not in ["verified","unverified","rejected"]:
		return "Неизвестный статус проверки."
	if not record.get("parameters") is Dictionary:
		return "Нет параметров обновления."
	for parameter in record.parameters:
		if not parameter in PARAMETER_RANGES:
			return "Неизвестный параметр: " + str(parameter)
		var value = record.parameters[parameter]
		if not (value is float or value is int) or not is_finite(float(value)):
			return "Параметр должен быть конечным числом."
		var limits: Array = PARAMETER_RANGES[parameter]
		if value < limits[0] or value > limits[1]:
			return "Параметр вне допустимого диапазона."
	return ""

func due_updates(real_date: String, country: String) -> Array:
	var due: Array = []
	if not _valid_date(real_date):
		return due
	for record in updates:
		if not record is Dictionary or not validate_update(record).is_empty():
			continue
		if record.verification_status == "verified" and record.country == country and record.published_at <= real_date and record.effective_at <= real_date:
			due.append(record.duplicate(true))
	return due

func _load_updates() -> void:
	updates.clear()
	var file = FileAccess.open("res://data/events/reviewed_updates.json", FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and parsed.get("updates") is Array:
		for record in parsed.updates:
			if record is Dictionary and validate_update(record).is_empty():
				updates.append(record)

func parse_cbr_bytes(body: PackedByteArray) -> Dictionary:
	if body.is_empty() or body.size() > MAX_BODY_BYTES:
		return {"ok":false,"message":"Ответ ЦБ пуст или превышает ограничение размера."}
	# CBR's legacy endpoint uses Windows-1251. Fields used here are ASCII;
	# convert bytes as Latin-1 so Cyrillic display names cannot cause invalid UTF-8.
	var content = body.get_string_from_ascii()
	if content.contains("<!DOCTYPE") or content.contains("<!ENTITY"):
		return {"ok":false,"message":"Недопустимые XML declarations."}
	content = content.replace("windows-1251", "utf-8").replace("Windows-1251", "utf-8")
	var parser = XMLParser.new()
	if parser.open_buffer(content.to_utf8_buffer()) != OK:
		return {"ok":false,"message":"Не удалось прочитать XML ЦБ."}
	var current: Dictionary = {}
	var rates: Dictionary = {}
	var field: String = ""
	var root_date: String = ""
	var root_seen: bool = false
	var in_currency: bool = false
	var root_closed: bool = false
	var steps: int = 0
	while true:
		var error = parser.read()
		if error == ERR_FILE_EOF:
			break
		if error != OK:
			return {"ok":false,"message":"Повреждён XML ЦБ."}
		steps += 1
		if steps > 30000:
			return {"ok":false,"message":"XML ЦБ слишком сложен."}
		var kind = parser.get_node_type()
		if kind == XMLParser.NODE_ELEMENT:
			field = parser.get_node_name()
			if field == "ValCurs":
				if root_seen:
					return {"ok":false,"message":"Повторный корневой элемент."}
				root_seen = true
				root_date = parser.get_named_attribute_value_safe("Date")
			elif field == "Valute":
				if in_currency:
					return {"ok":false,"message":"Вложенная валюта в XML."}
				in_currency = true
				current = {}
		elif kind == XMLParser.NODE_TEXT and in_currency and field in ["CharCode","Nominal","Value"]:
			current[field] = str(current.get(field,"")) + parser.get_node_data().strip_edges()
		elif kind == XMLParser.NODE_ELEMENT_END:
			var ending = parser.get_node_name()
			if ending == "Valute":
				in_currency = false
				var code = str(current.get("CharCode",""))
				if code in ["USD","EUR"]:
					var nominal_string = str(current.get("Nominal",""))
					var value_string = str(current.get("Value","")).replace(",", ".")
					if not nominal_string.is_valid_int() or not value_string.is_valid_float():
						return {"ok":false,"message":"Нечисловой курс или номинал."}
					var nominal = int(nominal_string)
					var value = float(value_string)
					if nominal <= 0 or nominal > 1000000 or not is_finite(value) or value <= 0 or value > 1000000000 or rates.has(code):
						return {"ok":false,"message":"Недопустимый номинал, курс или дубликат валюты."}
					rates[code] = value / nominal
			elif ending == "ValCurs":
				root_closed = true
			field = ""
	var parts = root_date.split(".")
	if parts.size() != 3:
		return {"ok":false,"message":"В ответе ЦБ нет даты курса."}
	var effective = "%s-%s-%s" % [parts[2],parts[1],parts[0]]
	if not root_seen or not root_closed or in_currency or not _valid_date(effective) or not rates.has("USD") or not rates.has("EUR"):
		return {"ok":false,"message":"Неполный ответ ЦБ: требуются дата, USD и EUR."}
	return {"ok":true,"data":{"source":CBR_URL,"source_date":effective,"published_at":null,"effective_at":effective,"country":"RU","region":"","version":"cbr-daily-"+effective,"verification_status":"verified_source","rates":rates,"quote_currency":"RUB","raw_sha256":_sha256_bytes(body),"publication_note":"XML сообщает дату действия курса; отдельная дата публикации не передаётся.","informational_only":true}}

func _valid_snapshot(value: Dictionary) -> bool:
	if value.get("source") != CBR_URL or value.get("verification_status") != "verified_source" or not value.get("informational_only",false):
		return false
	if not value.get("effective_at") is String or not _valid_date(value.effective_at) or not value.get("rates") is Dictionary:
		return false
	for code in ["USD","EUR"]:
		var rate = value.rates.get(code)
		if not (rate is float or rate is int) or not is_finite(float(rate)) or rate <= 0 or rate > 1000000000:
			return false
	return true

func _read_cache(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > MAX_BODY_BYTES:
		file.close()
		return {}
	var record = JSON.parse_string(file.get_as_text())
	file.close()
	if not record is Dictionary or int(record.get("format_version",0)) != 1 or not record.get("payload") is String:
		return {}
	if record.get("sha256", "") != record.payload.sha256_text():
		return {}
	var data = JSON.parse_string(record.payload)
	return data if data is Dictionary and _valid_snapshot(data) else {}

func _save_cache(data: Dictionary) -> bool:
	if not _valid_snapshot(data):
		return false
	var payload = JSON.stringify(data)
	var file = FileAccess.open(cache_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"format_version":1,"payload":payload,"sha256":payload.sha256_text()}))
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK or _read_cache(cache_path + ".tmp").is_empty():
		return false
	if not _read_cache(cache_path).is_empty() and DirAccess.copy_absolute(cache_path, cache_path + ".bak") != OK:
		return false
	return DirAccess.rename_absolute(cache_path + ".tmp", cache_path) == OK

func load_cache() -> Dictionary:
	_load_updates()
	for suffix in ["", ".bak"]:
		var cached = _read_cache(cache_path + suffix)
		if not cached.is_empty():
			snapshot = cached
			last_message = "Сохранённые данные ЦБ" + (" (резервная копия)" if suffix != "" else "")
			return {"ok":true,"cached":true,"message":status_text()}
	var raw = FileAccess.get_file_as_bytes(BUNDLED_RAW)
	var provenance = JSON.parse_string(FileAccess.get_file_as_string(BUNDLED_META))
	if provenance is Dictionary and provenance.get("raw_sha256") == _sha256_bytes(raw):
		var parsed = parse_cbr_bytes(raw)
		if parsed.ok:
			snapshot = parsed.data
			snapshot["retrieved_at_utc"] = provenance.get("retrieved_at_utc", "")
			snapshot["request_date"] = provenance.get("request_date", "")
			last_message = "Архивный комплект данных ЦБ"
			return {"ok":true,"cached":false,"message":status_text()}
	last_message = "Проверенные данные недоступны. Игровая симуляция работает автономно."
	return {"ok":false,"cached":false,"message":last_message}

func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func status_text() -> String:
	if snapshot.is_empty():
		return "Нет проверенного снимка. Используется игровая модель."
	var date_label = "объявлен с %s" if snapshot.effective_at > Time.get_date_string_from_system(true) else "курс на %s"
	return "ЦБ РФ · %s · USD %.4f ₽ / EUR %.4f ₽. Справочно; дата курса не равна дате запуска игры." % [date_label % snapshot.effective_at, snapshot.rates.USD, snapshot.rates.EUR]

func news() -> Array:
	var result: Array = []
	if not snapshot.is_empty():
		result.append({"title":"Проверяемые данные Банка России", "body":status_text()+"\nНалоги, спрос и цены игрового профиля автоматически не изменяются.\n"+str(snapshot.get("publication_note","")),"source":snapshot.source,"published_at":snapshot.get("published_at"),"effective_at":snapshot.effective_at,"country":"RU","region":"","version":snapshot.version,"verification_status":"verified_source"})
	for record in updates:
		result.append(record.duplicate(true))
	return result

func refresh() -> void:
	if busy:
		return
	if request_node == null or not is_inside_tree():
		sync_finished.emit(false, "Сетевой модуль ещё не готов; сохранённые данные доступны.")
		return
	busy = true
	var error = request_node.request(CBR_URL, ["Accept: application/xml", "User-Agent: TechEmpire/0.1"])
	if error != OK:
		busy = false
		sync_finished.emit(false, "Не удалось начать обновление. Используются сохранённые данные.")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		last_message = "ЦБ недоступен (HTTP %d). %s" % [response_code,status_text()]
		sync_finished.emit(false,last_message)
		return
	var parsed = parse_cbr_bytes(body)
	if not parsed.ok:
		sync_finished.emit(false, str(parsed.message)+" Сохранённый снимок не изменён.")
		return
	var data: Dictionary = parsed.data
	if not snapshot.is_empty() and data.effective_at < snapshot.effective_at:
		sync_finished.emit(false,"Источник вернул более старые данные; сохранённый снимок оставлен.")
		return
	data["retrieved_at_utc"] = Time.get_datetime_string_from_system(true)
	data["raw_sha256"] = _sha256_bytes(body)
	if not _save_cache(data):
		sync_finished.emit(false,"Данные получены, но безопасная запись не удалась. Прежний снимок оставлен.")
		return
	snapshot = data
	last_message = status_text()
	sync_finished.emit(true, "Курс обновлён. " + status_text())
