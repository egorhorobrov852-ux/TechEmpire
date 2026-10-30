extends RefCounted
## Screens expose actual Simulation actions; no screen maintains a second economy.

var app

func _init(application) -> void:
	app = application

func show(id: String) -> void:
	var titles = {"business":"Ваши компании","plot":"Участок города","competitor":"Компания конкурента","finance":"Финансы","day_report":"Итоги дня","staff":"Команда","suppliers":"Поставщики","warehouse":"Склад","banks":"Банк и кредиты","property":"Недвижимость","market":"Рынок города","news":"Новости и экономика","aira":"AIRA · ваш советник","achievements":"Достижения","profile":"История империи","settings":"Оформление","saves":"Сохранения","more":"Управление империей","pause":"Игра на паузе","bankruptcy":"Неплатёжеспособность"}
	var v = app._make_panel(titles.get(id,"TECH EMPIRE"))
	match id:
		"plot": plot_page(v)
		"business": business_page(v)
		"competitor": competitor_page(v)
		"finance", "day_report": finance_page(v)
		"staff": staff_page(v)
		"suppliers": supplies_page(v)
		"warehouse": warehouse_page(v)
		"banks": bank_page(v)
		"property": property_page(v)
		"market": market_page(v)
		"news": news_page(v)
		"aira": aira_page(v)
		"achievements": achievements_page(v)
		"profile": profile_page(v)
		"settings": settings_page(v)
		"saves": saves_page(v)
		"more": more_page(v)
		"pause": pause_page(v)
		"bankruptcy": bankruptcy_page(v)

func metric(v: Node, title: String, amount, good: bool = false) -> void:
	var h = app.row(v)
	app.text(h,title,19,true)
	var value = app.text(h,app.money(amount),21)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if good:
		value.add_theme_color_override("font_color",app.palette.green if float(amount) >= 0 else app.palette.red)

func selected(v: Node) -> Dictionary:
	var b: Dictionary = app.company()
	if b.is_empty() or b.get("owner","") != "player":
		app.text(v,"Здесь пока нет вашей компании. Выберите свободный участок и откройте первый бизнес.",22)
		app.button(v,"Выбрать участок",func(): app.city.focus_plot(8); app.open_plot(8),"FindPlot",true)
		return {}
	app.text(v,str(b.name),25)
	app.text(v,"Участок %02d · %s" % [int(b.plot_id)+1,str(app.sim.catalog[b.type].name)],17,true)
	return b

func plot_page(v: Node) -> void:
	var plot: Dictionary = app.plot_info(app.selected_plot)
	if plot.is_empty():
		app.text(v,"Участок не найден.")
		return
	app.text(v,str(plot.get("name","Участок %02d" % (app.selected_plot+1))),27)
	app.text(v,"Район: " + str(plot.get("district","")),18,true)
	app.text(v,"Локация влияет на поток покупателей и аренду. Сначала изучите рынок: объём спроса ограничен.",20)
	metric(v,"Аренда / день",plot.get("rent",0))
	metric(v,"Стоимость помещения",plot.get("purchase_price",0))
	app.section(v,"Открыть бизнес","Вложения в оборудование — актив, а не расход текущего дня. Аренда начисляется ежедневно.")
	for type in ["shop","cafe","studio"]:
		var kind: String = type
		var config: Dictionary = app.sim.catalog[kind]
		var item = app.card(v)
		app.text(item,str(config.name),23)
		app.text(item,str(config.get("description","")),18,true)
		metric(item,"Оборудование",config.setup_cost)
		var registration_fee = int(round(float(app.sim.country.business_rules.registration_fee)*float(app.sim.country.get("amount_scale",1.0))))
		metric(item,"Регистрация и разрешение",registration_fee)
		app.button(item,"Открыть · " + app.money(int(config.setup_cost)+registration_fee),func():
			var result: Dictionary = app.sim.open_business(kind,app.selected_plot)
			if result.get("ok",false):
				for company in app.player_companies():
					if int(company.plot_id) == app.selected_plot:
						app.selected_company = str(company.id)
			app.act(result,"business","open")
		,"Open_" + kind,true)
	app.button(v,"Купить помещение",func(): app.act(app.sim.buy_property(app.selected_plot),"property"),"BuyPlot")

