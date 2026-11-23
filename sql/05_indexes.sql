-- Phase 4 indexes. Run ONLY on the optimized database, never on the baseline DB.
-- Tested with EXPLAIN (ANALYZE, BUFFERS) on mmt_tarunya; exploration timings are not official benchmark results.
SET search_path TO mmt;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- R09 and rewritten R12: covering B-tree on the shared booked_at range key.
-- booked_at leads because both queries constrain a time range; INCLUDE covers R09's booking_id join
-- and R12's grouping/filter/aggregate columns without making them search keys. It also avoids a
-- separate plain (booked_at) index: that would be an exact key-prefix duplicate of this index.
CREATE INDEX IF NOT EXISTS idx_bookings_booked_at_covering
    ON bookings USING btree (booked_at)
    INCLUDE (booking_id, booking_type, status, total_amount);

-- R10: partial covering B-tree for the rare delayed-flight subset and its departure_at ordering.
-- departure_at is the range/order key; output-only columns are INCLUDE columns; the predicate is
-- copied exactly from R10 so scheduled/other flights consume no entries.
CREATE INDEX IF NOT EXISTS idx_flights_delayed_departure
    ON flights USING btree (departure_at)
    INCLUDE (flight_id, flight_no, origin, destination)
    WHERE status = 'DELAYED';

-- R11: partial covering B-tree for the pending-payment queue.
-- booked_at leads for the cutoff and ORDER BY; the exact status predicate shrinks the index;
-- selected output columns are INCLUDE columns for an index-only scan.
CREATE INDEX IF NOT EXISTS idx_bookings_pending_payment_booked_at
    ON bookings USING btree (booked_at)
    INCLUDE (booking_id, booking_ref, customer_id, total_amount)
    WHERE status = 'PENDING_PAYMENT';

-- Rewritten R13: partial B-tree for equality probes by coupon_code.
-- NULL booking coupon codes cannot match a coupon; excluding them keeps this anti-join index small.
CREATE INDEX IF NOT EXISTS idx_bookings_coupon_code_nonnull
    ON bookings USING btree (coupon_code)
    WHERE coupon_code IS NOT NULL;

-- No retained R14 or R15 index: R14's candidate flight_bookings index was ignored during its full
-- aggregate; both tested R15 date indexes were ineffective or slower end-to-end. Do not keep those
-- candidates alongside other owners' future indexes without retesting and duplicate review.

-- Parv's tested requests (R01–R08, R16–R22).
-- R01/R02 need the sargable departure_at range rewrites in 06_optimized_queries.sql;
-- the original DATE()/::date predicates do not use departure_at as a B-tree range condition.

-- R01/R02: route equality followed by the departure range; also supports both route lookups.
CREATE INDEX IF NOT EXISTS idx_flights_route_departure
    ON flights USING btree (origin, destination, departure_at);

-- R01/R07/R08: flight join key with passengers covered for per-flight sums.
-- PHASE 5 FIX: booking_id added to INCLUDE. On large data R01 (avg 5.501 ms, target < 5 ms) and R07 fetched
-- one flight_bookings heap row per booking (101 and 148 rows) only to read booking_id for the bookings join;
-- on a cold first run those were random heap reads. With booking_id included, both read flight_bookings as an
-- Index Only Scan (Heap Fetches: 0). R08 keeps its Index Only Scan.
CREATE INDEX IF NOT EXISTS idx_flight_bookings_flight
    ON flight_bookings USING btree (flight_id) INCLUDE (passengers, booking_id);

-- R03/R18: city equality, then star-rating range; city alone is the leftmost prefix for R18.
CREATE INDEX IF NOT EXISTS idx_hotels_city_star
    ON hotels USING btree (city_name, star_rating);

-- R04: hotel_id is not the leftmost key of uq_room_types_id_hotel (room_type_id, hotel_id).
CREATE INDEX IF NOT EXISTS idx_room_types_hotel
    ON room_types USING btree (hotel_id);

-- R04: room-type equality then check-in range; included columns cover overlap and room aggregation.
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_roomtype_checkin
    ON hotel_bookings USING btree (room_type_id, check_in) INCLUDE (check_out, rooms);

-- R05: customer/status equality lookup; customer_id leads as the more selective condition.
CREATE INDEX IF NOT EXISTS idx_bookings_customer_status
    ON bookings USING btree (customer_id, status);

