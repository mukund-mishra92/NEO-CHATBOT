"""
Report Formatter for Diagnostic Support
Handles formatting diagnostic reports and statistics
"""

from typing import Dict, List, Any


class ReportFormatter:
    """Formats diagnostic reports and statistics"""
    
    def __init__(self, bot_level_issues: List[Dict[str, Any]], station_level_issues: List[Dict[str, Any]]):
        """
        Initialize report formatter
        
        Args:
            bot_level_issues: Bot-level issues
            station_level_issues: Station-level issues
        """
        self.bot_level_issues = bot_level_issues
        self.station_level_issues = station_level_issues
    
    def format_diagnostic_report(self, issue: Dict[str, Any]) -> str:
        """
        Format issue into readable diagnostic report
        
        Args:
            issue: Issue dictionary
        
        Returns:
            Formatted text report with ASCII box
        """
        report = f"""
╔═══════════════════════════════════════════════════════════════
║ DIAGNOSTIC REPORT - {issue['type'].replace('_', ' ')}
╠═══════════════════════════════════════════════════════════════

📌 PROBLEM:
{issue['problem']}

⚠️ SEVERITY: {issue['severity']}

🔧 SOLUTION STEPS:
{issue['solution']}
"""
        
        if issue.get('scenario'):
            report += f"""
📋 SCENARIO:
{issue['scenario']}
"""
        
        if issue.get('sql_query') and issue['sql_query'].strip():
            report += f"""
💻 SQL QUERY:
{issue['sql_query']}
"""
        
        if issue.get('outcome'):
            report += f"""
✅ EXPECTED OUTCOME:
{issue['outcome']}
"""
        
        if issue.get('reported_to_dev', '').upper() == 'Y':
            report += f"""
⚡ NOTE: This issue has been escalated to developers
"""
        
        report += "\n╚═══════════════════════════════════════════════════════════════\n"
        
        return report
    
    def get_statistics(self) -> Dict[str, Any]:
        """
        Get diagnostic support statistics
        
        Returns:
            Statistics dictionary with counts and breakdowns
        """
        all_issues = self.bot_level_issues + self.station_level_issues
        
        high_severity = sum(1 for i in all_issues if i['severity'].lower() == 'high')
        medium_severity = sum(1 for i in all_issues if i['severity'].lower() == 'medium')
        low_severity = sum(1 for i in all_issues if i['severity'].lower() == 'low')
        
        with_sql = sum(1 for i in all_issues if i.get('sql_query', '').strip())
        reported_to_dev = sum(1 for i in all_issues if i.get('reported_to_dev', '').upper() == 'Y')
        
        return {
            'total_issues': len(all_issues),
            'bot_level_count': len(self.bot_level_issues),
            'station_level_count': len(self.station_level_issues),
            'severity': {
                'high': high_severity,
                'medium': medium_severity,
                'low': low_severity
            },
            'with_sql_solutions': with_sql,
            'reported_to_developers': reported_to_dev
        }
