class ConfidenceEvaluator:

    def compute(self, generation_result, execution_result):

        llm_conf = generation_result.confidence
        exec_conf = 1.0 if execution_result.row_count > 0 else 0.4

        return (llm_conf * 0.7) + (exec_conf * 0.3)
