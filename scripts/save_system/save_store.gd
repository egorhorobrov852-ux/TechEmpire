extends RefCounted
## Local, versioned records. Payload checksums do not depend on JSON key order.

const FORMAT_VERSION = 2
const MAX_BYTES = 32 * 1024 * 1024
var directory: String
var game_validator: Callable

func _init(base_directory: String = "user://saves") -> void:
	directory = base_directory

func path_for(slot: String) -> String:
	return directory.path_join(slot + ".json")

func _safe_name(slot: String) -> bool:
	return not slot.is_empty() and slot.length() <= 40 and slot.is_valid_identifier()

func _valid_game(data: Dictionary) -> bool:
	var version = data.get("version")
	var day = data.get("day")
	if not (version is int or version is float) or not (day is int or day is float):
		return false
	var shape_valid = version == 1 and is_finite(float(day)) and day >= 1 and float(day) == floor(float(day)) and data.get("country_id") is String and data.get("companies") is Array
	if not shape_valid:
		return false
	return str(game_validator.call(data)).is_empty() if game_validator.is_valid() else true

func save_game(state: Dictionary, slot: String = "auto") -> Dictionary:
	if not _valid_game(state):
		return {"ok":false,"message":"Некорректное состояние: сохранение не изменено."}
	return write_record(slot, state, true)

func load_game(slot: String = "auto") -> Dictionary:
	var result = read_record(slot, true)
	if result.ok:
		result["state"] = result.data
	return result

func write_record(slot: String, data: Dictionary, require_game: bool = false) -> Dictionary:
	if not _safe_name(slot):
		return {"ok":false,"message":"Недопустимое имя сохранения."}
	var absolute = ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute) != OK:
		return {"ok":false,"message":"Не удалось создать папку сохранений."}
	var payload = JSON.stringify(data)
	if payload.length() > MAX_BYTES:
		return {"ok":false,"message":"Сохранение слишком велико."}
	var envelope = {"format_version":FORMAT_VERSION,"payload":payload,"sha256":payload.sha256_text(),"saved_at_utc":Time.get_datetime_string_from_system(true)}
	var path = path_for(slot)
	var tmp = path + ".tmp"
	var file = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return {"ok":false,"message":"Не удалось записать временный файл."}
	file.store_string(JSON.stringify(envelope))
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK or not _read_one(tmp).ok:
		return {"ok":false,"message":"Проверка записанного файла не прошла."}
	# A corrupt primary must never replace the last known good backup.
	var previous = _read_one(path)
	if previous.ok and (not require_game or _valid_game(previous.data)):
		var backup_tmp = path + ".bak.tmp"
		if DirAccess.copy_absolute(path, backup_tmp) != OK or DirAccess.rename_absolute(backup_tmp, path + ".bak") != OK:
			return {"ok":false,"message":"Не удалось обновить резервную копию."}
	if DirAccess.rename_absolute(tmp, path) != OK:
		return {"ok":false,"message":"Не удалось завершить безопасную запись."}
	return {"ok":true,"message":"Прогресс сохранён."}

func read_record(slot: String, require_game: bool = false) -> Dictionary:
	if not _safe_name(slot):
		return {"ok":false,"recovered":false,"message":"Недопустимое имя сохранения."}
	var path = path_for(slot)
	for suffix in ["", ".bak", ".tmp"]:
		var result = _read_one(path + suffix)
		if result.ok and (not require_game or _valid_game(result.data)):
			result["recovered"] = suffix != ""
			result["message"] = "Восстановлена резервная копия." if suffix != "" else "Сохранение загружено."
			return result
	return {"ok":false,"recovered":false,"message":"Сохранение отсутствует или повреждено. Предыдущий прогресс не перезаписан."}

func _read_one(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok":false}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok":false}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"ok":false}
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary:
		return {"ok":false}
	var envelope: Dictionary = json.data
	var version = envelope.get("format_version")
	if not (version is int or version is float):
		return {"ok":false}
	# Version 1 records are migrated on their next successful write.
	if version == 1 and envelope.get("state") is Dictionary:
		return {"ok":true,"data":envelope.state,"migrated":true}
	if version != FORMAT_VERSION or not envelope.get("payload") is String:
		return {"ok":false}
	var payload: String = envelope.payload
	if payload.sha256_text() != envelope.get("sha256", ""):
		return {"ok":false}
	if json.parse(payload) != OK or not json.data is Dictionary:
		return {"ok":false}
	return {"ok":true,"data":json.data,"saved_at_utc":envelope.get("saved_at_utc", ""),"migrated":false}
