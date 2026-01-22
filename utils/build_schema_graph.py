import os
import json
from pathlib import Path
from dotenv import load_dotenv

from sqlalchemy import create_engine, inspect
import networkx as nx


# =====================================================
# PATH & ENV LOADING
# =====================================================

ROOT_DIR = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT_DIR / "backend" / ".env"

if not ENV_PATH.exists():
    raise RuntimeError(
        f"❌ .env file not found at expected path: {ENV_PATH}"
    )

load_dotenv(dotenv_path=ENV_PATH)


# =====================================================
# DATABASE CONFIG
# =====================================================

DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT", "3306")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_NAME = os.getenv("DB_NAME")

if not all([DB_HOST, DB_USER, DB_NAME]):
    raise RuntimeError("❌ Missing required DB config in .env")

DB_URL = (
    f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}"
    f"@{DB_HOST}:{DB_PORT}/{DB_NAME}"
)


# =====================================================
# SCHEMA GRAPH BUILDER
# =====================================================

class SchemaGraphBuilder:
    def __init__(self, engine):
        self.engine = engine
        self.inspector = inspect(engine)
        self.graph = nx.DiGraph()

        self.schema = {
            "tables": {},
            "primary_keys": {},
            "foreign_keys": [],
            "indexes": {},
            "cardinality": {},
            "join_paths": {}
        }

    # -----------------------------
    # CORE EXTRACTION
    # -----------------------------

    def extract_tables_columns(self):
        for table in self.inspector.get_table_names():
            cols = self.inspector.get_columns(table)
            self.schema["tables"][table] = [
                {
                    "name": c["name"],
                    "type": str(c["type"]),
                    "nullable": c["nullable"]
                }
                for c in cols
            ]

    def extract_primary_keys(self):
        for table in self.inspector.get_table_names():
            pk = self.inspector.get_pk_constraint(table)
            self.schema["primary_keys"][table] = pk.get(
                "constrained_columns", []
            )

    def add_all_tables_as_nodes(self):
        """
        🔥 CRITICAL FIX:
        Add ALL tables as graph nodes
        (even those without foreign keys)
        """
        for table in self.inspector.get_table_names():
            self.graph.add_node(table)

    def extract_foreign_keys(self):
        for table in self.inspector.get_table_names():
            for fk in self.inspector.get_foreign_keys(table):
                if not fk["referred_table"]:
                    continue

                fk_entry = {
                    "child_table": table,
                    "child_columns": fk["constrained_columns"],
                    "parent_table": fk["referred_table"],
                    "parent_columns": fk["referred_columns"]
                }

                self.schema["foreign_keys"].append(fk_entry)

                self.graph.add_edge(
                    table,
                    fk["referred_table"],
                    child_columns=fk["constrained_columns"],
                    parent_columns=fk["referred_columns"]
                )

    def extract_indexes(self):
        for table in self.inspector.get_table_names():
            self.schema["indexes"][table] = self.inspector.get_indexes(table)

    # -----------------------------
    # DERIVED METADATA
    # -----------------------------

    def derive_cardinality(self):
        for fk in self.schema["foreign_keys"]:
            child = fk["child_table"]
            parent = fk["parent_table"]

            child_pk = set(self.schema["primary_keys"].get(child, []))
            fk_cols = set(fk["child_columns"])

            cardinality = (
                "one-to-one" if fk_cols == child_pk else "many-to-one"
            )

            self.schema["cardinality"][f"{child}->{parent}"] = cardinality

    def derive_join_paths(self, max_depth=4):
        tables = list(self.schema["tables"].keys())

        for src in tables:
            for dst in tables:
                if src == dst:
                    continue

                # Extra safety (should not trigger now)
                if src not in self.graph or dst not in self.graph:
                    continue

                try:
                    path = nx.shortest_path(self.graph, src, dst)
                    if len(path) <= max_depth:
                        self.schema["join_paths"][f"{src}->{dst}"] = path
                except nx.NetworkXNoPath:
                    continue

    # -----------------------------
    # BUILD PIPELINE
    # -----------------------------

    def build(self):
        self.extract_tables_columns()
        self.extract_primary_keys()
        self.add_all_tables_as_nodes()   # 🔥 FIX APPLIED HERE
        self.extract_foreign_keys()
        self.extract_indexes()
        self.derive_cardinality()
        self.derive_join_paths()
        return self.schema


# =====================================================
# MAIN RUNNER
# =====================================================

def main():
    print("🔄 Building schema graph...")

    engine = create_engine(DB_URL)
    builder = SchemaGraphBuilder(engine)
    schema_graph = builder.build()

    output_dir = ROOT_DIR / "data" / "database"
    output_dir.mkdir(parents=True, exist_ok=True)

    output_file = output_dir / "schema_graph.json"

    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(schema_graph, f, indent=2)

    print(f"✅ Schema graph saved to: {output_file}")


if __name__ == "__main__":
    main()
