from fastapi import FastAPI, Form
from fastapi.responses import HTMLResponse
from datetime import datetime

app = FastAPI()

# -------------------------------
# In-memory storage
# -------------------------------
user_budget = {
    "xp": 0,
    "streak": 0,
    "badges": [],
    "daily_bonus_given": False,
    "goals": []
}

# -------------------------------
# Setup Income
# -------------------------------
@app.post("/setup-income")
def setup_income(income: float):

    savings = income * 0.2
    needs = income * 0.5
    wants = income * 0.3

    user_budget["income"] = income
    user_budget["needs"] = needs
    user_budget["wants"] = wants
    user_budget["monthly_savings"] = savings

    user_budget["category_budget"] = {
        "Food": needs * 0.4,
        "Shopping": wants * 0.5,
        "Travel": wants * 0.5
    }

    user_budget["spent"] = {
        "Food": 0,
        "Shopping": 0,
        "Travel": 0
    }

    user_budget["xp"] = 0
    user_budget["streak"] = 0
    user_budget["badges"] = []
    user_budget["daily_bonus_given"] = False
    user_budget["goals"] = []

    return {"message": "Income configured successfully"}


# -------------------------------
# Add Expense
# -------------------------------
@app.post("/add-expense")
def add_expense(category: str, amount: float):

    if "income" not in user_budget:
        return {"error": "Setup income first"}

    if category not in user_budget["spent"]:
        return {"error": "Invalid category"}

    user_budget["spent"][category] += amount

    spent = user_budget["spent"][category]
    limit = user_budget["category_budget"][category]

    risk = (spent / limit) * 100

    if risk < 50:
        user_budget["xp"] += 10
        user_budget["streak"] += 1
    elif risk < 80:
        user_budget["xp"] += 5
        user_budget["streak"] = 0
    else:
        user_budget["streak"] = 0

    return {"risk": round(risk, 2), "xp": user_budget["xp"]}


# -------------------------------
# SMS Expense Detection API
# -------------------------------
@app.post("/sms-expense")
def sms_expense(amount: float = Form(...), merchant: str = Form(...)):

    merchant_lower = merchant.lower()

    # Simple merchant AI detection
    if "tea" in merchant_lower or "cafe" in merchant_lower:
        category = "Food"

    elif "uber" in merchant_lower or "ola" in merchant_lower:
        category = "Travel"

    elif "amazon" in merchant_lower or "flipkart" in merchant_lower:
        category = "Shopping"

    elif amount < 100:
        category = "Food"

    else:
        category = "Shopping"

    result = add_expense(category, amount)

    return {
        "merchant": merchant,
        "detected_category": category,
        "expense_result": result
    }


# -------------------------------
# Create Savings Goal
# -------------------------------
@app.post("/create-goal")
def create_goal(goal_name: str, target_amount: float):

    goal = {
        "name": goal_name,
        "target": target_amount,
        "saved": 0
    }

    user_budget["goals"].append(goal)

    return {"message": "Goal created", "goal": goal}


# -------------------------------
# Add Saving to Goal
# -------------------------------
@app.post("/add-saving")
def add_saving(goal_name: str, amount: float):

    for goal in user_budget["goals"]:

        if goal["name"] == goal_name:

            goal["saved"] += amount

            progress = (goal["saved"] / goal["target"]) * 100

            return {
                "goal": goal_name,
                "saved": goal["saved"],
                "progress_percent": round(progress, 2)
            }

    return {"error": "Goal not found"}


