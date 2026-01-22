"""
CSV Loader for Diagnostic Support
Handles loading and parsing support logs from CSV files
"""

import pandas as pd
import logging
from pathlib import Path
from typing import List, Dict, Any

from .text_utils import clean_text

logger = logging.getLogger(__name__)


class CSVLoader:
    """Loads bot-level and station-level support logs from CSV files"""
    
    def __init__(self, support_logs_path: Path):
        """
        Initialize CSV loader
        
        Args:
            support_logs_path: Path to support_logs directory
        """
        self.support_logs_path = support_logs_path
        self.bot_level_issues: List[Dict[str, Any]] = []
        self.station_level_issues: List[Dict[str, Any]] = []
    
    def load_all(self) -> tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """
        Load both bot-level and station-level CSV files
        
        Returns:
            Tuple of (bot_level_issues, station_level_issues)
        """
        self._load_bot_level()
        self._load_station_level()
        return self.bot_level_issues, self.station_level_issues
    
    def _load_bot_level(self):
        """Load Bot Level Issues CSV"""
        try:
            csv_path = self.support_logs_path / "NEO Support Logs(Bot Level).csv"
            if not csv_path.exists():
                logger.warning(f"Bot-level CSV not found: {csv_path}")
                return
            
            # Try different encodings
            for encoding in ['utf-8', 'latin1', 'cp1252', 'iso-8859-1']:
                try:
                    df = pd.read_csv(csv_path, skiprows=1, encoding=encoding)
                    logger.info(f"✅ Loaded bot CSV with {encoding} encoding")
                    break
                except UnicodeDecodeError:
                    continue
            else:
                logger.error(f"❌ Could not decode bot CSV with any encoding")
                return
            
            for _, row in df.iterrows():
                if pd.notna(row.iloc[0]):  # Check if S NO exists
                    issue = {
                        'id': int(row.iloc[0]) if pd.notna(row.iloc[0]) else 0,
                        'problem': clean_text(str(row.iloc[1])),
                        'severity': clean_text(str(row.iloc[2])),
                        'solution': clean_text(str(row.iloc[3])),
                        'sql_query': clean_text(str(row.iloc[4])),
                        'outcome': clean_text(str(row.iloc[5])),
                        'reported_to_dev': clean_text(str(row.iloc[6])),
                        'type': 'BOT_LEVEL'
                    }
                    
                    if issue['problem']:  # Only add if problem exists
                        self.bot_level_issues.append(issue)
            
            logger.info(f"✅ Loaded {len(self.bot_level_issues)} bot-level issues")
        
        except Exception as e:
            logger.error(f"❌ Error loading bot-level CSV: {e}")
            import traceback
            traceback.print_exc()
    
    def _load_station_level(self):
        """Load Station Level Issues CSV"""
        try:
            csv_path = self.support_logs_path / "NEO Support Logs(Station Level ).csv"
            if not csv_path.exists():
                logger.warning(f"Station-level CSV not found: {csv_path}")
                return
            
            # Try different encodings
            for encoding in ['utf-8', 'latin1', 'cp1252', 'iso-8859-1']:
                try:
                    df = pd.read_csv(csv_path, skiprows=1, encoding=encoding)
                    logger.info(f"✅ Loaded station CSV with {encoding} encoding")
                    break
                except UnicodeDecodeError:
                    continue
            else:
                logger.error(f"❌ Could not decode station CSV with any encoding")
                return
            
            for _, row in df.iterrows():
                if pd.notna(row.iloc[0]):
                    issue = {
                        'id': int(row.iloc[0]) if pd.notna(row.iloc[0]) else 0,
                        'problem': clean_text(str(row.iloc[1])),
                        'severity': clean_text(str(row.iloc[2])),
                        'scenario': clean_text(str(row.iloc[3])),
                        'solution': clean_text(str(row.iloc[4])),
                        'sql_query': clean_text(str(row.iloc[5])),
                        'outcome': clean_text(str(row.iloc[6])),
                        'reported_to_dev': clean_text(str(row.iloc[7])),
                        'type': 'STATION_LEVEL'
                    }
                    
                    if issue['problem']:
                        self.station_level_issues.append(issue)
            
            logger.info(f"✅ Loaded {len(self.station_level_issues)} station-level issues")
        
        except Exception as e:
            logger.error(f"❌ Error loading station-level CSV: {e}")
            import traceback
            traceback.print_exc()
