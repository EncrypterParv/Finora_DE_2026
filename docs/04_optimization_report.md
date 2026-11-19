# Phase 4 Optimization Report

## Method

The official before results are `benchmarks/results/baseline/` from the same benchmark laptop recorded in `team.json`: Devansh Chauhan – Apple M4, 16 GB RAM, macOS 26.4.1. PostgreSQL version: PostgreSQL 18.6 (Postgres.app). The session timezone was Asia/Kolkata. The baseline used the schema and load with its 20 primary-key/unique indexes. The after run used the same schema and load plus `sql/05_indexes.sql`, with query blocks from `sql/06_optimized_queries.sql`. Both summaries record three runs per query; averages below are taken directly from the corresponding `summary.csv` files.

## Results

| SQL Query | Before avg (ms) | After avg (ms) | Improvement % | What changed | Same result? |
|---|---:|---:|---:|---|---|
| R01 | 8.399 | 0.423 | 95.0% | idx_flight_bookings_flight, idx_flights_route_departure | Yes (proof §5) |
| R02 | 0.794 | 0.198 | 75.1% | idx_flights_route_departure | Yes (proof §5) |
| R03 | 0.212 | 0.501 | -136.3% | idx_hotels_city_star | Yes (query unchanged) |
| R04 | 2.071 | 0.457 | 77.9% | idx_hotel_bookings_roomtype_checkin, idx_room_types_hotel | Yes (query unchanged) |
| R05 | 5.871 | 0.247 | 95.8% | idx_bookings_customer_status | Yes (query unchanged) |
| R06 | 0.030 | 0.061 | -103.3% | query unchanged | Yes (query unchanged) |
| R07 | 2.146 | 0.656 | 69.4% | idx_flight_bookings_flight | Yes (query unchanged) |
| R08 | 5.279 | 2.515 | 52.4% | idx_flight_bookings_flight, idx_flights_scheduled_departure | Yes (query unchanged) |
| R09 | 12.216 | 16.907 | -38.4% | idx_bookings_booked_at_covering | Yes (query unchanged) |
| R10 | 0.693 | 0.433 | 37.5% | idx_flights_delayed_departure | Yes (query unchanged) |
| R11 | 4.869 | 0.519 | 89.3% | idx_bookings_pending_payment_booked_at | Yes (query unchanged) |
| R12 | 26.540 | 28.215 | -6.3% | idx_bookings_booked_at_covering | Yes (proof §5) |
| R13 | 11.659 | 1.031 | 91.2% | idx_bookings_coupon_code_nonnull | No — original was wrong; fixed (§6) |
| R14 | 26.957 | 57.784 | -114.4% | query unchanged | Yes (query unchanged) |
| R15 | 14.205 | 28.221 | -98.7% | query unchanged | Yes (query unchanged) |
| R16 | 60.403 | 114.480 | -89.5% | query unchanged | Yes (query unchanged) |
| R17 | 16.646 | 28.264 | -69.8% | idx_bookings_booked_at_covering | Yes (query unchanged) |
| R18 | 4.315 | 2.874 | 33.4% | idx_hotel_reviews_text_trgm, idx_hotels_city_star | Yes (query unchanged) |
| R19 | 1328.493 | 67.355 | 94.9% | rewrite (§4) | Yes (proof §5) |
| R20 | 6.718 | 2.187 | 67.4% | idx_bookings_booked_at_covering | Yes (proof §5) |
| R21 | 16.886 | 34.210 | -102.6% | query unchanged | Yes (query unchanged) |
| R22 | 32.400 | 0.307 | 99.1% | idx_bookings_booked_at_covering | Yes (proof §5) |
| R23 | 8.484 | 0.294 | 96.5% | idx_customers_email_lower | Yes (query unchanged) |
| R24 | 1.529 | 3.131 | -104.8% | idx_hotels_city_star | Yes (query unchanged) |
| R25 | 17.688 | 29.800 | -68.5% | idx_bookings_booked_at_covering | Yes (query unchanged) |
| W01 | 0.420 | 1.228 | -192.4% | query unchanged | Yes (query unchanged) |
| W02 | 9.370 | 0.641 | 93.2% | idx_bookings_pending_payment_booked_at | Yes (query unchanged) |
| W03 | 0.187 | 0.711 | -280.2% | query unchanged | Yes (query unchanged) |
| W04 | 0.995 | 2.594 | -160.7% | query unchanged | Yes (query unchanged) |
| W05 | 2.389 | 5.557 | -132.6% | idx_hotel_bookings_checkin_unassigned | Yes (query unchanged) |
| **Total of 30 averages** | **1628.864** | **431.801** | **73.5%** | — | — |