func business_page(v: Node) -> void:
	var companies = app.player_companies()
	if companies.size() > 1:
		for company in companies:
			var company_id: String = str(company.id)
			app.button(v,str(company.name) + " · №%02d" % (int(company.plot_id)+1),func(): app.selected_company=company_id; app.show_panel("business"))
	var b = selected(v)
	if b.is_empty(): return
	var spec: Dictionary = app.sim.catalog[b.type]
	var c = app.card(v)
	metric(c,"Цена",b.price)
	metric(c,"Базовая себестоимость",spec.unit_cost)
	app.text(c,"Команда: %d · Репутация: %.0f%%" % [b.staff.size(),float(b.reputation)*100.0],18,true)
	app.text(c,"Запас: %d / %d" % [int(b.stock),int(spec.stock_capacity)] if not spec.get("service",false) else "Услуги: спрос и мощности команды ограничены.",19)
	var report: Dictionary = b.get("last_report",{})
	metric(c,"Результат бизнеса",report.get("net_profit",0),true)
	app.text(c,"До общих налогов и кредитов империи. Полный итог — в разделе «Финансы».",16,true)
	var price = app.field(v,"Цена продажи · " + str(app.sim.country.get("symbol","₽")),float(b.price)/100.0,0.01,1000000,0.01)
	price.name = "BusinessPrice"
	app.button(v,"Установить цену",func(): app.act(app.sim.set_price(str(b.id),int(round(price.value*100))),"business","price"),"PriceApply",true)
	app.text(v,"Изменение цены меняет спрос. Высокая выручка не гарантирует прибыль.",17,true)
	app.button(v,"Нанять сотрудника · " + app.money(spec.wage) + "/день",func(): app.act(app.sim.hire(str(b.id)),"business","hire"),"HireStaff")
	if not spec.get("service",false):
		stock_order(v,b,"business")
	app.button(v,"Команда и обучение",func(): app.show_panel("staff"))
	app.button(v,"Склад и списания",func(): app.show_panel("warehouse"))
	var advertising = app.field(v,"Рекламный бюджет / день",float(b.get("advertising",0))/100.0,0,float(spec.wage)*3/100.0,1)
	app.button(v,"Применить бюджет рекламы",func(): app.act(app.sim.set_advertising(str(b.id),int(round(advertising.value*100))),"business"),"ApplyAdvertising")
	app.button(v,"Закрыть предприятие…",func(): confirm_close(v,str(b.id)))

func confirm_close(v: Node, company_id: String) -> void:
	app.text(v,"Закрытие остановит продажи и аренду. Оборудование будет продано с дисконтом, остатки товара списаны. Выходные пособия и кредиты останутся обязательствами.",18,true)
	app.button(v,"Подтвердить закрытие",func(): app.act(app.sim.close_business(company_id),"business"),"ConfirmClose")

func stock_order(v: Node, b: Dictionary, next: String) -> void:
	var spec: Dictionary = app.sim.catalog[b.type]
	var quantity = app.field(v,"Заказать единиц",min(120,int(spec.stock_capacity)),1,int(spec.stock_capacity))
	var quote_label = app.text(v,"",18,true)
	var update_quote = func(_value: float):
		var quote: Dictionary = app.sim.stock_quote(str(b.id),int(quantity.value),"standard")
		quote_label.text = "К оплате: %s · в том числе доставка %s\nПрибытие: день %d" % [app.money(quote.total),app.money(quote.transport),int(quote.arrives_day)]
	quantity.value_changed.connect(update_quote)
	update_quote.call(quantity.value)
	app.button(v,"Заказать товар",func(): app.act(app.sim.order_stock(str(b.id),int(quantity.value),"standard"),next,"stock"),"OrderStock",true)
	app.text(v,"Доставка: %d дн. Себестоимость с транспортом фиксируется при заказе. Резервируйте место под поставку." % int(spec.lead_days),17,true)

