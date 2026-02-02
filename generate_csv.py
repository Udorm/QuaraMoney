import csv
import random
from datetime import datetime, timedelta
import os

def generate_transactions(filename="transactions.csv", months=18):
    # Setup
    end_date = datetime.now()
    start_date = end_date - timedelta(days=months*30)
    
    headers = ["Date", "Amount", "Category", "Note", "Wallet"]
    
    categories = {
        "Food": {"min": 5, "max": 20, "freq": 0.8}, # Daily
        "Transport": {"min": 2, "max": 15, "freq": 0.6},
        "Groceries": {"min": 50, "max": 150, "freq": 0.15}, # Weekly-ish
        "Entertainment": {"min": 20, "max": 100, "freq": 0.1},
        "Health": {"min": 10, "max": 50, "freq": 0.05},
        "Shopping": {"min": 30, "max": 200, "freq": 0.05},
        "Utilities": {"min": 50, "max": 150, "freq": 0.03}, # Monthly
        "Rent": {"min": 1000, "max": 1000, "freq": 0.033}, # Monthly
    }
    
    income_categories = {
        "Salary": {"amount": 5000, "day": 25},
        "Freelance": {"min": 200, "max": 1000, "freq": 0.05}
    }
    
    wallets = ["Cash", "Credit Card", "Bank Account"]
    
    rows = []
    
    current_date = start_date
    while current_date <= end_date:
        date_str = current_date.strftime("%Y-%m-%d")
        
        # Monthly Income (Salary)
        if current_date.day == 25:
             rows.append([
                date_str,
                income_categories["Salary"]["amount"],
                "Salary",
                "Monthly Salary",
                "Bank Account"
            ])
            
        # Daily Expenses
        daily_transactions = random.randint(0, 5)
        for _ in range(daily_transactions):
            cat_name = random.choice(list(categories.keys()))
            cat_data = categories[cat_name]
            
            # Rent logic separate
            if cat_name == "Rent":
                 if current_date.day == 1:
                     rows.append([
                        date_str,
                        -1 * cat_data["min"],
                        "Rent",
                        "Monthly Rent",
                        "Bank Account"
                    ])
                 continue

            if cat_name == "Utilities":
                 if current_date.day == 10:
                     rows.append([
                        date_str,
                        -1 * random.uniform(cat_data["min"], cat_data["max"]),
                        "Utilities",
                        "Electric/Water",
                        "Bank Account"
                    ])
                 continue
                 
            
            # Regular random expenses
            if random.random() < cat_data["freq"]:
                amount = random.uniform(cat_data["min"], cat_data["max"])
                wallet = random.choice(wallets)
                note = f"{cat_name} expense"
                
                rows.append([
                    date_str,
                    f"-{amount:.2f}",
                    cat_name,
                    note,
                    wallet
                ])
                
        # Random Income
        if random.random() < income_categories["Freelance"]["freq"]:
             amount = random.uniform(income_categories["Freelance"]["min"], income_categories["Freelance"]["max"])
             rows.append([
                date_str,
                f"{amount:.2f}",
                "Freelance",
                "Side project",
                "Bank Account"
            ])
        
        current_date += timedelta(days=1)
        
    # Write to CSV
    with open(filename, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(headers)
        writer.writerows(rows)
        
    print(f"Generated {len(rows)} transactions in {filename}")

if __name__ == "__main__":
    generate_transactions()
