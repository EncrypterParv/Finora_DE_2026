# Phase 3 Baseline Timings: MakeMyTrip Travel Booking Database

## Method

All 30 queries (25 reads `R01`–`R25` and 5 writes `W01`–`W05`) were benchmarked under identical and reproducible experimental conditions:

- **Command**: `./benchmarks/run_benchmark.sh <database> baseline`
- **Profiling Tool**: PostgreSQL `EXPLAIN (ANALYZE, BUFFERS)` measuring exact execution times (`Execution Time: X ms`) and buffer hits/reads.
- **Run Protocol**: Each query was executed **3 times** sequentially; individual run times and their arithmetic **average** are reported.
- **Write Safety**: Write queries (`W01`–`W05`) were executed inside explicit `BEGIN; ... ROLLBACK;` transactions so that underlying database state and table row counts remained completely unchanged between runs.
- **Database State**: Un-indexed baseline loaded strictly from `sql/01_schema.sql` and `sql/02_load_data.sql`. It contains only the **20 Primary Key and UNIQUE constraints/indexes** inherent to the initial schema design; no tuning, secondary, or foreign-key indexes exist.
- **Hardware & Environment**:
  - **Machine**: Apple M4, 16 GB unified memory, macOS 26.4.1 (Devansh's benchmark machine)
  - **Database Engine**: PostgreSQL 18.6 (Postgres.app)
  - **Session Timezone**: `Asia/Kolkata`
  - **Raw Output**: Full execution plans for all 3 runs of all 30 queries are stored in `benchmarks/results/baseline/` (`summary.csv` and `R01.txt` through `W05.txt`).

---

## Baseline Timing Table

The table below reports the execution times across 3 runs and the verified arithmetic average for all 30 workload queries on the seed dataset.

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Flight search: Delhi → Mumbai on 5 July 2026 with seats left | READ | 10.198 | 8.142 | 6.858 | 8.399 |
| R02: Fare calendar: cheapest Bengaluru → Delhi fare for each day of July 2026 | READ | 0.836 | 0.797 | 0.750 | 0.794 |
| R03: Hotel search: 4★+ hotels in Goa with a swimming pool, best rated first | READ | 0.224 | 0.209 | 0.202 | 0.212 |
| R04: Room availability: rooms left per room type of hotel 208 for 10–12 July 2026 | READ | 2.170 | 2.020 | 2.023 | 2.071 |
| R05: "My Trips": customer 1021's upcoming confirmed trips | READ | 5.812 | 5.775 | 6.026 | 5.871 |
| R06: Support: open a booking by its reference | READ | 0.033 | 0.028 | 0.028 | 0.030 |
| R07: Airline manifest: passengers on flight 13047 ordered by seat | READ | 2.117 | 2.075 | 2.246 | 2.146 |
| R08: Revenue management: July 2026 flights with fewer than 5 passengers booked | READ | 5.244 | 5.258 | 5.336 | 5.279 |
| R09: Trends: 10 most-booked routes in June 2026 | READ | 12.415 | 12.040 | 12.194 | 12.216 |
| R10: Flight status board: delayed flights | READ | 0.730 | 0.689 | 0.661 | 0.693 |
| R11: Payments: bookings waiting for payment for more than 30 minutes (checked at 23:59 on 30 Jun 2026) | READ | 4.883 | 5.020 | 4.703 | 4.869 |
| R12: Finance: revenue per booking type per month in 2026 (excluding cancellations) | READ | 26.670 | 26.471 | 26.479 | 26.540 |
| R13: Marketing: coupons that have never been used | READ | 11.611 | 11.861 | 11.505 | 11.659 |
| R14: Airline partnerships: cancellation rate of flight bookings per airline | READ | 26.692 | 27.194 | 26.986 | 26.957 |
| R15: Hotel partnerships: room-nights sold per city for stays in June 2026 | READ | 14.551 | 13.972 | 14.093 | 14.205 |
| R16: Insights: average days between booking and travel, per booking type and loyalty tier | READ | 60.789 | 60.644 | 59.775 | 60.403 |
| R17: Loyalty: customers with 3 or more completed trips that started in 2026 | READ | 16.854 | 16.317 | 16.768 | 16.646 |
| R18: Hotel page: Goa reviews that mention breakfast | READ | 4.491 | 4.202 | 4.251 | 4.315 |
| R19: Operations: passengers booked on every flight departing in June 2026 | READ | 1332.184 | 1310.438 | 1342.858 | 1328.493 |
| R20: Finance: bookings per day and running total for June 2026 | READ | 7.216 | 6.411 | 6.526 | 6.718 |
| R21: Concessions: senior-citizen passengers (60+) per route in 2026 | READ | 16.869 | 16.752 | 17.038 | 16.886 |
| R22: Support console: all bookings, newest first, page 4,001 (25 per page) | READ | 32.528 | 32.436 | 32.236 | 32.400 |
| R23: Sign-in: find the customer by email, ignoring case | READ | 8.369 | 8.648 | 8.435 | 8.484 |
| R24: Hotel ranking: Goa hotels with at least 5 reviews, by average review rating | READ | 1.583 | 1.489 | 1.514 | 1.529 |
| R25: Insights: last-minute flight bookings (made less than 24 hours before departure) in 2026 | READ | 17.614 | 17.534 | 17.915 | 17.688 |
| W01: Checkout: create a pending flight booking for customer 1021 | WRITE | 0.450 | 0.415 | 0.396 | 0.420 |
| W02: Payment gateway callback: confirm the oldest booking that is waiting for payment | WRITE | 9.258 | 9.505 | 9.346 | 9.370 |
| W03: Customer cancels booking MMA7772F with a 70% refund | WRITE | 0.188 | 0.187 | 0.185 | 0.187 |
| W04: Flight ops: every flight that was scheduled to depart before 1 July 2026 has now departed | WRITE | 1.028 | 1.002 | 0.954 | 0.995 |
| W05: Front desk: assign room numbers to every guest checking in on 1 July 2026 | WRITE | 2.411 | 2.380 | 2.377 | 2.389 |
| **Total (sum of all 30)** | | | | | **1628.864** |

---

## Scan Type and Why (Per Query Analysis)

Below is an analysis of each query's execution plan detailing the exact scan nodes selected by the PostgreSQL optimizer, the rows removed by filters, and why the query behaves fast or slow on the baseline database.

- **R01**: `Seq Scan on flights f` | `Seq Scan on flight_bookings fb` | `Index Scan using pk_bookings on bookings b`
  - *Why*: `DATE(f.departure_at) = '2026-07-05'` applies a date function over a timestamp column which disqualifies any standard index scan on `departure_at`, filtering out 13,847 rows via sequential scan. Furthermore, `flight_bookings` lacks an index on `flight_id`, forcing a full sequential scan of 84,899 rows to evaluate the join. (*Phase 4 idea*: composite/range index on `(origin, destination, departure_at)` avoiding functional wrapping, plus index on `flight_bookings(flight_id)`).
- **R02**: `Seq Scan on flights`
  - *Why*: The predicate `departure_at::date BETWEEN '2026-07-01' AND '2026-07-31'` wraps `departure_at` in a date cast, causing a full sequential scan of 13,848 flights with 13,817 rows discarded by the filter. (*Phase 4 idea*: composite index on `(origin, destination, departure_at)` and rewriting filter to timestamp ranges).
- **R03**: `Seq Scan on hotels`
  - *Why*: The query filters by `city_name = 'Goa'`, `star_rating >= 4`, and `amenities ->> 'pool' = 'true'`, sequentially scanning all 3,000 hotels (2,902 rows removed) because no secondary B-tree or GIN index exists on hotels. (*Phase 4 idea*: composite index on `(city_name, star_rating)` or expression/GIN index on amenities).
- **R04**: `Seq Scan on hotel_bookings hb` | `Index Scan using uq_room_types_id_hotel on room_types rt` | `Index Scan using pk_bookings on bookings b`
  - *Why*: Finding overlapping bookings (`check_in < '2026-07-12' AND check_out > '2026-07-10'`) scans all 59,893 rows of `hotel_bookings` (59,684 removed by filter) due to absence of an index on date ranges or `room_type_id`. (*Phase 4 idea*: index on `hotel_bookings(room_type_id, check_in, check_out)`).
- **R05**: `Seq Scan on bookings b` | `Index Scan using pk_flight_bookings on flight_bookings fb` | `Index Scan using pk_flights on flights f` | `Index Scan using uq_hotel_bookings_booking_hotel on hotel_bookings hb`
  - *Why*: Although lookups into products use primary keys, locating bookings for `customer_id = 1021` sequentially scans all 144,792 rows of `bookings` (144,791 rows removed) because `customer_id` has no index. (*Phase 4 idea*: composite index on `bookings(customer_id, status)`).
- **R06**: `Index Scan using uq_bookings_booking_ref on bookings`
  - *Why*: The unique constraint index `uq_bookings_booking_ref` enables a direct B-tree point lookup touching exactly 1 row and 4 buffer pages in 0.030 ms. (*Phase 4 idea*: already optimal).
- **R07**: `Seq Scan on flight_bookings fb` | `Index Scan using pk_bookings on bookings b` | `Index Scan using pk_passengers on passengers p`
  - *Why*: Filtering `flight_id = 13047` forces a full sequential scan of 84,899 rows in `flight_bookings` (84,890 removed) because foreign keys lack automatic B-tree indexes. (*Phase 4 idea*: index on `flight_bookings(flight_id)`).
- **R08**: `Bitmap Heap Scan on flights f` using `Bitmap Index Scan on uq_flights_number_departure` | `Seq Scan on flight_bookings fb`
  - *Why*: Flights for July 2026 are retrieved efficiently using the unique index on `(flight_no, departure_at)`, but aggregating passengers per flight forces a complete sequential scan of 84,899 rows in `flight_bookings`. (*Phase 4 idea*: covering index on `flight_bookings(flight_id, passengers)`).
- **R09**: `Seq Scan on bookings b` | `Seq Scan on flight_bookings fb` | `Seq Scan on flights f`
  - *Why*: Joins across three un-indexed tables require full table scans, filtering 136,864 bookings for June 2026 via sequential scan, followed by Hash Joins and an in-memory top-N heapsort. (*Phase 4 idea*: index on `bookings(booked_at)` and join foreign keys).
- **R10**: `Seq Scan on flights`
  - *Why*: Full table scan of 13,848 flights (13,842 rows removed by filter) to identify only 6 delayed flights because there is no index on `status`. (*Phase 4 idea*: partial index on `flights(status) WHERE status = 'DELAYED'`).
- **R11**: `Parallel Seq Scan on bookings` (2 workers)
  - *Why*: Scans 144,792 bookings across two parallel workers (72,350 rows removed per worker) filtering for `status = 'PENDING_PAYMENT'` and old timestamps without any index. (*Phase 4 idea*: partial index on `bookings(booked_at) WHERE status = 'PENDING_PAYMENT'`).
- **R12**: `Seq Scan on bookings`
  - *Why*: Sequentially scans 144,792 bookings (100,517 rows removed by status and year filters) followed by a 3.2 MB memory Sort on `(booking_type, date_trunc)` due to lack of an index on booking date and status. (*Phase 4 idea*: composite index on `(booked_at, booking_type, status)`).
- **R13**: `Seq Scan on coupons c` | `Seq Scan on bookings b` (in hashed SubPlan)
  - *Why*: Scans all 144,792 bookings to build a hash table for the subquery `SELECT coupon_code FROM bookings`, followed by a sequential scan on 30 coupons; returns 0 rows due to SQL NULL semantics. (*Phase 4 idea*: rewrite using `NOT EXISTS` or filter `IS NOT NULL`, supported by an index on `bookings(coupon_code)`).
- **R14**: `Seq Scan on airlines a` | `Seq Scan on bookings b` | `Seq Scan on flight_bookings fb` | `Seq Scan on flights f`
  - *Why*: Four sequential scans joined via Hash Joins aggregating 144,792 bookings and 84,899 flight bookings without foreign key indexes, taking 26.957 ms. (*Phase 4 idea*: foreign key indexes on `flight_bookings(flight_id)`, `flight_bookings(booking_id)`, and `flights(airline_id)`).
- **R15**: `Seq Scan on bookings b` | `Seq Scan on hotel_bookings hb` | `Seq Scan on hotels h`
  - *Why*: Scans all 59,893 hotel bookings (56,518 removed by stay date filter) and joins all bookings and hotels via Hash Joins without date or FK indexes. (*Phase 4 idea*: composite index on `hotel_bookings(check_in, check_out)`).
- **R16**: `Seq Scan on bookings b` | `Seq Scan on customers c` | `Seq Scan on flight_bookings fb` | `Seq Scan on flights f` | `Seq Scan on hotel_bookings hb`
  - *Why*: Evaluates 5 large sequential scans joined via nested Hash Joins to compute lead time across loyalty tiers; takes 60.403 ms as all tables are read in their entirety. (*Phase 4 idea*: indexes on booking dates, customer loyalty tier, and join keys).
- **R17**: `Seq Scan on bookings b`
  - *Why*: Scans all 144,792 bookings (105,420 removed by date and status filters), aggregating completed 2026 trips by customer via HashAggregate and a 223 kB memory quicksort. (*Phase 4 idea*: index on `bookings(customer_id, booked_at) WHERE status = 'COMPLETED'`).
- **R18**: `Seq Scan on hotel_reviews r` | `Seq Scan on hotels h`
  - *Why*: Case-insensitive pattern match `review_text ~~* '%breakfast%'` causes a full sequential scan of 15,913 reviews (13,737 removed), plus sequential scan of 3,000 hotels (2,550 removed by city). (*Phase 4 idea*: index on `hotels(city_name)` and pg_trgm GIN index on `hotel_reviews(review_text)`).
- **R19**: `Bitmap Heap Scan on flights f` (via `Bitmap Index Scan on uq_flights_number_departure`) | `Seq Scan on flight_bookings fb` (inside SubPlan 1, executed 720 times) | `Index Only Scan using pk_passengers on passengers p`
  - *Why*: Correlated scalar subquery executes 720 times (once per June 2026 flight), running 720 sequential scans across all 84,899 rows of `flight_bookings` (over 61 million row inspections and 460,800 buffer hits), taking 1328.493 ms. (*Phase 4 idea*: rewrite scalar subquery to a set-based `LEFT JOIN ... GROUP BY` and index `flight_bookings(flight_id)`).
- **R20**: `Parallel Seq Scan on bookings` (2 workers)
  - *Why*: Both parallel workers sequentially scan bookings (68,432 rows removed per worker) filtering on `booked_at::date` for June 2026, followed by a GroupAggregate and window running total. (*Phase 4 idea*: index on `bookings(booked_at)` with non-casting date range predicates).
- **R21**: `Seq Scan on passengers p` | `Seq Scan on flight_bookings fb` | `Seq Scan on flights f`
  - *Why*: Sequential scans across 163,380 passengers (126,543 removed by `age >= 60`), 84,899 flight bookings, and 13,848 flights (8,760 removed by departure date), followed by Hash Joins. (*Phase 4 idea*: index on `passengers(age)` and `flights(departure_at)`).
- **R22**: `Seq Scan on bookings`
  - *Why*: Scans all 144,792 bookings and sorts them by `booked_at DESC` using an external merge sort spilling to disk (8,632 kB disk sort) to fulfill `OFFSET 100000 LIMIT 25`, taking 32.400 ms. (*Phase 4 idea*: index on `bookings(booked_at DESC)` enabling an index-ordered scan without sorting).
- **R23**: `Seq Scan on customers`
  - *Why*: `lower(email) = 'siddharth.sharma1021@rediffmail.com'` wraps email in the `lower()` function, bypassing the standard B-tree index and forcing a sequential scan of all 40,000 customers (39,999 rows removed). (*Phase 4 idea*: functional B-tree index on `lower(email)`).
- **R24**: `Seq Scan on hotel_reviews r` | `Seq Scan on hotels h`
  - *Why*: Scans all 3,000 hotels (2,550 removed by city) and all 15,913 reviews to join, group, and filter by `count(*) >= 5` via Hash Join and top-N heapsort. (*Phase 4 idea*: index on `hotels(city_name)` and `hotel_reviews(hotel_id)`).
- **R25**: `Seq Scan on flight_bookings fb` | `Seq Scan on bookings b` | `Seq Scan on flights f`
  - *Why*: Three sequential scans joined via Hash Joins; filters 96,768 bookings by date, and removes 25,282 rows via the join condition `(departure_at - booked_at) < 24 hours`. (*Phase 4 idea*: index on `bookings(booked_at)` and join keys).
- **W01**: `Insert on bookings`
  - *Why*: Direct single-row insert takes 0.420 ms; executes foreign key triggers against `customers` (0.232 ms) and `coupons` (0.008 ms), and updates primary/unique indexes. (*Phase 4 idea*: already fast; ensure future index additions do not cause write bloat).
- **W02**: `Index Scan using pk_bookings on bookings bookings_1` | `Index Scan using pk_bookings on bookings`
  - *Why*: Subquery identifies the oldest `PENDING_PAYMENT` booking using an Index Scan on `pk_bookings`, but inspects almost all 144,695 rows because `status` is not indexed, taking 9.370 ms. (*Phase 4 idea*: partial index on `bookings(booked_at) WHERE status = 'PENDING_PAYMENT'`).
- **W03**: `Index Scan using uq_bookings_booking_ref on bookings`
  - *Why*: Fast point cancellation update taking 0.187 ms via direct B-tree lookup on `uq_bookings_booking_ref`. (*Phase 4 idea*: already optimal).
- **W04**: `Seq Scan on flights`
  - *Why*: Scans all 13,848 flights (13,838 rows removed by filter on departure date and status) to update 10 departed flights in 0.995 ms. (*Phase 4 idea*: partial or composite index on `flights(departure_at, status)`).
- **W05**: `Seq Scan on hotel_bookings hb` | `Index Scan using pk_bookings on bookings b`
  - *Why*: Scans 59,893 hotel bookings (59,792 removed) to find 101 unassigned rooms on 1 July 2026 before updating them. (*Phase 4 idea*: partial index on `hotel_bookings(check_in) WHERE room_number IS NULL`).

---

## Slowest Query: R19 (Operations: passengers booked on every flight departing in June 2026)

From the measured baseline timings, **R19 is overwhelmingly the slowest query**, averaging **1328.493 ms** (accounting for **81.56% of the entire 30-query workload runtime** of 1628.864 ms).

### Root Cause Analysis from the Execution Plan

Inspecting `benchmarks/results/baseline/R19.txt` reveals the precise architectural bottleneck:
```text
Sort Key: ((SubPlan 1)) DESC, f.departure_at
-> Bitmap Heap Scan on flights f (actual time=2.196..1331.938 rows=720.00 loops=1)
     Recheck Cond: ((departure_at >= '2026-06-01 ...') AND (departure_at < '2026-07-01 ...'))
     SubPlan 1
       -> Aggregate (actual time=1.849..1.849 rows=1.00 loops=720)
            -> Nested Loop (actual time=1.639..1.849 rows=12.92 loops=720)
                 -> Seq Scan on flight_bookings fb (actual time=1.637..1.840 rows=6.64 loops=720)
                      Filter: (flight_id = f.flight_id)
                      Rows Removed by Filter: 84892
                      Buffers: shared hit=460800
```

1. **Correlated Scalar Subquery Execution**:
   The query calculates passenger counts using a correlated scalar subquery in the `SELECT` list:
   `(SELECT count(*) FROM flight_bookings fb JOIN passengers p ON p.booking_id = fb.booking_id WHERE fb.flight_id = f.flight_id)`
2. **720 Full Table Sequential Scans**:
   The outer query selects all 720 flights scheduled in June 2026. For **every single one of these 720 flights**, PostgreSQL executes `SubPlan 1`.
3. **Severe Buffer and I/O Overhead**:
   Because `flight_bookings` has no index on `flight_id`, each subquery execution triggers a full sequential scan of all 84,899 rows of `flight_bookings`.
   - 720 iterations $\times$ 84,899 rows checked $\approx$ **61.1 million row evaluations**.
   - Resulting in **460,800 buffer hits** exclusively within the subplan's sequential scan.
4. **Phase 4 Solution**:
   Transform the correlated subquery into a set-based `LEFT JOIN flight_bookings fb ON fb.flight_id = f.flight_id` combined with `GROUP BY f.flight_id`, and add a B-tree index on `flight_bookings(flight_id)`.

---

## Correctness Note: R13 (Marketing: coupons that have never been used)

### Observed Execution Plan and Row Count

From `benchmarks/results/baseline/R13.txt`:
```text
=== R13 run 1 ===
Seq Scan on coupons c (cost=3745.90..3747.28 rows=15 width=17) (actual time=11.581..11.581 rows=0.00 loops=1)
  Filter: (NOT (ANY ((coupon_code)::text = ((hashed SubPlan 1).col1)::text)))
  Rows Removed by Filter: 30
  Buffers: shared hit=1937
  SubPlan 1
    -> Seq Scan on bookings b (cost=0.00..3383.92 rows=144792 width=10) (actual time=0.005..6.048 rows=144792.00 loops=1)
Execution Time: 11.611 ms
```

### Explanation of the Bug

- **The Issue**: R13 consistently returns **`rows=0.00`**, filtering out all 30 existing coupons (`Rows Removed by Filter: 30`), despite several coupons in `coupons.csv` having never been used in any booking.
- **SQL Three-Valued Logic**:
  R13 uses the predicate:
  ```sql
  WHERE coupon_code NOT IN (SELECT coupon_code FROM bookings)
  ```
  In PostgreSQL (and standard SQL), `x NOT IN (subquery)` expands to `x <> val1 AND x <> val2 AND ... AND x <> NULL`.
  Because `bookings.coupon_code` contains `NULL` values (for bookings made without a coupon), whenever any element in the subquery is `NULL`, the comparison `x <> NULL` yields `UNKNOWN`. The conjunction of truth values containing `UNKNOWN` can never evaluate to `TRUE`. As a result, the `WHERE` clause rejects every single row.
- **Status for Phase 3**:
  The recorded execution timing (**11.659 ms average**) is completely valid as a benchmark of the baseline query as authored in `workload_30.sql`. However, the business output is mathematically incorrect. This bug is documented here and will be resolved in Phase 4 (`sql/06_optimized_queries.sql`) by rewriting the query with `NOT EXISTS` or filtering `WHERE coupon_code IS NOT NULL`.
