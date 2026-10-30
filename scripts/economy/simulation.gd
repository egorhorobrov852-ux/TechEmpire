extends RefCounted
## Native offline economic simulation. All money is integer minor units.
## Every financial mutation goes through the double-entry journal.

const Ledger = preload("res://scripts/economy/ledger.gd")
const Demand = preload("res://scripts/market/demand.gd")
const Calendar = preload("res://scripts/core/calendar.gd")

var state: Dictionary = {}
var catalog: Dictionary = {}
var country: Dictionary = {}
var city: Dictionary = {}

func _json(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func load_profile(country_id: String) -> void:
	country = _json("res://data/countries/%s.json" % country_id)
	if country.is_empty(): country = _json("res://data/countries/RU.json")
	city = _json("res://data/cities/%s.json" % country.city_id)
	catalog.clear()
	for id in ["shop", "cafe", "studio"]:
		var entry := _json("res://data/businesses/%s.json" % id)
		for key in ["setup_cost", "base_price", "unit_cost", "wage"]: entry[key] = _scale(int(entry[key]))
		catalog[id] = entry
	for plot in city.plots:
		plot.purchase_price = _scale(int(plot.purchase_price))
		plot.rent = _scale(int(plot.rent))

func new_game(country_id: String = "RU", seed_value: int = 42) -> void:
	load_profile(country_id)
	state = {"version": 1, "day": 1, "country_id": country.id, "city_id": city.id, "rng": maxi(1, absi(seed_value) % 2147483647), "next_id": 1, "entities": {}, "companies": [], "loans": [], "properties": [], "journal": [], "bills": [], "receipts": [], "history": [], "news": [], "achievements": [], "bankrupt": false, "labor_available": 285, "credit_score": 650, "macro": {"demand": 1.0, "supplier_price": 1.0, "property_value": 1.0, "annual_rate_delta": 0.0}, "last_report": {}, "tutorial_step": 0}
	_entity("player", int(country.start_capital))
	var ai_types := ["shop", "cafe", "studio"]
	var ai_plots := [0, 4, 15]
	for i in range(3):
		var owner := "ai_%d" % i
		_entity(owner, _scale(48000000))
		var company := _create_company(ai_types[i], ai_plots[i], "ai", owner)
		company.name = ["Север Маркет", "Кофе & Город", "Vector Studio"][i]
		company.price = int(round(float(catalog[company.type].base_price) * (1.0 + i * 0.03)))
		_hire(company)
		if company.type != "studio":
			var quantity := 180 if company.type == "shop" else 90
			var cost := quantity * int(catalog[company.type].unit_cost)
			_post(owner, {"inventory": cost, "cash": -cost}, "opening_stock", "Начальные запасы конкурента", company.id)
			company.lots.append({"quantity": quantity, "cost": cost, "expires_day": 1 + int(catalog[company.type].shelf_life)})
			company.stock = quantity
	_news("Добро пожаловать в " + city.name, "Выберите свободный участок, откройте бизнес, наймите сотрудника и оформите поставку. Доход не гарантирован.")
	_news("Экономический профиль", country.profile_label + ". Справочные источники доступны в разделе новостей; реальные текущие ставки не загружены.")

func _scale(amount: int) -> int:
	return int(round(float(amount) * float(country.get("amount_scale", 1.0))))

func _entity(id: String, capital: int) -> void:
	state.entities[id] = {"accounts": Ledger.empty_accounts(), "tax_loss": 0, "taxable_processed": 0, "zero_cash_days": 0, "tax_overdue_days": 0}
	_post(id, {"cash": capital, "equity": -capital}, "capital", "Первоначальный капитал")

func _id(prefix: String) -> String:
	var id := "%s_%d" % [prefix, int(state.next_id)]
	state.next_id = int(state.next_id) + 1
	return id

func _rand() -> float:
	state.rng = int((int(state.rng) * 48271) % 2147483647)
	return float(state.rng) / 2147483647.0

func _post(entity: String, postings: Dictionary, category: String, memo: String, company_id: String = "") -> void:
	Ledger.post(state, entity, postings, category, memo, company_id)

func player_cash() -> int:
	return _cash("player")

func _cash(entity: String) -> int:
	return int(state.entities[entity].accounts.cash)

func _ok(message: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "message": message}
	result.merge(extra)
	return result

func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}

func get_company(id: String) -> Dictionary:
	for company in state.companies:
		if company.id == id: return company
	return {}

func _player_company(id: String) -> Dictionary:
	var company := get_company(id)
	return company if not company.is_empty() and company.owner == "player" and company.status == "open" else {}

func _at_plot(plot_id: int) -> Dictionary:
	for company in state.companies:
		if int(company.plot_id) == plot_id and company.status == "open": return company
	return {}

func _property(plot_id: int) -> Dictionary:
	for property in state.properties:
		if int(property.plot_id) == plot_id: return property
	return {}

func _create_company(type_id: String, plot_id: int, owner: String, entity: String) -> Dictionary:
	var config: Dictionary = catalog[type_id]
	var company := {"id": _id("business"), "owner": owner, "entity": entity, "type": type_id, "plot_id": plot_id, "name": config.name, "status": "open", "price": int(config.base_price), "stock": 0, "lots": [], "orders": [], "staff": [], "reputation": 0.55, "quality": 1.0, "advertising": 0, "equipment_value": int(config.setup_cost), "opened_day": int(state.day), "loss_days": 0, "total_units": 0, "last_report": {}, "auto_restock": false}
	state.companies.append(company)
	_post(entity, {"equipment": int(config.setup_cost), "cash": -int(config.setup_cost)}, "equipment", "Оборудование: " + config.name, company.id)
	var registration := _scale(int(country.business_rules.registration_fee))
	_post(entity, {"registration": registration, "cash": -registration}, "permit", "Регистрация и игровое разрешение", company.id)
	return company

func open_business(type_id: String, plot_id: int) -> Dictionary:
	if state.bankrupt: return _error("Компания признана банкротом. Начните новую игру.")
	if not catalog.has(type_id): return _error("Неизвестная отрасль.")
	if plot_id < 0 or plot_id >= city.plots.size(): return _error("Участок за границей города.")
	if not _at_plot(plot_id).is_empty(): return _error("Участок уже занят действующей компанией.")
	var cost := int(catalog[type_id].setup_cost) + _scale(int(country.business_rules.registration_fee))
	if player_cash() < cost: return _error("Недостаточно средств на оборудование и разрешение.")
	var company := _create_company(type_id, plot_id, "player", "player")
	_achievement("first_business", "Первый бизнес")
	return _ok("Бизнес открыт. Наймите персонал и подготовьте товар к продаже.", {"company_id": company.id})

func set_price(id: String, price_minor: int) -> Dictionary:
	var company := _player_company(id)
	if company.is_empty(): return _error("Действующий бизнес не найден.")
	if price_minor <= 0 or price_minor > 10000000000: return _error("Укажите положительную цену в пределах игрового диапазона.")
	company.price = price_minor
	return _ok("Цена изменена. Реакция покупателей станет видна после завершения дня.")

