from fastapi import FastAPI, Form
from fastapi.responses import HTMLResponse, JSONResponse
from datetime import datetime
import sqlite3
import json

app = FastAPI()

# ─────────────────────────────────────────────────────────────
# SQLite persistence
# ─────────────────────────────────────────────────────────────
DB_PATH = "finzo.db"

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    c = conn.cursor()
    c.execute("""
        CREATE TABLE IF NOT EXISTS config (
            key   TEXT PRIMARY KEY,
            value TEXT
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS goals (
            name   TEXT PRIMARY KEY,
            target REAL,
            saved  REAL DEFAULT 0
        )
    """)
    conn.commit()
    conn.close()

init_db()

# ── Helpers ───────────────────────────────────────────────────
def set_config(key, value):
    conn = get_db()
    conn.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
                 (key, json.dumps(value)))
    conn.commit()
    conn.close()

def get_config(key, default=None):
    conn = get_db()
    row = conn.execute("SELECT value FROM config WHERE key=?", (key,)).fetchone()
    conn.close()
    return json.loads(row["value"]) if row else default

def get_spent():
    return get_config("spent", {"Food": 0, "Shopping": 0, "Travel": 0})

def set_spent(spent):
    set_config("spent", spent)

def get_category_budget():
    return get_config("category_budget", {"Food": 0, "Shopping": 0, "Travel": 0})

def get_meta():
    return get_config("meta", {"xp": 0, "streak": 0, "badges": []})

def set_meta(meta):
    set_config("meta", meta)

# ─────────────────────────────────────────────────────────────
# Setup Income
# ─────────────────────────────────────────────────────────────
@app.post("/setup-income")
def setup_income(income: float):
    savings = income * 0.2
    needs   = income * 0.5
    wants   = income * 0.3

    set_config("income",          income)
    set_config("needs",           needs)
    set_config("wants",           wants)
    set_config("monthly_savings", savings)
    set_config("category_budget", {
        "Food":     needs * 0.4,
        "Shopping": wants * 0.5,
        "Travel":   wants * 0.5,
    })
    set_spent({"Food": 0, "Shopping": 0, "Travel": 0})
    set_meta({"xp": 0, "streak": 0, "badges": []})

    conn = get_db()
    conn.execute("DELETE FROM goals")
    conn.commit()
    conn.close()

    return {
        "message": "Income configured successfully",
        "income":  income,
        "needs":   needs,
        "wants":   wants,
        "savings": savings,
    }

# ─────────────────────────────────────────────────────────────
# Add Expense
# ─────────────────────────────────────────────────────────────
@app.post("/add-expense")
def add_expense(category: str, amount: float):
    income = get_config("income")
    if income is None:
        return {"error": "Setup income first"}

    if category not in ["Food", "Shopping", "Travel"]:
        return {"error": "Invalid category"}

    spent = get_spent()
    spent[category] = spent.get(category, 0) + amount
    set_spent(spent)

    cat_budget = get_category_budget()
    limit = cat_budget.get(category, 1)
    risk  = (spent[category] / limit) * 100 if limit > 0 else 0

    meta = get_meta()
    if risk < 50:
        meta["xp"]     = meta.get("xp", 0) + 10
        meta["streak"] = meta.get("streak", 0) + 1
    elif risk < 80:
        meta["xp"]     = meta.get("xp", 0) + 5
        meta["streak"] = 0
    else:
        meta["streak"] = 0
    set_meta(meta)

    return {
        "risk":     round(risk, 2),
        "xp":       meta["xp"],
        "streak":   meta["streak"],
        "category": category,
        "spent":    spent[category],
    }

# ─────────────────────────────────────────────────────────────
# SMS Expense Detection
# ─────────────────────────────────────────────────────────────
@app.post("/sms-expense")
def sms_expense(amount: float = Form(...), merchant: str = Form(...)):
    merchant_lower = merchant.lower()

    if any(k in merchant_lower for k in ["tea", "cafe", "swiggy", "zomato", "food", "restaurant", "hotel", "dhaba"]):
        category = "Food"
    elif any(k in merchant_lower for k in ["uber", "ola", "rapido", "irctc", "travel", "metro", "bus", "train", "flight"]):
        category = "Travel"
    elif any(k in merchant_lower for k in ["amazon", "flipkart", "myntra", "shop", "store", "mall", "mart"]):
        category = "Shopping"
    elif amount < 100:
        category = "Food"
    else:
        category = "Shopping"

    result = add_expense(category, amount)

    return {
        "merchant":          merchant,
        "detected_category": category,
        "expense_result":    result,
    }

