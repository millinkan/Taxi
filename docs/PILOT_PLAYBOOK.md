# Pilot playbook: the first firm (4 cars, driver-dispatcher)

The pilot has to answer one question for the owner with numbers: **how much
extra revenue does RideDesk bring in a month?** Everything below serves that.

## Week 0: before go-live (about 2 days of work)

**Measure the baseline first.** You can't prove improvement without it.
- Ask the owner for last month's rides and revenue, split by airport/long
  distance and local if possible.
- **Mystery-call test**: call the firm 10 times at different hours (including
  Friday night and early morning) and count how many go unanswered. That
  number, multiplied by the average fare, is the opening line of the pitch.

**Set up the firm** (see [ONBOARDING_A_FIRM.md](ONBOARDING_A_FIRM.md)):
- [ ] Onboard with region `liechtenstein`. Go through **Settings › Fixed
      prices** and **Tariffs** with the owner and replace every template price
      with theirs.
- [ ] Enter all 4 vehicles (seats, van or not). Auto-confirm uses this.
- [ ] Dispatcher mobile, SMS sender ID (e.g. `TaxiVaduz`), Google review link,
      logo, brand colour.
- [ ] Twilio number plus conditional call forwarding on the firm's line
      ([VOICE_AGENT.md](VOICE_AGENT.md)).
- [ ] Leave **auto-confirm off** for the first week. The owner should see and
      tap every booking to build trust. Switch it on (e.g. ≥ 6 h ahead) in
      week 2.

**Train the dispatcher (15 minutes, on their phone):**
1. A test booking arrives as SMS → tap the link → **Bestätigen**. The
   customer gets an SMS.
2. Save the board (`https://app…/dispatch`) to the home screen.
3. **Telefonbuchung** for calls they take themselves. That also brings their
   phone customers into the system for stats and review requests.
4. After a ride: **Erledigt** (optionally with the final price). That
   triggers the review request.

## Week 1: go live quietly

- [ ] Put the booking page link (Settings › Firm shows it) on the **Google
      Business Profile** as the "Book" / website link. This is the
      highest-traffic, zero-cost placement.
- [ ] Put a QR code to the booking page in each car ("Rückfahrt / nächste Fahrt
      online buchen").
- [ ] Switch on call forwarding (busy / no answer).
- [ ] Every day: read the **Calls** page. Look at transcripts where the agent
      transferred or the caller hung up, and note misunderstood place names
      (add them as aliases in **Places**) and phrasing problems.
- [ ] Make 10–20 test calls in Swiss German and settle on the speech
      provider settings ([VOICE_AGENT.md](VOICE_AGENT.md)).

## Weeks 2–4: grow

- [ ] Turn on auto-confirm for bookings ≥ 6 h ahead.
- [ ] Hotels and businesses: give the 3–5 nearest hotels and the large
      employers a link with tracking, e.g. `…/taxi-firm?utm_source=hotel-x`.
      The dashboard then shows which partner sends rides.
- [ ] Optional small **Google Ads** test (CHF 10–20 a day), only on
      high-value searches: "Taxi Flughafen Zürich Liechtenstein",
      "Taxi Vaduz Zürich Flughafen", "airport transfer Liechtenstein". Use the
      booking page as the landing page. Upload the **Google Ads export** from
      the dashboard weekly so Google learns which clicks turn into paid rides.

## Week 4 and week 8: the numbers meeting

Open **Results** (30 days) with the owner:

| Show | Why it matters |
|---|---|
| Revenue through the platform | The direct answer: rides that came online, by AI phone, as return trips or as empty legs |
| Calls answered by the AI, and calls → booking | Calls that would have gone to a competitor |
| Return trips and empty legs sold | Revenue that didn't exist before |
| Repeat-customer share and reviews requested | The compounding effect: Google ranking and loyalty |
| Avg. time to confirm | Customer experience: should be minutes |

Agree the commercial model from these numbers (for example a monthly fee,
or a percentage of platform revenue). Then ask the owner for a referral to a
befriended firm in a neighbouring town. One firm per town keeps the
partnership exclusive.

## Pilot success criteria (suggested)

- ≥ 90% of calls answered by a human or the AI (baseline from the
  mystery-call test).
- Platform revenue ≥ 3× the monthly fee in month 2.
- Median confirmation time < 10 minutes.
- No booking lost to a technical failure. Check the `failed` call outcome and
  failed messages weekly.