func supplier_offers() -> Array:
	return [{"id": "standard", "name": "Региональный поставщик", "lead_days": 2, "price_factor": 1.0, "transport": _scale(35000), "credit_days": 0}, {"id": "express", "name": "Экспресс-логистика", "lead_days": 1, "price_factor": 1.12, "transport": _scale(70000), "credit_days": 0}, {"id": "credit", "name": "Оплата через 7 дней", "lead_days": 3, "price_factor": 1.06, "transport": _scale(45000), "credit_days": 7}]

func stock_quote(id: String, quantity: int, supplier: String = "standard") -> Dictionary:
	var company := get_company(id)
	if company.is_empty(): return {}
	for offer in supplier_offers():
		if offer.id == supplier:
			var unit_cost := int(round(float(catalog[company.type].unit_cost) * float(offer.price_factor) * float(state.macro.supplier_price)))
			return {"total": quantity * unit_cost + int(offer.transport), "unit_cost": unit_cost, "transport": int(offer.transport), "arrives_day": int(state.day) + int(offer.lead_days), "credit_days": int(offer.credit_days)}
	return {}

func order_stock(id: String, quantity: int, supplier: String = "standard") -> Dictionary:
	var company := _player_company(id)
	if company.is_empty(): return _error("Действующий бизнес не найден.")
	return _order(company, quantity, supplier)

func _order(company: Dictionary, quantity: int, supplier: String = "standard") -> Dictionary:
	var config: Dictionary = catalog[company.type]
	if config.service: return _error("IT-услуги не требуют товарного склада.")
	if quantity <= 0: return _error("Количество должно быть положительным.")
	var reserved := int(company.stock)
	for order in company.orders: reserved += int(order.quantity)
	if reserved + quantity > int(config.stock_capacity): return _error("Поставка превысит вместимость склада, включая заказы в пути.")
	var quote := stock_quote(company.id, quantity, supplier)
	if quote.is_empty(): return _error("Поставщик не найден.")
	var entity: String = company.entity
	if int(quote.credit_days) == 0 and _cash(entity) < int(quote.total): return _error("Недостаточно денег для оплаты поставки.")
	if int(quote.credit_days) > 0 and -int(state.entities[entity].accounts.payables) + int(quote.total) > _scale(5000000): return _error("Заказ превысит лимит торгового кредита, включая новую поставку.")
	var order := {"id": _id("order"), "quantity": quantity, "cost": int(quote.total), "arrives_day": int(quote.arrives_day), "supplier": supplier}
	company.orders.append(order)
	if int(quote.credit_days) > 0:
		_post(entity, {"in_transit": int(quote.total), "payables": -int(quote.total)}, "supplier_credit", "Закупка с отсрочкой оплаты", company.id)
		state.bills.append({"id": _id("bill"), "entity": entity, "company_id": company.id, "category": "supplier", "amount": int(quote.total), "due_day": int(state.day) + int(quote.credit_days)})
	else:
		_post(entity, {"in_transit": int(quote.total), "cash": -int(quote.total)}, "purchase", "Оплата товара и транспортных расходов", company.id)
	return _ok("Поставка оформлена. День прибытия: %d." % order.arrives_day)

func hire(id: String) -> Dictionary:
	var company := _player_company(id)
	if company.is_empty(): return _error("Действующий бизнес не найден.")
	if state.bankrupt: return _error("Найм недоступен при банкротстве.")
	return _hire(company)

func _hire(company: Dictionary) -> Dictionary:
	if company.staff.size() >= 6: return _error("Для помещения доступно не более 6 рабочих мест.")
	if int(state.labor_available) <= 0: return _error("На рынке труда нет свободных кандидатов.")
	var fee := _scale(20000)
	if _cash(company.entity) < fee: return _error("Недостаточно денег для найма.")
	var skill := 0.9 + _rand() * 0.3
	var wage := int(round(float(catalog[company.type].wage) * (0.95 + (skill - 0.9) * 0.4)))
	var names := ["Алексей", "Мария", "Ирина", "Даниил", "София", "Никита", "Анна", "Артём", "Вера", "Михаил"]
	var staff := {"id": _id("staff"), "name": names[int(_rand() * names.size())], "skill": skill, "wage": wage, "satisfaction": 0.85, "training_until": 0, "hired_day": int(state.day)}
	company.staff.append(staff)
	state.labor_available = int(state.labor_available) - 1
	_post(company.entity, {"wages": fee, "cash": -fee}, "hiring", "Подбор сотрудника " + staff.name, company.id)
	return _ok("Сотрудник принят. Зарплата начисляется каждый игровой день.")

func fire(id: String, staff_id: String) -> Dictionary:
	var company := _player_company(id)
	if company.is_empty(): return _error("Действующий бизнес не найден.")
	for worker in company.staff:
		if worker.id == staff_id:
			var severance := int(worker.wage) * 3
			if player_cash() < severance: return _error("Нужны средства на выходное пособие: три дневные зарплаты.")
			_post("player", {"wages": severance, "cash": -severance}, "severance", "Выходное пособие " + worker.name, id)
			company.staff.erase(worker)
			state.labor_available = int(state.labor_available) + 1
			return _ok("Сотрудник уволен, пособие выплачено.")
	return _error("Сотрудник не найден.")

func train(id: String, staff_id: String) -> Dictionary:
	var company := _player_company(id)
	if company.is_empty(): return _error("Действующий бизнес не найден.")
	for worker in company.staff:
		if worker.id == staff_id:
			if int(worker.training_until) > int(state.day): return _error("Обучение уже идёт.")
			if float(worker.skill) >= 1.8: return _error("Сотрудник достиг максимальной квалификации.")
			var cost := int(catalog[company.type].wage) * 2
			if player_cash() < cost: return _error("Недостаточно средств на обучение.")
			_post("player", {"training": cost, "cash": -cost}, "training", "Обучение: " + worker.name, id)
			worker.skill = minf(1.8, float(worker.skill) + 0.12)
			worker.training_until = int(state.day) + 2
			worker.satisfaction = minf(1.0, float(worker.satisfaction) + 0.05)
			return _ok("Обучение оплачено. Следующий день сотрудник не обслуживает клиентов.")
	return _error("Сотрудник не найден.")

func set_salary(id: String, staff_id: String, wage: int) -> Dictionary:
	var company := _player_company(id)
	if company.is_empty(): return _error("Действующий бизнес не найден.")
	if wage < int(catalog[company.type].wage) / 2 or wage > int(catalog[company.type].wage) * 5: return _error("Зарплата вне доступного диапазона.")
	for worker in company.staff:
		if worker.id == staff_id:
			worker.wage = wage
			return _ok("Условия оплаты изменены.")
	return _error("Сотрудник не найден.")

