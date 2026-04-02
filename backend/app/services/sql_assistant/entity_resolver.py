import re
from typing import Dict


class EntityResolver:
    """
    Resolves user-provided entity references into canonical DB formats.
    Based on the logic from the previous integrated assistant.
    """

    def resolve(self, question: str) -> Dict[str, str]:
        entities = {}

        # BOT: bot 1 → BOT-0001
        bot_match = re.search(r"\bbot\s*[-_ ]?\s*(\d{1,4})\b", question, re.IGNORECASE)
        if bot_match:
            num = int(bot_match.group(1))
            entities["BOT_ID"] = f"BOT-{num:04d}"

        # STATION: station 3 → STATION-0003
        station_match = re.search(r"\bstation\s*[-_ ]?\s*(\d{1,4})\b", question, re.IGNORECASE)
        if station_match:
            num = int(station_match.group(1))
            entities["STATION_ID"] = f"STATION-{num:04d}"

        # WAVE: wave 12 → WAVE-000012
        wave_match = re.search(r"\bwave\s*[-_ ]?\s*(\d{1,6})\b", question, re.IGNORECASE)
        if wave_match:
            num = int(wave_match.group(1))
            entities["WAVE_ID"] = f"WAVE-{num:06d}"

        # ORDER: order 45 → ORD-000045
        order_match = re.search(r"\border\s*[-_ ]?\s*(\d{1,6})\b", question, re.IGNORECASE)
        if order_match:
            num = int(order_match.group(1))
            entities["ORDER_ID"] = f"ORD-{num:06d}"

        # BIN: bin 23 → BIN-0023
        bin_match = re.search(r"\bbin\s*[-_ ]?\s*(\d{1,6})\b", question, re.IGNORECASE)
        if bin_match:
            num = int(bin_match.group(1))
            entities["BIN_ID"] = f"BIN-{num:04d}"

        return entities

    def substitute(self, question: str, entities: Dict[str, str]) -> str:
        """
        Replace user references with canonical entity IDs.
        """
        result = question

        for key, value in entities.items():

            if key == "BOT_ID":
                result = re.sub(r"\bbot\s*[-_ ]?\d+\b", value, result, flags=re.IGNORECASE)

            elif key == "STATION_ID":
                result = re.sub(r"\bstation\s*[-_ ]?\d+\b", value, result, flags=re.IGNORECASE)

            elif key == "WAVE_ID":
                result = re.sub(r"\bwave\s*[-_ ]?\d+\b", value, result, flags=re.IGNORECASE)

            elif key == "ORDER_ID":
                result = re.sub(r"\border\s*[-_ ]?\d+\b", value, result, flags=re.IGNORECASE)

            elif key == "BIN_ID":
                result = re.sub(r"\bbin\s*[-_ ]?\d+\b", value, result, flags=re.IGNORECASE)

        return result
