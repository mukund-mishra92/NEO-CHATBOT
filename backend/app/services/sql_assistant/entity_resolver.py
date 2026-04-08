import re
from typing import Dict


class EntityResolver:
    """
    Resolves user-provided entity references into canonical DB formats.
    Based on the logic from the previous integrated assistant.
    """

    def resolve(self, question: str) -> Dict[str, str]:
        entities = {}

        # BOT: "bot 1" → BOT-0001, "bot FRK001" → FRK001, "bot-id BOT-0003" → BOT-0003
        bot_numeric = re.search(r"\bbot\s*[-_ ]?\s*(\d{1,4})\b", question, re.IGNORECASE)
        bot_alpha = re.search(
            r"\bbot[-_ ](?:id\s*[-:= ]?\s*)?([A-Z]{2,}[-_ ]?\d{2,6})\b", question, re.IGNORECASE
        )
        if bot_numeric:
            num = int(bot_numeric.group(1))
            entities["BOT_ID"] = f"BOT-{num:04d}"
        elif bot_alpha:
            entities["BOT_ID"] = bot_alpha.group(1).upper().replace(" ", "-")

        # STATION: "station 3" → STATION-0003, "station ST-05" → ST-05
        station_numeric = re.search(r"\bstation\s*[-_ ]?\s*(\d{1,4})\b", question, re.IGNORECASE)
        station_alpha = re.search(
            r"\bstation[-_ ](?:id\s*[-:= ]?\s*)?([A-Z]{1,}[-_ ]?\d{2,6})\b", question, re.IGNORECASE
        )
        if station_numeric:
            num = int(station_numeric.group(1))
            entities["STATION_ID"] = f"STATION-{num:04d}"
        elif station_alpha:
            entities["STATION_ID"] = station_alpha.group(1).upper().replace(" ", "-")

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
