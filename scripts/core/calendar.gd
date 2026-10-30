extends RefCounted

static func parts(day: int) -> Dictionary:
	# Separate game calendar: Gregorian dates beginning 2025-01-01.
	var unix := 1735689600 + (day - 1) * 86400
	var date := Time.get_datetime_dict_from_unix_time(unix)
	date.week = int((day - 1) / 7) + 1
	date.quarter = int((int(date.month) - 1) / 3) + 1
	return date

static func label(day: int) -> String:
	var date := parts(day)
	return "%02d.%02d.%04d · неделя %d · Q%d" % [date.day, date.month, date.year, date.week, date.quarter]
