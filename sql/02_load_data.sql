-- ============================================================================
-- Script: sql/02_load_data.sql
-- Project: MakeMyTrip Travel Booking Database (DBMS Project - Team 91)
-- Purpose: Load seed data from CSV exports into schema 'mmt', analyze tables,
--          verify loaded row counts, and execute integrity and data validation checks.
--
-- How to run (from repository root):
--     psql -d <database_name> -f sql/02_load_data.sql
--
-- Prerequisite:
--     Assumes sql/01_schema.sql has already been executed on the database
--     so that the schema 'mmt' and all 12 tables and constraints exist.
-- ============================================================================

\set ON_ERROR_STOP on
SET search_path TO mmt;

-- ----------------------------------------------------------------------------
-- 3. Data Loading (\copy in parent-before-child order)
-- ----------------------------------------------------------------------------
-- Parents: none (independent table)
\copy airports FROM 'seed_data/airports.csv' WITH (FORMAT csv, HEADER true)
-- Parents: none (independent table)
\copy airlines FROM 'seed_data/airlines.csv' WITH (FORMAT csv, HEADER true)
-- Parents: airlines (airline_code), airports (origin, destination)
\copy flights FROM 'seed_data/flights.csv' WITH (FORMAT csv, HEADER true)
-- Parents: none (independent table)
\copy hotels FROM 'seed_data/hotels.csv' WITH (FORMAT csv, HEADER true)
-- Parents: hotels (hotel_id)
\copy room_types FROM 'seed_data/room_types.csv' WITH (FORMAT csv, HEADER true)
-- Parents: none (independent table)
\copy customers FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true)
-- Parents: none (independent table)
\copy coupons FROM 'seed_data/coupons.csv' WITH (FORMAT csv, HEADER true)
-- Parents: customers (customer_id), coupons (coupon_code)
\copy bookings FROM 'seed_data/bookings.csv' WITH (FORMAT csv, HEADER true)
-- Parents: bookings (booking_id), flights (flight_id)
\copy flight_bookings FROM 'seed_data/flight_bookings.csv' WITH (FORMAT csv, HEADER true)
-- Parents: flight_bookings (booking_id)
\copy passengers FROM 'seed_data/passengers.csv' WITH (FORMAT csv, HEADER true)
-- Parents: bookings (booking_id), hotels (hotel_id), room_types (room_type_id)
\copy hotel_bookings FROM 'seed_data/hotel_bookings.csv' WITH (FORMAT csv, HEADER true)
-- Parents: hotel_bookings (booking_id, hotel_id)
\copy hotel_reviews FROM 'seed_data/hotel_reviews.csv' WITH (FORMAT csv, HEADER true)

-- ----------------------------------------------------------------------------
-- 4. Analyze Tables
-- ----------------------------------------------------------------------------
ANALYZE;

-- ----------------------------------------------------------------------------
-- 5. Row Count Verification
-- ----------------------------------------------------------------------------
SELECT
    table_name,
    actual_count,
    expected_count,
    (actual_count = expected_count) AS matches
FROM (
    SELECT 'airports' AS table_name, count(*) AS actual_count, 16 AS expected_count FROM airports
    UNION ALL
    SELECT 'airlines', count(*), 5 FROM airlines
    UNION ALL
    SELECT 'flights', count(*), 13848 FROM flights
    UNION ALL
    SELECT 'hotels', count(*), 3000 FROM hotels
    UNION ALL
    SELECT 'room_types', count(*), 9000 FROM room_types
    UNION ALL
    SELECT 'customers', count(*), 40000 FROM customers
    UNION ALL
    SELECT 'coupons', count(*), 30 FROM coupons
    UNION ALL
    SELECT 'bookings', count(*), 144792 FROM bookings
    UNION ALL
    SELECT 'flight_bookings', count(*), 84899 FROM flight_bookings
    UNION ALL
    SELECT 'passengers', count(*), 163380 FROM passengers
    UNION ALL
    SELECT 'hotel_bookings', count(*), 59893 FROM hotel_bookings
    UNION ALL
    SELECT 'hotel_reviews', count(*), 15913 FROM hotel_reviews
) counts;

-- ----------------------------------------------------------------------------
-- 6. Integrity Checks (IC1 - IC10)
-- ----------------------------------------------------------------------------

-- IC1: flight_bookings.passengers equals the number of passengers rows for that booking
SELECT count(*) AS ic1_violations
FROM flight_bookings fb
LEFT JOIN (
    SELECT booking_id, count(*) AS actual_passengers
    FROM passengers
    GROUP BY booking_id
) p ON p.booking_id = fb.booking_id
WHERE fb.passengers <> coalesce(p.actual_passengers, 0);

-- IC2: no flight booking was made after its flight departed (bookings.booked_at > flights.departure_at)
SELECT count(*) AS ic2_violations
FROM flight_bookings fb
JOIN bookings b ON b.booking_id = fb.booking_id
JOIN flights f  ON f.flight_id = fb.flight_id
WHERE b.booked_at > f.departure_at;

-- IC3: every booking is in exactly one of flight_bookings / hotel_bookings, never both and never neither
SELECT count(*) AS ic3_violations
FROM bookings b
LEFT JOIN flight_bookings fb ON fb.booking_id = b.booking_id
LEFT JOIN hotel_bookings hb  ON hb.booking_id = b.booking_id
WHERE (fb.booking_id IS NOT NULL AND hb.booking_id IS NOT NULL)
   OR (fb.booking_id IS NULL AND hb.booking_id IS NULL);

