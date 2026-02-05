"""
Quick fix: Add Table_category column to existing Table_information.csv
This will activate the priority system immediately without full regeneration
"""

import pandas as pd
from pathlib import Path

def add_categories_to_existing_csv():
    """Add Table_category column to existing CSV based on table name patterns"""
    
    csv_path = Path("Table_information.csv")
    df = pd.read_csv(csv_path)
    
    print(f"📊 Current CSV: {len(df)} tables")
    print(f"Columns: {list(df.columns)}")
    
    if 'Table_category' in df.columns:
        print("✅ Table_category already exists!")
        return
    
    # Categorize each table
    def categorize(table_name: str) -> str:
        """Same logic as schema_generator_service.py"""
        name_lower = table_name.lower()
        
        # HIGH PRIORITY - Master tables
        if 'bot' in name_lower and 'master' in name_lower and 'log' not in name_lower:
            return 'bot_master'
        if 'station' in name_lower and 'master' in name_lower:
            return 'station_master'
        if 'wave' in name_lower and 'master' in name_lower:
            return 'wave_master'
        if 'bin' in name_lower and ('master' in name_lower or 'info' in name_lower):
            return 'bin_master'
        if 'order' in name_lower and 'master' in name_lower:
            return 'order_master'
        
        # LOW PRIORITY - Telemetry/sensor data
        if any(x in name_lower for x in ['teleoperation', 'feedback', 'telemetry', 'sensor']):
            return 'telemetry_table'
        
        # LOW PRIORITY - Logs/archives
        if any(x in name_lower for x in ['_log', '_archive', '_history']):
            return 'log_table'
        
        # MEDIUM - Transactions
        if any(x in name_lower for x in ['wave', 'order', 'pick', 'put']) and 'master' not in name_lower:
            return 'transaction_table'
        
        # MEDIUM - Configuration
        if 'master' in name_lower or 'config' in name_lower:
            return 'config_master'
        
        return 'general_table'
    
    # Add category column
    df['Table_category'] = df['Table_name'].apply(categorize)
    
    # Add verification status (all existing are verified from NEO_Table_Summary 1.csv)
    df['Description_verified'] = 'YES'
    
    # Save with new columns
    df.to_csv(csv_path, index=False, encoding='utf-8')
    
    print(f"\n✅ Updated CSV with categories!")
    print(f"New columns: {list(df.columns)}")
    
    # Show category distribution
    print(f"\n📊 Category Distribution:")
    category_counts = df['Table_category'].value_counts()
    for category, count in category_counts.items():
        print(f"   {category}: {count} tables")
    
    # Show critical tables
    print(f"\n🔑 Critical Tables:")
    for table in ['bot_master', 'bot_master_log', 'hw_station_master']:
        if table in df['Table_name'].values:
            row = df[df['Table_name'] == table].iloc[0]
            print(f"   {table} → {row['Table_category']}")
    
    print(f"\n✅ Table_information.csv updated successfully!")
    print(f"⚡ Priority system is now ACTIVE - restart server to apply")

if __name__ == "__main__":
    add_categories_to_existing_csv()