-- R08: scheduled-flight subset ordered by departure; predicate is copied from the query.
CREATE INDEX IF NOT EXISTS idx_flights_scheduled_departure
    ON flights USING btree (departure_at) WHERE status = 'SCHEDULED';

-- R18: GIN trigrams support the leading-wildcard ILIKE substring search.
CREATE INDEX IF NOT EXISTS idx_hotel_reviews_text_trgm
    ON hotel_reviews USING gin (review_text gin_trgm_ops);

-- Indexes requested by Yash (R23–R25, W01–W05)
-- (Analysed by Parv.) R23 sign-in: WHERE lower(email) = '...' cannot use uq_customers_email (on email itself).
-- Expression B-tree on lower(email) matches the predicate exactly.
CREATE INDEX IF NOT EXISTS idx_customers_email_lower
    ON customers (lower(email));

-- R24 Goa hotel ranking: hotel_reviews joined on hotel_id; INCLUDE rating so avg(rating) can be read from the index.
-- The hotels side uses idx_hotels_city_star.
CREATE INDEX IF NOT EXISTS idx_hotel_reviews_hotel_rating
    ON hotel_reviews (hotel_id) INCLUDE (rating);

-- W05 front desk: check_in = '2026-07-01' AND room_number IS NULL. Partial B-tree holds only stays without a room;
-- idx_hotel_bookings_roomtype_checkin cannot be used (room_type_id leads). Rows leave this index once a room is assigned.
CREATE INDEX IF NOT EXISTS idx_hotel_bookings_checkin_unassigned
    ON hotel_bookings (check_in) WHERE room_number IS NULL;

-- Tested, nothing added: R25 (already uses idx_bookings_booked_at_covering), W01/W03 (insert / unique lookup),
-- W02 (already served by idx_bookings_pending_payment_booked_at), W04 (small table, no gain).

-- PHASE 5 FIX: R03 on large data read 1311 buffers: idx_hotels_city_star matched every 4★+ Goa hotel, then
-- the pool filter, a heap fetch per row and a top-N sort ran before LIMIT 20. Keys are city equality,
-- the exact pool expression from R03, then user_rating in the query's ORDER BY direction, so the scan
-- returns rows already ordered and stops after 20 rows that pass star_rating >= 4 (INCLUDE column).
CREATE INDEX IF NOT EXISTS idx_hotels_city_pool_rating
    ON hotels USING btree (city_name, (amenities ->> 'pool'), user_rating DESC NULLS LAST)
    INCLUDE (star_rating, hotel_name);

-- PHASE 5 FIX: W02 on large data walked pk_bookings in booking_id order, filtering status row by row
-- (2,895,317 rows removed) because pending bookings sit at the high end of booking_id. A partial index on
-- booking_id for pending rows only answers min(booking_id) WHERE status = 'PENDING_PAYMENT' from its first
-- entry. Write overhead: W01 inserts a pending entry; W02/W03 remove a row when its status leaves pending.
CREATE INDEX IF NOT EXISTS idx_bookings_pending_payment_id
    ON bookings USING btree (booking_id)
    WHERE status = 'PENDING_PAYMENT';

ANALYZE;
-- Write overhead review for this file's indexes:
-- idx_bookings_booked_at_covering: W01 inserts an entry; W02/W03 change included status and update it.
-- idx_flights_delayed_departure: W04 can remove delayed flights from this partial index as status changes.
-- idx_bookings_pending_payment_booked_at: W01 inserts pending entries; W02 removes a confirmed row;
-- W03 may remove a row if its target was pending before cancellation.
-- idx_bookings_coupon_code_nonnull: none of W01–W05 changes coupon_code; W01's NULL coupon is excluded,
-- while W02/W03 only change status. W05 updates room_number, not an indexed column (no R15 index retained).
-- Parv's indexes: W01 inserts into idx_bookings_customer_status; W02/W03 change status in that index.
-- W04 may remove rows from idx_flights_scheduled_departure; W05 changes no Parv-indexed column.
-- idx_customers_email_lower: no workload write touches customers.
-- idx_hotel_reviews_hotel_rating: no workload write touches hotel_reviews.
-- idx_hotel_bookings_checkin_unassigned: W05 sets room_number, so updated rows leave this partial index (extra index write).
