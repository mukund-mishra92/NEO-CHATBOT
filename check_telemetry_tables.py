import pandas as pd

df = pd.read_csv('Table_information.csv')

# Find telemetry/operation tables
tele_tables = df[df['Table_name'].str.contains('tele|oper|sensor|feedback', case=False, na=False)]

print("Tables related to telemetry/operation/sensors:")
print("="*100)
for _, row in tele_tables.iterrows():
    print(f"\nTable: {row['Table_name']}")
    print(f"Description: {row['Table_description']}")
print("\n" + "="*100)

# Check if teleoperation_numeric_data_feedback exists
if 'teleoperation_numeric_data_feedback' in df['Table_name'].values:
    print("\n✅ teleoperation_numeric_data_feedback EXISTS in Table_information.csv")
    row = df[df['Table_name'] == 'teleoperation_numeric_data_feedback'].iloc[0]
    print(f"Description: {row['Table_description']}")
else:
    print("\n❌ teleoperation_numeric_data_feedback NOT FOUND in Table_information.csv")
    print(f"Total tables in CSV: {len(df)}")
