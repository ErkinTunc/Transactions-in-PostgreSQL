# TP4 — Transactions in PostgreSQL

Hands-on lab to explore row/table locks, 2PL, isolation levels (READ COMMITTED, REPEATABLE READ, SERIALIZABLE), phantom tuples, deadlocks, and FK-related locks using a minimal shop schema (`produit`, `panier`). Exercises Q1–Q25 are summarized below with runnable hints. Based on the provided TP PDF.

## Prerequisites

- Linux with sudo
- PostgreSQL (≥ 12 recommended)
- Two terminals (we’ll run **two concurrent sessions** with autocommit off)

## Install & Setup

```bash
# 1) Install PostgreSQL
sudo apt install postgresql

# 2) Start PostgreSQL service
sudo systemctl start postgresql

# 3) Open psql as postgres user
sudo -u postgres psql
```

Inside `psql` (Session 1):

```sql
-- 4) Create lab database
CREATE DATABASE tp4;

-- 5) Connect
\c tp4

-- Disable autocommit in psql client
\set AUTOCOMMIT off

-- Enable pgrowlocks extension (for inspecting row locks)
CREATE EXTENSION IF NOT EXISTS pgrowlocks;
```

From another terminal (outside psql):

```bash
# 7) Load schema + seed data (expects create.sql to be in repo root)
sudo -u postgres psql tp4 < create.sql
```

Repeat the `\c tp4` and `\set AUTOCOMMIT off` in **Session 2** as well.

## Database Schema (minimal)

```
PRODUIT(id, nom, prix)
PANIER(client, produit)
```

Use physical tuple id for lock inspection:

```sql
SELECT ctid, * FROM produit;
SELECT * FROM pgrowlocks('produit');
```

Row-level explicit locks during reads/writes:

```sql
-- Shared read lock
SELECT ctid, * FROM produit WHERE nom='banane' FOR SHARE;

-- Exclusive lock for update
SELECT ctid, * FROM produit WHERE nom='pomme' FOR UPDATE;
```

## How to Work the Exercises

- Use **one transaction per session**; commit/rollback as directed.
- If an operation blocks in one session, **continue in the other**.

### Exercise 1 — Manual Strict 2PL

Follow each scenario’s sequence. Examples:

**Q1 Concurrent read**
- S1: `SELECT * FROM produit;`
- S2: `SELECT prix FROM produit WHERE nom='banane';`
- S1: `COMMIT;`
- S2: `COMMIT;`

**Q2 Non-repeatable read**
- S1: read `pomme`
- S2: `UPDATE produit SET prix=6 WHERE nom='pomme';`
- S1: read `pomme` again
- S2: `ROLLBACK;`
- S1: `ROLLBACK;`
Show what changed and why it’s non-repeatable. Use `FOR SHARE/UPDATE` to enforce 2PL.

**Q3 Dirty read (should be prevented with proper locking)**
- S1: `UPDATE produit SET prix=6 WHERE nom='pomme';` (uncommitted)
- S2: read `pomme`
- S1: `ROLLBACK;`
- S2: `ROLLBACK;`
Discuss visibility under different isolation levels later.

**Q4 Dirty write**
- Conflicting updates on `carotte` then rollbacks. Observe blocking/ordering.

**Q5 Deadlock**
- Cross-updates on `pomme` and `carotte` in opposite order across sessions to trigger a deadlock. Capture the error and locks seen via `pgrowlocks`.

**Q6** Propose a read+read+update+update pattern that deadlocks with 2PL (e.g., both sessions take `FOR SHARE` on different rows, then both try `FOR UPDATE` on the other row).

### Exercise 2 — Phantom Tuples & 2PL Limits

**Q7 Phantom insert**
- S1: `SELECT * FROM produit WHERE prix >= 5 FOR SHARE;`
- S2: `INSERT INTO produit(nom, prix) VALUES ('kaki', 6); COMMIT;`
- S1: repeat the `SELECT` and show the phantom.

**Q8** Is the schedule serializable? Explain the phantom issue.

**Q9** Show non-repeatable read using an `UPDATE` instead of `INSERT`.

**Q10** Both sessions check if client 0 has a vegetable; if yes, each adds a different one then commit; else rollback. Analyze serializability and whether row locks suffice.

**Q11** Mitigate with **table-level locks** (`LOCK TABLE ... IN SHARE/EXCLUSIVE MODE`) and test.

### Exercise 3 — Isolation: READ COMMITTED (default)

- Each statement sees a snapshot at its own start, plus the txn’s own writes.

**Q12–Q15** Predict and verify: dirty read/write prevention, non-repeatable reads, phantoms under READ COMMITTED. Inspect locks with `pgrowlocks`.

**Q16** Try cross-updates to trigger deadlock; check whether other errors can be produced at this level.

**Q17** Scenario:
1) S1: `UPDATE produit SET prix = prix + 1;`
2) S2: `DELETE FROM produit WHERE prix = 5;`
3) S1: `COMMIT;`
4) S2: `COMMIT;`
Explain outcomes by tracing which rows each statement saw and locked.

### Exercise 4 — Isolation: REPEATABLE READ

- Snapshot fixed at txn start (first statement), plus the txn’s own writes.

**Q18–Q19** Verify which earlier cases disappear vs. now raise serialization errors. Compare frequency of errors vs READ COMMITTED.

**Q20** Basket scenario with two fruits and concurrent deletions producing anomaly under REPEATABLE READ. Demonstrate.

**Q21** Re-run under SERIALIZABLE; confirm anomaly is prevented.

### Exercise 5 — Foreign Keys & Locks

- Compare the four explicit row locks used by Postgres and observe FK behavior during modifications.

**Q22–Q25**
- Modify a `panier` row; observe locks on both tables.
- Concurrently: change a product’s price while editing a referencing `panier` entry—explain if/why allowed.
- Try deleting a product while a `panier` references it; explain.
- Try changing a product’s id while referenced; explain.

## Useful Commands

```sql
-- Show current transaction isolation level
SHOW TRANSACTION ISOLATION LEVEL;

-- Switch isolation level for next transaction
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- Inspect locks (extension + table)
CREATE EXTENSION IF NOT EXISTS pgrowlocks;
SELECT * FROM pgrowlocks('produit');
SELECT * FROM pgrowlocks('panier');

-- See physical tuple id
SELECT ctid, * FROM produit;
```

## Repository Structure (suggested)

```
.
├─ create.sql        # DDL + seed data (used by setup step)
├─ README.md         # This file
└─ notes/            # Your observations per question (optional)
```

## Workflow

1) Prepare both sessions (autocommit off).
2) For each question: run exactly the listed sequence; if one session blocks, continue in the other.
3) Observe locks (`pgrowlocks`), isolation effects, and outcomes; record findings.

## Troubleshooting

- If `pgrowlocks` missing: `CREATE EXTENSION IF NOT EXISTS pgrowlocks;` in `tp4`.
- If statements don’t block as expected, confirm autocommit is off and both are in a transaction.
- Ensure `create.sql` matches the schema and contains initial tuples for `produit`/`panier`.