-- IC4: booking_type matches the child table (FLIGHT <-> flight_bookings, HOTEL <-> hotel_bookings)
SELECT count(*) AS ic4_violations
FROM bookings b
LEFT JOIN flight_bookings fb ON fb.booking_id = b.booking_id
LEFT JOIN hotel_bookings hb  ON hb.booking_id = b.booking_id
WHERE (b.booking_type = 'FLIGHT' AND (fb.booking_id IS NULL OR hb.booking_id IS NOT NULL))
   OR (b.booking_type = 'HOTEL'  AND (hb.booking_id IS NULL OR fb.booking_id IS NOT NULL))
   OR (b.booking_type NOT IN ('FLIGHT', 'HOTEL'));

-- IC5: no flight is overbooked: sum(passengers) over non-cancelled bookings <= total_seats
SELECT count(*) AS ic5_violations
FROM (
    SELECT f.flight_id, f.total_seats, sum(fb.passengers) AS booked_passengers
    FROM flights f
    JOIN flight_bookings fb ON fb.flight_id = f.flight_id
    JOIN bookings b         ON b.booking_id = fb.booking_id
    WHERE b.status <> 'CANCELLED'
    GROUP BY f.flight_id, f.total_seats
    HAVING sum(fb.passengers) > f.total_seats
) overbooked;

-- IC6: hotel_reviews.hotel_id equals the hotel of its booking
SELECT count(*) AS ic6_violations
FROM hotel_reviews r
JOIN hotel_bookings hb ON hb.booking_id = r.booking_id
WHERE r.hotel_id <> hb.hotel_id;

-- IC7: reviews exist only for COMPLETED bookings and are created on or after check_out
SELECT count(*) AS ic7_violations
FROM hotel_reviews r
JOIN bookings b        ON b.booking_id = r.booking_id
JOIN hotel_bookings hb ON hb.booking_id = r.booking_id
WHERE b.status <> 'COMPLETED'
   OR (r.created_at AT TIME ZONE 'Asia/Kolkata')::date < hb.check_out;

-- IC8: coupon used only for a matching booking type (applies_to = 'ALL' or = booking_type)
SELECT count(*) AS ic8_violations
FROM bookings b
JOIN coupons c ON c.coupon_code = b.coupon_code
WHERE b.coupon_code IS NOT NULL
  AND c.applies_to <> 'ALL'
  AND c.applies_to <> b.booking_type;

-- IC9: booking date within the coupon's valid_from..valid_to, and discount <= max_discount
SELECT count(*) AS ic9_violations
FROM bookings b
JOIN coupons c ON c.coupon_code = b.coupon_code
WHERE b.coupon_code IS NOT NULL
  AND (
      (b.booked_at AT TIME ZONE 'Asia/Kolkata')::date < c.valid_from
      OR (b.booked_at AT TIME ZONE 'Asia/Kolkata')::date > c.valid_to
      OR b.discount > c.max_discount
  );

-- IC10: no booking earlier than the customer's created_at
SELECT count(*) AS ic10_violations
FROM bookings b
JOIN customers c ON c.customer_id = b.customer_id
WHERE b.booked_at < c.created_at;

-- ----------------------------------------------------------------------------
-- Data-Problem Queries (DP1 - DP5: Known issues to report, not failures)
-- ----------------------------------------------------------------------------

-- DP1: hotel bookings with guests > rooms * room_types.max_guests
SELECT count(*) AS dp1_count
FROM hotel_bookings hb
JOIN room_types rt ON rt.room_type_id = hb.room_type_id
WHERE hb.guests > hb.rooms * rt.max_guests;

-- DP2: duplicate seat_no on the same flight among non-cancelled bookings
-- counts (flight_id, seat_no) pairs assigned to more than one passenger
SELECT count(*) AS dp2_count
FROM (
    SELECT fb.flight_id, p.seat_no
    FROM passengers p
    JOIN flight_bookings fb ON fb.booking_id = p.booking_id
    JOIN bookings b         ON b.booking_id = fb.booking_id
    WHERE b.status <> 'CANCELLED'
      AND p.seat_no IS NOT NULL
      AND p.seat_no <> ''
    GROUP BY fb.flight_id, p.seat_no
    HAVING count(*) > 1
) dupes;

-- DP3: passengers with a seat_no whose booking is PENDING_PAYMENT
SELECT count(*) AS dp3_count
FROM passengers p
JOIN bookings b ON b.booking_id = p.booking_id
WHERE b.status = 'PENDING_PAYMENT'
  AND p.seat_no IS NOT NULL
  AND p.seat_no <> '';

-- DP4: flight_bookings where fare_paid <> bookings.total_amount + bookings.discount
SELECT count(*) AS dp4_count
FROM flight_bookings fb
JOIN bookings b ON b.booking_id = fb.booking_id
WHERE fb.fare_paid <> (b.total_amount + b.discount);

-- DP5: flights still SCHEDULED or DELAYED with departure_at before 2026-07-01 00:00+05:30
SELECT count(*) AS dp5_count
FROM flights
WHERE status IN ('SCHEDULED', 'DELAYED')
  AND departure_at < TIMESTAMPTZ '2026-07-01 00:00:00+05:30';
