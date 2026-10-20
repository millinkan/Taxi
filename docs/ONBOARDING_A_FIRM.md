# Onboarding a firm

Adding a firm takes about 30 minutes and needs no code change and no deploy.

## 1. Create it (platform admin)

**Admin › Onboard a firm**:
- Firm name, short name (URL slug, e.g. `taxi-schaan`), licence number.
- Dispatcher mobile (receives booking SMS) and public phone number.
- Owner login (name, email, initial password; the owner changes it).
- **Regional template**: `liechtenstein` creates about 23 places (towns,
  stations, airports, resorts), 9 fixed-price routes × 3 vehicle classes,
  and metered tariffs. **All prices are starting values.**

To add a new region, copy `core/config/regions/liechtenstein.yml`, adjust the
places, routes and defaults, and it appears in the dropdown.

## 2. Configure it (as the firm: Admin › Open as, or the owner's login)

| Where | What |
|---|---|
| Settings › Firm | Brand colour, logo URL, Google review link, SMS sender ID, policies (lead time, cancellation, auto-confirm), voice greeting |
| Settings › Tariffs | Base fare, per km, minimum, night surcharge, per vehicle class |
| Settings › Fixed prices | The firm's real airport and long-distance prices |
| Settings › Places | Quick-pick places (★) for the booking form; aliases for the phone agent |
| Settings › Vehicles | Every car with seats. Needed for auto-confirm and capacity |

## 3. Connect the phone (optional, recommended)

Buy a Twilio number, set its webhooks, enter it as the firm's **voice number**,
tick **AI phone assistant active**, and set conditional call forwarding on the
firm's line. Step by step: [VOICE_AGENT.md](VOICE_AGENT.md).

## 4. Publish the booking page

- `https://app.<domain>/<slug>`, or the firm's own domain: CNAME it to the
  platform host, enter it under Admin › firm › custom domain, add it to
  `proxy.hosts` in `core/config/deploy.yml`, and deploy.
- Link it from the Google Business Profile, the website, cars (QR code) and
  hotel partners.

## 5. Check it

- Book a test ride on the page: the dispatcher gets an SMS and the customer
  gets an SMS. Confirm via the SMS link, then cancel.
- `npm run check-core -- <voice number>` from the voice folder.
- Call the firm, let it ring through to the agent, and check **Calls**.