## Indexes

All `CREATE INDEX` statements in `sql/05_indexes.sql` are listed below. The definitions and rationales follow the SQL comments; sizes come from `/tmp/storage.txt`.

| Index | Definition | Queries served | Why this type and key order | Size |
|---|---|---|---|---:|
| `idx_bookings_booked_at_covering` | `ON bookings USING btree (booked_at)     INCLUDE (booking_id, booking_type, status, total_amount)` | R09, R12, R17, R20, R22, R25, W01-W03 | booked_at leads for the shared time range and ordering; INCLUDE columns cover query joins and selected/grouped values; a plain booked_at index would duplicate its key prefix. | 8368 kB |
| `idx_flights_delayed_departure` | `ON flights USING btree (departure_at)     INCLUDE (flight_id, flight_no, origin, destination)     WHERE status = 'DELAYED'` | R10, W04 | Partial covering B-tree on departure_at for the delayed subset and output columns; W04 can remove rows when status changes. | 16 kB |
| `idx_bookings_pending_payment_booked_at` | `ON bookings USING btree (booked_at)     INCLUDE (booking_id, booking_ref, customer_id, total_amount)     WHERE status = 'PENDING_PAYMENT'` | R11, W01-W03 | Partial covering B-tree on booked_at for cutoff/order; exact pending status predicate shrinks it and output columns are included. | 16 kB |
| `idx_bookings_coupon_code_nonnull` | `ON bookings USING btree (coupon_code)     WHERE coupon_code IS NOT NULL` | R13 | Partial B-tree for coupon equality probes; NULL coupon codes cannot match and are excluded. | 144 kB |
| `idx_flights_route_departure` | `ON flights USING btree (origin, destination, departure_at)` | R01, R02 | Equality route columns precede the departure range, matching both route filters. | 448 kB |
| `idx_flight_bookings_flight` | `ON flight_bookings USING btree (flight_id) INCLUDE (passengers)` | R01, R07, R08 | flight_id equality/join key; passengers included for per-flight aggregation. | 1888 kB |
| `idx_hotels_city_star` | `ON hotels USING btree (city_name, star_rating)` | R03, R18, R24 | city_name equality leads; star_rating follows for R03 filtering; city alone supports city lookup. | 40 kB |
| `idx_room_types_hotel` | `ON room_types USING btree (hotel_id)` | R04 | hotel_id lookup; it is not the leftmost key in the existing unique index. | 160 kB |
| `idx_hotel_bookings_roomtype_checkin` | `ON hotel_bookings USING btree (room_type_id, check_in) INCLUDE (check_out, rooms)` | R04 | room_type_id equality then check_in range; check_out and rooms included for overlap and aggregation. | 1856 kB |
| `idx_bookings_customer_status` | `ON bookings USING btree (customer_id, status)` | R05, W01-W03 | customer_id/status equality lookup; customer_id leads as the more selective condition. | 2624 kB |
| `idx_flights_scheduled_departure` | `ON flights USING btree (departure_at) WHERE status = 'SCHEDULED'` | R08, W04 | Partial B-tree on departure_at for scheduled flights; exact query predicate shrinks the index. | 40 kB |
| `idx_hotel_reviews_text_trgm` | `ON hotel_reviews USING gin (review_text gin_trgm_ops)` | R18 | GIN trigram index supports leading-wildcard ILIKE substring search. | 504 kB |
| `idx_customers_email_lower` | `ON customers (lower(email))` | R23 | Expression B-tree on lower(email) exactly matches the case-insensitive predicate; uq_customers_email stores email itself. | 2080 kB |
| `idx_hotel_reviews_hotel_rating` | `ON hotel_reviews (hotel_id) INCLUDE (rating)` | R24 | hotel_id supports the join; rating is included for the average aggregation. Hotels use idx_hotels_city_star. | 368 kB |
| `idx_hotel_bookings_checkin_unassigned` | `ON hotel_bookings (check_in) WHERE room_number IS NULL` | W05 | Partial B-tree on check_in for unassigned stays; room_type_id leads the existing room-type index, and rows leave this index after room_number is set. | 80 kB |

### Table sizes

