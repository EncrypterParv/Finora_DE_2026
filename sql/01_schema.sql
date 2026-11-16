DROP SCHEMA IF EXISTS mmt CASCADE;
CREATE SCHEMA mmt;
SET search_path TO mmt;

CREATE TABLE airports (
    iata_code CHAR(3) NOT NULL,
    airport_name TEXT NOT NULL,
    city_name TEXT NOT NULL,
    country_code CHAR(2) NOT NULL,
    CONSTRAINT pk_airports PRIMARY KEY (iata_code),
    CONSTRAINT chk_airports_iata_code CHECK (iata_code ~ '^[A-Z]{3}$')
);
COMMENT ON CONSTRAINT chk_airports_iata_code ON airports IS 'Airport identifiers use three uppercase IATA letters.';

CREATE TABLE airlines (
    airline_code CHAR(2) NOT NULL,
    airline_name TEXT NOT NULL,
    CONSTRAINT pk_airlines PRIMARY KEY (airline_code),
    CONSTRAINT uq_airlines_airline_name UNIQUE (airline_name)
);

CREATE TABLE flights (
    flight_id INTEGER NOT NULL,
    airline_code CHAR(2) NOT NULL,
    flight_no VARCHAR(10) NOT NULL,
    origin CHAR(3) NOT NULL,
    destination CHAR(3) NOT NULL,
    departure_at TIMESTAMPTZ NOT NULL,
    arrival_at TIMESTAMPTZ NOT NULL,
    aircraft VARCHAR(20) NOT NULL,
    total_seats SMALLINT NOT NULL,
    base_fare NUMERIC(10,2) NOT NULL,
    status VARCHAR(12) NOT NULL,
    CONSTRAINT pk_flights PRIMARY KEY (flight_id),
    CONSTRAINT uq_flights_number_departure UNIQUE (flight_no, departure_at),
    CONSTRAINT fk_flights_airline FOREIGN KEY (airline_code) REFERENCES airlines (airline_code) ON DELETE RESTRICT,
    CONSTRAINT fk_flights_origin FOREIGN KEY (origin) REFERENCES airports (iata_code) ON DELETE RESTRICT,
    CONSTRAINT fk_flights_destination FOREIGN KEY (destination) REFERENCES airports (iata_code) ON DELETE RESTRICT,
    CONSTRAINT chk_flights_distinct_airports CHECK (origin <> destination),
    CONSTRAINT chk_flights_arrival_after_departure CHECK (arrival_at > departure_at),
    CONSTRAINT chk_flights_number_prefix CHECK (flight_no LIKE airline_code || '-%'),
    CONSTRAINT chk_flights_status CHECK (status IN ('SCHEDULED','DELAYED','DEPARTED','LANDED','CANCELLED')),
    CONSTRAINT chk_flights_seats_and_fare_positive CHECK (total_seats > 0 AND base_fare > 0)
);
COMMENT ON CONSTRAINT fk_flights_airline ON flights IS 'Each flight belongs to an existing airline.';
COMMENT ON CONSTRAINT fk_flights_origin ON flights IS 'Each flight origin must be a known airport.';
COMMENT ON CONSTRAINT fk_flights_destination ON flights IS 'Each flight destination must be a known airport.';
COMMENT ON CONSTRAINT chk_flights_distinct_airports ON flights IS 'A flight cannot have the same origin and destination.';
COMMENT ON CONSTRAINT chk_flights_arrival_after_departure ON flights IS 'Arrival must occur after departure.';
COMMENT ON CONSTRAINT chk_flights_number_prefix ON flights IS 'Flight number must begin with its airline code and a hyphen.';
COMMENT ON CONSTRAINT chk_flights_status ON flights IS 'Restricts flight status to the supported lifecycle values.';
COMMENT ON CONSTRAINT chk_flights_seats_and_fare_positive ON flights IS 'Flights must offer seats at a positive base fare.';

