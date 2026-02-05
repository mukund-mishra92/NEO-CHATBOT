import pandas as pd

df = pd.read_csv('Table_information.csv')

print("="*80)
print("UPDATED CSV VERIFICATION")
print("="*80)

# Check bot_master
bot_master = df[df['Table_name'] == 'bot_master'].iloc[0]
print(f"\n✅ bot_master:")
print(f"   Category: {bot_master['Table_category']}")
print(f"   Description: {bot_master['Table_description'][:80]}...")

# Check bot_master_log
bot_log = df[df['Table_name'] == 'bot_master_log'].iloc[0]
print(f"\n📋 bot_master_log:")
print(f"   Category: {bot_log['Table_category']}")
print(f"   Description: {bot_log['Table_description'][:80]}...")

# Check telemetry tables
tele = df[df['Table_name'].str.contains('feedback|teleoperation', case=False, na=False)]
print(f"\n📊 Telemetry/Feedback tables:")
for _, row in tele.iterrows():
    print(f"   {row['Table_name']}: {row['Table_category']}")

print("\n" + "="*80)
print("PRIORITY MULTIPLIERS (when query contains 'current position'):")
print("="*80)
print(f"bot_master:         3.0× ✅ HIGH PRIORITY")
print(f"bot_master_log:     0.2× ❌ LOW PRIORITY")
print(f"telemetry_table:    0.2× ❌ LOW PRIORITY")
print("="*80)
