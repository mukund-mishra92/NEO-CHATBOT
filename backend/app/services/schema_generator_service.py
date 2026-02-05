"""
Schema Generator Service - Generate Table_information.csv from live database
Uses OpenAI extended thinking mode (o1) for intelligent descriptions
"""

import logging
import time
import pymysql
import pandas as pd
from typing import Dict, List, Any, Optional, Tuple
from pathlib import Path
from openai import OpenAI

logger = logging.getLogger(__name__)


class SchemaGeneratorService:
    """
    Generate and manage Table_information.csv from live database
    - Extracts schema from MySQL INFORMATION_SCHEMA
    - Uses OpenAI o1 (extended thinking) for intelligent descriptions
    - Provides validation and editing capabilities
    """
    
    def __init__(self, db_config: Dict[str, Any], openai_api_key: str):
        """Initialize schema generator
        
        Args:
            db_config: Database connection config (host, port, user, password, database)
            openai_api_key: OpenAI API key for generating descriptions
        """
        self.db_config = db_config
        self.client = OpenAI(api_key=openai_api_key)
        logger.info("✅ Schema Generator Service initialized")
    
    def _get_connection(self, retry_attempts: int = 3, connect_timeout: int = 20):
        """Get database connection with retry logic"""
        last_error = None
        
        for attempt in range(1, retry_attempts + 1):
            try:
                if attempt > 1:
                    logger.info(f"🔄 DB connection attempt {attempt}/{retry_attempts}...")
                
                conn = pymysql.connect(
                    host=self.db_config['host'],
                    port=self.db_config['port'],
                    user=self.db_config['user'],
                    password=self.db_config['password'],
                    database=self.db_config['database'],
                    charset='utf8mb4',
                    connect_timeout=connect_timeout,
                    read_timeout=30,
                    write_timeout=30,
                    cursorclass=pymysql.cursors.DictCursor
                )
                
                if attempt > 1:
                    logger.info(f"✅ DB connection successful on attempt {attempt}")
                
                return conn
                
            except Exception as e:
                last_error = e
                if attempt < retry_attempts:
                    wait_time = 1.0 * attempt
                    logger.warning(f"⚠️ DB connection failed (attempt {attempt}/{retry_attempts}): {e}")
                    time.sleep(wait_time)
        
        raise last_error
    
    def extract_schema_from_db(self) -> List[Dict[str, Any]]:
        """Extract complete schema information from database
        
        Returns:
            List of dicts with table schema information
        """
        logger.info("📊 Extracting schema from database...")
        
        conn = self._get_connection()
        try:
            with conn.cursor() as cur:
                # Get all tables with basic info
                cur.execute(f"""
                    SELECT 
                        TABLE_NAME,
                        TABLE_COMMENT,
                        TABLE_ROWS,
                        CREATE_TIME,
                        UPDATE_TIME
                    FROM INFORMATION_SCHEMA.TABLES
                    WHERE TABLE_SCHEMA = %s
                    AND TABLE_TYPE = 'BASE TABLE'
                    ORDER BY TABLE_NAME
                """, (self.db_config['database'],))
                
                tables = cur.fetchall()
                logger.info(f"✅ Found {len(tables)} tables in database")
                
                schema_data = []
                
                for table in tables:
                    table_name = table['TABLE_NAME']
                    logger.info(f"   📋 Processing table: {table_name}")
                    
                    # Get columns for this table
                    cur.execute("""
                        SELECT 
                            COLUMN_NAME,
                            COLUMN_TYPE,
                            IS_NULLABLE,
                            COLUMN_KEY,
                            COLUMN_DEFAULT,
                            EXTRA,
                            COLUMN_COMMENT
                        FROM INFORMATION_SCHEMA.COLUMNS
                        WHERE TABLE_SCHEMA = %s AND TABLE_NAME = %s
                        ORDER BY ORDINAL_POSITION
                    """, (self.db_config['database'], table_name))
                    
                    columns = cur.fetchall()
                    
                    # Format columns as "COLUMN_NAME(TYPE)"
                    column_list = []
                    primary_keys = []
                    
                    for col in columns:
                        col_name = col['COLUMN_NAME']
                        col_type = col['COLUMN_TYPE']
                        column_list.append(f"{col_name}({col_type})")
                        
                        if col['COLUMN_KEY'] == 'PRI':
                            primary_keys.append(col_name)
                    
                    schema_data.append({
                        'Table_name': table_name,
                        'Table_comment': table.get('TABLE_COMMENT', ''),
                        'Table_columns': ', '.join(column_list),
                        'Primary_key': ', '.join(primary_keys) if primary_keys else '',
                        'Table_rows': table.get('TABLE_ROWS', 0),
                        'Create_time': table.get('CREATE_TIME'),
                        'Update_time': table.get('UPDATE_TIME'),
                        'column_details': columns,  # Full column info for AI
                        'table_category': self._categorize_table(table_name, columns)  # NEW
                    })
                
                logger.info(f"✅ Extracted schema for {len(schema_data)} tables")
                return schema_data
                
        finally:
            conn.close()
    
    def _load_verified_descriptions(self, reference_csv_path: Path = None) -> Dict[str, Dict[str, str]]:
        """Load verified table descriptions from reference CSV
        
        Args:
            reference_csv_path: Path to verified CSV (default: data/database/NEO_Table_Summary 1.csv)
            
        Returns:
            Dict mapping table_name to {description, verified: True}
        """
        if reference_csv_path is None:
            # Default to NEO_Table_Summary 1.csv in data/database
            reference_csv_path = Path(__file__).parent.parent.parent.parent / "data" / "database" / "NEO_Table_Summary 1.csv"
        
        verified_descriptions = {}
        
        try:
            if reference_csv_path.exists():
                df = pd.read_csv(reference_csv_path)
                logger.info(f"📚 Loaded {len(df)} verified descriptions from {reference_csv_path.name}")
                
                for _, row in df.iterrows():
                    table_name = row['Table_name']
                    description = row.get('Table_description', '')
                    
                    if description and description.strip():
                        verified_descriptions[table_name] = {
                            'description': description.strip(),
                            'verified': True
                        }
                
                logger.info(f"✅ Found {len(verified_descriptions)} verified table descriptions")
            else:
                logger.warning(f"⚠️ Verified descriptions file not found: {reference_csv_path}")
        
        except Exception as e:
            logger.error(f"❌ Failed to load verified descriptions: {e}")
        
        return verified_descriptions
    
    def _categorize_table(self, table_name: str, columns: List[Dict]) -> str:
        """Categorize table by its purpose and entity type
        
        Returns category like: 'bot_master', 'station_master', 'wave_transaction', etc.
        """
        name_lower = table_name.lower()
        
        # Entity-specific master tables (HIGH PRIORITY for current state queries)
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
        
        # Log/audit tables (LOW PRIORITY for current state, use for history)
        if any(x in name_lower for x in ['_log', '_archive', '_history', 'audit']):
            return 'log_table'
        
        # Telemetry/feedback tables (LOW PRIORITY for business queries)
        if any(x in name_lower for x in ['teleoperation', 'feedback', 'telemetry', 'sensor']):
            return 'telemetry_table'
        
        # Transaction tables (orders, picks, puts, etc.)
        if any(x in name_lower for x in ['order', 'pick', 'put', 'wave', 'shipment']) and 'master' not in name_lower:
            return 'transaction_table'
        
        # Configuration/master tables
        if 'master' in name_lower or 'config' in name_lower:
            return 'config_master'
        
        return 'general_table'
    
    def generate_ai_description(self, table_info: Dict[str, Any], use_extended_thinking: bool = True) -> str:
        """Generate intelligent table description using OpenAI
        
        Args:
            table_info: Table information dict from extract_schema_from_db()
            use_extended_thinking: Use o1 model for deeper analysis (slower but better)
            
        Returns:
            Generated description string
        """
        table_name = table_info['Table_name']
        columns = table_info['column_details']
        existing_comment = table_info.get('Table_comment', '')
        table_category = table_info.get('table_category', 'general_table')
        
        # Build context for AI
        column_details = []
        for col in columns:
            col_str = f"- {col['COLUMN_NAME']} ({col['COLUMN_TYPE']})"
            if col['COLUMN_KEY'] == 'PRI':
                col_str += " [PRIMARY KEY]"
            if col['COLUMN_KEY'] == 'MUL':
                col_str += " [FOREIGN KEY]"
            if col['EXTRA']:
                col_str += f" [{col['EXTRA']}]"
            if col['COLUMN_COMMENT']:
                col_str += f" - {col['COLUMN_COMMENT']}"
            column_details.append(col_str)
        
        prompt = f"""Analyze this database table and generate a concise, informative description (max 200 characters).

DATABASE: NEO Warehouse Management System

TABLE: {table_name}
CATEGORY: {table_category}
EXISTING COMMENT: {existing_comment or 'None'}
ROW COUNT: {table_info.get('Table_rows', 'Unknown')}

COLUMNS:
{chr(10).join(column_details)}

INSTRUCTIONS:
1. Identify the table's purpose and business domain
2. CRITICAL: Note table type clearly:
   - Master tables (bot_master, station_master): PRIMARY source for current entity state
   - Log/archive tables: Historical data, auditing, debugging
   - Telemetry tables: Raw sensor data, low-level diagnostics
   - Transaction tables: Business operations, orders, picks, puts
3. For MASTER tables, emphasize they contain CURRENT/LIVE state
4. For LOG/TELEMETRY tables, emphasize they are for HISTORY/DEBUGGING
5. Highlight 3-6 most important fields that define this table's identity
6. Keep description under 200 characters
7. Use format: "[Type - Purpose]. Key fields: FIELD1, FIELD2, FIELD3."

EXAMPLES:
- bot_master: "Robot master and LIVE state (position, battery, alarms, auto/manual). Key fields: BOT_ID, STATUS, GRIDX, GRIDY, BATTERY."
- bot_master_log: "Log/audit table recording BOT state changes over time. Key fields: BOT_ID, TIMESTAMP, GRIDX, GRIDY."
- teleoperation_numeric_data_feedback: "Telemetry/sensor feedback for low-level bot diagnostics. Key fields: bot_id, axis positions, timestamps."
- alarm_master: "Master/configuration table (alarm definitions). Key fields: ALARM_ID, ALARM_CODE, ALARM_DESCRIPTION."
- wave_master: "Transaction table tracking wave processing. Key fields: WAVE_ID, STATUS, STATION_ID."

EXAMPLES:
- "Master/configuration table. Key fields: ALARM_ID, ALARM_CODE, ALARM_SOURCE, ALARM_DESCRIPTION, ALARM_TYPE."
- "Transaction/operational table tracking order fulfillment. Key fields: ORDER_ID, STATUS, STATION_ID, TIMESTAMP."
- "Log/audit table recording bot movements. Key fields: BOT_ID, GRIDX, GRIDY, TIMESTAMP."

Generate a similar description for {table_name}:"""
        
        try:
            if use_extended_thinking:
                # Use o1 for extended thinking (better quality, slower)
                model = "GPT-5.2"  # or "o1-mini" for faster results
                logger.info(f"   🤖 Generating AI description with extended thinking (o1)...")
            else:
                # Use standard GPT for faster results
                model = "gpt-4o"
                logger.info(f"   🤖 Generating AI description with {model}...")
            
            response = self.client.chat.completions.create(
                model=model,
                messages=[
                    {"role": "user", "content": prompt}
                ],
                max_completion_tokens=300 if use_extended_thinking else 150,
                temperature=0.3
            )
            
            description = response.choices[0].message.content.strip()
            
            # Truncate if too long
            if len(description) > 255:
                description = description[:252] + "..."
            
            logger.info(f"   ✅ Generated description: {description[:80]}...")
            return description
            
        except Exception as e:
            logger.error(f"   ❌ Failed to generate AI description: {e}")
            # Fallback to basic description
            return f"Schema-based summary for '{table_name}'. Key fields: {', '.join([c['COLUMN_NAME'] for c in columns[:6]])}."
    
    def generate_csv(
        self, 
        output_path: Path, 
        use_ai_descriptions: bool = True,
        use_extended_thinking: bool = False,
        batch_size: int = 10
    ) -> Tuple[bool, str, int]:
        """Generate Table_information.csv from database schema
        
        Args:
            output_path: Path to save CSV file
            use_ai_descriptions: Use OpenAI to generate descriptions (default: True)
            use_extended_thinking: Use o1 for better descriptions (slower, default: False)
            batch_size: Process tables in batches to avoid rate limits
            
        Returns:
            Tuple of (success: bool, message: str, table_count: int)
        """
        try:
            logger.info("🚀 Starting schema generation...")
            
            # Extract schema
            schema_data = self.extract_schema_from_db()
            
            if not schema_data:
                return False, "No tables found in database", 0
            
            # Load verified descriptions from reference CSV
            logger.info("📚 Loading verified table descriptions...")
            verified_descriptions = self._load_verified_descriptions()
            
            # Apply descriptions: verified first, then AI generation for unverified
            verified_count = 0
            ai_generated_count = 0
            unverified_tables = []
            
            if use_ai_descriptions:
                for i, table_info in enumerate(schema_data, 1):
                    table_name = table_info['Table_name']
                    
                    # Check if we have verified description
                    if table_name in verified_descriptions:
                        table_info['Table_description'] = verified_descriptions[table_name]['description']
                        table_info['description_verified'] = True
                        verified_count += 1
                        logger.info(f"✅ {i}/{len(schema_data)}: {table_name} - Using VERIFIED description")
                    
                    else:
                        # Generate AI description for unverified tables
                        logger.info(f"🤖 {i}/{len(schema_data)}: {table_name} - Generating AI description (UNVERIFIED)")
                        
                        description = self.generate_ai_description(
                            table_info,
                            use_extended_thinking=use_extended_thinking
                        )
                        
                        table_info['Table_description'] = description
                        table_info['description_verified'] = False
                        ai_generated_count += 1
                        unverified_tables.append(table_name)
                        
                        # Rate limiting for OpenAI API
                        if ai_generated_count % batch_size == 0 and i < len(schema_data):
                            logger.info(f"⏳ Batch complete, waiting 2s to avoid rate limits...")
                            time.sleep(2)
            else:
                # Use existing comments or basic descriptions
                for table_info in schema_data:
                    table_name = table_info['Table_name']
                    
                    # Check verified descriptions even without AI
                    if table_name in verified_descriptions:
                        table_info['Table_description'] = verified_descriptions[table_name]['description']
                        table_info['description_verified'] = True
                        verified_count += 1
                    elif table_info['Table_comment']:
                        table_info['Table_description'] = table_info['Table_comment']
                        table_info['description_verified'] = False
                        unverified_tables.append(table_name)
                    else:
                        table_info['Table_description'] = f"Table: {table_name}"
                        table_info['description_verified'] = False
                        unverified_tables.append(table_name)
            
            # Log summary
            logger.info(f"\n📊 Description Summary:")
            logger.info(f"   ✅ Verified: {verified_count} tables")
            logger.info(f"   🤖 AI Generated: {ai_generated_count} tables")
            logger.info(f"   ⚠️  Unverified: {len(unverified_tables)} tables")
            
            if unverified_tables:
                logger.warning(f"\n⚠️  UNVERIFIED TABLES (need manual verification):")
                for table in unverified_tables[:10]:  # Show first 10
                    logger.warning(f"   - {table}")
                if len(unverified_tables) > 10:
                    logger.warning(f"   ... and {len(unverified_tables) - 10} more")
            
            # Convert to DataFrame with required columns
            df = pd.DataFrame([
                {
                    'Table_name': t['Table_name'],
                    'Table_description': t['Table_description'],
                    'Table_columns(Data type)': t['Table_columns'],
                    'Primary_key': t['Primary_key'],
                    'Table_category': t.get('table_category', 'general_table'),
                    'Description_verified': 'YES' if t.get('description_verified', False) else 'NO'
                }
                for t in schema_data
            ])
            
            # Save to CSV
            output_path.parent.mkdir(parents=True, exist_ok=True)
            df.to_csv(output_path, index=False, encoding='utf-8')
            
            logger.info(f"✅ Schema CSV generated successfully: {output_path}")
            logger.info(f"   📊 Total tables: {len(df)}")
            logger.info(f"   ✅ Verified: {verified_count}")
            logger.info(f"   ⚠️  Unverified: {len(unverified_tables)}")
            
            message = f"Successfully generated schema for {len(df)} tables\n"
            message += f"✅ {verified_count} verified descriptions\n"
            if unverified_tables:
                message += f"⚠️ {len(unverified_tables)} unverified tables (review needed)"
            
            return True, message, len(df)
            
        except Exception as e:
            error_msg = f"Failed to generate schema: {str(e)}"
            logger.error(f"❌ {error_msg}")
            return False, error_msg, 0
    
    def validate_csv(self, csv_path: Path) -> Tuple[bool, str, List[str]]:
        """Validate existing Table_information.csv against live database
        
        Args:
            csv_path: Path to CSV file to validate
            
        Returns:
            Tuple of (valid: bool, message: str, issues: List[str])
        """
        try:
            logger.info(f"🔍 Validating CSV: {csv_path}")
            
            # Read CSV
            df = pd.read_csv(csv_path)
            csv_tables = set(df['Table_name'].tolist())
            
            # Get live schema
            live_schema = self.extract_schema_from_db()
            live_tables = {t['Table_name'] for t in live_schema}
            
            issues = []
            
            # Check for missing tables (in CSV but not in DB)
            missing_in_db = csv_tables - live_tables
            if missing_in_db:
                issues.append(f"Tables in CSV but not in database: {', '.join(sorted(missing_in_db))}")
            
            # Check for new tables (in DB but not in CSV)
            missing_in_csv = live_tables - csv_tables
            if missing_in_csv:
                issues.append(f"New tables in database not in CSV: {', '.join(sorted(missing_in_csv))}")
            
            # Check for schema mismatches
            for table in live_schema:
                if table['Table_name'] in csv_tables:
                    csv_row = df[df['Table_name'] == table['Table_name']].iloc[0]
                    csv_columns = set(csv_row['Table_columns(Data type)'].split(', '))
                    db_columns = set(table['Table_columns'].split(', '))
                    
                    if csv_columns != db_columns:
                        issues.append(f"Column mismatch in {table['Table_name']}")
            
            if issues:
                return False, f"Validation found {len(issues)} issues", issues
            else:
                return True, "CSV is up-to-date with database schema", []
                
        except Exception as e:
            error_msg = f"Validation failed: {str(e)}"
            logger.error(f"❌ {error_msg}")
            return False, error_msg, []
    
    def update_table_description(
        self, 
        csv_path: Path, 
        table_name: str, 
        new_description: str
    ) -> Tuple[bool, str]:
        """Update description for a specific table in CSV
        
        Args:
            csv_path: Path to CSV file
            table_name: Table to update
            new_description: New description text
            
        Returns:
            Tuple of (success: bool, message: str)
        """
        try:
            df = pd.read_csv(csv_path)
            
            if table_name not in df['Table_name'].values:
                return False, f"Table '{table_name}' not found in CSV"
            
            # Update description
            df.loc[df['Table_name'] == table_name, 'Table_description'] = new_description
            
            # Save back to CSV
            df.to_csv(csv_path, index=False, encoding='utf-8')
            
            logger.info(f"✅ Updated description for table: {table_name}")
            return True, f"Successfully updated description for {table_name}"
            
        except Exception as e:
            error_msg = f"Failed to update description: {str(e)}"
            logger.error(f"❌ {error_msg}")
            return False, error_msg