| Table | Size |
|---|---:|
| `airlines` | 8192 bytes |
| `airports` | 8192 bytes |
| `bookings` | 15 MB |
| `coupons` | 8192 bytes |
| `customers` | 4224 kB |
| `flight_bookings` | 5120 kB |
| `flights` | 1536 kB |
| `hotel_bookings` | 3584 kB |
| `hotel_reviews` | 1728 kB |
| `hotels` | 576 kB |
| `passengers` | 10 MB |
| `room_types` | 520 kB |

Total size of the 15 `idx_%` indexes: **18 MB**.

## Rewrites

### R01

Why: Made the departure date predicate sargable for the composite route/date index.

**Original SQL**

```sql
SELECT f.flight_id, f.flight_no, f.departure_at, f.arrival_at, f.base_fare,
       f.total_seats - coalesce(sum(fb.passengers) FILTER (WHERE b.status <> 'CANCELLED'), 0) AS seats_left
FROM flights f
LEFT JOIN flight_bookings fb ON fb.flight_id = f.flight_id
LEFT JOIN bookings b         ON b.booking_id = fb.booking_id
WHERE f.origin = 'DEL' AND f.destination = 'BOM'
  AND DATE(f.departure_at) = '2026-07-05'
  AND f.status <> 'CANCELLED'
GROUP BY f.flight_id, f.flight_no, f.departure_at, f.arrival_at, f.base_fare, f.total_seats
ORDER BY f.departure_at;
```

**Rewritten SQL**

```sql
SELECT f.flight_id, f.flight_no, f.departure_at, f.arrival_at, f.base_fare,
       f.total_seats - coalesce(sum(fb.passengers) FILTER (WHERE b.status <> 'CANCELLED'), 0) AS seats_left
FROM flights f
LEFT JOIN flight_bookings fb ON fb.flight_id = f.flight_id
LEFT JOIN bookings b         ON b.booking_id = fb.booking_id
WHERE f.origin = 'DEL' AND f.destination = 'BOM'
  AND f.departure_at >= '2026-07-05' AND f.departure_at < '2026-07-06'
  AND f.status <> 'CANCELLED'
GROUP BY f.flight_id, f.flight_no, f.departure_at, f.arrival_at, f.base_fare, f.total_seats
ORDER BY f.departure_at;
```

### R02

Why: Replaced the date cast filter with a session-local sargable range.

**Original SQL**

```sql
SELECT departure_at::date AS day, min(base_fare) AS cheapest_fare
FROM flights
WHERE origin = 'BLR' AND destination = 'DEL'
  AND departure_at::date BETWEEN '2026-07-01' AND '2026-07-31'
GROUP BY 1
ORDER BY 1;
```

**Rewritten SQL**

```sql
SELECT departure_at::date AS day, min(base_fare) AS cheapest_fare
FROM flights
WHERE origin = 'BLR' AND destination = 'DEL'
  AND departure_at >= '2026-07-01' AND departure_at < '2026-08-01'
GROUP BY 1
ORDER BY 1;
```

### R12

Why: EXTRACT(YEAR FROM booked_at) replaced by a half-open booked_at range so the booked_at index can be used; date_trunc kept for grouping/output.

**Original SQL**

```sql
SELECT date_trunc('month', booked_at) AS month, booking_type, count(*) AS bookings, sum(total_amount) AS revenue
FROM bookings
WHERE status <> 'CANCELLED'
  AND EXTRACT(YEAR FROM booked_at) = 2026
GROUP BY 1, 2
ORDER BY 1, 2;
```

**Rewritten SQL**

```sql
SELECT date_trunc('month', booked_at) AS month, booking_type, count(*) AS bookings, sum(total_amount) AS revenue
FROM bookings
WHERE status <> 'CANCELLED'
  AND booked_at >= '2026-01-01' AND booked_at < '2027-01-01'
GROUP BY 1, 2
ORDER BY 1, 2;
```

### R13

Why: NOT IN returned 0 rows because bookings.coupon_code contains NULLs (x NOT IN (..., NULL) is never TRUE). NOT EXISTS returns the 10 unused coupons — an intended correction of a wrong result.

**Original SQL**

```sql
SELECT c.coupon_code, c.applies_to, c.discount_pct
FROM coupons c
WHERE c.coupon_code NOT IN (SELECT b.coupon_code FROM bookings b);
```

**Rewritten SQL**

