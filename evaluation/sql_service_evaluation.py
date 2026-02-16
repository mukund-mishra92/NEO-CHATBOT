from backend.app.services.sql_assistant.sql_assistant import SQLAssistantService

import json
import time

def evaluate(version_label):
    assistant = SQLAssistantService()

    with open("data/sql_evaluation_data.json") as f:
        tests = json.load(f)

    results = []

    for test in tests:
        start = time.time()
        response = assistant.run(test["question"])
        latency = time.time() - start

        result = {
            "id": test["id"],
            "success": response.success,
            "latency": latency,
            "retry_count": response.retry_count,
            "used_tables": response.used_tables,
        }

        results.append(result)

    return results

print(evaluate("v1.0"))
