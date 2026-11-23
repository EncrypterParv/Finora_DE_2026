# Phase 5 Scalability Report (large dataset)

## Method

- **Data:** `large_data.zip` loaded into a new database `mmt_large` with `sql/01_schema.sql`, then `sql/02_load_data.sql` with only `seed_data/` changed to `large_data/`, then `sql/05_indexes.sql` and `ANALYZE`. Session timezone: `ALTER DATABASE mmt_large SET timezone = 'Asia/Kolkata'`. PostgreSQL server settings were not changed.
- **Machine:** team.json records the benchmark laptop as “Devansh Chauhan – Apple M4, 16 GB RAM, macOS 26.4.1” and the server as “PostgreSQL 18.6 (Postgres.app)”. Measured today: CPU `Apple M4`, memory 16 GB, macOS **26.6**, `PostgreSQL 18.6 (Postgres.app) on aarch64-apple-darwin23.6.0, compiled by Apple clang version 15.0.0 (clang-1500.3.9.4), 64-bit`. Same laptop as the baseline/optimized runs; macOS was updated since then (team.json still says the older version), while the hardware and PostgreSQL 18.6 are unchanged.
- **Power:** `pmset -g batt` before loading: “Now drawing from 'Battery Power'  -InternalBattery-0 (id=22151267)	80%; discharging; 14:04 remaining present: true”. Before the final run: “Now drawing from 'Battery Power'”. All large runs were made on battery power.
- **Other software:** a second, separate PostgreSQL server (EDB installer, `/Library/PostgreSQL/18/bin/postgres -D /Library/PostgreSQL/18/data`, port 5432) was running on the laptop, as during the earlier runs; it was left running and idle. Only Postgres.app (port 5433) was benchmarked.
- **Load:** `\copy` of all 12 files took **134.77 s** (wall clock, `/usr/bin/time -p`, includes the script's ANALYZE and checks); `sql/05_indexes.sql` took **11.34 s**; the extra `ANALYZE` took 1.40 s. No `\copy` errors.
- **Benchmark:** `caffeinate -i ./benchmarks/run_benchmark.sh mmt_large large 3 sql/06_optimized_queries.sql` (3 runs per query; the target is the average of 3 runs, README 5.2). The original `queries/workload_30.sql` was not run on large data. The benchmark was run three times in total: run 1 (Mon Nov 23 19:09:48 IST 2026), then the R03 and W02 fixes, run 2, then the R01 fix, run 3 (Mon Nov 23 19:14:33 IST 2026 – Mon Nov 23 19:14:58 IST 2026). `benchmarks/results/large/` holds **run 3**, the final official result; runs 1 and 2 are not in the repo; their key plan lines are quoted in §3 as the “before” evidence. The large benchmark was therefore run **3 times in total (two fix rounds)** and the committed results are the final run.
- **Seed comparison:** the seed column is `benchmarks/results/optimized/summary.csv` from Phase 4. Those seed runs did not have the three Phase 5 index changes.
- **Order of work:** the Phase 5 fixes were added to `sql/05_indexes.sql` *after* the Phase 4 run, so `benchmarks/results/optimized/` (the seed column) was measured without them; the large column includes them.

### Row counts (from the `COPY` lines of the load output)

| Table | Seed rows | Large rows | Large ÷ seed |
|---|---:|---:|---:|
| airports | 16 | 16 | 1.00 |
| airlines | 5 | 5 | 1.00 |
| flights | 13848 | 13848 | 1.00 |
| hotels | 3000 | 60000 | 20.00 |
| room_types | 9000 | 180000 | 20.00 |
| customers | 40000 | 800000 | 20.00 |
| coupons | 30 | 30 | 1.00 |
| bookings | 144792 | 2897285 | 20.01 |
| flight_bookings | 84899 | 1698936 | 20.01 |
| passengers | 163380 | 3272394 | 20.03 |
| hotel_bookings | 59893 | 1198349 | 20.01 |
| hotel_reviews | 15913 | 318847 | 20.04 |

### Integrity checks and data profile on large data (from the load script output)

| Check | Result | What it checks |
|---|---:|---|
| IC1 | 0 | flight_bookings.passengers equals the number of passengers rows for that booking |
| IC2 | 0 | no flight booking was made after its flight departed (bookings.booked_at > flights.departure_at) |
| IC3 | 0 | every booking is in exactly one of flight_bookings / hotel_bookings, never both and never neither |
| IC4 | 0 | booking_type matches the child table (FLIGHT <-> flight_bookings, HOTEL <-> hotel_bookings) |
| IC5 | 10856 | no flight is overbooked: sum(passengers) over non-cancelled bookings <= total_seats |
| IC6 | 0 | hotel_reviews.hotel_id equals the hotel of its booking |
| IC7 | 0 | reviews exist only for COMPLETED bookings and are created on or after check_out |
| IC8 | 0 | coupon used only for a matching booking type (applies_to = 'ALL' or = booking_type) |
| IC9 | 0 | booking date within the coupon's valid_from..valid_to, and discount <= max_discount |
| IC10 | 0 | no booking earlier than the customer's created_at |
| DP1 | 199997 | hotel bookings with guests > rooms * room_types.max_guests |
| DP2 | 373747 | duplicate seat_no on the same flight among non-cancelled bookings |
| DP3 | 27 | passengers with a seat_no whose booking is PENDING_PAYMENT |
| DP4 | 0 | flight_bookings where fare_paid <> bookings.total_amount + bookings.discount |
| DP5 | 10 | flights still SCHEDULED or DELAYED with departure_at before 2026-07-01 00:00+05:30 |

IC5 reports **10856** overbooked flights on the large data (it is 0 on seed, docs/02). The large file has the same 13848 flights as seed but 20.01× the flight bookings, so many flights sell more seats than they have. This is a property of the supplied data, not a load error; the schema does not enforce IC5 (it needs a trigger), so `R01` reports negative “seats left” for such flights. All other ICs are 0.

## 1. Results: all 30 queries

| Query | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Target | Meets target? | If not, what you changed |
|---|---:|---:|---:|---|:---:|---|
| R01 | 0.283 | 0.849 | 3.00 | < 5 ms | Yes | missed in large run 2 (5.501 ms); PHASE 5 FIX: idx_flight_bookings_flight |
| R02 | 0.086 | 0.281 | 3.27 | < 5 ms | Yes | — |
| R03 | 0.169 | 0.708 | 4.19 | < 5 ms | Yes | missed in large run 1 (6.460 ms); PHASE 5 FIX: idx_hotels_city_pool_rating |
| R04 | 0.136 | 1.158 | 8.51 | < 5 ms | Yes | — |
| R05 | 0.053 | 0.063 | 1.19 | < 5 ms | Yes | — |
| R06 | 0.041 | 0.065 | 1.59 | < 5 ms | Yes | — |
| R07 | 0.296 | 1.974 | 6.67 | < 5 ms | Yes | missed in large run 1 (10.056 ms); no change of its own; also served by the R01 fix (idx_flight_bookings_flight now covers booking_id) |
| R08 | 0.844 | 20.310 | 24.06 | < 250 ms | Yes | — |
| R09 | 7.506 | 128.031 | 17.06 | < 5,000 ms | Yes | — |
| R10 | 0.029 | 0.119 | 4.10 | < 5 ms | Yes | — |
| R11 | 0.023 | 0.555 | 24.13 | < 5 ms | Yes | — |
| R12 | 10.443 | 599.131 | 57.37 | < 5,000 ms | Yes | — |
| R13 | 0.084 | 1.268 | 15.10 | < 250 ms | Yes | — |
| R14 | 28.128 | 1128.729 | 40.13 | < 5,000 ms | Yes | — |
| R15 | 14.265 | 297.488 | 20.85 | < 5,000 ms | Yes | — |
| R16 | 56.895 | 2361.164 | 41.50 | < 5,000 ms | Yes | — |
| R17 | 16.157 | 823.057 | 50.94 | < 5,000 ms | Yes | — |
| R18 | 1.492 | 34.586 | 23.18 | < 250 ms | Yes | — |
| R19 | 33.073 | 715.196 | 21.62 | < 5,000 ms | Yes | — |
| R20 | 1.131 | 42.099 | 37.22 | < 5,000 ms | Yes | — |
| R21 | 16.527 | 296.991 | 17.97 | < 5,000 ms | Yes | — |
| R22 | 0.039 | 0.187 | 4.79 | < 250 ms | Yes | — |
| R23 | 0.026 | 0.153 | 5.88 | < 5 ms | Yes | — |
| R24 | 0.794 | 28.682 | 36.12 | < 250 ms | Yes | — |
| R25 | 14.515 | 373.327 | 25.72 | < 5,000 ms | Yes | — |
| W01 | 0.924 | 2.365 | 2.56 | < 5 ms | Yes | — |
| W02 | 0.421 | 1.001 | 2.38 | < 5 ms | Yes | missed in large run 1 (591.673 ms); PHASE 5 FIX: idx_bookings_pending_payment_id |
| W03 | 0.213 | 0.823 | 3.86 | < 5 ms | Yes | — |
| W04 | 1.221 | 2.991 | 2.45 | < 1,000 ms | Yes | — |
| W05 | 1.265 | 81.267 | 64.24 | < 250 ms | Yes | — |

**Targets met on large data (final run): 30/30.** Sum of the 30 averages: 207.079 ms on seed, 6944.618 ms on large.
Run 1 missed 3 target(s): R03 (6.460 ms), R07 (10.056 ms), W02 (591.673 ms). Run 2 missed 1: R01 (5.501 ms). Run 3 missed 0.

## 2. Growth analysis

Groups use the ratio in §1: *stayed about the same* (< 3×), *grew about 20×* (3–40×), *grew more than 20×* (> 40×). “Buffers” is the top-level `Buffers: shared hit+read` of run 3 in the saved plan (seed → large); “temp” is temp blocks written; “batches” is the largest hash `Batches:` value.

### Stayed about the same (5 queries)

| Query | Growth | Buffers seed → large | Spill on large | Why (from the plan) |
|---|---:|---:|---|---|
| R05 | 1.19 | 15 → 6 | none | customer equality lookup in idx_bookings_customer_status plus primary-key probes; B-tree depth grows with log n |
| R06 | 1.59 | 4 → 4 | none | single unique-key lookup on uq_bookings_booking_ref; B-tree depth grows with log n |
| W01 | 2.56 | 185 → 202 | none | one-row INSERT: one heap tuple plus one entry in each bookings index; independent of table size apart from B-tree depth |
| W02 | 2.38 | 73 → 75 | none | min(booking_id) is the first entry of the new partial idx_bookings_pending_payment_id, then one primary-key update |
| W04 | 2.45 | 338 → 330 | none | Seq Scan of flights, which has the same row count on seed and large |

### Grew about 20× (20 queries)

| Query | Growth | Buffers seed → large | Spill on large | Why (from the plan) |
|---|---:|---:|---|---|
| R01 | 3.00 | 36 → 414 | none | one flight found through idx_flights_route_departure, then its bookings read from idx_flight_bookings_flight and probed in pk_bookings; the B-tree descents grow with log n, but each flight now has more bookings to probe (flight_bookings rows read per run: seed 6 → large 101) |
| R02 | 3.27 | 15 → 15 | none | flights has the same row count on seed and large, so the plan reads the same pages; the difference is sub-millisecond timing noise |
| R03 | 4.19 | 72 → 22 | none | index scan in ORDER BY order on the new idx_hotels_city_pool_rating stops after 20 rows; reads are bounded by LIMIT, not by table size |
| R04 | 8.51 | 51 → 75 | none | one hotel's room types, then that room type's overlapping stays; the number of stays per room type grew with the data |
| R07 | 6.67 | 74 → 1169 | none | per-flight manifest: rows per flight grew (more bookings and passengers on the same flight), each probed by primary key (flight_bookings rows read per run: seed 9 → large 148) |
| R08 | 24.06 | 2274 → 2512 | none | every SCHEDULED July flight is read and its bookings summed from the covering idx_flight_bookings_flight; the flight count is the same but bookings per flight grew |
| R09 | 17.06 | 865 → 14255 | none | hash join over all flight_bookings (Seq Scan) against a booked_at range read from the covering index: work proportional to table size |
| R10 | 4.10 | 3 → 3 | none | flights has the same row count on seed and large; partial index read is identical; difference is sub-millisecond timing noise |
| R11 | 24.13 | 4 → 17 | none | the pending-payment partial index holds a fixed share of bookings, so its scanned range grew with the data |
| R13 | 15.10 | 62 → 92 | none | anti-join probes idx_bookings_coupon_code_nonnull once per coupon; 30 coupons in both datasets, so only index depth grows |
| R15 | 20.85 | 2459 → 48545 | none | full Seq Scans and hash joins over bookings, hotel_bookings and hotels: work proportional to table size |
| R18 | 23.18 | 284 → 4584 | none | trigram GIN index finds matching reviews; the number of matching reviews grew with the data |
| R19 | 21.62 | 2030 → 37102 | temp written 18368; hash batches 16 (seed 1) | Seq Scans of passengers and flight_bookings joined by hash; on large data the hash spills into batches |
| R20 | 37.22 | 66 → 1154 | none | index-only range scan on booked_at: reads a fixed share of bookings, so it grew with the data |
| R21 | 17.97 | 2082 → 37486 | temp written 5044; hash batches 8 (seed 1) | Seq Scans of passengers and flight_bookings joined by hash; on large data the hash spills into batches |
| R22 | 4.79 | 13 → 13 | none | keyset page: 25 rows read backwards from idx_bookings_booked_at_covering; reads are bounded by LIMIT |
| R23 | 5.88 | 4 → 4 | none | expression-index lookup on lower(email); B-tree depth grows with log n |
| R24 | 36.12 | 989 → 28595 | none | all Goa hotels and their reviews from the covering idx_hotel_reviews_hotel_rating: hotels per city and reviews per hotel grew with the data |
| R25 | 25.72 | 1154 → 20019 | temp written 10436; hash batches 8 (seed 1) | Seq Scan of flight_bookings joined to a booked_at range; hashes spill into batches on large data |
| W03 | 3.86 | 70 → 71 | none | single unique-key lookup then one row update; B-tree depth grows with log n |

### Grew more than 20× (5 queries)

| Query | Growth | Buffers seed → large | Spill on large | Why (from the plan) |
|---|---:|---:|---|---|
| R12 | 57.37 | 358 → 6919 | temp written 3354; sort on disk 26720kB | reads a 2026 range from the covering index and then sorts every qualifying row for GroupAggregate; on large data the sort no longer fits in work_mem and spills to disk |
| R14 | 40.13 | 3547 → 51267 | temp written 21976; hash batches 16 (seed 1) | full Seq Scans and hash joins over bookings and flight_bookings; on large data the hash tables exceed work_mem and are split into batches written to temp files |
| R16 | 41.50 | 5494 → 70659 | temp written 69520; hash batches 16 (seed 1) | full Seq Scans of five tables with hash joins; on large data the hashes exceed work_mem and are split into batches written to temp files |
| R17 | 50.94 | 991 → 19705 | temp written 7168; hash batches 33 (seed 5) | index range scan with heap fetches over booked_at, then a hash aggregate; on large data the hash aggregate exceeds work_mem and spills into batches |
| W05 | 64.24 | 1616 → 37191 | none | every 1 July check-in without a room: the number of matching stays grew with the data, and each updated row also writes index entries for hotel_bookings |

Note: R01 (0.849 ÷ 0.283) lands exactly on the 3× boundary and is therefore listed in the 3–40× group.

**Reading the groups.** Queries in the first group are single-key lookups, single-row writes, or work on `flights`, which did not grow (13848 rows in both), so their cost follows B-tree depth. In the middle group, 11 of 20 queries still finish under 5 ms on large data (R01, R02, R03, R04, R07, R10, R11, R13, R22, R23, W03): their ratios look large only because the seed times were a few hundredths of a millisecond, or because the number of rows per key (bookings per flight, stays per room type, reviews per hotel) grew with the data. The others in this group read a fixed share of a table, so their time grew with it.
In the last group, R12, R14, R16, R17 grew more than the data because they hit a memory limit that seed data never reached: the plan switches to hash batches written to temp files, or to an external-merge sort on disk (columns above).
W05 does not spill: it updates 89 rows on seed and 1681 on large data (run 3 plans), and each updated row writes a new heap tuple plus index entries; its first run on large data was cold (184.626, 30.201, 28.975 ms for runs 1–3), which lifts the average above the 20× line.
All of them are inside their targets (the slowest, R16, at 2361.164 ms against < 5,000 ms), so no index was added for them; §6 lists them as the main risk at 100×.

## 3. What broke at scale and how it was fixed

Each fix is in `sql/05_indexes.sql` with a `-- PHASE 5 FIX:` comment. It was tested on `mmt_large` inside `BEGIN … ROLLBACK` before being kept, then applied and followed by `ANALYZE`. No query was rewritten in Phase 5, so `sql/06_optimized_queries.sql` is unchanged and no result-equality proof was needed (an index cannot change a query's result).

Average of 3 runs on large data, per benchmark run:

| Query | Target | Run 1 (ms) | Run 2 (ms) | Run 3, final (ms) | Change |
|---|---|---:|---:|---:|---|
| R03 | < 5 ms | 6.460 | 0.157 | 0.708 | sql/05_indexes.sql: new B-tree (city_name, (amenities ->> 'pool'), user_rating DESC NULLS LAST) INCLUDE (star_rating, hotel_name) |
| W02 | < 5 ms | 591.673 | 1.327 | 1.001 | sql/05_indexes.sql: new partial B-tree (booking_id) WHERE status = 'PENDING_PAYMENT' |
| R01 | < 5 ms | 4.272 | 5.501 | 0.849 | sql/05_indexes.sql: booking_id added to the INCLUDE list of the existing idx_flight_bookings_flight |
| R07 | < 5 ms | 10.056 | 2.416 | 1.974 | none of its own (see R01) |

### R03

**Cause:** `idx_hotels_city_star` found every 4★+ Goa hotel (2740 index entries on large data), then the heap was visited for each one to test the pool flag, and a top-N sort ran before `LIMIT 20` (1311 buffers). Even warm, runs 2 and 3 took 3.914 and 3.789 ms, close to the target, and the cold first run (11.678 ms) pushed the average over 5 ms. **Fix:** `idx_hotels_city_pool_rating` puts the pool expression in the key and `user_rating DESC NULLS LAST` after it, so rows come out already in ORDER BY order and the scan stops after 20 rows that pass `star_rating >= 4`. An alternative partial index (`WHERE amenities ->> 'pool' = 'true'`) was tested and rejected: the planner still used a bitmap scan plus sort.

Execution times of the three runs: before (large benchmark run 1) 11.678, 3.914, 3.789 ms; after (final run, `benchmarks/results/large/R03.txt`) 1.943, 0.078, 0.102 ms.

Before (large benchmark run 1, run 3):
```
  Buffers: shared hit=1311
        Sort Method: top-N heapsort  Memory: 27kB
        ->  Bitmap Heap Scan on hotels  (cost=40.16..1596.42 rows=14 width=34) (actual time=0.337..3.411 rows=1920.00 loops=1)
              Filter: ((amenities ->> 'pool'::text) = 'true'::text)
              Rows Removed by Filter: 820
              ->  Bitmap Index Scan on idx_hotels_city_star  (cost=0.00..40.16 rows=2787 width=0) (actual time=0.195..0.195 rows=2740.00 loops=1)
                    Index Cond: ((city_name = 'Goa'::text) AND (star_rating >= 4))
  Buffers: shared hit=144
Execution Time: 3.789 ms
```
After (final run, run 3):
```
  Buffers: shared hit=22
  ->  Index Scan using idx_hotels_city_pool_rating on hotels  (cost=0.41..4789.82 rows=587 width=34) (actual time=0.031..0.076 rows=20.00 loops=1)
        Index Cond: ((city_name = 'Goa'::text) AND ((amenities ->> 'pool'::text) = 'true'::text))
        Filter: (star_rating >= 4)
  Buffers: shared hit=178
Execution Time: 0.102 ms
```

### W02

**Cause:** for `min(booking_id) WHERE status = 'PENDING_PAYMENT'` the planner walked `pk_bookings` from the lowest booking_id, expecting to meet a pending row early; on large data the pending rows sit at the high end, so it removed 2895317 rows first. On seed it used `idx_bookings_pending_payment_booked_at` instead. **Fix:** `idx_bookings_pending_payment_id`, a partial index on booking_id holding only pending rows; `min()` is its first entry. Write overhead: W01 adds one entry, W02/W03 remove one when a booking leaves PENDING_PAYMENT.

Execution times of the three runs: before (large benchmark run 1) 529.582, 604.474, 640.963 ms; after (final run, `benchmarks/results/large/W02.txt`) 2.011, 0.514, 0.479 ms.

Before (large benchmark run 1, run 3):
```
  Buffers: shared hit=470 read=46024 dirtied=8
                  ->  Index Scan using pk_bookings on bookings bookings_1  (cost=0.43..120647.86 rows=2125 width=8) (actual time=639.877..639.877 rows=1.00 loops=1)
                        Filter: ((status)::text = 'PENDING_PAYMENT'::text)
                        Rows Removed by Filter: 2895317
  ->  Index Scan using pk_bookings on bookings  (cost=0.43..8.45 rows=1 width=56) (actual time=639.920..639.920 rows=1.00 loops=1)
        Index Cond: (booking_id = (InitPlan 2).col1)
  Buffers: shared hit=204 read=33
Execution Time: 640.963 ms
```
After (final run, run 3):
```
  Buffers: shared hit=75 dirtied=1
                  ->  Index Only Scan using idx_bookings_pending_payment_id on bookings bookings_1  (cost=0.28..68.16 rows=2125 width=8) (actual time=0.053..0.053 rows=1.00 loops=1)
                        Heap Fetches: 1
  ->  Index Scan using pk_bookings on bookings  (cost=0.43..8.45 rows=1 width=56) (actual time=0.074..0.074 rows=1.00 loops=1)
        Index Cond: (booking_id = (InitPlan 2).col1)
  Buffers: shared hit=250
Execution Time: 0.479 ms
```

### R01

**Cause:** in run 2 R01 averaged 5.501 ms (target < 5 ms) because of its cold first run (the warm runs were about 1 ms). The plan read `flight_bookings` through `idx_flight_bookings_flight` with a heap fetch per booking only to get booking_id for the join to bookings. **Fix:** booking_id added to that index's INCLUDE list, so `flight_bookings` becomes an Index Only Scan (Heap Fetches: 0). The index grew from 38232064 to 53616640 bytes (measured in the rollback test); no new index was added. R07 and R08 use the same index.

Execution times of the three runs: before (large benchmark run 2) 13.956, 1.195, 1.353 ms; after (final run, `benchmarks/results/large/R01.txt`) 1.224, 0.657, 0.667 ms.

Before (large benchmark run 2, run 1):
```
  Sort Method: quicksort  Memory: 25kB
  Buffers: shared hit=424 read=88
                    ->  Bitmap Heap Scan on flights f  (cost=4.32..11.69 rows=2 width=34) (actual time=0.147..0.150 rows=1.00 loops=1)
                          Filter: ((status)::text <> 'CANCELLED'::text)
                          ->  Bitmap Index Scan on idx_flights_route_departure  (cost=0.00..4.32 rows=2 width=0) (actual time=0.123..0.124 rows=1.00 loops=1)
                                Index Cond: ((origin = 'DEL'::bpchar) AND (destination = 'BOM'::bpchar) AND (departure_at >= '2026-07-05 00:00:00+05:30'::timestamp with time zone) AND (departure_at < '2026-07-06 00:00:00+05:30'::timestamp with time zone))
                    ->  Index Scan using idx_flight_bookings_flight on flight_bookings fb  (cost=0.43..16.67 rows=128 width=14) (actual time=0.187..3.602 rows=101.00 loops=1)
                          Index Cond: (flight_id = f.flight_id)
              ->  Index Scan using pk_bookings on bookings b  (cost=0.43..0.56 rows=1 width=18) (actual time=0.096..0.096 rows=1.00 loops=101)
                    Index Cond: (booking_id = fb.booking_id)
  Buffers: shared hit=563 read=14
Execution Time: 13.956 ms
```
After (final run, run 1):
```
  Sort Method: quicksort  Memory: 25kB
  Buffers: shared hit=412 read=2
                    ->  Bitmap Heap Scan on flights f  (cost=4.32..11.69 rows=2 width=34) (actual time=0.057..0.059 rows=1.00 loops=1)
                          Filter: ((status)::text <> 'CANCELLED'::text)
                          ->  Bitmap Index Scan on idx_flights_route_departure  (cost=0.00..4.32 rows=2 width=0) (actual time=0.034..0.034 rows=1.00 loops=1)
                                Index Cond: ((origin = 'DEL'::bpchar) AND (destination = 'BOM'::bpchar) AND (departure_at >= '2026-07-05 00:00:00+05:30'::timestamp with time zone) AND (departure_at < '2026-07-06 00:00:00+05:30'::timestamp with time zone))
                    ->  Index Only Scan using idx_flight_bookings_flight on flight_bookings fb  (cost=0.43..8.75 rows=127 width=14) (actual time=0.201..0.218 rows=101.00 loops=1)
                          Index Cond: (flight_id = f.flight_id)
                          Heap Fetches: 0
              ->  Index Scan using pk_bookings on bookings b  (cost=0.43..0.56 rows=1 width=18) (actual time=0.007..0.007 rows=1.00 loops=101)
                    Index Cond: (booking_id = fb.booking_id)
  Buffers: shared hit=575 read=6
Execution Time: 1.224 ms
```

### R07

**Cause:** in run 1 R07 averaged 10.056 ms; its plan is the same shape as on seed, and the miss came from the first run reading pages from disk (`read=` in the first Buffers line of the “before” excerpt below) while the warm runs were about 2 ms. Covering indexes for all three tables were tested: they turned every step into an Index Only Scan but cost 156 MB (passengers) + 137 MB (bookings) of extra index, so they were not kept. R07 has no fix of its own; it uses the R01 change (Index Only Scan on flight_bookings).

**Honest caveat:** in run 3 the first runs of R01 and R07 read only a couple of pages from disk (see the `read=` values in the “after” excerpts), i.e. their pages were already cached from the earlier tests. Part of their improvement in the final run is therefore cache state, not the index; the structural part is the removed heap fetches (Heap Fetches: 0) and the lower buffer count.

Execution times of the three runs: before (large benchmark run 1) 25.792, 2.306, 2.071 ms; after (final run, `benchmarks/results/large/R07.txt`) 2.320, 1.798, 1.804 ms.

Before (large benchmark run 1, run 1):
```
  Sort Method: quicksort  Memory: 37kB
  Buffers: shared hit=807 read=497
              ->  Index Scan using idx_flight_bookings_flight on flight_bookings fb  (cost=0.43..16.68 rows=127 width=8) (actual time=0.140..0.787 rows=148.00 loops=1)
                    Index Cond: (flight_id = 13047)
              ->  Index Scan using pk_bookings on bookings b  (cost=0.43..8.42 rows=1 width=17) (actual time=0.080..0.080 rows=0.96 loops=148)
                    Index Cond: (booking_id = fb.booking_id)
                    Filter: ((status)::text <> 'CANCELLED'::text)
                    Rows Removed by Filter: 0
        ->  Index Scan using pk_passengers on passengers p  (cost=0.43..0.54 rows=3 width=27) (actual time=0.088..0.089 rows=1.86 loops=142)
              Index Cond: (booking_id = b.booking_id)
  Buffers: shared hit=475 read=5
Execution Time: 25.792 ms
```
After (final run, run 1):
```
  Sort Method: quicksort  Memory: 37kB
  Buffers: shared hit=1167 read=2
              ->  Index Only Scan using idx_flight_bookings_flight on flight_bookings fb  (cost=0.43..10.73 rows=126 width=8) (actual time=0.379..0.387 rows=148.00 loops=1)
                    Index Cond: (flight_id = 13047)
                    Heap Fetches: 0
              ->  Index Scan using pk_bookings on bookings b  (cost=0.43..8.45 rows=1 width=17) (actual time=0.006..0.006 rows=0.96 loops=148)
                    Index Cond: (booking_id = fb.booking_id)
                    Filter: ((status)::text <> 'CANCELLED'::text)
                    Rows Removed by Filter: 0
        ->  Index Scan using pk_passengers on passengers p  (cost=0.43..0.54 rows=3 width=27) (actual time=0.004..0.005 rows=1.86 loops=142)
              Index Cond: (booking_id = b.booking_id)
  Buffers: shared hit=495
Execution Time: 2.320 ms
```

## 4. Storage

`pg_database_size`: seed (`mmt_seedsz`, same scripts 01 + 02 + 05 + ANALYZE) **95.0 MB**, large (`mmt_large`) **1679.9 MB** (17.69×). Schema `mmt` tables: seed 42.5 MB heap + 43.8 MB indexes; large 792.5 MB heap + 878.6 MB indexes. Indexes are 1.11× the heap size on large data (seed 1.03×).

| Table | Indexes | Seed table (MB) | Seed indexes (MB) | Seed total (MB) | Large table (MB) | Large indexes (MB) | Large total (MB) | Total large ÷ seed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| bookings | 7 | 15.1 | 19.1 | 34.2 | 298.1 | 392.7 | 691.0 | 20.18 |
| passengers | 1 | 10.0 | 4.9 | 15.0 | 190.5 | 98.4 | 289.0 | 19.32 |
| customers | 4 | 4.1 | 6.4 | 10.6 | 82.1 | 154.3 | 236.5 | 22.32 |
| flight_bookings | 2 | 5.0 | 4.4 | 9.4 | 98.5 | 87.5 | 186.1 | 19.73 |
| hotel_bookings | 4 | 3.5 | 5.0 | 8.5 | 69.7 | 98.7 | 168.4 | 19.76 |
| hotel_reviews | 4 | 1.7 | 1.6 | 3.3 | 30.2 | 29.2 | 59.4 | 18.07 |
| room_types | 3 | 1.0 | 0.6 | 1.6 | 10.5 | 10.6 | 21.1 | 13.13 |
| hotels | 3 | 0.6 | 0.3 | 0.9 | 11.6 | 5.7 | 17.3 | 18.56 |
| flights | 5 | 1.5 | 1.4 | 2.9 | 1.2 | 1.4 | 2.7 | 0.92 |
| airlines | 2 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.00 |
| airports | 1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.00 |
| coupons | 1 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 1.00 |

`bookings` is the largest table: 691.0 MB on large data, of which 392.7 MB is its 7 indexes. Source: `pg_relation_size`, `pg_indexes_size`, `pg_total_relation_size` (sizes include the three Phase 5 indexes in both databases).

## 5. Architecture for 100×

### 5.1 Partitioning: `bookings` by RANGE (booked_at), one partition per month

**Why this table and key.** `bookings` holds the most rows (2897285 on large data) and is the parent of both product tables. Most reports filter on a booked_at range (R09, R12, R17, R20, R25 all use `idx_bookings_booked_at_covering`), old months are only read, and new rows always arrive at the newest month. RANGE on booked_at matches all three; LIST (by type) would give only two partitions, and HASH would give no pruning for date ranges and no way to archive old months.

**DDL:** `sql/08_partitioning.sql` builds a separate schema `mmt_part` from `mmt.bookings`: `CREATE TABLE bookings (LIKE mmt.bookings …) PARTITION BY RANGE (booked_at)`, one partition per month for Jan 2025 – Dec 2026 plus a DEFAULT partition (25 partitions in all). On `mmt_large` it ran in 31.96 s and copied 2897285 rows (mmt.bookings has 2897285). 18 partitions hold rows; partitions after the last booked month are empty and the default is empty. Rows per populated partition range from 148639 to 164590. Total size of the partitions: 531.7 MB versus 691.0 MB for `mmt.bookings` (the partitioned copy has only the PK and UNIQUE indexes, not the 5 extra indexes from 05).

**Pruning evidence** (`EXPLAIN (ANALYZE, BUFFERS)` on `mmt_large` after `sql/08_partitioning.sql`, with `SET search_path TO mmt_part`; key plan lines are quoted below the table):

| Test | Partitions scanned | Buffers (hit + read) | Planning (ms) | Execution (ms) |
|---|---:|---:|---:|---:|
| (a) `booked_at >= '2026-06-01' AND booked_at < '2026-07-01'` | 1 of 25 | 2096 | 1.006 | 16.299 |
| (b) R12 with `EXTRACT(YEAR FROM booked_at) = 2026` | 25 of 25 | 38184 | 2.589 | 562.166 |
| (c) R12 with `booked_at >= '2026-01-01' AND booked_at < '2027-01-01'` | 12 of 25 | 12632 | 0.985 | 597.258 |
| (d) `booking_ref = …` lookup | 25 of 25 | 55 | 1.472 | 3.486 |
(a) `booked_at >= '2026-06-01' AND booked_at < '2026-07-01'`: 1 of 25 partitions scanned
```
Finalize Aggregate  (cost=4970.39..4970.40 rows=1 width=40) (actual time=15.224..16.283 rows=1.00 loops=1)
              ->  Parallel Seq Scan on bookings_2026_06 bookings  (cost=0.00..3501.69 rows=93694 width=6) (actual time=0.005..8.593 rows=79656.00 loops=2)
  Buffers: shared hit=2096
Planning:
  Buffers: shared hit=71 read=16 dirtied=1
Planning Time: 1.006 ms
Execution Time: 16.299 ms
```
(b) R12 with `EXTRACT(YEAR FROM booked_at) = 2026`: 25 of 25 partitions scanned
```
GroupAggregate  (cost=69310.48..71198.50 rows=13346 width=54) (actual time=365.404..561.411 rows=12.00 loops=1)
              Sort Method: external merge  Disk: 8576kB
              Worker 0:  Sort Method: external merge  Disk: 6936kB
              Worker 1:  Sort Method: external merge  Disk: 11208kB
              ->  Parallel Append  (cost=0.00..67964.40 rows=5563 width=20) (actual time=68.746..272.926 rows=294714.00 loops=3)
                    ->  Seq Scan on bookings_2026_07 bookings_19  (cost=0.00..0.00 rows=1 width=20) (actual time=0.038..0.038 rows=0.00 loops=1)
                    ->  Seq Scan on bookings_2026_08 bookings_20  (cost=0.00..0.00 rows=1 width=20) (actual time=0.042..0.042 rows=0.00 loops=1)
        ... 22 more partition scans ...
                    ->  Parallel Seq Scan on bookings_2026_02 bookings_14  (cost=0.00..3485.11 rows=402 width=20) (actual time=0.037..47.506 rows=136767.00 loops=1)
  Buffers: shared hit=88 read=38096 written=23, temp read=3340 written=3352
Planning:
  Buffers: shared hit=247 read=55 dirtied=39
Planning Time: 2.589 ms
Execution Time: 562.166 ms
```
(c) R12 with `booked_at >= '2026-01-01' AND booked_at < '2027-01-01'`: 12 of 25 partitions scanned
```
GroupAggregate  (cost=141628.86..165962.24 rows=884850 width=54) (actual time=433.095..594.612 rows=12.00 loops=1)
        Sort Method: external merge  Disk: 26720kB
        ->  Append  (cost=0.00..36079.98 rows=884850 width=20) (actual time=0.041..259.252 rows=884142.00 loops=1)
              ->  Seq Scan on bookings_2026_01 bookings_1  (cost=0.00..5417.17 rows=151282 width=20) (actual time=0.041..34.805 rows=151143.00 loops=1)
              ->  Seq Scan on bookings_2026_02 bookings_2  (cost=0.00..4896.95 rows=136706 width=20) (actual time=0.059..32.159 rows=136767.00 loops=1)
        ... 9 more partition scans ...
              ->  Seq Scan on bookings_2026_12 bookings_12  (cost=0.00..0.00 rows=1 width=20) (actual time=0.002..0.002 rows=0.00 loops=1)
  Buffers: shared hit=7269 read=5363, temp read=3340 written=3354
Planning:
  Buffers: shared read=12
Planning Time: 0.985 ms
Execution Time: 597.258 ms
```
(d) `booking_ref = …` lookup: 25 of 25 partitions scanned
```
Append  (cost=0.42..152.00 rows=25 width=55) (actual time=3.421..3.437 rows=1.00 loops=1)
  ->  Index Scan using bookings_2025_01_booking_ref_booked_at_key on bookings_2025_01 bookings_1  (cost=0.42..8.44 rows=1 width=33) (actual time=0.470..0.470 rows=0.00 loops=1)
  ->  Index Scan using bookings_2025_02_booking_ref_booked_at_key on bookings_2025_02 bookings_2  (cost=0.42..8.44 rows=1 width=33) (actual time=0.346..0.346 rows=0.00 loops=1)
        ... 22 more partition scans ...
  ->  Seq Scan on bookings_default bookings_25  (cost=0.00..0.00 rows=1 width=110) (actual time=0.002..0.002 rows=0.00 loops=1)
  Buffers: shared hit=1 read=54
Planning:
  Buffers: shared hit=19 read=2
Planning Time: 1.472 ms
Execution Time: 3.486 ms
```


- (a) only `bookings_2026_06` is scanned: pruning works for a range on the partition key.
- (b) a function on the key hides it from the planner, so all 25 partitions are scanned (38184 buffers).
- (c) the sargable range (the Phase 4 R12 rewrite) scans only the 12 partitions of 2026 (12632 buffers, 0.33× the buffers of (b)). Its execution time (597.258 ms vs 562.166 ms) did not drop, because both plans then sort all qualifying rows and the sort spills to disk (26720kB in (c)); pruning removes I/O, not that sort. A monthly summary table (§5.4) is the fix for R12 at 100×.
- (d) `booking_ref` is not the partition key, so the lookup probes every partition (25) — planning 1.472 ms, execution 3.486 ms, versus 0.065 ms for R06 (same kind of lookup) on the unpartitioned table. Lookups by a non-key column get slower as partitions are added.

**Primary-key rule.** On a partitioned table every PRIMARY KEY and UNIQUE constraint must include the partition key, so 08 declares `PRIMARY KEY (booking_id, booked_at)` and `UNIQUE (booking_ref, booked_at)`. Consequences: (1) booking_ref is only unique per booked_at, not globally, so two bookings in different months could share a ref; the application (or a separate small `booking_refs(booking_ref PRIMARY KEY, booking_id)` table) must guarantee global uniqueness. (2) `flight_bookings` and `hotel_bookings` cannot keep a foreign key on booking_id alone, because a foreign key must reference a complete unique key, now (booking_id, booked_at); either add booked_at to the child tables and use a composite FK, or enforce the link in the application. (3) New partitions must exist before rows for that month arrive (a W01 row for a month with no partition goes to the DEFAULT partition), so a monthly job creates next month's partition in advance.

### 5.2 Sharding

Three candidate keys for `bookings`: **customer_id**, **product** (flight vs hotel) and **travel date**. The deciding pair is the brief's: My Trips (R05, one customer) on large data takes 0.063 ms and the airline manifest (R07, one flight) 1.974 ms; both are customer-facing (< 5 ms).

- **By customer_id (recommended).** Every booking, its flight/hotel rows and passengers live with the customer, so R05, R06 (with a ref → customer lookup), R23 (customer by email, via a global email → customer index), W01, W02 and W03 touch one shard. Customer load spreads evenly (hash of customer_id) and grows with customers, not with time.
- **By product** gives only two shards, cannot grow, and the flight shard would be far larger than the hotel shard.
- **By travel date** keeps manifests (R07) and availability (R01, R04) local, but all new bookings for the busiest upcoming dates hit one shard (a hot spot), and My Trips would touch every shard.

**Cross-shard queries under customer_id**, and how to handle them:

| Query type | Queries | Handling |
|---|---|---|
| Per-flight / per-room live counts | R01 (seats left), R04 (rooms left), R07 (manifest), R08 | Keep a per-flight and per-room-type inventory counter on a small, unsharded inventory service updated in the booking transaction; the manifest (R07) is a scatter-gather on `flight_id` across shards, acceptable for an airline tool. |
| Reports and analytics | R09, R12, R14–R17, R19–R21, R25 | Scatter-gather: each shard computes a partial aggregate, a coordinator merges them; better, feed a separate analytics replica / warehouse. |
| Lookups by a non-shard key | R06 (booking_ref), R11 (pending queue), R13, W05 | A small global lookup table (booking_ref → customer_id); queue and batch jobs run on every shard in parallel. |
| Catalog reads | R02, R03, R10, R18, R22, R23, R24, W04 | `flights`, `airports`, `airlines`, `hotels`, `room_types`, `coupons` are small reference tables (flights: 13848 rows) replicated to every shard; reviews stay with hotels. |

### 5.3 Read replicas and caching

| Route | Queries | Sum of their large averages (ms) | Why |
|---|---|---:|---|
| Replica (stale by seconds is fine) | R09, R12, R14, R15, R16, R17, R19, R20, R21, R25 | 6765.213 | Reports and analytics; together they are the expensive part of the workload. |
| Cache (catalog/search results, short TTL) | R02, R03, R10, R24 | 29.790 | Search/browse results that change slowly; a cache hit avoids the database entirely. |
| Primary (must see the latest committed data) | W01, W02, W03, W04, W05, R01, R04, R11, R06, R23 | 91.227 | All writes; R01 seats left and R04 rooms left (overselling risk if stale); R11 pending-payment queue (acts on current status); R06 / R23 read-your-writes (a customer who just booked or signed up must see it). |

The remaining queries (R05, R07, R08, R13, R18, R22) can go to a replica (partner tools, manifests and search over committed data) as long as the replica lag is small. Moving the replica group off the primary removes 6765.213 ms of the 6944.618 ms total of one pass of the workload.

### 5.4 Maintenance

- **Autovacuum for `bookings`.** W02 and W03 change status on existing rows, and every changed row leaves a dead tuple in the heap and in the indexes that cover status (`bookings` has 7 indexes on large data). With the default `autovacuum_vacuum_scale_factor = 0.2` and threshold 50, autovacuum waits for 50 + 0.2 × 2897285 = 579507 dead rows. Recommended per-table setting (not applied here, to keep the server settings unchanged): `ALTER TABLE mmt.bookings SET (autovacuum_vacuum_scale_factor = 0.01, autovacuum_analyze_scale_factor = 0.02);` i.e. vacuum after 50 + 0.01 × 2897285 = 29023 dead rows. With monthly partitions each partition gets its own threshold, and only the current months churn.
- **Index-only scans need a fresh visibility map.** R09, R12, R20, R25 and the Phase 5 fixes rely on Index Only Scans; after heavy status churn the visibility map goes stale and they turn back into heap fetches, so regular vacuuming is what keeps them fast.
- **Archiving.** With monthly partitions, old months are archived with `ALTER TABLE bookings DETACH PARTITION bookings_2025_01` (add `CONCURRENTLY` to avoid blocking), then dumped or moved to cheaper storage and dropped, instead of a long `DELETE` that bloats the table.
- **Summary tables.** R12, R14 and R16 spill to disk on large data (§2). A monthly revenue table (month, booking_type, count, revenue) refreshed by a nightly job, or `REFRESH MATERIALIZED VIEW CONCURRENTLY`, turns them into reads of a few hundred rows; only the current month needs recomputing.
- **Index-bloat checks.** Compare `pg_relation_size` of each bookings index over time against the row count (the §4 numbers are the starting point), or use `pgstattuple`/`pgstatindex`; rebuild bloated indexes with `REINDEX INDEX CONCURRENTLY`.

### 5.5 R22: choosing the “last seen” value on large data

R22 uses keyset pagination: `WHERE (booked_at, booking_id) < (:last_booked_at, :last_booking_id) ORDER BY booked_at DESC, booking_id DESC LIMIT 25`. The app does not compute the cursor; it remembers the (booked_at, booking_id) of the last row of the page it just showed and sends it with “next page”. `sql/06_optimized_queries.sql` keeps the seed cursor (`2025-06-18 22:17:24+05:30`, 46410); that literal is what the benchmark ran (0.187 ms average on large data).
For the large data, the cursor for page 4,001 (the last row of page 4,000 = row 100,000 in booked_at DESC, booking_id DESC order) was found with `SELECT booked_at, booking_id FROM mmt.bookings ORDER BY booked_at DESC, booking_id DESC OFFSET 99999 LIMIT 1`: **booked_at = 2026-06-12 03:56:17+05:30, booking_id = 2896507**. With that cursor the keyset query ran in 0.406, 0.087, 0.102 ms over three runs (Index Scan Backward on `idx_bookings_booked_at_covering`, excerpt below), so its time does not depend on how deep the page is. The tie-breaker booking_id makes the order total: on large data many bookings can share a booked_at second, and with booked_at alone a page boundary inside such a group would skip or repeat rows.

Cursor query and its result on `mmt_large` (booked_at | booking_id):
```
SELECT booked_at, booking_id FROM mmt.bookings ORDER BY booked_at DESC, booking_id DESC OFFSET 99999 LIMIT 1;
2026-06-12 03:56:17+05:30|2896507
```
Keyset query with that cursor, `EXPLAIN (ANALYZE, BUFFERS)`, three runs:
```
=== R22 large cursor run 1 ===
  Buffers: shared hit=12 read=2
        ->  Index Scan Backward using idx_bookings_booked_at_covering on bookings  (cost=0.43..180326.50 rows=2795890 width=47) (actual time=0.292..0.296 rows=26.00 loops=1)
              Index Cond: (booked_at <= '2026-06-12 03:56:17+05:30'::timestamp with time zone)
  Buffers: shared hit=229 read=1
Execution Time: 0.406 ms
=== R22 large cursor run 2 ===
  Buffers: shared hit=14
        ->  Index Scan Backward using idx_bookings_booked_at_covering on bookings  (cost=0.43..180326.50 rows=2795890 width=47) (actual time=0.017..0.022 rows=26.00 loops=1)
              Index Cond: (booked_at <= '2026-06-12 03:56:17+05:30'::timestamp with time zone)
  Buffers: shared hit=230
Execution Time: 0.087 ms
=== R22 large cursor run 3 ===
  Buffers: shared hit=14
        ->  Index Scan Backward using idx_bookings_booked_at_covering on bookings  (cost=0.43..180326.50 rows=2795890 width=47) (actual time=0.027..0.033 rows=26.00 loops=1)
              Index Cond: (booked_at <= '2026-06-12 03:56:17+05:30'::timestamp with time zone)
  Buffers: shared hit=230
Execution Time: 0.102 ms
```

## 6. Conclusion

**Ready for next year (20×)? Yes, with caveats.** On 2897285 bookings every one of the 30 queries meets its README 5.2 target in the final run (30/30), with three index changes and no query rewrites. The database is 1679.9 MB.

**Remaining risks**, closest to their target first (large average ÷ target):

- W01: 2.365 ms against < 5 ms (0.47 of the target).
- R16: 2361.164 ms against < 5,000 ms (0.47 of the target).
- R07: 1.974 ms against < 5 ms (0.39 of the target).
- W05: 81.267 ms against < 250 ms (0.33 of the target).
- R04: 1.158 ms against < 5 ms (0.23 of the target).
- **Cold cache.** The customer-facing targets are tight enough that one cold first run decides the average: R07 (run 1) and R01 (run 2) missed only because their first run read pages from disk, and R03's cold first run pushed it over (§3). On a busy production server those pages stay hot; after a restart or failover they will not.
- **Memory spills.** On large data R12, R14, R16, R17, R19, R21, R25 already write temp files (hash batches or disk sorts), so their time grows faster than the data; they are the first to be at risk at 100×. Summary tables and partition-wise aggregation (§5.4, §5.1) are the plan.
- **Data quality.** IC5 is violated by 10856 flights in the large data; seat availability needs a trigger or an inventory counter, not only a check script.
- **Measurement.** All runs were on battery power, with a second PostgreSQL server running on the laptop, and macOS 26.6 rather than the version in team.json.