func set_advertising(id: String, daily_budget: int) -> Dictionary:
	var company := _player_company(id)
	if company.is_empty(): return _error("Действующий бизнес не найден.")
	if daily_budget < 0 or daily_budget > int(catalog[company.type].wage) * 3: return _error("Недоступный рекламный бюджет.")
	company.advertising = daily_budget
	return _ok("Рекламный бюджет установлен; он списывается ежедневно.")

func loan_offer(amount_minor: int, term_days: int = 90) -> Dictionary:
	var rate := float(country.annual_loan_rate) + float(state.macro.annual_rate_delta) + maxf(0.0, (650.0 - float(state.credit_score)) / 5000.0)
	return {"amount": amount_minor, "term_days": term_days, "annual_rate": rate, "daily_principal": int(ceil(float(amount_minor) / maxf(1.0, float(term_days)))), "first_interest": int(round(float(amount_minor) * rate / 365.0)), "estimated_total_interest": int(round(float(amount_minor) * rate * float(term_days + 1) / 730.0))}

func take_loan(amount_minor: int, term_days: int = 90) -> Dictionary:
	if state.bankrupt: return _error("Банк отказал компании-банкроту.")
	return _take_loan("player", amount_minor, term_days)

func _take_loan(entity: String, amount_minor: int, term_days: int) -> Dictionary:
	if term_days not in [30, 90, 180]: return _error("Срок должен составлять 30, 90 или 180 дней.")
	if amount_minor < _scale(1000000) or amount_minor > _scale(50000000): return _error("Сумма вне диапазона банковского продукта.")
	var active := 0
	for loan in state.loans:
		if loan.entity == entity and int(loan.remaining) > 0:
			active += 1
			if int(loan.arrears_days) > 0: return _error("Сначала погасите просроченные платежи.")
	if active >= 2: return _error("Достигнут лимит действующих кредитов.")
	var balance := Ledger.report(state, entity, int(state.day))
	if int(balance.liabilities) + amount_minor > maxi(_scale(10000000), int(float(maxi(0, int(balance.equity))) * 1.2)): return _error("Банк отклонил заявку: чрезмерная долговая нагрузка.")
	if entity == "player" and int(state.credit_score) < 400: return _error("Кредитная история недостаточна.")
	var offer := loan_offer(amount_minor, term_days)
	var loan := {"id": _id("loan"), "entity": entity, "principal": amount_minor, "remaining": amount_minor, "rate": float(offer.annual_rate), "term_days": term_days, "installment": int(offer.daily_principal), "principal_due": 0, "interest_due": 0, "next_due": int(state.day) + 1, "arrears_days": 0, "restructured": false, "issued_day": int(state.day)}
	state.loans.append(loan)
	_post(entity, {"cash": amount_minor, "loans": -amount_minor}, "loan_draw", "Кредит: %d дней, %.1f%% годовых" % [term_days, float(loan.rate) * 100.0])
	return _ok("Кредит получен. Основной долг и проценты выплачиваются ежедневно.", {"loan_id": loan.id})

func restructure_loan(loan_id: String) -> Dictionary:
	for loan in state.loans:
		if loan.id != loan_id or loan.entity != "player": continue
		if loan.restructured or int(loan.remaining) <= 0: return _error("Повторная реструктуризация недоступна.")
		var fee := int(round(float(loan.remaining) * 0.02))
		if player_cash() < fee: return _error("Нужны средства на комиссию 2% остатка долга.")
		_post("player", {"interest": fee, "cash": -fee}, "restructure_fee", "Комиссия реструктуризации")
		loan.installment = maxi(1, int(ceil(float(loan.remaining) / 180.0)))
		loan.term_days = 180
		loan.principal_due = 0
		loan.rate = float(loan.rate) + 0.03
		loan.restructured = true
		loan.arrears_days = 0
		state.credit_score = maxi(300, int(state.credit_score) - 35)
		return _ok("Платёж уменьшен, срок продлён, ставка увеличена на 3 п.п.")
	return _error("Кредит не найден.")

func buy_property(plot_id: int) -> Dictionary:
	if state.bankrupt: return _error("При банкротстве покупка недоступна.")
	if plot_id < 0 or plot_id >= city.plots.size(): return _error("Участок не найден.")
	if not _property(plot_id).is_empty(): return _error("Недвижимость уже принадлежит игроку.")
	var amount := int(round(float(city.plots[plot_id].purchase_price) * float(state.macro.property_value)))
	if player_cash() < amount: return _error("Недостаточно средств на покупку недвижимости.")
	_post("player", {"property": amount, "cash": -amount}, "property_buy", "Покупка помещения №%d" % (plot_id + 1))
	state.properties.append({"plot_id": plot_id, "owner": "player", "book_value": amount, "condition": 1.0, "listed": false, "tenant_until": 0})
	return _ok("Помещение приобретено. Для собственного бизнеса аренды нет; обслуживание остаётся.")

func property_value(plot_id: int) -> int:
	if plot_id < 0 or plot_id >= city.plots.size(): return 0
	var condition := 1.0
	var owned := _property(plot_id)
	if not owned.is_empty(): condition = float(owned.condition)
	return int(round(float(city.plots[plot_id].purchase_price) * float(state.macro.property_value) * (0.6 + condition * 0.4)))

func sell_property(plot_id: int) -> Dictionary:
	var owned := _property(plot_id)
	if owned.is_empty(): return _error("Можно продать только собственное помещение.")
	var proceeds := int(round(float(property_value(plot_id)) * 0.96))
	var book := int(owned.book_value)
	var postings := {"cash": proceeds, "property": -book}
	if proceeds >= book: postings.other_income = -(proceeds - book)
	else: postings.disposal_loss = book - proceeds
	_post("player", postings, "property_sell", "Продажа помещения, комиссия 4%")
	state.properties.erase(owned)
	return _ok("Помещение продано. Действующий бизнес продолжит арендовать его.")

func repair_property(plot_id: int) -> Dictionary:
	var owned := _property(plot_id)
	if owned.is_empty(): return _error("Собственность не найдена.")
	if float(owned.condition) >= 0.99: return _error("Ремонт пока не требуется.")
	var cost := int(round(float(owned.book_value) * 0.025))
	if player_cash() < cost: return _error("Недостаточно средств на ремонт.")
	_post("player", {"maintenance": cost, "cash": -cost}, "repair", "Ремонт помещения №%d" % (plot_id + 1))
	owned.condition = minf(1.0, float(owned.condition) + 0.3)
	return _ok("Ремонт завершён; состояние улучшено.")

func set_property_listing(plot_id: int, listed: bool) -> Dictionary:
	var owned := _property(plot_id)
	if owned.is_empty(): return _error("Собственность не найдена.")
	if not _at_plot(plot_id).is_empty(): return _error("Помещение уже занято бизнесом.")
	owned.listed = listed
	if not listed: owned.tenant_until = 0
	return _ok("Объявление об аренде опубликовано." if listed else "Объявление снято.")

