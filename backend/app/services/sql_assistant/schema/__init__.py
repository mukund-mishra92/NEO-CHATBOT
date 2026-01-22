"""
Schema Package
Database schema introspection, validation, and discovery
"""

from .parser import SchemaParser
from .validator import SchemaValidator
from .discovery import SchemaDiscovery

__all__ = [
    'SchemaParser',
    'SchemaValidator',
    'SchemaDiscovery'
]

__version__ = '2.0.0'
