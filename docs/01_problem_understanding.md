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

<!-- Tarunya: Need / Stakeholders / Type / Assumptions -->

### P4 – Airline manifests, low-load reports and cancellation rates (R07, R08, R14, R19, W04)

<!-- Tarunya: Need / Stakeholders / Type / Assumptions -->

### P5 – Checkout and payments (R11, W01, W02, W03)

<!-- Devansh: Need / Stakeholders / Type / Assumptions -->

### P6 – Coupons-never-used report returns nothing (R13)

<!-- Devansh: Need / Stakeholders / Type / Assumptions -->

### P7 – Room-nights per city and front-desk check-in (R15, W05)

<!-- Yash: Need / Stakeholders / Type / Assumptions -->

### P8 – Finance, loyalty and insight reports; 20× growth (R09, R12, R16, R17, R20, R21, R22, R25)

<!-- Yash: Need / Stakeholders / Type / Assumptions -->
