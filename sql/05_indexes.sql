-- Phase 4 indexes. Run ONLY on the optimized database, never on the baseline DB.
-- Tested with EXPLAIN (ANALYZE, BUFFERS) on mmt_tarunya; exploration timings are not official benchmark results.
SET search_path TO mmt;

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

-- Indexes requested by Parv (R01–R08, R16–R22)
-- TODO: Add only Parv's owner-tested indexes. Check for exact duplicates and key-prefix duplicates.

-- Indexes requested by Yash (R23–R25, W01–W05)
-- TODO: Add only Yash's owner-tested indexes. Check for exact duplicates and key-prefix duplicates.

ANALYZE;
-- Write overhead review for this file's indexes:
-- idx_bookings_booked_at_covering: W01 inserts an entry; W02/W03 change included status and update it.
-- idx_flights_delayed_departure: W04 can remove delayed flights from this partial index as status changes.
-- idx_bookings_pending_payment_booked_at: W01 inserts pending entries; W02 removes a confirmed row;
-- W03 may remove a row if its target was pending before cancellation.
-- idx_bookings_coupon_code_nonnull: none of W01–W05 changes coupon_code; W01's NULL coupon is excluded,
-- while W02/W03 only change status. W05 updates room_number, not an indexed column (no R15 index retained).
