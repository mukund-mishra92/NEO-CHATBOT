"""
Sync Table Descriptions from NEO_Table_Summary 1.csv to Table_information.csv
Updates descriptions and adds Table_category and Description_verified columns
"""

import pandas as pd
import os
from pathlib import Path

# Paths
SOURCE_CSV = Path("data/database/NEO_Table_Summary 1.csv")
TARGET_CSV = Path("data/database/Table_information.csv")

def categorize_table(table_name: str, description: str) -> str:
    """Categorize table based on name and description patterns"""
    name_lower = table_name.lower()
    desc_lower = description.lower()
    
    # Bot master tables (LIVE state)
    if 'bot_master' == name_lower and 'dashboard' not in name_lower:
        return 'bot_master'
    
    # Station master tables (LIVE state)
    if name_lower in ['hw_station_master', 'station_master']:
        return 'station_master'
    
    # Other master tables (reference/configuration)
    if 'master' in name_lower and 'log' not in name_lower:
        if 'dashboard' in name_lower or 'config' in name_lower:
            return 'config_master'
        elif 'wave' in name_lower:
            return 'wave_master'
        elif 'bin' in name_lower:
            return 'bin_master'
        elif 'order' in name_lower:
            return 'order_master'
        else:
            return 'config_master'
    
    # Log tables (historical data)
    if 'log' in name_lower or 'history' in name_lower or 'archive' in name_lower:
        return 'log_table'
    
    # Telemetry tables (sensor/real-time data)
    if 'telemetry' in name_lower or 'teleoperation' in name_lower or 'sensor' in name_lower:
        return 'telemetry_table'
    
    # Transaction tables (business operations)
    if any(word in name_lower for word in ['transaction', 'payload', 'operation', 'wave']):
        return 'transaction_table'
    
    # Default
    return 'general_table'


def sync_descriptions():
    """Sync descriptions from source to target CSV"""
    
    if not SOURCE_CSV.exists():
        print(f"❌ Source file not found: {SOURCE_CSV}")
        return False
    
    if not TARGET_CSV.exists():
        print(f"❌ Target file not found: {TARGET_CSV}")
        return False
    
    print(f"📖 Reading source: {SOURCE_CSV}")
    source_df = pd.read_csv(SOURCE_CSV)
    
    print(f"📖 Reading target: {TARGET_CSV}")
    target_df = pd.read_csv(TARGET_CSV)
    
    # Create lookup dictionary from source
    source_lookup = {}
    for _, row in source_df.iterrows():
        table_name = row['Table_name']
        source_lookup[table_name] = {
            'description': row['Table_description'],
            'columns': row['Table_columns(Data type)'],
            'primary_key': row['Primary_key']
        }
    
    # Update target with source descriptions
    updated_count = 0
    new_count = 0
    
    for idx, row in target_df.iterrows():
        table_name = row['Table_name']
        
        if table_name in source_lookup:
            source_data = source_lookup[table_name]
            
            # Check if description is different
            if row['Table_description'] != source_data['description']:
                target_df.at[idx, 'Table_description'] = source_data['description']
                updated_count += 1
                print(f"  ✓ Updated: {table_name}")
            
            # Update columns and primary key too
            target_df.at[idx, 'Table_columns(Data type)'] = source_data['columns']
            target_df.at[idx, 'Primary_key'] = source_data['primary_key']
    
    # Add Table_category column if not exists
    if 'Table_category' not in target_df.columns:
        print("\n📋 Adding Table_category column...")
        target_df['Table_category'] = target_df.apply(
            lambda row: categorize_table(row['Table_name'], row['Table_description']),
            axis=1
        )
    
    # Add Description_verified column if not exists
    if 'Description_verified' not in target_df.columns:
        print("📋 Adding Description_verified column...")
        target_df['Description_verified'] = target_df['Table_name'].apply(
            lambda name: 'YES' if name in source_lookup else 'NO'
        )
    
    # Save updated target
    print(f"\n💾 Saving updated file: {TARGET_CSV}")
    target_df.to_csv(TARGET_CSV, index=False)
    
    print(f"\n✅ Sync completed!")
    print(f"   - Updated descriptions: {updated_count}")
    print(f"   - Total tables: {len(target_df)}")
    print(f"   - Verified tables: {len([t for t in target_df['Table_name'] if t in source_lookup])}")
    
    return True


if __name__ == "__main__":
    print("=" * 60)
    print("🔄 Syncing Table Descriptions")
    print("=" * 60)
    sync_descriptions()
    print("=" * 60)
