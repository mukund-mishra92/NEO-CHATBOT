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
        # Step 1: synonym normalization
        normalized = self.synonym_resolver.normalize(question)

        # Step 2: entity extraction
        entities = self.entity_resolver.resolve(normalized)

        # Step 3: entity substitution
        final_question = self.entity_resolver.substitute(normalized, entities)

        return final_question, entities