func staff_page(v: Node) -> void:
	var b = selected(v)
	if b.is_empty(): return
	var spec: Dictionary = app.sim.catalog[b.type]
	app.text(v,"Навыки команды определяют пропускную способность. Удовлетворённость влияет на работу и риск ухода.",20)
	app.button(v,"Нанять · " + app.money(spec.wage) + "/день",func(): app.act(app.sim.hire(str(b.id)),"staff","hire"),"HireStaff",true)
	if b.staff.is_empty():
		app.text(v,"Работников нет. Продажи ограничены до найма.",20,true)
	for employee in b.staff:
		var staff_id: String = str(employee.id)
		var item = app.card(v)
		app.text(item,str(employee.name),23)
		app.text(item,"Квалификация: %.0f%% · Довольство: %.0f%%" % [float(employee.skill)*100,float(employee.satisfaction)*100],18,true)
		metric(item,"Зарплата / день",employee.wage)
		var salary = app.field(item,"Новая дневная зарплата",float(employee.wage)/100.0,float(spec.wage)/200.0,float(spec.wage)*5/100.0)
		app.button(item,"Изменить зарплату",func(): app.act(app.sim.set_salary(str(b.id),staff_id,int(round(salary.value*100))),"staff"))
		app.button(item,"Обучить сотрудника",func(): app.act(app.sim.train(str(b.id),staff_id),"staff"))
		app.button(item,"Уволить",func(): app.act(app.sim.fire(str(b.id),staff_id),"staff"))

func supplies_page(v: Node) -> void:
	var b = selected(v)
	if b.is_empty(): return
	var spec: Dictionary = app.sim.catalog[b.type]
	app.section(v,"Городской оптовый склад","Оплата при заказе. Доставка по игровому календарю; нельзя продать товар в пути.")
	metric(v,"Базовая закупочная цена / ед.",spec.unit_cost)
	if spec.get("service",false):
		app.text(v,"Студия продаёт услуги. Товарный склад не требуется; затраты возникают при выполнении заказов.",21)
		app.button(v,"Управлять командой",func(): app.show_panel("staff"),"ServiceTeam",true)
	else:
		stock_order(v,b,"suppliers")
		app.section(v,"Экспресс-поставщик","Быстрее стандартной поставки, но дороже. Проверьте запас денежных средств.")
		var quantity = app.field(v,"Единиц экспресс-доставкой",50,1,int(spec.stock_capacity))
		app.button(v,"Заказать экспресс",func(): app.act(app.sim.order_stock(str(b.id),int(quantity.value),"express"),"suppliers","stock"),"ExpressOrder")
		app.section(v,"Поставка с отсрочкой оплаты","Товар через 3 дня, оплата через 7. Доставка включена в долг, закупка дороже стандартной.")
		app.button(v,"Заказать с оплатой через 7 дней",func(): app.act(app.sim.order_stock(str(b.id),int(quantity.value),"credit"),"suppliers","stock"),"CreditOrder")
	orders(v,b)

func orders(v: Node,b: Dictionary) -> void:
	app.section(v,"Ожидаемые поставки")
	var pending: Array = b.get("orders",[])
	if pending.is_empty():
		pending = app.sim.state.get("orders",[]).filter(func(o): return str(o.get("company_id",""))==str(b.id))
	if pending.is_empty():
		app.text(v,"Поставок в пути нет.",18,true)
	for order in pending:
		app.text(v,"%d ед. · доставка в день %d" % [int(order.get("quantity",0)),int(order.get("arrives_day",0))],19)