func close_business(id: String) -> Dictionary:
	var company := _player_company(id)
	if company.is_empty(): return _error("Действующий бизнес не найден.")
	_close(company)
	return _ok("Бизнес закрыт. Оборудование продано с дисконтом, остатки списаны. Обязательства сохраняются.")

func _close(company: Dictionary) -> void:
	var entity: String = company.entity
	var proceeds := int(round(float(company.equipment_value) * 0.4))
	_post(entity, {"cash": proceeds, "equipment": -int(company.equipment_value), "disposal_loss": int(company.equipment_value) - proceeds}, "closure", "Реализация оборудования при закрытии", company.id)
	company.equipment_value = 0
	var cost := _consume(company, int(company.stock))
	if cost > 0: _post(entity, {"cogs": cost, "inventory": -cost}, "writeoff", "Списание остатков при закрытии", company.id)
	# Pending paid deliveries remain owned and are liquidated below cost at arrival.
	for worker in company.staff:
		_expense(entity, int(worker.wage) * 3, "wages", "Выходное пособие при закрытии", company.id)
		state.labor_available = int(state.labor_available) + 1
	company.staff.clear()
	company.status = "closed"
	if company.owner == "player": _news("Предприятие закрыто", company.name + ": расходы на персонал и аренду прекращены; долги и поставки сохраняются.")

func _expense(entity: String, amount: int, category: String, memo: String, company_id: String = "") -> int:
	if amount <= 0: return 0
	var paid := mini(amount, _cash(entity))
	var unpaid := amount - paid
	var postings := {category: amount}
	if paid > 0: postings.cash = -paid
	if unpaid > 0: postings.payables = -unpaid
	_post(entity, postings, category, memo, company_id)
	if unpaid > 0: state.bills.append({"id": _id("bill"), "entity": entity, "company_id": company_id, "category": category, "amount": unpaid, "due_day": int(state.day)})
	return unpaid

func _consume(company: Dictionary, quantity: int) -> int:
	var remaining := mini(quantity, int(company.stock))
	var cost := 0
	for lot in company.lots.duplicate():
		if remaining <= 0: break
		var taken := mini(remaining, int(lot.quantity))
		var taken_cost := int(lot.cost) if taken == int(lot.quantity) else int(round(float(lot.cost) * float(taken) / float(lot.quantity)))
		lot.quantity = int(lot.quantity) - taken
		lot.cost = int(lot.cost) - taken_cost
		company.stock = int(company.stock) - taken
		remaining -= taken
		cost += taken_cost
		if int(lot.quantity) == 0: company.lots.erase(lot)
	return cost

func _deliveries() -> void:
	for company in state.companies:
		for order in company.orders.duplicate():
			if int(order.arrives_day) > int(state.day): continue
			if company.status == "closed":
				var proceeds := int(order.cost) / 2
				_post(company.entity, {"cash": proceeds, "in_transit": -int(order.cost), "disposal_loss": int(order.cost) - proceeds}, "delivery_liquidation", "Ликвидация поставки закрытого бизнеса", company.id)
			else:
				_post(company.entity, {"inventory": int(order.cost), "in_transit": -int(order.cost)}, "delivery", "Товар прибыл; транспорт включён в стоимость", company.id)
				company.lots.append({"quantity": int(order.quantity), "cost": int(order.cost), "expires_day": int(state.day) + int(catalog[company.type].shelf_life)})
				company.stock = int(company.stock) + int(order.quantity)
			company.orders.erase(order)
		for lot in company.lots.duplicate():
			if int(lot.expires_day) <= int(state.day):
				var cost := int(lot.cost)
				_post(company.entity, {"cogs": cost, "inventory": -cost}, "spoilage", "Списание просроченного товара", company.id)
				company.stock = int(company.stock) - int(lot.quantity)
				company.lots.erase(lot)
				if company.owner == "player": _news("Списание на складе", company.name + ": товар испортился. Сократите размер следующей закупки.")

func _collections() -> void:
	for receipt in state.receipts.duplicate():
		# A tenant's arrears are collected only when the actual debtor pays.
		if receipt.has("source_bill_id"): continue
		if int(receipt.due_day) > int(state.day): continue
		_post(receipt.entity, {"cash": int(receipt.amount), "receivables": -int(receipt.amount)}, "collection", "Поступила оплата ранее выполненного проекта", receipt.company_id)
		state.receipts.erase(receipt)

func _sell(company: Dictionary, allocation: Dictionary) -> void:
	var units := int(allocation.units)
	var config: Dictionary = catalog[company.type]
	var amount := units * int(company.price)
	if units > 0:
		var account := "receivables" if int(config.credit_days) > 0 else "cash"
		_post(company.entity, {account: amount, "revenue": -amount}, "sale", "%d %s по %d" % [units, config.unit_label, int(company.price)], company.id)
		if int(config.credit_days) > 0: state.receipts.append({"entity": company.entity, "company_id": company.id, "amount": amount, "due_day": int(state.day) + int(config.credit_days)})
		if not config.service:
			var cost := _consume(company, units)
			_post(company.entity, {"cogs": cost, "inventory": -cost}, "cogs", "Себестоимость проданных товаров", company.id)
	company.total_units = int(company.total_units) + units
	var customer_effect := 0.004 if units > 0 else -0.008
	company.reputation = clampf(float(company.reputation) + customer_effect, 0.1, 1.0)
	company.last_report = allocation.duplicate(true)

func _operating_costs(company: Dictionary) -> void:
	var entity: String = company.entity
	var owned := _property(int(company.plot_id))
	if owned.is_empty() or entity != "player":
		var rent := int(round(float(city.plots[int(company.plot_id)].rent) * (1.0 + float(country.inflation) * float(state.day) / 365.0)))
		var unpaid := _expense(entity, rent, "rent", "Аренда помещения", company.id)
		if not owned.is_empty():
			var paid := rent - unpaid
			var postings := {"other_income": -rent}
			if paid > 0: postings.cash = paid
			if unpaid > 0:
				postings.receivables = unpaid
				var source_bill: Dictionary = state.bills[-1]
				source_bill.recipient = "player"
				state.receipts.append({"entity": "player", "company_id": company.id, "amount": unpaid, "due_day": int(state.day), "source_bill_id": source_bill.id})
			_post("player", postings, "rent_income", "Аренда от конкурента, включая дебиторскую задолженность")
	var expected_wage := float(catalog[company.type].wage) * (1.0 + float(country.inflation) * float(state.day) / 365.0)
	var mean_skill := 0.0
	for worker in company.staff.duplicate():
		var unpaid := _expense(entity, int(worker.wage), "wages", "Зарплата " + worker.name, company.id)
		var satisfaction_change := 0.001 if float(worker.wage) >= expected_wage * 0.95 else -0.012
		if unpaid > 0: satisfaction_change -= 0.12
		worker.satisfaction = clampf(float(worker.satisfaction) + satisfaction_change, 0.0, 1.0)
		mean_skill += float(worker.skill)
		if float(worker.satisfaction) < 0.2:
			company.staff.erase(worker)
			state.labor_available = int(state.labor_available) + 1
			if company.owner == "player": _news("Сотрудник ушёл", worker.name + " покинул " + company.name + " из-за неудовлетворённости условиями.")
	company.quality = clampf(0.7 + (mean_skill / maxf(1.0, float(company.staff.size()))) * 0.3, 0.7, 1.3)
	if int(company.advertising) > 0: _expense(entity, int(company.advertising), "marketing", "Рекламная кампания", company.id)
	var depreciation := mini(int(company.equipment_value), maxi(1, int(catalog[company.type].setup_cost) / int(catalog[company.type].equipment_life)))
	if depreciation > 0:
		_post(entity, {"depreciation": depreciation, "equipment": -depreciation}, "depreciation", "Амортизация оборудования, без списания денег", company.id)
		company.equipment_value = int(company.equipment_value) - depreciation

