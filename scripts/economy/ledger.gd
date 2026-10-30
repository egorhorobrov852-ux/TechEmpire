extends RefCounted
## Double-entry ledger: debit balances are positive, credit balances negative.

const ASSETS := ["cash", "inventory", "in_transit", "equipment", "property", "receivables"]
const LIABILITIES := ["loans", "payables", "tax_payable"]
const EXPENSES := ["cogs", "wages", "rent", "marketing", "training", "maintenance", "depreciation", "tax", "interest", "penalties", "registration", "disposal_loss"]

static func empty_accounts() -> Dictionary:
	var result := {"equity": 0, "revenue": 0, "other_income": 0}
	for key in ASSETS + LIABILITIES + EXPENSES:
		result[key] = 0
	return result

static func post(state: Dictionary, entity_id: String, postings: Dictionary, category: String, memo: String, company_id: String = "") -> void:
	var sum := 0
	for value in postings.values(): sum += int(value)
	assert(sum == 0, "Unbalanced journal transaction")
	var entity: Dictionary = state.entities[entity_id]
	for key in postings:
		entity.accounts[key] = int(entity.accounts.get(key, 0)) + int(postings[key])
	state.journal.append({"id": state.journal.size() + 1, "day": state.day, "entity": entity_id, "company_id": company_id, "category": category, "memo": memo, "postings": postings.duplicate(true)})

static func report(state: Dictionary, entity_id: String, day: int, company_id: String = "") -> Dictionary:
	var movement := empty_accounts()
	# The journal is append-only and chronological. Walk today's suffix only;
	# closing day 700 must not rescan all preceding sales for every business.
	for index in range(state.journal.size() - 1, -1, -1):
		var row: Dictionary = state.journal[index]
		if int(row.day) < day: break
		if row.entity != entity_id or int(row.day) != day: continue
		if not company_id.is_empty() and row.company_id != company_id: continue
		for key in row.postings:
			movement[key] = int(movement.get(key, 0)) + int(row.postings[key])
	var result := {"day": day, "revenue": -int(movement.revenue), "cogs": int(movement.cogs), "wages": int(movement.wages), "rent": int(movement.rent), "tax": int(movement.tax), "interest": int(movement.interest), "depreciation": int(movement.depreciation), "other_income": -int(movement.other_income), "cash_flow": int(movement.cash), "units": 0, "demand": 0, "market_share": 0.0}
	result.gross_profit = result.revenue - result.cogs
	var operating := 0
	for key in EXPENSES:
		if key not in ["cogs", "tax", "interest"]: operating += int(movement[key])
	result.operating_expenses = operating
	result.net_profit = result.gross_profit + result.other_income - operating - result.tax - result.interest
	var accounts: Dictionary = state.entities[entity_id].accounts
	var assets := 0
	var liabilities := 0
	var earnings := -int(accounts.revenue) - int(accounts.other_income)
	for key in ASSETS: assets += int(accounts[key])
	for key in LIABILITIES: liabilities -= int(accounts[key])
	for key in EXPENSES: earnings -= int(accounts[key])
	result.merge({"cash": int(accounts.cash), "inventory": int(accounts.inventory), "in_transit": int(accounts.in_transit), "equipment": int(accounts.equipment), "property": int(accounts.property), "receivables": int(accounts.receivables), "payables": -int(accounts.payables), "tax_payable": -int(accounts.tax_payable), "assets": assets, "liabilities": liabilities, "equity": -int(accounts.equity) + earnings})
	return result