CREATE TABLE hotels (
    hotel_id INTEGER NOT NULL,
    hotel_name TEXT NOT NULL,
    city_name TEXT NOT NULL,
    star_rating SMALLINT NOT NULL,
    user_rating NUMERIC(2,1),
    amenities JSONB NOT NULL,
    check_in_time TIME NOT NULL,
    check_out_time TIME NOT NULL,
    CONSTRAINT pk_hotels PRIMARY KEY (hotel_id),
    CONSTRAINT chk_hotels_star_rating CHECK (star_rating BETWEEN 1 AND 5),
    CONSTRAINT chk_hotels_user_rating CHECK (user_rating BETWEEN 0 AND 5),
    CONSTRAINT chk_hotels_amenities_object CHECK (jsonb_typeof(amenities) = 'object')
);
COMMENT ON CONSTRAINT chk_hotels_star_rating ON hotels IS 'Hotel star ratings range from one to five.';
COMMENT ON CONSTRAINT chk_hotels_user_rating ON hotels IS 'Optional user rating must be between zero and five.';
COMMENT ON CONSTRAINT chk_hotels_amenities_object ON hotels IS 'Amenities are stored as a JSON object of flags.';

CREATE TABLE room_types (
    room_type_id INTEGER NOT NULL,
    hotel_id INTEGER NOT NULL,
    room_name TEXT NOT NULL,
    max_guests SMALLINT NOT NULL,
    price_per_night NUMERIC(10,2) NOT NULL,
    total_rooms SMALLINT NOT NULL,
    CONSTRAINT pk_room_types PRIMARY KEY (room_type_id),
    CONSTRAINT uq_room_types_id_hotel UNIQUE (room_type_id, hotel_id),
    CONSTRAINT fk_room_types_hotel FOREIGN KEY (hotel_id) REFERENCES hotels (hotel_id) ON DELETE RESTRICT,
    CONSTRAINT chk_room_types_positive_capacity_and_price CHECK (max_guests > 0 AND total_rooms > 0 AND price_per_night > 0)
);
COMMENT ON CONSTRAINT fk_room_types_hotel ON room_types IS 'Each room type belongs to an existing hotel.';
COMMENT ON CONSTRAINT chk_room_types_positive_capacity_and_price ON room_types IS 'Room capacity, inventory, and nightly price must be positive.';

CREATE TABLE customers (
    customer_id INTEGER NOT NULL,
    full_name TEXT NOT NULL,
    email VARCHAR(254) NOT NULL,
    phone CHAR(10) NOT NULL,
    loyalty_tier VARCHAR(10) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT pk_customers PRIMARY KEY (customer_id),
    CONSTRAINT uq_customers_email UNIQUE (email),
    CONSTRAINT uq_customers_phone UNIQUE (phone),
    CONSTRAINT chk_customers_phone_digits CHECK (phone ~ '^[0-9]{10}$'),
    CONSTRAINT chk_customers_loyalty_tier CHECK (loyalty_tier IN ('BLUE','SILVER','GOLD','PLATINUM'))
);
COMMENT ON CONSTRAINT chk_customers_phone_digits ON customers IS 'Customer phone numbers contain exactly ten digits.';
COMMENT ON CONSTRAINT chk_customers_loyalty_tier ON customers IS 'Restricts loyalty tiers to the supported values.';

CREATE TABLE coupons (
    coupon_code VARCHAR(20) NOT NULL,
    applies_to VARCHAR(6) NOT NULL,
    discount_pct SMALLINT NOT NULL,
    max_discount NUMERIC(10,2) NOT NULL,
    valid_from DATE NOT NULL,
    valid_to DATE NOT NULL,
    CONSTRAINT pk_coupons PRIMARY KEY (coupon_code),
    CONSTRAINT chk_coupons_applies_to CHECK (applies_to IN ('FLIGHT','HOTEL','ALL')),
    CONSTRAINT chk_coupons_discount_pct CHECK (discount_pct BETWEEN 1 AND 100),
    CONSTRAINT chk_coupons_validity_dates CHECK (valid_to >= valid_from)
);
COMMENT ON CONSTRAINT chk_coupons_applies_to ON coupons IS 'Coupons apply to a flight, hotel, or all booking types.';
COMMENT ON CONSTRAINT chk_coupons_discount_pct ON coupons IS 'Coupon percentage discount must be from one to one hundred.';
COMMENT ON CONSTRAINT chk_coupons_validity_dates ON coupons IS 'Coupon expiry cannot precede its start date.';