```sql
SELECT c.coupon_code, c.applies_to, c.discount_pct
FROM coupons c
WHERE NOT EXISTS (SELECT 1 FROM bookings b WHERE b.coupon_code = c.coupon_code);
```

### R19

Why: Aggregated passenger rows once for June flights instead of a correlated count per flight.

**Original SQL**

```sql
SELECT f.flight_id, f.flight_no, f.departure_at,
       (SELECT count(*) FROM passengers p JOIN flight_bookings fb ON fb.booking_id = p.booking_id
         WHERE fb.flight_id = f.flight_id) AS passengers
FROM flights f
WHERE f.departure_at >= '2026-06-01' AND f.departure_at < '2026-07-01'
ORDER BY passengers DESC, f.departure_at;
```

**Rewritten SQL**

```sql
SELECT f.flight_id, f.flight_no, f.departure_at, coalesce(pc.passengers, 0) AS passengers
FROM flights f
LEFT JOIN (SELECT fb.flight_id, count(*) AS passengers
           FROM passengers p JOIN flight_bookings fb ON fb.booking_id = p.booking_id
           GROUP BY fb.flight_id) pc ON pc.flight_id = f.flight_id
WHERE f.departure_at >= '2026-06-01' AND f.departure_at < '2026-07-01'
ORDER BY passengers DESC, f.departure_at;
```

### R20

Why: Replaced booked_at::date filtering with a sargable session-local range.

**Original SQL**

```sql
SELECT day, bookings, sum(bookings) OVER (ORDER BY day) AS running_total
FROM (
    SELECT booked_at::date AS day, count(*) AS bookings
    FROM bookings
    WHERE booked_at::date BETWEEN '2026-06-01' AND '2026-06-30'
    GROUP BY 1
) d
ORDER BY day;
```

**Rewritten SQL**

```sql
SELECT day, bookings, sum(bookings) OVER (ORDER BY day) AS running_total
FROM (
    SELECT booked_at::date AS day, count(*) AS bookings
    FROM bookings
    WHERE booked_at >= '2026-06-01' AND booked_at < '2026-07-01'
    GROUP BY 1
) d
ORDER BY day;
```

### R22

Why: Keyset pagination avoids sorting and skipping the preceding 100,000 rows.

**Original SQL**

```sql
SELECT booking_id, booking_ref, booking_type, status, total_amount, booked_at
FROM bookings
ORDER BY booked_at DESC
OFFSET 100000
LIMIT 25;
```

**Rewritten SQL**

```sql
SELECT booking_id, booking_ref, booking_type, status, total_amount, booked_at
FROM bookings
WHERE (booked_at, booking_id) < (TIMESTAMPTZ '2025-06-18 22:17:24+05:30', 46410)
ORDER BY booked_at DESC, booking_id DESC
LIMIT 25;
```

R22 uses a keyset cursor taken from the last row of the previous page and includes `booking_id` as a tie-breaker. Recompute the cursor from row 100,000 on the large data set.

## Correctness proofs

Proofs were run against `mmt_proof`, loaded from the schema and seed data without extra indexes. Counts, both `EXCEPT ALL` directions, and ordered hashes are read from `/tmp/proofs_out.txt`.

| Query | Original rows | Rewritten rows | Only in original | Only in rewritten | Ordered md5 matches? |
|---|---:|---:|---:|---:|---|
| R01 | 1 | 1 | 0 | 0 | Yes |
| R02 | 31 | 31 | 0 | 0 | Yes |
| R12 | 12 | 12 | 0 | 0 | Yes |
| R13 | 0 | 10 | 0 | 10 | No |
| R19 | 720 | 720 | 0 | 0 | Yes |
| R20 | 30 | 30 | 0 | 0 | Yes |
| R22 | 25 | 25 | 0 | 0 | Yes |

All equivalent rewrites have zero rows in each `EXCEPT ALL` direction and matching ordered hashes. R13 is intentionally a wrong-result correction: the original returns zero rows and the `NOT EXISTS` rewrite returns ten unused coupons. NULL values in `bookings.coupon_code` make `NOT IN` evaluate to UNKNOWN for otherwise unmatched coupon codes.

Unused coupons from the proof output:

- `STAYHAPPY22 | HOTEL | 15`
- `DIWALI29 | ALL | 20`
- `MONSOON24 | FLIGHT | 5`
- `ICICISTAY28 | HOTEL | 15`
- `FLYNOW21 | FLIGHT | 12`
- `FIRSTTRIP26 | ALL | 10`
- `MMTSUPER30 | FLIGHT | 5`
- `HDFCFLY27 | FLIGHT | 12`
- `WEEKEND25 | HOTEL | 8`
- `GOAFEST23 | ALL | 20`

