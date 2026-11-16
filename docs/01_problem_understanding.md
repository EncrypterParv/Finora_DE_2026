# Phase 1: Problem Understanding
Classification: customer-facing / real-time vs reporting / analytics.
Assumptions are labelled A1, A2, …

### P1 – Flight search, fare calendar and seats left (R01, R02, R10)

**Need:** Travellers must instantly see flights, fares and accurate seats left for a route and date, the cheapest fare per day of a month, and delayed flights. **Stakeholders:** Traveller, revenue management, airline partner, support. **Type:** Real-time. **Assumptions:** (A1) Seats left = `total_seats` − passengers on non-cancelled bookings; pending bookings hold seats. (A2) A "day" is the IST date.

### P2 – Hotel search and room availability (R03, R04, R18, R24)

**Need:** Travellers filter hotels by city, stars and amenities, see rooms left per room type for their dates, and read and rank reviews. **Stakeholders:** Traveller, hotel partner, revenue management. **Type:** R03, R04 real-time; R18, R24 interactive (< 250 ms). **Assumptions:** (A1) Night *d* is occupied when check_in ≤ *d* < check_out; cancellations free rooms. (A2) `amenities` is a JSON object of yes/no flags.

### P3 – My Trips, booking lookup and sign-in (R05, R06, R23)

**Need:** Travellers see their upcoming confirmed trips; support opens any booking by reference; sign-in finds the customer by email, ignoring case. **Stakeholders:** Traveller, customer support. **Type:** Real-time. **Assumptions:** (A1) "Upcoming" means CONFIRMED. (A2) `booking_ref` and lower-cased emails are unique (verified in the seed data).

### P4 – Airline manifests, low-load reports and cancellation rates (R07, R08, R14, R19, W04)

**Need:** Airlines need seat-ordered manifests, low-load July flights, cancellation rates per airline and June passenger counts; ops must mark departed flights in bulk. **Stakeholders:** Airline partner, revenue management, flight ops. **Type:** R07 real-time; R08 interactive; R14, R19 reporting; W04 batch. **Assumptions:** (A1) Manifests exclude cancelled bookings; R08 and R19 count all bookings, as written.

### P5 – Checkout and payments (R11, W01, W02, W03)

**Need:** Checkout must create pending bookings instantly; payments needs bookings stuck in payment over 30 minutes; gateway callbacks and cancellations must apply immediately under load. **Stakeholders:** Payments, traveller, support. **Type:** Real-time. **Assumptions:** (A1) W02 confirms the oldest pending booking (lowest `booking_id`). (A2) A cancellation records a time and a refund ≤ the amount paid.

### P6 – Coupons-never-used report returns nothing (R13)

**Need:** Marketing wants the coupons nobody has used, but the report is always empty. **Stakeholders:** Marketing. **Type:** Reporting. **Assumptions:** (A1) This is a correctness bug: `bookings.coupon_code` contains NULLs, so `NOT IN` is never TRUE; fixed and proven in Phase 4. (A2) "Used" means appearing on any booking, including cancelled ones.

### P7 – Room-nights per city and front-desk check-in (R15, W05)

**Need:** Hotel partners need room-nights sold per city for a month; the front desk must assign rooms to all confirmed guests checking in today, quickly. **Stakeholders:** Hotel partner, front desk. **Type:** R15 reporting; W05 interactive (< 250 ms). **Assumptions:** (A1) Room-nights count only the nights inside the month, × rooms, on non-cancelled bookings. (A2) W05 assigns rooms only to CONFIRMED bookings checking in that day that have no room yet.

### P8 – Finance, loyalty and insight reports; 20× growth (R09, R12, R16, R17, R20, R21, R22, R25)

**Need:** Finance, loyalty and insights teams need revenue by month and type, booking lead times, repeat customers, last-minute bookings, top routes, senior concessions and running totals; support pages through all bookings. These reports time out, and bookings will grow 20×. **Stakeholders:** Finance / revenue management, loyalty, marketing / insights, support. **Type:** Reporting (R09, R12, R16, R17, R20, R21, R25); R22 interactive (< 250 ms). **Assumptions:** (A1) Reports may use slightly stale summary data if the refresh is stated. (A2) Revenue excludes cancellations; all periods are IST calendar periods.