func _property_day() -> void:
	for owned in state.properties:
		owned.condition = maxf(0.15, float(owned.condition) - 0.001)
		var cost := maxi(1, int(round(float(owned.book_value) * 0.00012)))
		_expense("player", cost, "maintenance", "Обслуживание собственности №%d" % (int(owned.plot_id) + 1))
		if not owned.listed or not _at_plot(int(owned.plot_id)).is_empty(): continue
		if int(owned.tenant_until) <= int(state.day) and int(state.day) % 7 == 0:
			if float(owned.condition) > 0.5 and _rand() < 0.5 * float(state.macro.demand): owned.tenant_until = int(state.day) + 30
		if int(owned.tenant_until) > int(state.day):
			var rent := int(round(float(city.plots[int(owned.plot_id)].rent) * float(owned.condition)))
			_post("player", {"cash": rent, "other_income": -rent}, "rent_income", "Доход от внешнего арендатора")

func _loan_day() -> void:
	for loan in state.loans:
		if int(loan.remaining) <= 0 and int(loan.interest_due) <= 0: continue
		if int(loan.next_due) > int(state.day): continue
		var entity: String = loan.entity
		var interest := int(round(float(loan.remaining) * float(loan.rate) / 365.0))
		if interest > 0:
			_post(entity, {"interest": interest, "payables": -interest}, "interest_accrual", "Проценты по кредиту " + loan.id)
			loan.interest_due = int(loan.interest_due) + interest
		loan.principal_due = mini(int(loan.remaining), int(loan.principal_due) + int(loan.installment))
		var paid_interest := mini(_cash(entity), int(loan.interest_due))
		if paid_interest > 0:
			_post(entity, {"payables": paid_interest, "cash": -paid_interest}, "interest_payment", "Оплата процентов " + loan.id)
			loan.interest_due = int(loan.interest_due) - paid_interest
		var principal := mini(_cash(entity), int(loan.principal_due))
		if principal > 0:
			_post(entity, {"loans": principal, "cash": -principal}, "principal_payment", "Погашение основного долга " + loan.id)
			loan.remaining = int(loan.remaining) - principal
			loan.principal_due = int(loan.principal_due) - principal
		loan.next_due = int(state.day) + 1
		if int(loan.principal_due) > 0 or int(loan.interest_due) > 0:
			loan.arrears_days = int(loan.arrears_days) + 1
			var penalty := maxi(1, int(round(float(loan.principal_due) * 0.001)))
			_expense(entity, penalty, "penalties", "Штраф за просрочку кредита " + loan.id)
			if entity == "player": state.credit_score = maxi(200, int(state.credit_score) - 8)
		else:
			loan.arrears_days = 0
			if entity == "player": state.credit_score = mini(850, int(state.credit_score) + 1)

func _taxes() -> void:
	for entity_id in state.entities:
		var entity: Dictionary = state.entities[entity_id]
		# Include actions performed between day closures. A snapshot of cumulative
		# pretax earnings ensures registration, training and disposal are each
		# deducted once, even when they were posted after the previous tax run.
		var accounts: Dictionary = entity.accounts
		var cumulative := -int(accounts.revenue) - int(accounts.other_income)
		for key in Ledger.EXPENSES:
			if key != "tax": cumulative -= int(accounts[key])
		var pretax := cumulative - int(entity.taxable_processed)
		entity.taxable_processed = cumulative
		if pretax < 0: entity.tax_loss = int(entity.tax_loss) - pretax
		else:
			var loss_used := mini(pretax, int(entity.tax_loss))
			entity.tax_loss = int(entity.tax_loss) - loss_used
			var tax := int(round(float(pretax - loss_used) * float(country.profit_tax)))
			if tax > 0: _post(entity_id, {"tax": tax, "tax_payable": -tax}, "tax_accrual", "Игровой налог на прибыль с учётом переноса убытка")
		if int(state.day) % 30 == 0 or int(entity.tax_overdue_days) > 0:
			var due := -int(entity.accounts.tax_payable)
			var paid := mini(due, _cash(entity_id))
			if paid > 0: _post(entity_id, {"tax_payable": paid, "cash": -paid}, "tax_payment", "Месячная уплата налога")
			entity.tax_overdue_days = int(entity.tax_overdue_days) + 1 if due > paid else 0
			if due > paid: _expense(entity_id, maxi(1, int(round(float(due - paid) * 0.001))), "penalties", "Пени за просрочку налога")

func _pay_bills() -> void:
	for bill in state.bills.duplicate():
		if int(bill.due_day) > int(state.day): continue
		var paid := mini(_cash(bill.entity), int(bill.amount))
		if paid > 0:
			_post(bill.entity, {"payables": paid, "cash": -paid}, "bill_payment", "Погашение обязательства: " + bill.category, bill.company_id)
			if bill.has("recipient"):
				_post(bill.recipient, {"cash": paid, "receivables": -paid}, "rent_collection", "Арендатор погасил задолженность", bill.company_id)
				for receipt in state.receipts.duplicate():
					if receipt.get("source_bill_id", "") != bill.id: continue
					receipt.amount = int(receipt.amount) - paid
					if int(receipt.amount) <= 0: state.receipts.erase(receipt)
			bill.amount = int(bill.amount) - paid
		if int(bill.amount) <= 0: state.bills.erase(bill)