## Top five improvements by milliseconds saved

These are ranked by baseline average minus optimized average. The plan excerpts are from run 3 of each raw plan file.

### R19: 1261.138 ms saved per run on average

**Baseline plan (run 3)**

```text
->  Bitmap Heap Scan on flights f  (cost=102.55..1273215.21 rows=718 width=27) (actual time=5.447..1342.573 rows=720.00 loops=1)
->  Bitmap Index Scan on uq_flights_number_departure  (cost=0.00..102.38 rows=718 width=0) (actual time=0.203..0.203 rows=730.00 loops=1)
->  Seq Scan on flight_bookings fb  (cost=0.00..1701.24 rows=7 width=8) (actual time=1.653..1.855 rows=6.64 loops=720)
Rows Removed by Filter: 84892
->  Index Only Scan using pk_passengers on passengers p  (cost=0.42..10.21 rows=2 width=8) (actual time=0.001..0.001 rows=1.95 loops=4781)
Execution Time: 1342.858 ms
```

**Optimized plan (run 3)**

```text
->  Seq Scan on passengers p  (cost=0.00..2913.80 rows=163380 width=8) (actual time=0.006..8.055 rows=163380.00 loops=1)
->  Seq Scan on flight_bookings fb  (cost=0.00..1488.99 rows=84899 width=12) (actual time=0.005..5.967 rows=84899.00 loops=1)
->  Bitmap Heap Scan on flights f  (cost=102.55..305.32 rows=718 width=19) (actual time=0.199..0.277 rows=720.00 loops=1)
->  Bitmap Index Scan on uq_flights_number_departure  (cost=0.00..102.38 rows=718 width=0) (actual time=0.190..0.192 rows=720.00 loops=1)
Execution Time: 72.426 ms
```

### R22: 32.093 ms saved per run on average

**Baseline plan (run 3)**

```text
->  Seq Scan on bookings  (cost=0.00..3383.92 rows=144792 width=47) (actual time=0.005..7.908 rows=144792.00 loops=1)
Execution Time: 32.236 ms
```

**Optimized plan (run 3)**

```text
->  Index Scan Backward using idx_bookings_booked_at_covering on bookings  (cost=0.42..2873.86 rows=44171 width=47) (actual time=0.016..0.020 rows=26.00 loops=1)
Rows Removed by Filter: 1
Execution Time: 0.077 ms
```

### R13: 10.628 ms saved per run on average

**Baseline plan (run 3)**

```text
Seq Scan on coupons c  (cost=3745.90..3747.28 rows=15 width=17) (actual time=11.474..11.474 rows=0.00 loops=1)
Rows Removed by Filter: 30
->  Seq Scan on bookings b  (cost=0.00..3383.92 rows=144792 width=10) (actual time=0.005..5.947 rows=144792.00 loops=1)
Execution Time: 11.505 ms
```

**Optimized plan (run 3)**

```text
->  Seq Scan on coupons c  (cost=0.00..1.30 rows=30 width=17) (actual time=0.005..0.007 rows=30.00 loops=1)
->  Index Only Scan using idx_bookings_coupon_code_nonnull on bookings b  (cost=0.29..22.36 rows=896 width=10) (actual time=0.004..0.004 rows=0.67 loops=30)
Execution Time: 0.162 ms
```

### W02: 8.729 ms saved per run on average

**Baseline plan (run 3)**

```text
->  Index Scan using pk_bookings on bookings bookings_1  (cost=0.29..6066.50 rows=92 width=8) (actual time=9.147..9.147 rows=1.00 loops=1)
Rows Removed by Filter: 144695
->  Index Scan using pk_bookings on bookings  (cost=0.29..8.31 rows=1 width=56) (actual time=9.155..9.155 rows=1.00 loops=1)
Execution Time: 9.346 ms
```

**Optimized plan (run 3)**

```text
->  Index Only Scan using idx_bookings_pending_payment_booked_at on bookings bookings_1  (cost=0.14..13.81 rows=111 width=8) (actual time=0.049..0.062 rows=97.00 loops=1)
->  Index Scan using pk_bookings on bookings  (cost=0.29..8.31 rows=1 width=56) (actual time=0.088..0.089 rows=1.00 loops=1)
Execution Time: 0.493 ms
```

