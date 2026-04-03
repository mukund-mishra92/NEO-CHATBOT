from decimal import Decimal
from datetime import datetime, date


class SQLFormatter:
    """
    Formats SQL results into structured markdown output.
    Handles:
        - Normal tabular data
        - Zero rows
        - Large datasets (preview + message)
    """

    DISPLAY_LIMIT = 500  # max rows to send (safety cap for very large results)
    PAGE_SIZE = 10        # frontend shows this many per page

    # ----------------------------------------------------------
    # SAFE VALUE CONVERSION
    # ----------------------------------------------------------
    def _safe_str(self, value):
        if value is None:
            return ""
        if isinstance(value, Decimal):
            return str(float(value))
        if isinstance(value, (datetime, date)):
            return value.isoformat()
        return str(value)

    # ----------------------------------------------------------
    # TABLE RENDERING
    # ----------------------------------------------------------
    def _format_table(self, rows):
        headers = list(rows[0].keys())
        display_rows = rows[:self.DISPLAY_LIMIT]
        total = len(rows)

        header_row = "| " + " | ".join(headers) + " |"
        separator = "| " + " | ".join(["---"] * len(headers)) + " |"

        data_rows = []
        for row in display_rows:
            values = [self._safe_str(row.get(col, "")) for col in headers]
            data_rows.append("| " + " | ".join(values) + " |")

        table_md = "\n".join([header_row, separator] + data_rows)

        if total > self.DISPLAY_LIMIT:
            table_md += (
                f"\n\nShowing first {self.DISPLAY_LIMIT} of {total} rows.\n"
                f"You can refine filters to reduce results."
            )

        return table_md

    # ----------------------------------------------------------
    # MAIN FORMATTER
    # ----------------------------------------------------------
    def format(self, question, sql, execution_result, confidence):

        row_count = execution_result.row_count
        rows = execution_result.rows or []

        # Case 2: No data
        if row_count == 0:
            table_section = (
                "No data found for this query in the current database.\n\n"
                "Possible reasons:\n"
                "- Table exists but has no records\n"
                "- Filters may be too restrictive\n"
                "- Data not loaded in this environment"
            )

        # Case 1: Data exists (normal)
        else:
            table_section = self._format_table(rows)

        return (
            f"### SQL Query\n"
            f"```sql\n{sql}\n```\n\n"
            f"Rows returned: {row_count}\n\n"
            f"{table_section}"
        )