# -------------------------------
# UI Dashboard
# -------------------------------
@app.get("/ui", response_class=HTMLResponse)
def ui():

    if "income" not in user_budget:
        return HTMLResponse("<h2>Please setup income in /docs first</h2>")

    xp = user_budget["xp"]

    total_spent = sum(user_budget["spent"].values())
    spendable = user_budget["needs"] + user_budget["wants"]

    necessities_spent = user_budget["spent"]["Food"]
    discretionary_spent = user_budget["spent"]["Shopping"] + user_budget["spent"]["Travel"]

    if total_spent == 0:
        vital_score = 100
    else:
        vital_score = (necessities_spent / total_spent) * 100

    vital_score = round(vital_score, 2)

    if vital_score >= 70:
        vitality_status = "Excellent Financial Health"
        vitality_color = "green"
    elif vital_score >= 50:
        vitality_status = "Balanced Spending"
        vitality_color = "orange"
    else:
        vitality_status = "High Discretionary Spending"
        vitality_color = "red"

    score = 100
    category_html = ""
    all_safe = True
    overspending_warning = ""

    for category in user_budget["spent"]:

        spent = user_budget["spent"][category]
        limit = user_budget["category_budget"][category]
        risk = (spent / limit) * 100

        if risk > 80:
            score -= 20
            color = "red"
            label = "High Risk"
            all_safe = False
        elif risk > 50:
            score -= 10
            color = "orange"
            label = "Medium Risk"
            all_safe = False
        else:
            color = "green"
            label = "Low Risk"

        if risk > 70 and overspending_warning == "":
            overspending_warning = f"Warning: Your {category} spending is increasing faster than your budget."

        category_html += f"""
        <div style='margin-bottom:15px;'>
            <strong>{category}</strong> — ₹{spent} / ₹{limit}<br>
            <span style='color:{color};'>{round(risk,1)}% ({label})</span>
            <div style='background:#eee;height:8px;border-radius:5px;margin-top:5px;'>
                <div style='width:{min(risk,100)}%;background:{color};height:8px;border-radius:5px;'></div>
            </div>
        </div>
        """

    score = max(score, 0)

    today = datetime.now().day
    days_passed = max(today, 1)

    daily_spend_rate = total_spent / days_passed
    remaining_budget = spendable - total_spent

    if daily_spend_rate > 0:
        days_until_empty = remaining_budget / daily_spend_rate
        predicted_day = int(today + days_until_empty)
    else:
        predicted_day = 30

    if predicted_day < 30:
        ai_prediction = f"⚠ At current spending speed, budget may run out around day {predicted_day}."
    else:
        ai_prediction = "✅ Your spending pace is safe for the full month."

    goals_html = ""

    for goal in user_budget["goals"]:

        progress = (goal["saved"] / goal["target"]) * 100
        progress = min(progress,100)

        remaining_goal = goal["target"] - goal["saved"]
        monthly_save = user_budget.get("monthly_savings",0)

        if monthly_save > 0:
            months_needed = round(remaining_goal / monthly_save,1)
        else:
            months_needed = "Unknown"

        goals_html += f"""
        <div style='margin-bottom:15px;'>
            <strong>{goal["name"]}</strong><br>
            ₹{goal["saved"]} / ₹{goal["target"]}
            <div style='background:#eee;height:10px;border-radius:6px;margin-top:5px;'>
                <div style='width:{progress}%;background:green;height:10px;border-radius:6px;'></div>
            </div>
            <small>{round(progress,1)}% complete</small><br>
            <small>Estimated completion: {months_needed} months</small>
        </div>
        """

    if xp < 30:
        plant = "🌱"
        stage = "Seed"
        size = 70
    elif xp < 70:
        plant = "🌿"
        stage = "Sprout"
        size = 90
    elif xp < 120:
        plant = "🌳"
        stage = "Young Tree"
        size = 120
    elif xp < 200:
        plant = "🌲"
        stage = "Strong Tree"
        size = 150
    else:
        plant = "🌴"
        stage = "Money Tree"
        size = 180

    remaining_days = max(30 - today, 1)
    safe_daily_spend = remaining_budget / remaining_days

    growth_percent = min((xp / 200) * 100, 100)

    html = f"""
<html>
<head>
<title>Finzo Growth System</title>
</head>
<body>

<h1>🌱 Finzo Financial Growth</h1>

<div style="font-size:{size}px;">{plant}</div>
<h2>{stage}</h2>

<h3>Financial Vitality Score</h3>
<h2 style="color:{vitality_color};">{vital_score}%</h2>

<h3>AI Spending Prediction</h3>
<p>{ai_prediction}</p>

<h3>Overspending Alert</h3>
<p>{overspending_warning if overspending_warning else "No risky spending detected."}</p>

<h3>Savings Goals</h3>
{goals_html if goals_html else "No goals created yet"}

<h3>Budget Overview</h3>
<p>Total Spent: ₹{total_spent}</p>
<p>Remaining Budget: ₹{remaining_budget}</p>
<p>Safe Daily Spend: ₹{round(safe_daily_spend,2)}</p>

<h3>Expense Tracker</h3>
{category_html}

</body>
</html>
"""

    return HTMLResponse(content=html)