func warehouse_page(v: Node) -> void:
	var b = selected(v)
	if b.is_empty(): return
	var spec: Dictionary = app.sim.catalog[b.type]
	app.text(v,"Остаток: %d ед.\nВместимость: %d ед." % [int(b.stock),int(spec.stock_capacity)],25)
	var stock_value: int = 0
	for lot in b.get("lots",[]): stock_value += int(lot.cost)
	metric(v,"Балансовая стоимость",stock_value)
	app.text(v,"Непроданные продукты кафе портятся. Дефицит ограничивает продажи и ухудшает репутацию. Себестоимость списывается только при продаже или порче.",20,true)
	orders(v,b)
	app.button(v,"Перейти к закупкам",func(): app.show_panel("suppliers"),"WarehouseSuppliers",true)

func finance_page(v: Node) -> void:
	var report: Dictionary = app.sim.financials()
	v.name = "FinanceReport"
	app.text(v,"Результаты последнего игрового дня",18,true)
	var summary = app.card(v)
	metric(summary,"Чистая прибыль",report.get("net_profit",0),true)
	metric(summary,"Денежный поток",report.get("cash_flow",0),true)
	metric(summary,"Денежные средства",app.sim.player_cash())
	app.section(v,"Прибыли и убытки")
	for entry in [["Выручка","revenue"],["Себестоимость продаж","cogs"],["Валовая прибыль","gross_profit"],["Зарплаты","wages"],["Аренда","rent"],["Операционные расходы","operating_expenses"],["Налоги","tax"],["Проценты","interest"]]:
		metric(v,entry[0],report.get(entry[1],0))
	app.text(v,"Кредит увеличивает деньги и обязательства. Покупка оборудования уменьшает деньги и увеличивает активы. Эти операции не являются выручкой или себестоимостью.",18,true)
	app.section(v,"Баланс империи")
	for entry in [["Активы","assets"],["Обязательства","liabilities"],["Собственный капитал","equity"],["Запасы","inventory"],["Дебиторская задолженность","receivables"],["Кредиторская задолженность","payables"]]:
		metric(v,entry[0],report.get(entry[1],0))
	app.section(v,"Журнал операций","Каждое движение отражено в экономическом ядре. Последние 18 операций:")
	var journal: Array = app.sim.state.get("journal",[]).filter(func(item): return item.get("entity","")=="player")
	for i in range(maxi(0,journal.size()-18),journal.size()):
		var item: Dictionary = journal[i]
		if str(item.get("owner",item.get("entity","player"))) != "player": continue
		var memo = str(item.get("description",item.get("memo",item.get("kind","Операция"))))
		app.text(v,"День %d · %s" % [int(item.get("day",1)),memo],17,true)
	app.button(v,"Разобрать с AIRA",func(): app.show_panel("aira"),"FinanceAira",true)

func bank_page(v: Node) -> void:
	app.text(v,"Кредит — обязательство. Ежедневный платёж включает проценты и погашение основного долга. Просрочка ведёт к пеням и снижению кредитного рейтинга.",20)
	var amount = app.field(v,"Сумма · " + str(app.sim.country.get("symbol","₽")),100000 if app.sim.state.country_id=="RU" else 10000,100,10000000,100)
	app.text(v,"Срок · игровых дней",18,true)
	var term = OptionButton.new()
	term.custom_minimum_size.y = 52
	for days in [30,90,180]: term.add_item(str(days)+" дней",days)
	term.select(1)
	v.add_child(term)
	var offer_label = app.text(v,"",18,true)
	var update_offer = func():
		var offer: Dictionary = app.sim.loan_offer(int(round(amount.value*100)),term.get_selected_id())
		offer_label.text = "Ставка: %.1f%% годовых\nПервый платёж: %s\nПроценты за срок ≈ %s\nОдобрение зависит от лимита и кредитной истории." % [float(offer.annual_rate)*100,app.money(int(offer.daily_principal)+int(offer.first_interest)),app.money(offer.estimated_total_interest)]
	amount.value_changed.connect(func(_value: float): update_offer.call())
	term.item_selected.connect(func(_index: int): update_offer.call())
	update_offer.call()
	app.button(v,"Получить кредит на этих условиях",func(): app.act(app.sim.take_loan(int(round(amount.value*100)),term.get_selected_id()),"banks"),"TakeLoan",true)
	app.section(v,"Ваши обязательства")
	var count = 0
	for loan in app.sim.state.get("loans",[]):
		if loan.get("entity","") != "player" or int(loan.remaining) <= 0: continue
		count += 1
		var loan_id: String = str(loan.id)
		var c = app.card(v)
		app.text(c,"Кредит " + loan_id,23)
		metric(c,"Остаток долга",loan.get("remaining",loan.get("principal",0)))
		metric(c,"Основной долг / день",loan.installment)
		metric(c,"Начисленные проценты к оплате",loan.interest_due)
		app.text(c,"Просрочка: %d дн. · ставка %.1f%%" % [int(loan.arrears_days),float(loan.rate)*100],18,true)
		app.text(c,"Реструктуризация: комиссия 2% остатка, срок 180 дней, ставка +3 п.п. Доступна один раз.",17,true)
		app.button(c,"Реструктурировать",func(): app.act(app.sim.restructure_loan(loan_id),"banks"))
	if count == 0: app.text(v,"Активных кредитов нет.",20,true)