# ─────────────────────────────────────────────────────────────
# FIX #12: Create Goal — now uses JSON body, no URL encoding issues
# ─────────────────────────────────────────────────────────────
@app.post("/create-goal")
def create_goal(goal_name: str, target_amount: float):
    conn = get_db()
    try:
        conn.execute(
            "INSERT OR REPLACE INTO goals (name, target, saved) VALUES (?, ?, 0)",
            (goal_name, target_amount)
        )
        conn.commit()
    finally:
        conn.close()

    return {
        "message": "Goal created",
        "goal": {"name": goal_name, "target": target_amount, "saved": 0}
    }

# ─────────────────────────────────────────────────────────────
# Add Saving
# ─────────────────────────────────────────────────────────────
@app.post("/add-saving")
def add_saving(goal_name: str, amount: float):
    conn = get_db()
    row  = conn.execute("SELECT * FROM goals WHERE name=?", (goal_name,)).fetchone()

    if not row:
        conn.close()
        return {"error": "Goal not found"}

    new_saved = row["saved"] + amount
    conn.execute("UPDATE goals SET saved=? WHERE name=?", (new_saved, goal_name))
    conn.commit()
    conn.close()

    progress = (new_saved / row["target"]) * 100 if row["target"] > 0 else 0

    return {
        "goal":             goal_name,
        "saved":            new_saved,
        "target":           row["target"],
        "progress_percent": round(progress, 2),
    }

# ─────────────────────────────────────────────────────────────
# FIX #12: NEW — Get Goals (Flutter loads this on initState)
# ─────────────────────────────────────────────────────────────
@app.get("/get-goals")
def get_goals():
    conn  = get_db()
    rows  = conn.execute("SELECT * FROM goals").fetchall()
    conn.close()

    goals = [{"name": r["name"], "target": r["target"], "saved": r["saved"]} for r in rows]
    return {"goals": goals}

# ─────────────────────────────────────────────────────────────
# FIX #13/#14: NEW — JSON dashboard endpoint (replaces HTML parsing)
# Flutter calls this instead of parsing /ui HTML
# ─────────────────────────────────────────────────────────────
@app.get("/dashboard")
def dashboard():
    income = get_config("income")
    if income is None:
        return {"error": "income_not_set"}

    spent      = get_spent()
    cat_budget = get_category_budget()
    meta       = get_meta()
    needs      = get_config("needs", 0)
    wants      = get_config("wants", 0)

    total_spent      = sum(spent.values())
    spendable        = needs + wants
    remaining_budget = spendable - total_spent

    today            = datetime.now().day
    days_passed      = max(today, 1)
    remaining_days   = max(30 - today, 1)
    daily_spend_rate = total_spent / days_passed
    safe_daily_spend = remaining_budget / remaining_days

    if daily_spend_rate > 0:
        days_until_empty = remaining_budget / daily_spend_rate
        predicted_day    = int(today + days_until_empty)
    else:
        predicted_day = 30

    if predicted_day < 30:
        ai_prediction = f"⚠ At current speed, budget may run out around day {predicted_day}."
    else:
        ai_prediction = "✅ Your spending pace is safe for the full month."

    # Category risk %
    category_risk = {}
    overspending_alert = ""
    for cat in ["Food", "Shopping", "Travel"]:
        s     = spent.get(cat, 0)
        limit = cat_budget.get(cat, 1)
        risk  = (s / limit) * 100 if limit > 0 else 0
        category_risk[cat] = round(risk, 1)
        if risk > 70 and not overspending_alert:
            overspending_alert = f"⚠ {cat} spending is increasing faster than budget."

    return {
        "income":            income,
        "totalSpent":        total_spent,
        "remainingBudget":   round(remaining_budget, 2),
        "safeDailySpend":    round(safe_daily_spend, 2),
        "aiPrediction":      ai_prediction,
        "overspendingAlert": overspending_alert,
        "categorySpent":     spent,
        "categoryRisk":      category_risk,
        "categoryBudget":    cat_budget,
        "xp":                meta.get("xp", 0),
        "streak":            meta.get("streak", 0),
    }

