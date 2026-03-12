from typing import Tuple, Dict
from .synonym_resolver import SynonymResolver
from .entity_resolver import EntityResolver


class QueryPreprocessor:
    """
    Runs normalization steps before SQL generation.
    """

    def __init__(self):
        self.synonym_resolver = SynonymResolver()
        self.entity_resolver = EntityResolver()

    def process(self, question: str) -> Tuple[str, Dict[str, str]]:
        """
        Correct processing order:
        1. Extract entities from raw question
        2. Substitute canonical IDs
        3. Apply synonym normalization
        """

        # Step 1: entity extraction from raw question
        entities = self.entity_resolver.resolve(question)

        # Step 2: substitute canonical entity IDs
        substituted = self.entity_resolver.substitute(question, entities)

        # Step 3: synonym normalization (safe stage)
        final_question = self.synonym_resolver.normalize(substituted)

        return final_question, entities