func _ai_actions() -> void:
	for company in state.companies.duplicate():
		if company.owner != "ai" or company.status != "open": continue
		var config: Dictionary = catalog[company.type]
		var entity: String = company.entity
		if company.staff.is_empty() and _cash(entity) > int(config.wage) * 7: _hire(company)
		if not config.service:
			var pipeline := int(company.stock)
			for order in company.orders: pipeline += int(order.quantity)
			if pipeline < int(config.capacity) * 2:
				var qty := mini(int(config.stock_capacity) - pipeline, int(config.capacity) * 3)
				_order(company, qty, "standard")
		if int(state.day) % 7 == 0 and not company.last_report.is_empty():
			var previous_units := int(company.last_report.get("units", 0))
			var target := int(round(float(config.capacity) * maxf(1.0, float(company.staff.size())) * 0.65))
			var adjustment := 1.025 if previous_units >= target else 0.97
			var min_price := int(config.unit_cost) + int(round(float(config.base_price) * 0.1))
			company.price = clampi(int(round(float(company.price) * adjustment)), mini(min_price, int(config.base_price)), int(config.base_price) * 2)
			if previous_units >= int(float(config.capacity) * float(company.staff.size()) * 0.9) and company.staff.size() < 3 and _cash(entity) > int(config.wage) * 25: _hire(company)
		if _cash(entity) < int(config.wage) * 3 and int(company.loss_days) < 10: _take_loan(entity, _scale(5000000), 90)
		if int(company.loss_days) >= 18:
			_close(company)
			_news("Конкурент закрыл предприятие", company.name + " прекратил работу из-за устойчивых убытков.")
		elif int(state.day) % 45 == 0 and _cash(entity) > int(config.setup_cost) * 3:
			for plot in city.plots:
				if _at_plot(int(plot.id)).is_empty() and _property(int(plot.id)).is_empty():
					var branch := _create_company(company.type, int(plot.id), "ai", entity)
					branch.name = company.name + " · филиал"
					_hire(branch)
					_news("Новый филиал конкурента", branch.name + ": спрос теперь распределяется между большим числом компаний.")
					break

func _macro_day() -> void:
	if int(state.day) % 21 != 0: return
	var choice := int(_rand() * 4.0)
	if choice == 0:
		state.macro.demand = maxf(0.65, float(state.macro.demand) * 0.92)
		state.macro.property_value = maxf(0.65, float(state.macro.property_value) * 0.96)
		_news("Игровое событие: спад потребления", "Общий спрос снизился на 8%, стоимость недвижимости — на 4%. Это событие симуляции, не реальная новость.")
	elif choice == 1:
		state.macro.demand = minf(1.3, float(state.macro.demand) * 1.06)
		state.macro.property_value = minf(1.5, float(state.macro.property_value) * 1.03)
		_news("Игровое событие: рост деловой активности", "Спрос вырос на 6%, недвижимость — на 3%. Прибыль зависит от решений компаний.")
	elif choice == 2:
		state.macro.supplier_price = minf(1.8, float(state.macro.supplier_price) * 1.07)
		_news("Игровое событие: дорожает сырьё", "Новые поставки подорожали на 7%. Уже оплаченные заказы сохраняют свою стоимость.")
	else:
		state.macro.annual_rate_delta = minf(0.1, float(state.macro.annual_rate_delta) + 0.015)
		_news("Игровое событие: ужесточение кредитования", "Ставка новых кредитов выросла на 1,5 п.п. Условия действующих договоров не изменены.")

func end_day() -> Dictionary:
	if state.is_empty(): return _error("Сначала начните новую игру.")
	if state.bankrupt: return _error("Симуляция завершена банкротством. Можно изучить отчёт или начать новую игру.")
	state.day = int(state.day) + 1
	_macro_day()
	_ai_actions()
	_collections()
	_deliveries()
	for type_id in catalog:
		var demand := Demand.demand_for(type_id, int(state.day), catalog, state.macro, int(city.population))
		var distribution := Demand.allocate(state.companies, type_id, demand, catalog[type_id], city.plots, int(state.day))
		for company in state.companies:
			if company.type == type_id and company.status == "open": _sell(company, distribution.get(company.id, {"units": 0, "demand": demand, "market_share": 0.0}))
	for company in state.companies:
		if company.status == "open": _operating_costs(company)
	_property_day()
	_loan_day()
	_taxes()
	_pay_bills()
	for company in state.companies:
		if company.status != "open": continue
		var allocation: Dictionary = company.last_report.duplicate(true)
		company.last_report = Ledger.report(state, company.entity, int(state.day), company.id)
		for key in ["units", "demand", "market_share"]: company.last_report[key] = allocation.get(key, 0)
		company.loss_days = int(company.loss_days) + 1 if int(company.last_report.net_profit) < 0 else 0
	var report := financials()
	state.last_report = report.duplicate(true)
	state.history.append({"day": int(state.day), "cash": player_cash(), "profit": int(report.net_profit), "revenue": int(report.revenue), "equity": int(report.equity)})
	if state.history.size() > 730: state.history.pop_front()
	var player: Dictionary = state.entities.player
	player.zero_cash_days = int(player.zero_cash_days) + 1 if player_cash() == 0 and int(report.payables) > 0 else 0
	var oldest_bill := 0
	for bill in state.bills:
		if bill.entity == "player": oldest_bill = maxi(oldest_bill, int(state.day) - int(bill.due_day))
	var loan_overdue := 0
	for loan in state.loans:
		if loan.entity == "player": loan_overdue = maxi(loan_overdue, int(loan.arrears_days))
	if int(player.zero_cash_days) >= 14 or oldest_bill >= 30 or loan_overdue >= 30 or int(player.tax_overdue_days) >= 30:
		state.bankrupt = true
		_news("Банкротство", "Компания не смогла исполнить просроченные обязательства. Изучите журнал и рекомендации AIRA; новая игра доступна из меню.")
	if int(report.net_profit) > 0: _achievement("first_profit", "Первый прибыльный день")
	if int(state.day) >= 31: _achievement("first_month", "Месяц в бизнесе")
	if int(report.equity) >= int(country.start_capital) * 2: _achievement("double_equity", "Удвоенный капитал")
	return _ok("День завершён. Все продажи, расходы, поставки и обязательства обработаны.", {"report": report})

func financials() -> Dictionary:
	if state.is_empty(): return {}
	return Ledger.report(state, "player", int(state.day))

func date_label() -> String:
	return Calendar.label(int(state.get("day", 1)))