func property_page(v: Node) -> void:
	app.text(v,"Стоимость помещений меняется вместе с рынком. Собственный объект требует обслуживания; свободное помещение не приносит доход само по себе.",20)
	for plot in app.sim.city.plots:
		var plot_id = int(plot.id)
		var c = app.card(v)
		app.text(c,str(plot.get("name","Участок %02d" % (plot_id+1))),22)
		metric(c,"Рыночная стоимость",app.sim.property_value(plot_id))
		var owned = false
		var property_info: Dictionary = {}
		for property in app.sim.state.get("properties",[]):
			if int(property.get("plot_id",-1))==plot_id and property.get("owner","player")=="player":
				owned=true
				property_info=property
		if owned:
			app.text(c,"В собственности · содержание оплачивается ежедневно",17,true)
			app.text(c,"Состояние: %.0f%% · Арендатор до дня %d" % [float(property_info.condition)*100,int(property_info.tenant_until)],18,true)
			app.button(c,"Ремонт · 2,5% балансовой стоимости",func(): app.act(app.sim.repair_property(plot_id),"property"))
			var listed: bool = property_info.listed
			app.button(c,"Снять с аренды" if listed else "Предложить в аренду",func(): app.act(app.sim.set_property_listing(plot_id,not listed),"property"))
			app.button(c,"Продать помещение",func(): app.act(app.sim.sell_property(plot_id),"property"))
		else:
			metric(c,"Аренда / день",plot.rent)
			app.button(c,"Купить",func(): app.act(app.sim.buy_property(plot_id),"property"))
	app.text(v,"Внешний арендатор ищется раз в неделю; простой и обслуживание возможны. Новое строительство — в разработке.",18,true)

func market_page(v: Node) -> void:
	app.text(v,"Клиенты сравнивают цену, качество, репутацию и расположение. Конкуренты закупают товар и оплачивают свои расходы по тем же правилам.",20)
	for b in app.sim.state.companies:
		if b.get("status","active")=="closed": continue
		var id: String = str(b.id)
		var c = app.card(v)
		app.text(c,str(b.name),23)
		app.text(c,"Ваша компания" if b.owner=="player" else "Независимый конкурент",17,true)
		metric(c,"Цена продажи",b.price)
		var report: Dictionary = b.get("last_report",{})
		app.text(c,"Продано: %d · Доля рынка: %.1f%%" % [int(report.get("units",0)),float(report.get("market_share",0))*100.0],19)
		app.button(c,"Показать на карте",func(): app.selected_company=id; app.city.focus_plot(int(b.plot_id)); app.open_plot(int(b.plot_id)))

