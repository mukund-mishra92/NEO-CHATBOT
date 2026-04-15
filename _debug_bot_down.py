"""Debug: why 'minutes' hits KPI but 'hours' doesn't."""
import sys, warnings, logging
warnings.filterwarnings("ignore")
sys.path.insert(0, "backend")
logging.disable(logging.CRITICAL)

from app.services.sql_assistant.kpi_resolver import DashboardKPIResolver
from app.services.sql_assistant.match_utils import strip_matching_noise, strip_time_noise_for_embedding
import numpy as np

r = DashboardKPIResolver()
logging.disable(logging.NOTSET)
logging.basicConfig(level=logging.CRITICAL)

q1 = "How many minutes bot 27 was down today in frk..?"
q2 = "how many hours bot 27 was down today in frk"

for qi, (q, label) in enumerate([(q1, "minutes"), (q2, "hours")]):
    mq = strip_matching_noise(q)
    eq = strip_time_noise_for_embedding(q)
    e = r._get_question_embedding(eq)

    print(f"\nQ{qi+1} ({label}): {q}")
    print(f"  match_question: '{mq}'")
    print(f"  embed_question: '{eq}'")

    scored = []
    for kpi in r.kpis:
        kw = r._score_match(mq, kpi)
        kpi_emb = r.kpi_embeddings.get(kpi.id)
        if e is not None and kpi_emb is not None:
            emb = float(np.dot(e, kpi_emb))
            hyb = r.EMBEDDING_WEIGHT * emb + r.KEYWORD_WEIGHT * kw
        else:
            emb = None
            hyb = kw
        scored.append((hyb, kw, emb, kpi.kpi_name, kpi.id))

    scored.sort(reverse=True)
    print(f"  Top 8 (hybrid scores):")
    for hyb, kw, emb, name, kid in scored[:8]:
        emb_str = f"{emb:.4f}" if emb is not None else "N/A"
        flag = " <<<" if hyb >= 0.55 else ""
        print(f"    hyb={hyb:.4f}  kw={kw:.4f}  emb={emb_str}  [{kid}] {name}{flag}")

# Now run full resolve with logging
print("\n" + "=" * 80)
print("FULL RESOLVE RESULTS:")
print("=" * 80)

for qi, (q, label) in enumerate([(q1, "minutes"), (q2, "hours")]):
    logging.disable(logging.NOTSET)
    handler = logging.StreamHandler()
    handler.setLevel(logging.DEBUG)
    handler.setFormatter(logging.Formatter('  [%(levelname)s] %(message)s'))
    kpi_logger = logging.getLogger('app.services.sql_assistant.kpi_resolver')
    kpi_logger.setLevel(logging.DEBUG)
    kpi_logger.addHandler(handler)

    result = r.resolve(q)

    kpi_logger.removeHandler(handler)
    logging.disable(logging.CRITICAL)

    logging.disable(logging.NOTSET)
    if result:
        tc = result.top_candidates[:3] if result.top_candidates else []
        tc_str = " | ".join(f"{c['kpi_name']}={c['score']:.4f}" for c in tc)
        print(f"\nQ{qi+1} ({label}): KPI={result.kpi_name} score={result.match_score:.4f}  [{tc_str}]")
    else:
        print(f"\nQ{qi+1} ({label}): None (no match)")
    logging.disable(logging.CRITICAL)

logging.disable(logging.NOTSET)
