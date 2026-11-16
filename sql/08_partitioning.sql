-- =====================================================================
-- sql/08_partitioning.sql  —  Phase 5 design: partition bookings by month
-- Builds a SEPARATE schema mmt_part from the already-loaded mmt schema.
-- Never touches mmt and must never be run on the baseline database.
-- Run after 01_schema.sql + 02_load_data.sql:
--     psql -d \<db> -f sql/08_partitioning.sql
-- =====================================================================
\set ON_ERROR_STOP on
DROP SCHEMA IF EXISTS mmt_part CASCADE;
CREATE SCHEMA mmt_part;
SET search_path TO mmt_part;

-- Same columns, defaults and CHECKs as mmt.bookings; partitioned by booking time.
CREATE TABLE bookings (LIKE mmt.bookings INCLUDING DEFAULTS INCLUDING CONSTRAINTS)
   PARTITION BY RANGE (booked_at);

-- PRIMARY KEY rule: on a partitioned table, every PRIMARY KEY / UNIQUE constraint
-- must include the partition key column(s).
ALTER TABLE bookings ADD CONSTRAINT pk_bookings PRIMARY KEY (booking_id, booked_at);
ALTER TABLE bookings ADD CONSTRAINT uq_bookings_ref UNIQUE (booking_ref, booked_at);
-- Consequences:
--  * booking_ref is no longer guaranteed globally unique (only per booked_at).
--  * flight_bookings / hotel_bookings can no longer have an FK on booking_id alone,
--    because an FK must reference a complete unique key, now (booking_id, booked_at).

-- One partition per month, Jan 2025 – Dec 2026. Boundaries are midnight in the session time zone (Asia/Kolkata).
DO $$
DECLARE m date := DATE '2025-01-01';
BEGIN
  WHILE m < DATE '2027-01-01' LOOP
    EXECUTE format('CREATE TABLE %I PARTITION OF bookings FOR VALUES FROM (%L) TO (%L)',
                   'bookings_' || to_char(m, 'YYYY_MM'),
                   m::timestamptz, (m + interval '1 month')::timestamptz);
    m := m + interval '1 month';
  END LOOP;
END $$;

-- Safety net for rows outside the defined range
CREATE TABLE bookings_default PARTITION OF bookings DEFAULT;

INSERT INTO bookings SELECT * FROM mmt.bookings;
ANALYZE bookings;

-- ---------------------------------------------------------------------
-- Evidence (seed data, Parv's machine, PostgreSQL 18.6; full output kept outside the repo):
--  E3  booked_at in June 2026      -> only bookings_2026_06 scanned (105 buffers)          = pruning works
--  E4a EXTRACT(YEAR FROM booked_at) -> all 25 partitions scanned (1,916 buffers, 48.9 ms)  = function on key blocks pruning
--  E4b booked_at >= 2026 AND < 2027 -> only 2026 partitions (634 buffers, 24.2 ms)          = sargable range restores pruning
--  E5  booking_ref lookup          -> every partition probed (planning 1.9 ms > execution 0.25 ms) = non-key lookups get worse
--  E6  W01-style row (2026-07-01)  -> routed to bookings_2026_07                            = partitions must exist ahead of time
--  E7  storage: 28 MB partitioned vs 23 MB unpartitioned (+22%)
-- ---------------------------------------------------------------------