func competitor_page(v: Node) -> void:
	var b: Dictionary = app.sim.get_company(app.selected_company)
	if b.is_empty(): return
	app.text(v,str(b.name),26)
	app.text(v,"Конкурент · участок %02d" % (int(b.plot_id)+1),18,true)
	metric(v,"Цена продажи",b.price)
	app.text(v,"Сотрудники: %d\nРепутация: %.0f%%\nКачество: %.0f%%" % [b.staff.size(),float(b.reputation)*100,float(b.quality)*100],23)
	app.text(v,"Алгоритм реагирует на дефицит, маржу и спрос; компания может менять цены, нанимать, брать кредит и закрываться.",20,true)
	app.button(v,"Сравнить рынок",func(): app.show_panel("market"),"CompareMarket",true)

func news_page(v: Node) -> void:
	app.text(v,app.feed.status_text(),18,true)
	app.button(v,"Обновить официальный курс ЦБ РФ",func(): app.feed.refresh(),"RefreshData",true)
	app.text(v,"Курсы показаны справочно. Интернет не нужен для игры. Игровые налоги и ставки не подменяются новостями автоматически.",18,true)
	for news in app.feed.news():
		var c = app.card(v)
		app.text(c,str(news.get("title","Экономические данные")),23)
		app.text(c,str(news.get("body","")),19)
		app.text(c,"Источник: %s\nПубликация: %s · Действует: %s" % [str(news.get("source","")),str(news.get("published_at","")),str(news.get("effective_at",""))],15,true)
	app.section(v,"События города")
	var entries: Array = app.sim.state.get("news",[])
	for i in range(mini(15,entries.size())):
		var n = entries[i]
		if n is Dictionary:
			var c = app.card(v)
			app.text(c,str(n.get("title",n.get("message","Событие"))),21)
			app.text(c,str(n.get("body",n.get("description",""))),18,true)
		else: app.text(v,str(n),20)

func aira_page(v: Node) -> void:
	v.name = "AiraAdvice"
	app.text(v,"AIRA",36)
	app.text(v,"Анализ вашей экономики · день %d" % int(app.sim.state.day),18,true)
	for advice in app.sim.aira():
		var c = app.card(v)
		app.text(c,str(advice),21)
	app.text(v,"Советник работает на устройстве, использует журнал и текущее состояние игры. Рекомендации не гарантируют прибыль.",17,true)
	app.button(v,"Открыть отчёт",func(): app.show_panel("finance"),"AiraReport",true)
	app.button(v,"Проверить кредиты",func(): app.show_panel("banks"))

func achievements_page(v: Node) -> void:
	var unlocked: Array = app.sim.state.get("achievements",[])
	app.text(v,"Прогресс строится на решениях, а не на обязательных ежедневных входах.",21)
	if unlocked.is_empty(): app.text(v,"Откройте первую компанию и завершите день, чтобы начать историю достижений.",20,true)
	for achievement in unlocked:
		var c = app.card(v)
		app.text(c,"✓ " + (str(achievement.get("name",achievement.get("title","Достижение"))) if achievement is Dictionary else str(achievement)),23)
	app.text(v,"Будущие этапы: новые города, отрасли и международная экспансия — в разработке.",18,true)

func profile_page(v: Node) -> void:
	app.text(v,"Основатель империи",28)
	app.text(v,"%s · День %d\nДействующих предприятий: %d" % [str(app.sim.city.name),int(app.sim.state.day),app.player_companies().size()],22)
	metric(v,"Капитал",app.sim.financials().get("equity",0),true)
	app.section(v,"История компании")
	var history: Array = app.sim.state.get("history",[])
	for i in range(history.size()-1,maxi(-1,history.size()-20),-1):
		var event = history[i]
		if event is Dictionary:
			app.text(v,"День %d · прибыль %s · капитал %s" % [int(event.get("day",1)),app.money(event.get("profit",0)),app.money(event.get("equity",0))],18,true)
		else: app.text(v,str(event),18,true)
	app.text(v,"Игровое время продвигается кнопкой «Завершить день». В свёрнутом приложении дни не начисляются.",18,true)

