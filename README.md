# TP3 — Query Optimization & Index Use in DuckDB (IMDB dataset)

This lab explores **how DuckDB plans and executes queries**: reading logical/physical plans, understanding **join ordering**, checking **index usage**, and measuring costs with **EXPLAIN ANALYZE** and JSON profiles.

---

## 1) Requirements

- **DuckDB CLI** v0.9+ (static build recommended)
- OS: Linux / macOS / Windows
- (Optional) A browser to open JSON plans in a visualizer

Check versions:
```bash
duckdb --version
```

---

## 2) Repo Layout (suggested)

```
tp3/
├── README.md                  # this file
├── queries.sql                # all SQL used in the lab
├── scripts/                   # optional helper shell/batch scripts
├── explain/                   # JSON outputs from EXPLAIN ANALYZE
└── notes/                     # optional notes or screenshots
```

> Keep the **large data** outside the repo or in a separate storage (add them to `.gitignore`).

---

## 3) Dataset Setup (IMDB for DuckDB)

### Option A — Import a prepackaged DuckDB database
If you have a prepared folder (e.g., `imdb-duck/`) containing DuckDB data:
```sql
-- in DuckDB
IMPORT DATABASE 'imdb-duck';
```

### Option B — CSVs (slower to prepare)
If you only have CSVs, create tables and import with `COPY`:
```sql
CREATE TABLE titles (...);
CREATE TABLE people (...);
CREATE TABLE crew (...);
-- then
COPY titles FROM 'path/to/titles.csv' (HEADER, DELIMITER ',', QUOTE '"');
COPY people FROM 'path/to/people.csv' (HEADER, DELIMITER ',', QUOTE '"');
COPY crew   FROM 'path/to/crew.csv'   (HEADER, DELIMITER ',', QUOTE '"');
```
Verify:
```sql
.tables
.schema
```

---

## 4) Quick Start

Launch DuckDB on a fresh DB file:
```bash
duckdb imdb.db
```

Inspect a trivial query and plan:
```sql
SET explain_output='all';
EXPLAIN SELECT * FROM titles WHERE title_id='tt0024216';
```

Enable runtime profiling to JSON:
```sql
PRAGMA enable_profiling='json';
PRAGMA profiling_output='explain/analyze_titles.json';
EXPLAIN ANALYZE SELECT * FROM titles WHERE title_id='tt0024216';
```
> Open the produced JSON in a plan visualizer to see operator trees, timings, and row counts.

---

## 5) Tasks

### A. Plan Reading (logical vs physical)
Compare the **optimized logical plan** and the **physical plan** for a few queries:
```sql
-- Filter on equality (high selectivity)
EXPLAIN ANALYZE SELECT t.title_id FROM titles t WHERE t.premiered = 1882;

-- Filter on a common year (lower selectivity)
EXPLAIN ANALYZE SELECT t.title_id FROM titles t WHERE t.premiered = 1982;
```
**What to note**
- Scan type (Sequential vs Index Scan).
- Estimated vs actual row counts.
- Operator timings and pipeline breaks.

### B. Index Creation & Effects
Create an index and rerun the same filters:
```sql
CREATE INDEX IF NOT EXISTS idx_titles_premiered ON titles(premiered);
EXPLAIN ANALYZE SELECT t.title_id FROM titles t WHERE t.premiered = 1882;
EXPLAIN ANALYZE SELECT t.title_id FROM titles t WHERE t.premiered = 1982;
```
**Questions to answer**
- When does DuckDB choose an index scan vs a sequential scan?
- How do **selectivity** and **covering** (whether all needed columns are in the index) change the plan?

### C. Join Ordering
Study the join order on three tables:
```sql
SELECT p.person_id, p.name
FROM titles t, people p, crew c
WHERE t.title_id = c.title_id
  AND c.person_id = p.person_id
  AND c.category = 'director'
  AND t.premiered < 1880;
```
Then **force** an order using explicit `JOIN (...)` parenthesization:
```sql
WITH
  t AS (SELECT title_id              FROM titles WHERE premiered < 1880),
  c AS (SELECT title_id, person_id   FROM crew   WHERE category = 'director'),
  p AS (SELECT person_id, name       FROM people)
SELECT p.person_id, p.name
FROM p
JOIN (c JOIN t ON c.title_id = t.title_id)
  ON c.person_id = p.person_id;
```
**What to note**
- Build/Probe roles for hash joins (the **build** side is usually the smaller input).
- Cardinality estimates and how they influence the chosen order.

