"""
Text Utilities for Diagnostic Support
Handles text cleaning, normalization, and parsing
"""

import pandas as pd
import re
from typing import List


def clean_text(text: str) -> str:
    """
    Remove special characters and clean text
    
    Args:
        text: Raw text input
    
    Returns:
        Cleaned and normalized text
    """
    if pd.isna(text) or not isinstance(text, str):
        return ""
    
    # Normalize quotes, dashes, bullets, non-breaking spaces
    replacements = {
        '\u2018': "'", '\u2019': "'", '\u201C': '"', '\u201D': '"',  # curly quotes
        '\u2013': '-', '\u2014': '-',                                # en/em dashes
        '\u00A0': ' ',                                               # non-breaking space
        '\u2022': ' ', '\u00B7': ' ', '\u25CF': ' ',                # bullets: • · ●
    }
    for k, v in replacements.items():
        text = text.replace(k, v)

    # Remove remaining unknown replacement chars
    text = re.sub(r'[\uFFFD\u0000]', '', text)

    # Collapse whitespace
    text = re.sub(r'\s+', ' ', text)
    return text.strip()


def parse_solution_steps(solution_text: str) -> List[str]:
    """
    Parse solution text into individual steps
    Supports numbered lists, bullets, and multi-line formats
    
    Args:
        solution_text: Raw solution text from CSV
    
    Returns:
        List of individual step strings
    
    Examples:
        "1. Step one\n2. Step two" → ["Step one", "Step two"]
        "• First\n• Second" → ["First", "Second"]
    """
    if not solution_text or pd.isna(solution_text):
        return []
    
    # Clean the text
    solution_text = clean_text(str(solution_text))
    
    # Try bullet characters first
    bullet_split = re.split(r'(?:\n|\r|\s){0,}\u2022|\u00B7|\*|-\s+', solution_text)
    bullet_steps = [s.strip() for s in bullet_split if isinstance(s, str) and s.strip()]
    if len(bullet_steps) > 1:
        return bullet_steps

    # Try different patterns for numbered steps
    patterns = [
        r'(?:^|\n)(\d+)\.\s*([^\n]+)',            # 1. Step text
        r'(?:^|\n)Step\s*(\d+):\s*([^\n]+)',      # Step 1: text
        r'(?:^|\n)(\d+)\)\s*([^\n]+)',            # 1) Step text
    ]
    
    steps = []
    for pattern in patterns:
        matches = re.findall(pattern, solution_text, re.MULTILINE | re.IGNORECASE)
        if matches:
            steps = [step_text.strip() for _, step_text in matches]
            break
    
    # If no numbered pattern found, try splitting by newlines
    if not steps:
        lines = [line.strip() for line in re.split(r'[\n\r]+', solution_text) if line.strip()]
        if len(lines) > 1:
            steps = lines
        else:
            # Single step solution
            steps = [solution_text] if solution_text else []
    
    return steps


def parse_sql_queries(sql_text: str) -> List[str]:
    """
    Parse SQL query text into individual queries
    Handles multiple queries separated by semicolons or blank lines
    
    Args:
        sql_text: Raw SQL text from CSV
    
    Returns:
        List of individual SQL query strings
    
    Examples:
        "SELECT * FROM a; SELECT * FROM b" → ["SELECT * FROM a", "SELECT * FROM b"]
    """
    if not sql_text or pd.isna(sql_text):
        return []
    
    # Normalize quotes/dashes
    raw = str(sql_text)
    raw = raw.replace('\u2018', "'").replace('\u2019', "'")
    raw = raw.replace('\u201C', '"').replace('\u201D', '"')
    raw = raw.replace('\u2013', '-').replace('\u2014', '-')
    raw = raw.replace('\r', '\n')

    # Split by semicolon first
    parts = []
    for chunk in raw.split(';'):
        cleaned = clean_text(chunk)
        if cleaned:
            parts.append(cleaned)

    # If no semicolons, split by double newlines
    if len(parts) <= 1:
        parts = [clean_text(x) for x in re.split(r'\n\s*\n+', raw) if clean_text(x)]
    
    queries = [p for p in parts if p]
    return queries
