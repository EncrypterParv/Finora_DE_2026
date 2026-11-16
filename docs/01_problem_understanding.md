# Phase 1: Problem Understanding
Classification: customer-facing / real-time vs reporting / analytics.
Assumptions are labelled A1, A2, …

### P1 – Flight search, fare calendar and seats left (R01, R02, R10)

**Need:** A traveller searching a route and date must instantly see each flight's times, fare and an accurate seats-left count; the fare calendar must show the cheapest fare for every day of a month; the status board must list delayed flights. Slow or stale seat counts lose sales and risk overbooking.
**Stakeholders:** Traveller (primary), revenue management (fares/inventory), airline partner, customer support (status queries).
**Type:** Customer-facing / real-time (all three queries).
**Assumptions:** (A1) Seats left = `total_seats` − passengers on that flight's non-cancelled bookings, as R01 computes; pending-payment bookings still hold seats. (A2) "Lag" means the count is slow to compute live, not deliberately cached. (A3) A "day" is the Indian (IST, +05:30) calendar date; all timestamps in the data are +05:30. (A4) Cancelled flights are hidden from search.

### P2 – Hotel search and room availability (R03, R04, R18, R24)

**Need:** A traveller filters hotels by city, star rating and amenities (e.g. pool), sorted by rating; on a hotel's page they see rooms left per room type for their dates, reviews mentioning a topic (e.g. breakfast) and a ranking by review score.
**Stakeholders:** Traveller (primary), hotel partner (visibility and ranking), revenue management (room inventory).
**Type:** Customer-facing. R03 and R04 are real-time (search/booking path); R18 and R24 are interactive page content, which the brief's targets group with partner tools (< 250 ms).
**Assumptions:** (A1) `amenities` is a JSON object of yes/no flags. (A2) A room is occupied on night *d* when check_in ≤ *d* < check_out (the overlap rule in R04). (A3) Cancelled bookings free their rooms; pending ones hold them. (A4) Review `rating` (1–5 per stay) is separate from the hotel's overall `user_rating`.

### P3 – My Trips, booking lookup and sign-in (R05, R06, R23)

**Need:** A signed-in traveller must instantly see their upcoming confirmed trips (flights and hotels, by travel date); support agents must open any booking from its reference; sign-in must find the customer by email regardless of letter case. Delays here make the app feel broken.
**Stakeholders:** Traveller (primary), customer support.
**Type:** Customer-facing / real-time (R05, R06, R23).
**Assumptions:** (A1) "Upcoming" means status CONFIRMED, as R05 filters. (A2) `booking_ref` is unique per booking (verified in seed data). (A3) Emails are unique ignoring case (no case-only duplicates in the seed data), so sign-in returns at most one customer.

### P4 – Airline manifests, low-load reports and cancellation rates (R07, R08, R14, R19, W04)

**Need:** Airline partners need a flight's passenger manifest sorted by seat, revenue management needs July flights with fewer than 5 passengers booked, partnerships need cancellation rates per airline, operations need passenger counts for every June flight, and flight status must be updated in bulk once flights depart.
**Stakeholders:** Airline partner (primary), revenue management, flight operations.
**Type:** Mixed. R07 is real-time (gate/check-in); R08 is an interactive partner tool; R14 and R19 are reporting/analytics; W04 is a batch job.
**Assumptions:** (A1) Manifests exclude cancelled bookings, as R07 does; passengers without a seat (not yet checked in) are listed last. (A2) R08 and R19 count passengers on all bookings, including cancelled ones, exactly as the queries are written. (A3) W04 runs once, after 1 Jul 2026 00:00 IST.

### P5 – Checkout and payments (R11, W01, W02, W03)

**Need:** Checkout must create a pending booking instantly; the payments team needs the queue of bookings stuck in payment for over 30 minutes; payment-gateway callbacks must confirm bookings and customer cancellations must record the refund immediately, even under heavy load.
**Stakeholders:** Payments team (primary), traveller, customer support.
**Type:** Customer-facing / real-time (R11, W01, W02, W03).
**Assumptions:** (A1) A booking stays PENDING_PAYMENT until the gateway confirms it; W02 confirms the oldest pending booking first (lowest booking_id). (A2) A cancellation always records both a time and a refund, and the refund never exceeds the amount paid. (A3) "Under load" means many concurrent checkouts, so these writes must touch few rows and few indexes.

### P6 – Coupons-never-used report returns nothing (R13)

**Need:** Marketing wants the list of coupons no customer has ever used, so that it can retire or re-promote them, but the report always comes back empty.
**Stakeholders:** Marketing (primary).
**Type:** Reporting / analytics (R13).
**Assumptions:** (A1) The empty result is a correctness bug, not a performance problem: most bookings have no coupon, so `bookings.coupon_code` contains NULLs, and `x NOT IN (… NULL …)` is never TRUE. To be fixed and proven in Phase 4. (A2) "Used" means appearing on any booking, including cancelled ones, as R13 is written.

### P7 – Room-nights per city and front-desk check-in (R15, W05)

<!-- Yash: Need / Stakeholders / Type / Assumptions -->

### P8 – Finance, loyalty and insight reports; 20× growth (R09, R12, R16, R17, R20, R21, R22, R25)

<!-- Yash: Need / Stakeholders / Type / Assumptions -->