func aira() -> Array:
	var advice: Array = []
	if state.is_empty(): return ["Начните игру, чтобы AIRA получила ваши финансовые данные."]
	var report := financials()
	if state.bankrupt: advice.append("Неплатёжеспособность: обязательства просрочены, бизнесу не хватило ликвидности. Изучите последние расходы и долги перед новой попыткой.")
	var daily_fixed := 0
	var owned_count := 0
	for company in state.companies:
		if company.owner != "player" or company.status != "open": continue
		owned_count += 1
		var wages := 0
		for worker in company.staff: wages += int(worker.wage)
		var rent := 0 if not _property(int(company.plot_id)).is_empty() else int(city.plots[int(company.plot_id)].rent)
		daily_fixed += wages + rent + int(company.advertising)
		if company.staff.is_empty(): advice.append(company.name + ": без сотрудников нет продаж, но аренда продолжает начисляться. Наймите работника либо закройте помещение.")
		if not catalog[company.type].service and int(company.stock) == 0:
			advice.append(company.name + (": товара нет, ожидается %d поставок. Учтите время доставки." % company.orders.size() if company.orders.size() > 0 else ": склад пуст. Закажите товар; иначе выручки не будет."))
		if float(company.price) > float(catalog[company.type].base_price) * 1.5: advice.append(company.name + ": цена существенно выше базовой. Чувствительность покупателей уменьшает продажи; проверьте прибыль при меньшей цене.")
		if not company.last_report.is_empty() and int(company.last_report.net_profit) < 0:
			advice.append(company.name + ": убыток дня %s. Продано %d; зарплаты %s, аренда %s, себестоимость %s. Сопоставьте загрузку персонала и маржу." % [_money(-int(company.last_report.net_profit)), int(company.last_report.units), _money(int(company.last_report.wages)), _money(int(company.last_report.rent)), _money(int(company.last_report.cogs))])
		if not company.last_report.is_empty(): advice.append(company.name + ": доля спроса %.1f%%. Конкуренты обслуживают тот же конечный рынок; реклама не создаёт бесконечных клиентов." % (float(company.last_report.market_share) * 100.0))
	if owned_count == 0: advice.append("Начните с одного бизнеса на свободном участке. Покупка оборудования уменьшит деньги, но сохранит актив на балансе; работники и запас товара оплачиваются отдельно.")
	if daily_fixed > 0:
		var days := float(player_cash()) / float(daily_fixed)
		advice.append("Запас ликвидности без новых продаж: %.1f игровых дней при зарплатах, аренде и рекламе %s в день. Кредитные платежи и закупки сократят этот срок." % [days, _money(daily_fixed)])
	if int(report.receivables) > 0: advice.append("В дебиторской задолженности %s: IT-проекты признаны выручкой, деньги поступят через три дня. Прибыль не равна денежному потоку." % _money(int(report.receivables)))
	if int(report.tax_payable) > 0: advice.append("Начисленный налог %s нужно оплатить в конце 30-дневного игрового периода. Сохраните деньги к сроку." % _money(int(report.tax_payable)))
	for loan in state.loans:
		if loan.entity == "player" and int(loan.remaining) > 0:
			advice.append("Кредит %s: остаток %s, ближайший основной платёж %s плюс проценты; просрочка %d дн. Кредит повышает деньги и обязательства, выручку он не увеличивает." % [loan.id, _money(int(loan.remaining)), _money(int(loan.installment)), int(loan.arrears_days)])
	if int(report.payables) > 0: advice.append("Кредиторская задолженность %s — реальные обязательства. Новые покупки не устраняют дефицит денег." % _money(int(report.payables)))
	advice.append("Данные: %s, калибровка от %s. AIRA анализирует вашу игровую модель локально; актуальная реальная статистика не загружена." % [country.profile_label, country.as_of])
	return advice

func _money(amount: int) -> String:
	return "%.2f %s" % [float(amount) / 100.0, country.symbol]

func _news(title: String, body: String) -> void:
	state.news.push_front({"day": int(state.day), "title": title, "body": body, "kind": "simulation", "source": "TECH EMPIRE", "published_at": Calendar.label(int(state.day)), "effective_day": int(state.day), "verification_status": "internal_simulation"})
	if state.news.size() > 150: state.news.pop_back()

func _achievement(id: String, name: String) -> void:
	for entry in state.achievements:
		if entry.id == id: return
	state.achievements.append({"id": id, "name": name, "day": int(state.day)})

