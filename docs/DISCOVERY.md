# Discovery: being found by Google and AI assistants

People don't type a firm's URL. They search "taxi vaduz" on Google or Maps, or
ask an assistant ("I need a taxi from Bar Sonne in Vaduz"). This document
explains what RideDesk publishes for each firm so those searches end on the
platform, ideally on the **Taxi now** page.

## The customer's path

```
"taxi vaduz" ─► Google Maps card ──[Order]──────► /<firm>/now   (Taxi now)
                                  ──[Website]────► /<firm>       (book ahead)
                                  ──[Call]───────► firm's line ─► AI agent on busy/no answer
"taxi vaduz" ─► Google results ───► route page /<firm>/routes/1-vaduz-flughafen-zuerich
ChatGPT / Gemini / Perplexity / Copilot / Claude
              ─► reads llms.txt, discovery.json, schema.org markup
              ─► answers with the Taxi-now link, pre-filled: /now?pickup=…&dropoff=…
```

Every link handed to Google or an assistant carries `utm_*` tags, so bookings
they bring show up in the booking's attribution and on the admin's Discovery page.

## What is published (per firm)

| URL | For | Content |
|---|---|---|
| every public page | Google, assistants | schema.org `LocalBusiness` + `TaxiService` JSON-LD: phone, area, opening hours, fixed-price offers, an `OrderAction` pointing at Taxi now |
| `/now` | people | Taxi-now form with a GPS button; pre-fills from `?pickup=&dropoff=&lat=&lng=&from=&to=&pax=` |
| `/taxi/<place>` | Google, assistants | one landing page per place: every municipality and village (`/taxi/bendern`), neighbouring towns, and transfer pages for airports and resorts (`/taxi/flughafen-zuerich`). Each page has real prices from that place, travel times, a pre-filled Taxi-now button, nearby places and an FAQ |
| `/routes/<id>-<slug>` | Google | one landing page per fixed-price route |
| `/sitemap.xml` | crawlers | booking page, Taxi now, deals, all route pages |
| `/llms.txt` | assistants | plain-language summary with order links and prices |
| `/discovery.json` | assistants, partners | the same as structured JSON, including a `url_template` for Taxi now |
| `/robots.txt` (host level) | crawlers | hides token pages and staff areas; lists the sitemaps |

Everything is generated from the firm's live settings by `Discovery::Profile`,
so the formats never disagree with each other or with the prices.

## Covering every search: "taxi vaduz", "taxi bendern", "taxi zurich airport"

Each place in the firm's settings becomes a page, so coverage grows with the
places list. The Liechtenstein template contains all 11 municipalities, the
villages people search for by name (Bendern, Nendeln, Schaanwald, Mäls, Steg,
Masescha, Malbun), the neighbouring towns (Buchs, Sevelen, Grabs, Gams,
Trübbach, Sargans, Feldkirch) and the airports and resorts. For firms
onboarded earlier, **Add missing localities** on the Discovery page adds what
is missing without touching existing places or prices.

The page language is the firm's default, with `?lang=en` as a linked
alternate (`hreflang`), so English searches ("taxi zurich airport
liechtenstein") find the English version. Slugs are the same in both
languages.

`Discovery::Keywords` maps the search phrases onto these pages: place names
and aliases, "taxi <village> <airport>", "taxi von <village> nach <airport>",
"taxi <airport> <town>", "taxi sofort liechtenstein". The Discovery page shows
the list and exports it as a Google Ads Editor CSV, so paid search lands on
the same pages and is attributed (`utm_medium=cpc`).

We deliberately build **one page per place, not one per phrase**. Google
treats mass-produced near-duplicate pages ("doorway pages") as spam and can
demote the whole site. Each page carries data specific to that place.

## Pushing

Pushes happen automatically (`Discovery::AutoPush`):

* **On every change.** A committed change to a fixed price, a place, an
  empty-leg deal, or a public firm setting (name, phones, opening hours,
  service area, Taxi now on/off, …) queues a push 5 minutes later. Further
  edits in those 5 minutes join the waiting push, so onboarding or a price
  list update produces one submission, not hundreds.
* **Daily at 05:00** (`DiscoveryRefreshJob`) for every active firm, which
  also catches deals that expired on their own.
* **Only changed URLs.** Automatic IndexNow pushes send the pages whose
  sitemap `lastmod` moved since the last successful push. IndexNow asks for
  this, and engines throttle keys that resubmit unchanged pages. A firm-level
  change resends every page, since name and phone appear on all of them.
  With nothing changed, the push is logged as skipped.

`DISCOVERY_AUTO_PUSH=false` turns the automatic pushes off. The
**Push to search engines & AI** button (admin › firm › Discovery) sends every
page immediately. The log marks each push as automatic or by whom. Channels:

* **IndexNow**: one request reaches Bing (the index behind ChatGPT search
  and Copilot), Yandex, Seznam, Naver and others. No account is needed;
  ownership is proven by `/indexnow-key.txt`. It is skipped for local hosts
  (localhost, `.test`, private IPs).
* **Google Search Console**: Google has no instant push for ordinary pages.
  The supported route is submitting the sitemap through the Search Console
  API. Setup:
  1. Verify the property in Search Console: `sc-domain:<custom domain>` for a
     firm with its own domain, otherwise the platform's URL-prefix property.
  2. Create a service account in Google Cloud, enable the Search Console API,
     and add the service account's email as an **owner** of the property.
  3. Set `GOOGLE_SERVICE_ACCOUNT_JSON` (and `GOOGLE_SEARCH_CONSOLE_SITE` if the
     platform property differs from `APP_PROTOCOL://APP_HOST/`).

`/robots.txt` names the search and AI crawlers (Googlebot, Bingbot,
OAI-SearchBot, ChatGPT-User, GPTBot, PerplexityBot, Claude-SearchBot,
ClaudeBot, Applebot, Google-Extended and others) in the same group as `*`, so
they get the same rules: everything public is open, token pages and staff
areas are not. The list also admits the crawlers that collect model training
data (GPTBot, ClaudeBot, Google-Extended, Applebot-Extended). For a taxi firm
that is usually wanted, because it is how assistants learn the firm exists.
Remove them from `DiscoveryController::WELCOME_CRAWLERS` if a firm objects.

## The Google Business Profile matters most

For "taxi near me" searches the Maps card wins over everything else. Do this
once per firm, with the owner:

1. Claim or create the profile at business.google.com (category "Taxi service").
2. Paste the three links from the Discovery page: **Website**, **Order
   link** (Taxi now) and **Appointment link** (book ahead).
3. Save the profile's share link in the firm's settings. It goes into the
   markup as `sameAs` and into the readiness checklist.

Reviews drive the Maps ranking. The automatic review request after each
completed ride already feeds it.

## Limits, stated plainly

* No API puts a booking button inside Google's own interface for a taxi firm.
  "Reserve with Google" is limited to approved booking partners in other
  verticals. The Order and Appointment links on the profile are the practical
  equivalent.
* Assistants decide for themselves what to show. We give them accurate,
  machine-readable facts and a link they can fill in; we can't force a
  ranking.
* Pages need crawling before they show up. A push shortens that from weeks to
  hours or days, but it doesn't make it instant.