func settings_page(v: Node) -> void:
	app.section(v,"Цветовая тема")
	for key in app.ThemeFactory.THEMES:
		var id: String = key
		var title: String = app.ThemeFactory.THEMES[id].name
		app.button(v,("✓ " if app.settings.theme==id else "") + title,func(): app.settings.theme=id; app.settings.accent=""; app.apply_theme(),"Theme_" + id,app.settings.theme==id)
	var dark = CheckButton.new()
	dark.text = "Тёмный режим"
	dark.custom_minimum_size.y = 56
	dark.button_pressed = app.settings.get("dark",false)
	dark.toggled.connect(func(enabled: bool): app.settings.dark=enabled; app.apply_theme())
	v.add_child(dark)
	var rounded = CheckButton.new()
	rounded.text = "Скруглённые карточки"
	rounded.custom_minimum_size.y = 56
	rounded.button_pressed = app.settings.get("rounded",true)
	rounded.toggled.connect(func(enabled: bool): app.settings.rounded=enabled; app.apply_theme())
	v.add_child(rounded)
	app.text(v,"Свой акцент",20)
	var picker = ColorPickerButton.new()
	picker.color = app.palette.accent
	picker.custom_minimum_size.y = 56
	picker.edit_alpha = false
	picker.popup_closed.connect(func(): app.settings.accent=picker.color.to_html(false); app.apply_theme())
	v.add_child(picker)
	var tutorial = CheckButton.new()
	tutorial.text = "Подсказки обучения"
	tutorial.button_pressed = app.settings.get("tutorial",true)
	tutorial.custom_minimum_size.y = 56
	tutorial.toggled.connect(func(enabled: bool): app.settings.tutorial=enabled; app.apply_theme())
	v.add_child(tutorial)
	app.text(v,"Камера: перетащите карту; два пальца — масштаб и вращение. На компьютере: колесо и правая кнопка мыши. Кнопка «Назад» закрывает панель.",18,true)

func saves_page(v: Node) -> void:
	app.text(v,"Автосохранение после решений и при сворачивании. Ручной слот независим. Каждый слот имеет контрольную сумму и резервную копию.",20)
	app.button(v,"Сохранить вручную",func(): app.toast(app.store.save_game(app.sim.state,"manual").message); app.show_panel("saves"),"ManualSave",true)
	app.button(v,"Загрузить ручное сохранение",func(): app.load_slot("manual"),"ManualLoad")
	app.button(v,"Загрузить автосохранение",func(): app.load_slot("auto"),"AutoLoad")
	for slot in ["auto","manual"]:
		var saved = app.store.load_game(slot)
		app.text(v,("Автосохранение" if slot=="auto" else "Ручное") + (" · день %d" % int(saved.state.day) if saved.ok else " · пусто"),18,true)

func more_page(v: Node) -> void:
	for spec in [["staff","Сотрудники"],["suppliers","Поставщики"],["warehouse","Склады"],["property","Недвижимость"],["news","Новости"],["achievements","Достижения"],["profile","Профиль и история"],["settings","Настройки и темы"],["saves","Сохранить / загрузить"],["pause","Главное меню"]]:
		var id: String = spec[0]
		app.button(v,spec[1],func(): app.show_panel(id),"More_"+id)

func pause_page(v: Node) -> void:
	app.text(v,"Прогресс сохраняется автоматически. Игровое время остановлено до следующего завершения дня.",21)
	app.button(v,"Вернуться в город",app.close_panel,"Resume",true)
	app.button(v,"Сохранить вручную",func(): app.toast(app.store.save_game(app.sim.state,"manual").message))
	app.button(v,"В главное меню",func(): app.autosave(); app.show_menu(),"BackMenu")

func bankruptcy_page(v: Node) -> void:
	app.text(v,"Средств и доступных активов не хватило для исполнения обязательств.",24)
	app.text(v,"История и журнал сохранены. AIRA объяснит причины; можно загрузить ручное сохранение или начать новую историю.",20,true)
	app.button(v,"Разобрать причины с AIRA",func(): app.show_panel("aira"),"BankruptAira",true)
	app.button(v,"Загрузить сохранение",func(): app.show_panel("saves"))
	app.button(v,"Главное меню",func(): app.autosave(); app.show_menu())