CREATE TABLE bookings (
    booking_id BIGINT NOT NULL,
    booking_ref CHAR(8) NOT NULL,
    customer_id INTEGER NOT NULL,
    booking_type VARCHAR(6) NOT NULL,
    booked_at TIMESTAMPTZ NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL,
    coupon_code VARCHAR(20),
    discount NUMERIC(10,2) NOT NULL DEFAULT 0,
    payment_method VARCHAR(10) NOT NULL,
    status VARCHAR(16) NOT NULL,
    cancelled_at TIMESTAMPTZ,
    refund_amount NUMERIC(12,2),
    CONSTRAINT pk_bookings PRIMARY KEY (booking_id),
    CONSTRAINT uq_bookings_booking_ref UNIQUE (booking_ref),
    CONSTRAINT fk_bookings_customer FOREIGN KEY (customer_id) REFERENCES customers (customer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_bookings_coupon FOREIGN KEY (coupon_code) REFERENCES coupons (coupon_code) ON DELETE RESTRICT,
    CONSTRAINT chk_bookings_ref_format CHECK (booking_ref ~ '^MM[0-9A-Z]{6}$'),
    CONSTRAINT chk_bookings_type CHECK (booking_type IN ('FLIGHT','HOTEL')),
    CONSTRAINT chk_bookings_payment_method CHECK (payment_method IN ('UPI','CARD','WALLET','NETBANKING','EMI')),
    CONSTRAINT chk_bookings_status CHECK (status IN ('PENDING_PAYMENT','CONFIRMED','COMPLETED','CANCELLED')),
    CONSTRAINT chk_bookings_cancelled_at_matches_status CHECK ((status = 'CANCELLED') = (cancelled_at IS NOT NULL)),
    CONSTRAINT chk_bookings_refund_matches_status CHECK ((status = 'CANCELLED') = (refund_amount IS NOT NULL)),
    CONSTRAINT chk_bookings_refund_le_total CHECK (refund_amount IS NULL OR (refund_amount > 0 AND refund_amount <= total_amount)),
    CONSTRAINT chk_bookings_cancel_after_booking CHECK (cancelled_at IS NULL OR cancelled_at >= booked_at),
    CONSTRAINT chk_bookings_coupon_discount CHECK ((coupon_code IS NULL) = (discount = 0)),
    CONSTRAINT chk_bookings_discount_nonnegative CHECK (discount >= 0),
    CONSTRAINT chk_bookings_total_positive CHECK (total_amount > 0)
);
COMMENT ON CONSTRAINT fk_bookings_customer ON bookings IS 'Each booking belongs to an existing customer.';
COMMENT ON CONSTRAINT fk_bookings_coupon ON bookings IS 'A non-null coupon code must refer to an existing coupon.';
COMMENT ON CONSTRAINT chk_bookings_ref_format ON bookings IS 'Booking references use the MM prefix and six uppercase alphanumeric characters.';
COMMENT ON CONSTRAINT chk_bookings_type ON bookings IS 'Restricts bookings to flight or hotel products.';
COMMENT ON CONSTRAINT chk_bookings_payment_method ON bookings IS 'Restricts payment method to supported values.';
COMMENT ON CONSTRAINT chk_bookings_status ON bookings IS 'Restricts booking status to supported lifecycle values.';
COMMENT ON CONSTRAINT chk_bookings_cancelled_at_matches_status ON bookings IS 'Cancellation timestamp is present exactly for cancelled bookings.';
COMMENT ON CONSTRAINT chk_bookings_refund_matches_status ON bookings IS 'Refund amount is present exactly for cancelled bookings.';
COMMENT ON CONSTRAINT chk_bookings_refund_le_total ON bookings IS 'A refund must be positive and cannot exceed the booking amount.';
COMMENT ON CONSTRAINT chk_bookings_cancel_after_booking ON bookings IS 'Cancellation cannot precede booking creation.';
COMMENT ON CONSTRAINT chk_bookings_coupon_discount ON bookings IS 'Coupon presence and nonzero discount must agree.';
COMMENT ON CONSTRAINT chk_bookings_discount_nonnegative ON bookings IS 'Discount amounts cannot be negative.';
COMMENT ON CONSTRAINT chk_bookings_total_positive ON bookings IS 'Booking total must be positive.';

CREATE TABLE flight_bookings (
    booking_id BIGINT NOT NULL,
    flight_id INTEGER NOT NULL,
    cabin VARCHAR(10) NOT NULL,
    passengers SMALLINT NOT NULL,
    fare_paid NUMERIC(12,2) NOT NULL,
    CONSTRAINT pk_flight_bookings PRIMARY KEY (booking_id),
    CONSTRAINT fk_flight_bookings_booking FOREIGN KEY (booking_id) REFERENCES bookings (booking_id) ON DELETE CASCADE,
    CONSTRAINT fk_flight_bookings_flight FOREIGN KEY (flight_id) REFERENCES flights (flight_id) ON DELETE RESTRICT,
    CONSTRAINT chk_flight_bookings_cabin CHECK (cabin IN ('ECONOMY','PREMIUM','BUSINESS')),
    CONSTRAINT chk_flight_bookings_passengers_positive CHECK (passengers > 0),
    CONSTRAINT chk_flight_bookings_fare_positive CHECK (fare_paid > 0)
);
COMMENT ON CONSTRAINT fk_flight_bookings_booking ON flight_bookings IS 'Flight details are owned by a booking and are deleted with it.';
COMMENT ON CONSTRAINT fk_flight_bookings_flight ON flight_bookings IS 'Each flight booking references an existing flight.';
COMMENT ON CONSTRAINT chk_flight_bookings_cabin ON flight_bookings IS 'Restricts cabin to the supported fare classes.';
COMMENT ON CONSTRAINT chk_flight_bookings_passengers_positive ON flight_bookings IS 'A flight booking must include at least one passenger.';
COMMENT ON CONSTRAINT chk_flight_bookings_fare_positive ON flight_bookings IS 'A flight booking must have a positive fare.';

CREATE TABLE passengers (
    booking_id BIGINT NOT NULL,
    seq_no SMALLINT NOT NULL,
    full_name TEXT NOT NULL,
    age SMALLINT NOT NULL,
    gender CHAR(1) NOT NULL,
    seat_no VARCHAR(4),
    CONSTRAINT pk_passengers PRIMARY KEY (booking_id, seq_no),
    CONSTRAINT fk_passengers_flight_booking FOREIGN KEY (booking_id) REFERENCES flight_bookings (booking_id) ON DELETE CASCADE,
    CONSTRAINT chk_passengers_seq_no CHECK (seq_no >= 1),
    CONSTRAINT chk_passengers_age CHECK (age BETWEEN 0 AND 120),
    CONSTRAINT chk_passengers_gender CHECK (gender IN ('M','F','X')),
    CONSTRAINT chk_passengers_seat_format CHECK (seat_no IS NULL OR seat_no ~ '^[0-9]{1,2}[A-K]$')
);
COMMENT ON CONSTRAINT fk_passengers_flight_booking ON passengers IS 'Passenger rows belong to flight booking details and are deleted with them.';
COMMENT ON CONSTRAINT chk_passengers_seq_no ON passengers IS 'Passenger sequence numbers start at one.';
COMMENT ON CONSTRAINT chk_passengers_age ON passengers IS 'Passenger age must be within the supported range.';
COMMENT ON CONSTRAINT chk_passengers_gender ON passengers IS 'Restricts passenger gender codes to the supported values.';
COMMENT ON CONSTRAINT chk_passengers_seat_format ON passengers IS 'Assigned seats use a row number and seat letter; unassigned seats are null.';

CREATE TABLE hotel_bookings (
    booking_id BIGINT NOT NULL,
    hotel_id INTEGER NOT NULL,
    room_type_id INTEGER NOT NULL,
    check_in DATE NOT NULL,
    check_out DATE NOT NULL,
    rooms SMALLINT NOT NULL,
    guests SMALLINT NOT NULL,
    room_number VARCHAR(5),
    CONSTRAINT pk_hotel_bookings PRIMARY KEY (booking_id),
    CONSTRAINT uq_hotel_bookings_booking_hotel UNIQUE (booking_id, hotel_id),
    CONSTRAINT fk_hotel_bookings_booking FOREIGN KEY (booking_id) REFERENCES bookings (booking_id) ON DELETE CASCADE,
    CONSTRAINT fk_hotel_bookings_hotel FOREIGN KEY (hotel_id) REFERENCES hotels (hotel_id) ON DELETE RESTRICT,
    CONSTRAINT fk_hotel_bookings_room_type_hotel FOREIGN KEY (room_type_id, hotel_id) REFERENCES room_types (room_type_id, hotel_id) ON DELETE RESTRICT,
    CONSTRAINT chk_hotel_bookings_dates CHECK (check_out > check_in),
    CONSTRAINT chk_hotel_bookings_rooms_guests CHECK (rooms >= 1 AND guests >= 1),
    CONSTRAINT chk_hotel_bookings_room_number CHECK (room_number IS NULL OR room_number ~ '^[0-9]{3,4}$')
);
COMMENT ON CONSTRAINT fk_hotel_bookings_booking ON hotel_bookings IS 'Hotel stay details are owned by a booking and are deleted with it.';
COMMENT ON CONSTRAINT fk_hotel_bookings_hotel ON hotel_bookings IS 'Each hotel booking references an existing hotel.';
COMMENT ON CONSTRAINT fk_hotel_bookings_room_type_hotel ON hotel_bookings IS 'The selected room type must belong to the selected hotel.';
COMMENT ON CONSTRAINT chk_hotel_bookings_dates ON hotel_bookings IS 'Hotel checkout must be later than check-in.';
COMMENT ON CONSTRAINT chk_hotel_bookings_rooms_guests ON hotel_bookings IS 'Hotel bookings require at least one room and one guest.';
COMMENT ON CONSTRAINT chk_hotel_bookings_room_number ON hotel_bookings IS 'Optional assigned room number contains three or four digits.';

CREATE TABLE hotel_reviews (
    review_id INTEGER NOT NULL,
    booking_id BIGINT NOT NULL,
    hotel_id INTEGER NOT NULL,
    rating SMALLINT NOT NULL,
    title TEXT NOT NULL,
    review_text TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT pk_hotel_reviews PRIMARY KEY (review_id),
    CONSTRAINT uq_hotel_reviews_booking UNIQUE (booking_id),
    CONSTRAINT fk_hotel_reviews_hotel_booking FOREIGN KEY (booking_id, hotel_id) REFERENCES hotel_bookings (booking_id, hotel_id) ON DELETE CASCADE,
    CONSTRAINT chk_hotel_reviews_rating CHECK (rating BETWEEN 1 AND 5)
);
COMMENT ON CONSTRAINT fk_hotel_reviews_hotel_booking ON hotel_reviews IS 'A review belongs to its matching hotel stay and is deleted with that stay.';
COMMENT ON CONSTRAINT chk_hotel_reviews_rating ON hotel_reviews IS 'Review rating must be between one and five.';
