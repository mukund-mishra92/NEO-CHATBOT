"""
Intent Package
Query intent classification and temporal scope detection
"""

from .classifier import IntentClassifier
from .temporal import TemporalClassifier

__all__ = [
    'IntentClassifier',
    'TemporalClassifier'
]

__version__ = '2.0.0'