### D. Subqueries, SEMI JOIN, and Estimates
Compare a subquery with `IN` (often becomes a **SEMI JOIN**) and an explicit join:
```sql
-- Subquery version
SELECT p.person_id, p.name
FROM people p
WHERE p.person_id IN (
  SELECT c.person_id
  FROM crew c
  WHERE c.category='director'
    AND c.title_id IN (
      SELECT t.title_id FROM titles t WHERE t.premiered < 1880
    )
);

-- Explicit joins version
SELECT p.person_id, p.name
FROM people p
JOIN crew   c ON c.person_id = p.person_id AND c.category='director'
JOIN titles t ON t.title_id   = c.title_id  AND t.premiered < 1880;
```
Optionally, experiment with **small `LIMIT` hints** inside subqueries to see how **cardinality estimates** can change plan choices (for learning purposes only).

---

## 6) Exporting Plans & Timing

Produce a JSON per experiment:
```sql
PRAGMA enable_profiling='json';
PRAGMA profiling_output='explain/q_join_1880.json';
EXPLAIN ANALYZE
SELECT p.person_id, p.name
FROM titles t, people p, crew c
WHERE t.title_id=c.title_id AND c.person_id=p.person_id
  AND c.category='director' AND t.premiered<1880;
```
Also try **`EXPLAIN VERBOSE`** to read the textual tree:
```sql
EXPLAIN VERBOSE SELECT ...;
```

---

## 7) Interpreting Results (Checklist)

- **Operator types**: Seq Scan, Index Scan, Hash Join, Filter, Projection.
- **Pipelines**: where do they break (materialization or repartition)?
- **Row counts**: estimated vs actual — any large misestimates?
- **Hash Join sides**: which side is Build vs Probe? Is the build side small?
- **Index**: used or skipped? If skipped, is selectivity too low or columns not covered?
- **Order of joins**: is the chosen order consistent with selectivity (smallest first)?

---

## 8) Troubleshooting

- **No index usage** even after `CREATE INDEX`  
  - The predicate may be too unselective; a sequential scan can be cheaper.
  - The query might need non-index columns → not a covering access.
  - Try equality filters or narrower ranges to see a difference.

- **CSV import issues**  
  - Check delimiter/quote; verify column types (especially INT vs VARCHAR).

- **JSON not written**  
  - Ensure `PRAGMA enable_profiling='json'` is set **before** the target query.
  - Ensure the target directory (e.g., `explain/`) exists and is writable.

---

## 9) Deliverables (suggested)

- `queries.sql` with all tested queries.
- 3–6 representative **JSON** profiles in `explain/`.
- A short **report** summarizing observations:
  - When indexes help and why.
  - Example of a good vs bad join order.
  - Differences between subquery `IN` (SEMI JOIN) and explicit joins.

---

## 10) Run Script (optional)

Create `scripts/profile.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
DB="${1:-imdb.db}"
duckdb "$DB" -c "PRAGMA enable_profiling='json'; PRAGMA profiling_output='explain/q1.json'; EXPLAIN ANALYZE SELECT t.title_id FROM titles t WHERE t.premiered=1882;"
duckdb "$DB" -c "PRAGMA enable_profiling='json'; PRAGMA profiling_output='explain/q_join.json'; EXPLAIN ANALYZE SELECT p.person_id, p.name FROM titles t, people p, crew c WHERE t.title_id=c.title_id AND c.person_id=p.person_id AND c.category='director' AND t.premiered<1880;"
echo 'Profiles saved in explain/'
```

Make it executable:
```bash
chmod +x scripts/profile.sh
```

---

## 11) License

MIT for original scripts in this folder. Dataset licenses remain with their respective owners.