# ─────────────────────────────────────────────────────────────
# Legacy /ui HTML endpoint (kept for compatibility)
# ─────────────────────────────────────────────────────────────
@app.get("/ui", response_class=HTMLResponse)
def ui():
    data = dashboard()
    if "error" in data:
        return HTMLResponse("<h2>Please setup income first</h2>")

    spent      = data["categorySpent"]
    cat_budget = data["categoryBudget"]
    cat_risk   = data["categoryRisk"]

    category_html = ""
    for cat in ["Food", "Shopping", "Travel"]:
        s     = spent.get(cat, 0)
        limit = cat_budget.get(cat, 1)
        risk  = cat_risk.get(cat, 0)
        color = "red" if risk > 80 else "orange" if risk > 50 else "green"
        label = "High Risk" if risk > 80 else "Medium Risk" if risk > 50 else "Low Risk"
        category_html += f"""
        <div style='margin-bottom:15px;'>
            <strong>{cat}</strong> — ₹{s} / ₹{limit}<br>
            <span style='color:{color};'>{risk}% ({label})</span>
            <div style='background:#eee;height:8px;border-radius:5px;margin-top:5px;'>
                <div style='width:{min(risk,100)}%;background:{color};height:8px;border-radius:5px;'></div>
            </div>
        </div>"""

    conn       = get_db()
    goals_rows = conn.execute("SELECT * FROM goals").fetchall()
    conn.close()

    monthly_save = get_config("monthly_savings", 0)
    goals_html   = ""
    for goal in goals_rows:
        progress      = min((goal["saved"] / goal["target"]) * 100, 100) if goal["target"] > 0 else 0
        remaining_goal = goal["target"] - goal["saved"]
        months_needed  = round(remaining_goal / monthly_save, 1) if monthly_save > 0 else "Unknown"
        goals_html += f"""
        <div style='margin-bottom:15px;'>
            <strong>{goal["name"]}</strong><br>
            ₹{goal["saved"]} / ₹{goal["target"]}
            <div style='background:#eee;height:10px;border-radius:6px;margin-top:5px;'>
                <div style='width:{progress}%;background:green;height:10px;border-radius:6px;'></div>
            </div>
            <small>{round(progress,1)}% complete — {months_needed} months to go</small>
        </div>"""

    xp    = data["xp"]
    plant = "🌱" if xp < 30 else "🌿" if xp < 70 else "🌳" if xp < 120 else "🌲" if xp < 200 else "🌴"
    stage = "Seed" if xp < 30 else "Sprout" if xp < 70 else "Young Tree" if xp < 120 else "Strong Tree" if xp < 200 else "Money Tree"
    size  = 70 if xp < 30 else 90 if xp < 70 else 120 if xp < 120 else 150 if xp < 200 else 180

    html = f"""<html><head><title>Finzo</title></head><body>
<h1>🌱 Finzo Financial Growth</h1>
<div style="font-size:{size}px;">{plant}</div><h2>{stage}</h2>
<h3>AI Spending Prediction</h3><p>{data["aiPrediction"]}</p>
<h3>Overspending Alert</h3><p>{data["overspendingAlert"] or "No risky spending detected."}</p>
<h3>Savings Goals</h3>{goals_html or "No goals created yet"}
<h3>Budget Overview</h3>
<p>Total Spent: ₹{data["totalSpent"]}</p>
<p>Remaining Budget: ₹{data["remainingBudget"]}</p>
<p>Safe Daily Spend: ₹{data["safeDailySpend"]}</p>
<h3>Expense Tracker</h3>{category_html}
</body></html>"""
    return HTMLResponse(content=html)