### R23: 8.190 ms saved per run on average

**Baseline plan (run 3)**

```text
Seq Scan on customers  (cost=0.00..1128.00 rows=200 width=22) (actual time=0.224..8.421 rows=1.00 loops=1)
Rows Removed by Filter: 39999
Execution Time: 8.435 ms
```

**Optimized plan (run 3)**

```text
Index Scan using idx_customers_email_lower on customers  (cost=0.41..8.43 rows=1 width=21) (actual time=0.013..0.013 rows=1.00 loops=1)
Execution Time: 0.041 ms
```

## Write overhead

| Write query | Before avg (ms) | After avg (ms) | Change % | New indexes maintained |
|---|---:|---:|---:|---|
| W01 | 0.420 | 1.228 | 192.4% | idx_bookings_booked_at_covering, idx_bookings_customer_status, idx_bookings_pending_payment_booked_at |
| W02 | 9.370 | 0.641 | -93.2% | idx_bookings_booked_at_covering, idx_bookings_customer_status, idx_bookings_pending_payment_booked_at |
| W03 | 0.187 | 0.711 | 280.2% | idx_bookings_booked_at_covering, idx_bookings_customer_status, idx_bookings_pending_payment_booked_at |
| W04 | 0.995 | 2.594 | 160.7% | idx_flights_delayed_departure, idx_flights_scheduled_departure |
| W05 | 2.389 | 5.557 | 132.6% | idx_hotel_bookings_checkin_unassigned (updated rows leave partial index) |

Index write effects follow the comments in `sql/05_indexes.sql`: booked-at/customer/pending indexes are maintained by relevant booking writes; delayed/scheduled flight partial indexes change with W04 status updates; W05 updates leave its unassigned partial index. The customer email and hotel review indexes are untouched by workload writes.

## Not improved

Every query whose optimized average is at least the baseline average, or whose improvement is below 10%, appears here. Reasons are grounded in the recorded optimized scan nodes.

| Query | Before avg (ms) | After avg (ms) | Improvement % | Plan-based reason |
|---|---:|---:|---:|---|
| R03 | 0.212 | 0.501 | -136.3% | Bitmap Heap Scan on hotels; Bitmap Index Scan on idx_hotels_city_star |
| R06 | 0.030 | 0.061 | -103.3% | Index Scan using uq_bookings_booking_ref on bookings |
| R09 | 12.216 | 16.907 | -38.4% | Seq Scan on flight_bookings; Index Only Scan using idx_bookings_booked_at_covering on bookings; Seq Scan on flights |
| R12 | 26.540 | 28.215 | -6.3% | Index Only Scan using idx_bookings_booked_at_covering on bookings |
| R14 | 26.957 | 57.784 | -114.4% | Seq Scan on bookings; Seq Scan on flight_bookings; Seq Scan on flights; Seq Scan on airlines |
| R15 | 14.205 | 28.221 | -98.7% | Seq Scan on bookings; Seq Scan on hotel_bookings; Seq Scan on hotels |
| R16 | 60.403 | 114.480 | -89.5% | Seq Scan on bookings; Seq Scan on customers; Seq Scan on flight_bookings; Seq Scan on flights; Seq Scan on hotel_bookings |
| R17 | 16.646 | 28.264 | -69.8% | Index Scan using idx_bookings_booked_at_covering on bookings |
| R21 | 16.886 | 34.210 | -102.6% | Seq Scan on passengers; Seq Scan on flight_bookings; Seq Scan on flights |
| R24 | 1.529 | 3.131 | -104.8% | Seq Scan on hotel_reviews; Bitmap Heap Scan on hotels; Bitmap Index Scan on idx_hotels_city_star |
| R25 | 17.688 | 29.800 | -68.5% | Seq Scan on flight_bookings; Index Only Scan using idx_bookings_booked_at_covering on bookings; Seq Scan on flights |
| W01 | 0.420 | 1.228 | -192.4% | (no scan) |
| W03 | 0.187 | 0.711 | -280.2% | Index Scan using uq_bookings_booking_ref on bookings |
| W04 | 0.995 | 2.594 | -160.7% | Seq Scan on flights |
| W05 | 2.389 | 5.557 | -132.6% | Index Scan using idx_hotel_bookings_checkin_unassigned on hotel_bookings; Index Scan using pk_bookings on bookings |
