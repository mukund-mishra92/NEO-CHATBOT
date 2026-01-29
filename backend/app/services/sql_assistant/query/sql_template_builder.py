class SQLTemplateBuilder:
    def build(self, frame, join_path_map, schema_graph):
        select_parts = []

        select_parts.extend(frame.metrics)
        select_parts.extend(frame.group_by)

        sql = f"SELECT {', '.join(select_parts)} FROM {frame.base_table}"

        # 🔥 Multi-level JOIN injection
        for path in join_path_map.values():
            for i in range(len(path) - 1):
                left, right = path[i], path[i + 1]
                fk = schema_graph.get_fk(left, right)

                sql += f" JOIN {right} ON {left}.{fk['child']} = {right}.{fk['parent']}"

        if frame.filters:
            sql += " WHERE " + " AND ".join(frame.filters)

        if frame.group_by:
            sql += " GROUP BY " + ", ".join(frame.group_by)

        if frame.order_by:
            sql += " ORDER BY " + ", ".join(frame.order_by)

        if frame.limit:
            sql += f" LIMIT {frame.limit}"

        return sql