func validate_state(data: Dictionary) -> String:
	# Validate before loading, including replay against the complete journal.
	for key in ["version", "day", "country_id", "city_id", "entities", "companies", "journal", "loans", "properties", "bills", "receipts", "rng", "macro", "next_id", "news", "history", "achievements", "bankrupt", "credit_score", "labor_available"]:
		if not data.has(key): return "Отсутствует поле: " + key
	if not _integer(data.version) or int(data.version) != 1: return "Неподдерживаемая версия экономического состояния."
	if not _integer(data.day) or int(data.day) < 1 or int(data.day) > 100000: return "Некорректный игровой день."
	for key in ["rng", "next_id", "credit_score", "labor_available"]:
		if not _integer(data[key]) or int(data[key]) < 0: return "Некорректный счётчик: " + key
	if data.country_id not in ["RU", "US"]: return "Неизвестный профиль страны."
	if data.city_id != ("yekaterinburg" if data.country_id == "RU" else "rivergate"): return "Город не соответствует стране."
	if not data.bankrupt is bool: return "Некорректный статус компании."
	if not data.macro is Dictionary or not data.macro.has_all(["demand", "supplier_price", "property_value", "annual_rate_delta"]): return "Повреждён макроэкономический профиль."
	for key in ["demand", "supplier_price", "property_value"]:
		if not _number_between(data.macro[key], 0.1, 10.0): return "Некорректный макропоказатель."
	if not _number_between(data.macro.annual_rate_delta, 0.0, 1.0): return "Некорректная ставка."
	if not data.entities is Dictionary or not data.entities.has("player"): return "Нет баланса игрока."
	for key in ["companies", "journal", "loans", "properties", "bills", "receipts", "news", "history", "achievements"]:
		if not data[key] is Array: return "Некорректный список: " + key
	var replay := {}
	for entity in data.entities:
		if not data.entities[entity] is Dictionary or not data.entities[entity].get("accounts") is Dictionary: return "Некорректный баланс."
		for key in ["tax_loss", "zero_cash_days", "tax_overdue_days"]:
			if not _integer(data.entities[entity].get(key)) or int(data.entities[entity][key]) < 0: return "Некорректное состояние обязательств."
		if not _integer(data.entities[entity].get("taxable_processed")): return "Повреждена история налоговой базы."
		replay[entity] = Ledger.empty_accounts()
	var previous_day := 1
	var previous_id := 0
	for row in data.journal:
		if not row is Dictionary or not row.get("postings") is Dictionary or not replay.has(row.get("entity", "")): return "Некорректная транзакция."
		if not row.has_all(["id", "day", "entity", "company_id", "category", "memo"]): return "Неполная транзакция."
		if not _integer(row.day) or int(row.day) < 1 or int(row.day) > int(data.day): return "Некорректная дата операции."
		if int(row.day) < previous_day or not _integer(row.id) or int(row.id) != previous_id + 1: return "Нарушена последовательность журнала."
		previous_day = int(row.day)
		previous_id = int(row.id)
		var sum := 0
		for key in row.postings:
			if not replay[row.entity].has(key): return "Неизвестный счёт журнала."
			var value = row.postings[key]
			if not _integer(value): return "Не целая денежная сумма."
			sum += int(value)
			replay[row.entity][key] = int(replay[row.entity][key]) + int(value)
		if sum != 0: return "Журнал не сбалансирован."
	for entity in replay:
		var actual: Dictionary = data.entities[entity].accounts
		for key in replay[entity]:
			if not actual.has(key) or not _integer(actual[key]) or int(actual[key]) != int(replay[entity][key]): return "Баланс не соответствует журналу."
		for key in Ledger.ASSETS:
			if int(actual[key]) < 0: return "Отрицательный актив."
		for key in Ledger.LIABILITIES:
			if int(actual[key]) > 0: return "Некорректный знак обязательства."
	var plots := {}
	var ids := {}
	var stock_values := {}
	var transit_values := {}
	var equipment_values := {}
	for entity in replay:
		stock_values[entity] = 0
		transit_values[entity] = 0
		equipment_values[entity] = 0
	for company in data.companies:
		if not company is Dictionary: return "Некорректная компания."
		for key in ["id", "type", "entity", "owner", "name", "stock", "lots", "orders", "staff", "plot_id", "status", "price", "equipment_value", "quality", "reputation", "advertising", "loss_days", "total_units", "opened_day", "last_report"]:
			if not company.has(key): return "Компания без поля " + key
		if company.type not in ["shop", "cafe", "studio"] or not replay.has(company.entity): return "Неизвестная компания."
		if company.owner not in ["player", "ai"] or company.status not in ["open", "closed"]: return "Неизвестный статус предприятия."
		if (company.owner == "player") != (company.entity == "player"): return "Некорректный владелец компании."
		if ids.has(company.id): return "Повтор идентификатора компании."
		ids[company.id] = true
		for key in ["stock", "plot_id", "price", "equipment_value", "advertising", "loss_days", "total_units", "opened_day"]:
			if not _integer(company[key]) or int(company[key]) < 0: return "Некорректное число предприятия."
		if int(company.stock) < 0 or int(company.plot_id) < 0 or int(company.plot_id) > 15 or int(company.price) <= 0: return "Некорректный склад, цена или участок."
		if not _number_between(company.quality, 0.1, 3.0) or not _number_between(company.reputation, 0.0, 1.0) or not company.last_report is Dictionary: return "Некорректные параметры качества."
		if company.status == "open":
			if plots.has(int(company.plot_id)): return "На участке два бизнеса."
			plots[int(company.plot_id)] = true
		if not company.lots is Array or not company.orders is Array or not company.staff is Array: return "Повреждены списки предприятия."
		var stock := 0
		for lot in company.lots:
			if not lot is Dictionary or not _integer(lot.get("quantity", -1)) or not _integer(lot.get("cost", -1)) or not _integer(lot.get("expires_day", -1)) or int(lot.quantity) <= 0 or int(lot.cost) < 0 or int(lot.expires_day) < 1: return "Некорректная партия товара."
			stock += int(lot.quantity)
			stock_values[company.entity] += int(lot.cost)
		if stock != int(company.stock): return "Остаток не соответствует партиям."
		for order in company.orders:
			if not order is Dictionary or not _integer(order.get("cost", -1)) or not _integer(order.get("quantity", -1)) or not _integer(order.get("arrives_day", -1)) or int(order.cost) < 0 or int(order.quantity) <= 0 or int(order.arrives_day) < 1 or order.get("supplier", "") not in ["standard", "express", "credit"]: return "Повреждён заказ."
			transit_values[company.entity] += int(order.cost)
		equipment_values[company.entity] += int(company.equipment_value)
		for worker in company.staff:
			if not worker is Dictionary or not _integer(worker.get("wage", -1)) or int(worker.wage) < 0 or not worker.has_all(["id", "name", "skill", "satisfaction", "training_until"]): return "Повреждены данные сотрудника."
			if not _number_between(worker.skill, 0.1, 3.0) or not _number_between(worker.satisfaction, 0.0, 1.0) or not _integer(worker.training_until): return "Некорректное состояние сотрудника."
	for entity in replay:
		if int(stock_values[entity]) != int(replay[entity].inventory) or int(transit_values[entity]) != int(replay[entity].in_transit) or int(equipment_values[entity]) != int(replay[entity].equipment): return "Активы предприятия не совпадают с балансом."
	var loan_balances := {}
	for entity in replay: loan_balances[entity] = 0
	for loan in data.loans:
		if not loan is Dictionary or not loan.has_all(["id", "entity", "principal", "remaining", "interest_due", "principal_due", "rate", "installment", "next_due", "arrears_days", "term_days", "restructured"]): return "Повреждён кредит."
		for key in ["principal", "remaining", "interest_due", "principal_due", "installment", "next_due", "arrears_days", "term_days"]:
			if not _integer(loan[key]) or int(loan[key]) < 0: return "Некорректное значение кредита."
		if not _number_between(loan.rate, 0.0, 2.0) or not loan.restructured is bool or int(loan.remaining) > int(loan.principal): return "Некорректные условия кредита."
		if not loan_balances.has(loan.entity) or int(loan.remaining) < 0 or int(loan.principal_due) > int(loan.remaining) or int(loan.interest_due) < 0: return "Некорректный долг."
		loan_balances[loan.entity] += int(loan.remaining)
	for entity in replay:
		if int(loan_balances[entity]) != -int(replay[entity].loans): return "Кредиты не совпадают с балансом."
	var book_value := 0
	var property_plots := {}
	for owned in data.properties:
		if not owned is Dictionary or not owned.has_all(["plot_id", "owner", "book_value", "condition", "listed", "tenant_until"]): return "Повреждена недвижимость."
		if not _integer(owned.plot_id) or int(owned.plot_id) < 0 or int(owned.plot_id) > 15 or property_plots.has(int(owned.plot_id)): return "Некорректный участок собственности."
		if owned.owner != "player" or not _integer(owned.book_value) or int(owned.book_value) <= 0 or not _number_between(owned.condition, 0.0, 1.0) or not owned.listed is bool or not _integer(owned.tenant_until): return "Некорректное состояние недвижимости."
		property_plots[int(owned.plot_id)] = true
		book_value += int(owned.book_value)
	if book_value != int(replay.player.property): return "Недвижимость не совпадает с балансом."
	var receivables := {}
	var payables := {}
	for entity in replay:
		receivables[entity] = 0
		payables[entity] = 0
	for receipt in data.receipts:
		if not receipt is Dictionary or not receipt.has_all(["entity", "company_id", "amount", "due_day"]): return "Повреждена дебиторская задолженность."
		if not receivables.has(receipt.entity) or not ids.has(receipt.company_id) or not _integer(receipt.amount) or int(receipt.amount) <= 0 or not _integer(receipt.due_day) or int(receipt.due_day) < 1: return "Некорректный счёт покупателя."
		receivables[receipt.entity] += int(receipt.amount)
	for bill in data.bills:
		if not bill is Dictionary or not bill.has_all(["id", "entity", "company_id", "category", "amount", "due_day"]): return "Повреждена кредиторская задолженность."
		if not payables.has(bill.entity) or not _integer(bill.amount) or int(bill.amount) <= 0 or not _integer(bill.due_day) or int(bill.due_day) < 1: return "Некорректный счёт поставщика."
		payables[bill.entity] += int(bill.amount)
	for loan in data.loans: payables[loan.entity] += int(loan.interest_due)
	for entity in replay:
		if int(receivables[entity]) != int(replay[entity].receivables): return "Счета покупателей не совпадают с балансом."
		if int(payables[entity]) != -int(replay[entity].payables): return "Кредиторская задолженность не совпадает с балансом."
	return ""

func _integer(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and absf(float(value)) < 9007199254740991.0

func _number_between(value, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum
