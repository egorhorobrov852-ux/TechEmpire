extends RefCounted

const Calendar = preload("res://scripts/core/calendar.gd")

static func demand_for(type_id: String, day: int, catalog: Dictionary, macro: Dictionary, population: int) -> int:
	var config: Dictionary = catalog[type_id]
	var seasonal := 1.0 + sin(float(day) * TAU / 365.0) * 0.08
	var weekday := int(Calendar.parts(day).weekday)
	var weekly := 0.76 if type_id == "studio" and weekday in [0,6] else 1.0
	return maxi(0, int(round(float(config.base_demand) * float(population) / 42000.0 * float(macro.demand) * seasonal * weekly)))

static func allocate(companies: Array, type_id: String, total: int, config: Dictionary, plots: Array, day: int) -> Dictionary:
	# A finite pool is assigned customer by customer. An outside option means
	# monopolists cannot force everyone to pay arbitrarily high prices.
	var rows: Array = []
	var sum_weight := 0.0
	for company in companies:
		if company.type != type_id or company.status != "open": continue
		var plot: Dictionary = plots[int(company.plot_id)]
		var ratio := float(company.price) / maxf(1.0, float(config.base_price))
		var affordability := exp(-float(config.elasticity) * maxf(0.0, ratio - 1.0))
		var weight := float(plot.traffic) * (0.55 + float(company.reputation)) * float(company.quality) * pow(1.0 / maxf(0.2, ratio), 0.5) * affordability
		weight *= 1.0 + minf(0.7, sqrt(float(company.advertising) / maxf(1.0, float(config.wage))) * 0.15)
		var capacity := 0.0
		for staff in company.staff:
			if int(staff.training_until) > day: continue
			capacity += float(config.capacity) * float(staff.skill) * (0.55 + float(staff.satisfaction) * 0.45)
		var max_sales := int(floor(capacity))
		if not config.service: max_sales = mini(max_sales, int(company.stock))
		if max_sales <= 0: weight = 0.0
		rows.append({"id": company.id, "weight": weight, "capacity": max_sales, "sold": 0, "expected": 0.0})
		sum_weight += weight
	var outside_weight := 0.32
	var accepted_total := 0
	for row in rows:
		row.expected = float(total) * float(row.weight) / (sum_weight + outside_weight)
		row.sold = mini(int(row.capacity), int(floor(float(row.expected))))
		accepted_total += int(row.sold)
	# Do not redistribute all shortages: customers may postpone a purchase.
	var remaining := maxi(0, mini(total - accepted_total, int(round(float(total) * sum_weight / (sum_weight + outside_weight))) - accepted_total))
	for row in rows:
		if remaining <= 0: break
		if int(row.sold) < int(row.capacity) and float(row.expected) - floor(float(row.expected)) >= 0.5:
			row.sold += 1
			remaining -= 1
	var result := {}
	for row in rows: result[row.id] = {"units": int(row.sold), "demand": total, "market_share": float(row.sold) / maxf(1.0, float(total))}
	return result
