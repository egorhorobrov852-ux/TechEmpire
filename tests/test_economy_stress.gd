extends SceneTree

const Simulation = preload("res://scripts/economy/simulation.gd")

func _initialize() -> void:
	var failures := 0
	var checked_days := 0
	for profile in ["RU", "US"]:
		for seed_value in [7, 42, 911]:
			var sim = Simulation.new()
			sim.new_game(profile, seed_value)
			sim.open_business("shop", 8)
			sim.open_business("cafe", 9)
			sim.open_business("studio", 1)
			for company in sim.state.companies:
				if company.owner == "player": sim.hire(company.id)
			for turn in range(180):
				if sim.state.bankrupt: break
				for company in sim.state.companies:
					if company.owner != "player" or company.status != "open": continue
					var config: Dictionary = sim.catalog[company.type]
					if not config.service:
						var pipeline := int(company.stock)
						for order in company.orders: pipeline += int(order.quantity)
						var quantity := mini(int(config.stock_capacity) - pipeline, int(config.capacity) * 3)
						if pipeline < int(config.capacity) * 2 and quantity > 0: sim.order_stock(company.id, quantity)
					if turn % 21 == 7 and company.staff.size() > 0: sim.train(company.id, company.staff[0].id)
					if turn % 14 == 0: sim.set_price(company.id, int(round(float(config.base_price) * (0.85 + float(turn % 5) * 0.08))))
					if turn == 40: sim.hire(company.id)
					if turn == 60 and company.staff.size() > 1: sim.fire(company.id, company.staff[-1].id)
				if turn == 35: sim.take_loan(int(sim.country.start_capital) / 5, 90)
				if turn == 65 and sim.state.loans.size() > 0:
					for loan in sim.state.loans:
						if loan.entity == "player": sim.restructure_loan(loan.id)
				if turn == 90: sim.buy_property(8)
				sim.end_day()
				checked_days += 1
				var validation: String = sim.validate_state(sim.state)
				if not validation.is_empty():
					push_error("STRESS %s seed=%d day=%d: %s" % [profile, seed_value, int(sim.state.day), validation])
					failures += 1
					break
				var json_copy: Dictionary = JSON.parse_string(JSON.stringify(sim.state))
				if turn % 15 == 0 and not sim.validate_state(json_copy).is_empty():
					push_error("JSON roundtrip failed under load")
					failures += 1
					break
			print("STRESS %s seed=%d reached day %d; cash=%d bankrupt=%s" % [profile, seed_value, int(sim.state.day), sim.player_cash(), str(sim.state.bankrupt)])
	print("ECONOMY STRESS: %d simulated days; %d failures" % [checked_days, failures])
	quit(1 if failures else 0)
