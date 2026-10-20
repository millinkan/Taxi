# End-to-end scenarios against a running server (see e2e/README.md).
#
# Runs inside `bin/rails runner` with the same DATABASE_URL as the server, so
# it can drive the app over HTTP/WebSocket like real users do and then look
# in the database (bookings, message log) to check the outcome.
require "net/http"
require "json"
require "open3"
require "csv"

BASE = ENV.fetch("E2E_BASE_URL")
FIRM = "taxi-demo"
PASSWORD = ENV.fetch("SEED_PASSWORD", "change-me-please")
REPO = File.expand_path("..", __dir__)
$results = []

# --- tiny browser: cookies, CSRF token, redirects -------------------------
class Client
  attr_reader :csrf, :last

  def initialize(name) = (@name = name; @cookies = {})

  def get(path) = request(Net::HTTP::Get.new(uri(path)))

  def post(path, form = {}, headers: {})
    req = Net::HTTP::Post.new(uri(path), headers)
    req.set_form_data(form_with_token(form))
    request(req)
  end

  def patch(path, form = {}) = post(path, form.merge("_method" => "patch"))
  def delete(path, form = {}) = post(path, form.merge("_method" => "delete"))

  def follow
    location = last["location"] or raise "no redirect from #{last.uri}"
    get(URI(location).request_uri)
  end

  def cookie_header = @cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
  def body = last.body.to_s.force_encoding("UTF-8")
  def redirected_to = last["location"] && URI(last["location"]).request_uri

  private
    def uri(path) = URI.join(BASE, path)

    def form_with_token(form)
      form = form.transform_keys(&:to_s)
      form["authenticity_token"] ||= @csrf if @csrf
      form
    end

    def request(req)
      req["Cookie"] = cookie_header if @cookies.any?
      req["Accept"] ||= "text/html"
      @last = Net::HTTP.start(req.uri.host, req.uri.port, read_timeout: 30) { |http| http.request(req) }
      Array(@last.get_fields("set-cookie")).each do |raw|
        name, value = raw.split(";").first.split("=", 2)
        @cookies[name] = value
      end
      if (token = @last.body.to_s[/<meta name="csrf-token" content="([^"]+)"/, 1])
        @csrf = token
      end
      @last
    end
end

# --- reporting ------------------------------------------------------------
def scenario(name)
  @scenario = name
  puts "\n▶ #{name}"
  yield
rescue StandardError => e
  check("finished without crashing", false, "#{e.class}: #{e.message} @ #{e.backtrace.find { |l| l.include?("scenarios.rb") }}")
end

def check(step, ok, detail = nil)
  $results << { scenario: @scenario, step: step, ok: !!ok, detail: detail }
  puts "  #{ok ? "PASS" : "FAIL"}  #{step}#{" (#{detail})" if detail}"
  ok
end

def sms(booking, purpose) = MessageLog.where(booking: booking, purpose: purpose).order(:id).last
def booking_from(client) = Booking.find_by!(public_token: client.redirected_to.to_s[%r{/b/([^/?]+)}, 1])
def tenant = Tenant.find_by!(slug: FIRM)
def local(days:, hour:, min: 0) = tenant.now.advance(days: days).change(hour: hour, min: min)
def place_id(name) = tenant.places.find_by!(name: name).id
def ws(*args)
  out, err, status = Open3.capture3("node", File.join(REPO, "e2e/ws_trip.mjs"), *args.map(&:to_s))
  raise "ws_trip failed: #{err}" unless status.success?

  JSON.parse(out.lines.last)
end

def signed_twilio_post(path, params, signature: :valid)
  url = "#{BASE}#{path}"
  sig = signature == :valid ? TwilioSignature.compute(url: url, params: params, auth_token: ENV.fetch("TWILIO_AUTH_TOKEN")) : signature
  req = Net::HTTP::Post.new(URI(url), sig ? { "X-Twilio-Signature" => sig } : {})
  req.set_form_data(params)
  Net::HTTP.start(req.uri.host, req.uri.port) { |http| http.request(req) }
end

def internal(method, path, body = nil, token: ENV.fetch("INTERNAL_API_TOKEN"))
  uri = URI("#{BASE}#{path}")
  req = (method == :get ? Net::HTTP::Get : Net::HTTP::Post).new(uri, "Content-Type" => "application/json")
  req["Authorization"] = "Bearer #{token}" if token
  req.body = body.to_json if body
  res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
  [ res, (JSON.parse(res.body) rescue {}) ]
end

def customer_booking(client, path: "/#{FIRM}", **fields)
  client.get(path)
  form = { "booking[name]" => "E2E Kunde", "booking[phone]" => "079 555 #{rand(10..99)} #{rand(10..99)}",
           "booking[passengers]" => 1, "booking[website]" => "" }
  fields.each { |key, value| form["booking[#{key}]"] = value }
  client.post("/#{FIRM}/bookings", form)
end

# --- setup ------------------------------------------------------------------
owner = Client.new("owner")
scenario "S0 setup: owner sets a 1-minute taxi-now answer window" do
  owner.get("/session/new")
  owner.post("/session", email_address: "owner@example.com", password: PASSWORD)
  check "owner signs in", owner.redirected_to == "/"
  owner.get("/settings/firm/edit")
  owner.patch("/settings/firm", "tenant[asap_response_minutes]" => 1)
  check "setting saved", tenant.asap_response_minutes == 1
end

# S2 starts now so its real timer runs while the other scenarios go on.
waiting = Client.new("waiting customer")
s2_booking = nil
scenario "S2 (part 1) taxi-now request nobody answers" do
  customer_booking(waiting, path: "/#{FIRM}/now", asap: 1, pickup_address: "Rathausplatz, Vaduz",
                            dropoff_address: "Triesen")
  s2_booking = booking_from(waiting)
  check "request accepted, pending", s2_booking.asap? && s2_booking.pending?
end

# --- S1 ---------------------------------------------------------------------
scenario "S1 bar at night: taxi now, ETA, live tracking, ride done" do
  bar = Client.new("customer at bar")
  bar.get("/#{FIRM}/now?pickup=Bar%20Sonne%2C%20Vaduz&lat=47.140500&lng=9.521500&pax=2")
  check "taxi-now page pre-filled from the link", bar.body.include?('value="Bar Sonne, Vaduz"') && bar.body.include?('value="47.1405"')

  customer_booking(bar, path: "/#{FIRM}/now?pickup=x", asap: 1, pickup_address: "Bar Sonne, Vaduz",
                        pickup_lat: "47.140500", pickup_lng: "9.521500", dropoff_address: "Schaan", passengers: 2,
                        notes: "vor dem Eingang")
  booking = booking_from(bar)
  check "booked without lead time", booking.asap? && booking.pending? && (booking.pickup_at - Time.current).abs < 60
  check "GPS pickup kept for the driver", booking.pickup_lat.to_f == 47.1405
  check "dispatcher SMS says TAXI SOFORT", sms(booking, "dispatcher_new_booking")&.body.to_s.start_with?("TAXI SOFORT")
  check "customer SMS: we are finding a car", sms(booking, "customer_received")&.body.to_s.include?("Taxi-Anfrage")

  bar.follow
  check "status page: searching, auto-refresh", bar.body.include?("Wir suchen ein freies Fahrzeug") && bar.body.include?('http-equiv="refresh"')

  driver = Client.new("driver")
  driver.get("/d/#{booking.dispatch_token}")
  check "SMS link shows ETA buttons", driver.body.include?('name="eta" value="10"')
  driver.post("/d/#{booking.dispatch_token}/confirm", eta: 10)
  booking.reload
  check "confirmed with ETA 10", booking.confirmed? && booking.eta_minutes == 10
  check "customer SMS with arrival time", sms(booking, "customer_confirmed")&.body.to_s.include?("Ankunft in ca. 10 Min.")

  bar.get("/#{FIRM}/b/#{booking.public_token}")
  check "status page shows the live map", bar.body.include?('data-controller="live-map"')

  driver.get("/d/#{booking.dispatch_token}")
  driver.post("/d/#{booking.dispatch_token}/start")
  check "driver on the way, customer told", booking.reload.on_the_way? && sms(booking, "customer_on_the_way")

  driver.get("/d/#{booking.dispatch_token}")
  check "driver page starts sharing by itself", driver.body.include?('data-driver-tracking-autostart-value="true"')

  trip = ws("trip", BASE, booking.dispatch_token, booking.public_token, booking.pickup_lat, booking.pickup_lng)
  check "both sockets accepted", trip["driver_confirmed"] && trip["customer_confirmed"]
  check "customer received every position live", trip["received"] == trip["sent"], "#{trip["received"]}/#{trip["sent"]}"
  check "distance to pickup shrinks", trip["distances_m"].each_cons(2).all? { |a, b| b < a }, trip["distances_m"].inspect
  check "ETA shown to customer", trip["eta_min"].all?(&:positive?), "#{trip["eta_min"].inspect} min"
  check "latency driver → customer", trip["latencies_ms"].any?, "#{trip["latencies_ms"].inspect} ms"
  check "customer cannot inject a position", !trip["fake_seen"] && booking.reload.driver_lat.to_f == trip["last_lat"]

  driver.post("/d/#{booking.dispatch_token}/complete", final_price: "24.50")
  booking.reload
  check "completed with final price", booking.completed? && booking.final_price_cents == 2450
  check "live position deleted", booking.driver_lat.nil? && booking.driver_located_at.nil?
end

# --- S3 + S5 ----------------------------------------------------------------
traveller = Client.new("traveller")
outbound = nil
scenario "S3 airport transfer booked ahead, empty leg sold" do
  tomorrow = local(days: 1, hour: 6)
  customer_booking(traveller, pickup_address: "Vaduz", pickup_place_id: place_id("Vaduz"),
                              dropoff_address: "Flughafen Zürich", dropoff_place_id: place_id("Flughafen Zürich"),
                              pickup_date: tomorrow.to_date.iso8601, pickup_time: "06:00", passengers: 2, luggage: 2,
                              flight_number: "LX 318", email: "")
  outbound = booking_from(traveller)
  check "fixed price CHF 290", outbound.quoted_price_cents == 29_000 && outbound.price_source == "fixed_route"
  check "flight number stored", outbound.flight_number == "LX318"
  check "waits for the dispatcher", outbound.pending? && sms(outbound, "dispatcher_new_booking")

  dispatcher = Client.new("dispatcher link")
  dispatcher.get("/d/#{outbound.dispatch_token}")
  dispatcher.post("/d/#{outbound.dispatch_token}/confirm")
  check "confirmed from the SMS link", outbound.reload.confirmed? && sms(outbound, "customer_confirmed")

  leg = outbound.empty_legs_created.first
  check "empty leg ZRH → Liechtenstein published", leg && leg.origin_label == "Flughafen Zürich"
  check "discounted 40 %", leg && leg.price_cents == 17_000, leg && "CHF #{leg.price_cents / 100}"

  bargain = Client.new("bargain hunter")
  bargain.get("/#{FIRM}/deals")
  check "deal listed publicly", bargain.body.include?("deal=#{leg.id}")
  slot = leg.available_from.in_time_zone(tenant.time_zone)
  customer_booking(bargain, path: "/#{FIRM}?deal=#{leg.id}", empty_leg_id: leg.id, pickup_address: leg.origin_label,
                            dropoff_address: leg.destination_label, pickup_date: slot.to_date.iso8601,
                            pickup_time: slot.strftime("%H:%M"))
  deal_booking = booking_from(bargain)
  check "empty leg booked at the deal price", deal_booking.source == "empty_leg" && deal_booking.quoted_price_cents == 17_000
  bargain.get("/#{FIRM}/deals")
  check "deal no longer offered", !bargain.body.include?("deal=#{leg.id}")
end

scenario "S5 return trip in one tap" do
  traveller.get("/#{FIRM}/b/#{outbound.public_token}")
  check "status page offers the return trip", traveller.body.include?("return_of=#{outbound.public_token}")
  traveller.get("/#{FIRM}?return_of=#{outbound.public_token}")
  check "route pre-filled reversed", traveller.body.include?('value="Flughafen Zürich"')
  back = local(days: 4, hour: 18)
  customer_booking(traveller, path: "/#{FIRM}?return_of=#{outbound.public_token}", return_of: outbound.public_token,
                              pickup_address: "Flughafen Zürich", pickup_place_id: place_id("Flughafen Zürich"),
                              dropoff_address: "Vaduz", dropoff_place_id: place_id("Vaduz"),
                              pickup_date: back.to_date.iso8601, pickup_time: "18:00", flight_number: "LX 319")
  ret = booking_from(traveller)
  check "linked to the outward ride", ret.source == "return_trip" && ret.outbound_booking == outbound
end

# --- S4 ---------------------------------------------------------------------
scenario "S4 customer cancels online" do
  planner = Client.new("planner")
  day = local(days: 2, hour: 10)
  customer_booking(planner, pickup_address: "Schaan", pickup_place_id: place_id("Schaan"), dropoff_address: "Vaduz",
                            dropoff_place_id: place_id("Vaduz"), pickup_date: day.to_date.iso8601, pickup_time: "10:00")
  booking = booking_from(planner)
  check "local ride priced by the meter", booking.price_source == "tariff" && booking.quoted_price_cents.to_i.positive?
  planner.follow
  planner.post("/#{FIRM}/b/#{booking.public_token}/cancel")
  check "cancelled", booking.reload.cancelled?
  check "dispatcher told", sms(booking, "dispatcher_cancelled")
end

# --- S6 ---------------------------------------------------------------------
scenario "S6 AI phone agent (tools against the core)" do
  out, status = Open3.capture2e({ "CORE_API_URL" => BASE }, "npm", "run", "check-core", "--", "+41445550000",
                                chdir: File.join(REPO, "voice"))
  check "voice service ↔ core integration check", status.success? && out.include?("OK"), out.lines.grep(/quote|booking/).map(&:strip).join(" | ")

  res, = internal(:get, "/internal/v1/voice/tenant?number=%2B41445550000", token: nil)
  check "API refuses calls without the token", res.code == "401"
  _, firm = internal(:get, "/internal/v1/voice/tenant?number=%2B41445550000")
  check "agent learns taxi-now is available", firm.dig("tenant", "asap_enabled") == true

  soon = tenant.now.advance(minutes: 5).strftime("%Y-%m-%dT%H:%M")
  _, quote = internal(:post, "/internal/v1/quotes", tenant_id: tenant.id, pickup_address: "Schaan",
                                                     dropoff_address: "Vaduz", pickup_at: soon, passengers: 1)
  check "quote: too soon to book normally, taxi now available", quote["lead_time_ok"] == false && quote["asap_available"] == true

  res, created = internal(:post, "/internal/v1/bookings", tenant_id: tenant.id, pickup_address: "Schaan",
                                 dropoff_address: "Vaduz", pickup_at: soon, passengers: 1, name: "Anrufer E2E",
                                 phone: "+41795550142", locale: "de", asap: true, call_sid: "CA_E2E_1",
                                 idempotency_key: "toolu_e2e_1")
  booking = tenant.bookings.find_by(reference: created.dig("booking", "reference"))
  check "agent booked a taxi-now request", res.code == "201" && booking&.asap? && booking.source == "voice"
  check "call linked to the booking", CallLog.find_by(call_sid: "CA_E2E_1")&.booking == booking

  _, again = internal(:post, "/internal/v1/bookings", tenant_id: tenant.id, pickup_address: "Schaan",
                             dropoff_address: "Vaduz", pickup_at: soon, passengers: 1, name: "Anrufer E2E",
                             phone: "+41795550142", locale: "de", asap: true, idempotency_key: "toolu_e2e_1")
  check "retried tool call does not double-book", again.dig("booking", "reference") == booking.reference

  link = Client.new("dispatcher")
  link.get("/d/#{booking.dispatch_token}")
  link.post("/d/#{booking.dispatch_token}/decline", reason: "no_capacity")
  check "dispatcher taps 'no car free', caller told", booking.reload.declined? && sms(booking, "customer_declined")
end

# --- S7 ---------------------------------------------------------------------
scenario "S7 AI down, dispatcher busy: call safety net" do
  call = { "CallSid" => "CA_E2E_FALLBACK", "From" => "+41795550177", "To" => "+41445550000" }
  res = signed_twilio_post("/twilio/voice/fallback", call)
  check "call forwarded to the dispatcher", res.code == "200" && res.body.include?("<Number>+41791234567</Number>")
  res = signed_twilio_post("/twilio/voice/dial_status", call.merge("DialCallStatus" => "no-answer"))
  check "no answer: voicemail", res.body.include?("<Record")
  res = signed_twilio_post("/twilio/voice/voicemail", call.merge("RecordingUrl" => "https://api.twilio.com/rec/RE1"))
  check "voicemail saved, call ends politely", res.body.include?("<Hangup/>")
  check "dispatcher gets the recording by SMS", MessageLog.where(purpose: "voicemail").last&.body.to_s.include?("RE1.mp3")
  check "caller gets a booking link by SMS", MessageLog.where(purpose: "missed_call_textback", to: "+41795550177").exists?
  check "unsigned webhook refused", signed_twilio_post("/twilio/voice/fallback", call, signature: nil).code == "403"
  check "forged webhook refused", signed_twilio_post("/twilio/voice/fallback", call, signature: "Zm9yZ2Vk").code == "403"
end

# --- S8 ---------------------------------------------------------------------
scenario "S8 found through Google and an AI assistant" do
  bot = Client.new("crawler")
  bot.get("/robots.txt")
  check "robots.txt lists the sitemap, hides tokens", bot.body.include?("Sitemap: #{BASE}/#{FIRM}/sitemap.xml") && bot.body.include?("Disallow: /d/")
  bot.get("/#{FIRM}/sitemap.xml")
  check "sitemap: taxi bendern + taxi now", bot.body.include?("/#{FIRM}/taxi/bendern</loc>") && bot.body.include?("/#{FIRM}/now</loc>")
  bot.get("/#{FIRM}/llms.txt")
  check "llms.txt offers Taxi now", bot.body.include?("[Taxi now](#{BASE}/#{FIRM}/now?utm_medium=discovery&utm_source=ai_assistant)")
  bot.get("/#{FIRM}/discovery.json")
  template = JSON.parse(bot.body).dig("actions", "taxi_now", "url_template")
  check "feed has a link template for assistants", template.to_s.include?("pickup={pickup}")

  bot.get("/#{FIRM}/taxi/bendern")
  check "'taxi bendern' page with airport price", bot.body.include?("<h1>Taxi Bendern</h1>") && bot.body.include?("CHF 290")
  bot.get("/#{FIRM}/taxi/flughafen-zuerich?lang=en")
  check "'taxi zurich airport liechtenstein' page in English", bot.body.include?("Taxi Flughafen Zürich – Liechtenstein") && bot.body.include?('hreflang="de"')
  bot.get("/#{FIRM}")
  check "schema.org order action on the home page", bot.body.include?('"@type":"OrderAction"')

  # The assistant fills its template with what the user said.
  link = template.sub("{pickup}", ERB::Util.url_encode("Hotel Real, Vaduz")).sub("{dropoff}", "Schaan").delete_prefix(BASE)
  user = Client.new("AI user")
  user.get(link)
  check "assistant's link opens a filled form", user.body.include?('value="Hotel Real, Vaduz"')
  user.post("/#{FIRM}/bookings", "booking[asap]" => 1, "booking[pickup_address]" => "Hotel Real, Vaduz",
                                 "booking[dropoff_address]" => "Schaan", "booking[passengers]" => 1,
                                 "booking[name]" => "KI Nutzer", "booking[phone]" => "079 555 11 22", "booking[website]" => "")
  booking = booking_from(user)
  check "booking credited to the AI assistant", booking.utm_source == "ai_assistant"
  Bookings::Lifecycle.new(booking).decline!(actor: Actor.system, reason: "e2e")
end

# --- S9 ---------------------------------------------------------------------
admin = Client.new("admin")
scenario "S9 platform admin in English: onboard, discovery, push" do
  admin.get("/session/new")
  admin.post("/session", email_address: "admin@example.com", password: PASSWORD)
  admin.get("/admin/tenants")
  admin.patch("/locale", lang: "en")
  admin.get("/admin/tenants")
  check "admin area switches to English", admin.body.include?("<h1>Firms</h1>") && admin.body.include?('<html lang="en">')

  admin.get("/admin/tenants/new")
  admin.post("/admin/tenants", "region" => "liechtenstein", "tenant[name]" => "Taxi Balzers E2E",
                               "tenant[slug]" => "taxi-balzers-e2e", "tenant[dispatcher_phone]" => "+41791119999",
                               "tenant[public_phone]" => "+4233889999", "tenant[status]" => "active",
                               "tenant[default_locale]" => "de", "owner[name]" => "Paul",
                               "owner[email_address]" => "balzers-e2e@example.com", "owner[password]" => "balzers-password-1")
  rival = Tenant.find_by(slug: "taxi-balzers-e2e")
  check "new firm onboarded with all localities", rival && rival.places.where(name: %w[Bendern Gamprin Planken]).count == 3

  admin.get("/admin/tenants/#{tenant.id}/discovery")
  check "discovery page: readiness + coverage", admin.body.include?("Search coverage") && admin.body.include?("is-ok")
  admin.post("/admin/tenants/#{tenant.id}/discovery")
  sleep 2
  pushes = tenant.discovery_pushes.order(:id).last(2)
  check "push queued and run", pushes.size == 2 && pushes.all? { |p| p.status != "pending" }, pushes.map { |p| "#{p.channel}=#{p.status}" }.join(", ")
  check "localhost correctly not submitted", pushes.all? { |p| p.status == "skipped" }

  admin.get("/admin/tenants/#{tenant.id}/discovery.csv")
  rows = CSV.parse(admin.body)
  check "Google Ads keyword CSV", rows.size > 1000 && rows.any? { |r| r[1] == "taxi bendern" }, "#{rows.size - 1} keywords"
  admin.get("/admin/tenants/#{tenant.id}/discovery")
  admin.post("/admin/tenants/#{tenant.id}/discovery/sync_places", region: "liechtenstein")
  admin.follow
  check "locality sync is idempotent", admin.body.include?("All localities are already there.")
end

# --- S10 --------------------------------------------------------------------
scenario "S10 dispatcher takes a phone booking" do
  owner.get("/dispatch/bookings/new")
  day = local(days: 1, hour: 14)
  owner.post("/dispatch/bookings", "booking[pickup_address]" => "Balzers", "booking[dropoff_address]" => "Bahnhof Sargans",
                                   "booking[pickup_date]" => day.to_date.iso8601, "booking[pickup_time]" => "14:00",
                                   "booking[passengers]" => 1, "booking[name]" => "Telefon Kunde",
                                   "booking[phone]" => "+4237771234", "booking[payment_method]" => "in_car",
                                   "confirm_now" => "1")
  booking = tenant.bookings.order(:id).last
  check "phone booking confirmed at once", booking.source == "phone_manual" && booking.confirmed?
  owner.get("/dispatch")
  check "board lists it", owner.body.include?(booking.pickup_address)
  owner.get("/dispatch/live")
  check "live map loads", owner.last.code == "200" && owner.body.include?("FleetChannel")
end

# --- S11 --------------------------------------------------------------------
scenario "S11 a rival firm cannot see another firm's data" do
  rival = Client.new("rival owner")
  rival.get("/session/new")
  rival.post("/session", email_address: "balzers-e2e@example.com", password: "balzers-password-1")
  demo_booking = tenant.bookings.order(:id).last
  rival.get("/dispatch/bookings/#{demo_booking.id}")
  check "other firm's ride: not found", rival.last.code == "404"
  rival.get("/taxi-balzers-e2e/b/#{demo_booking.public_token}")
  check "other firm's status page under own URL: not found", rival.last.code == "404"
  rival.get("/admin/tenants")
  check "admin area forbidden", rival.last.code == "403"
  check "other firm's live fleet: rejected", ws("fleet", BASE, tenant.id, rival.cookie_header)["confirmed"] == false
  check "own firm's dispatcher: allowed", ws("fleet", BASE, tenant.id, owner.cookie_header)["confirmed"] == true
  rival.get("/d/not-a-real-token-123456789")
  check "guessed SMS link: not found", rival.last.code == "404"
end

# --- S2 (part 2) --------------------------------------------------------------
scenario "S2 (part 2) the customer is not left waiting" do
  deadline = s2_booking.created_at + tenant.asap_response_minutes.minutes + 8.seconds
  sleep [ deadline - Time.current, 0 ].max
  s2_booking.reload
  check "request closed after the answer window", s2_booking.declined? && s2_booking.cancellation_reason == "no_response"
  check "customer SMS: no car free", sms(s2_booking, "customer_asap_unavailable")&.body.to_s.include?("kein Fahrzeug frei")
  check "dispatcher SMS: missed request", sms(s2_booking, "dispatcher_asap_missed")&.body.to_s.start_with?("VERPASST")
  waiting.get("/#{FIRM}/b/#{s2_booking.public_token}")
  check "status page offers to try again", waiting.body.include?("Leider ist gerade kein Fahrzeug frei") && waiting.body.include?("/#{FIRM}/now")
end

# --- S12 --------------------------------------------------------------------
scenario "S12 booking spam is stopped" do
  spammer = Client.new("spammer")
  limited = false
  12.times do |i|
    customer_booking(spammer, pickup_address: "Vaduz", dropoff_address: "Schaan",
                              pickup_date: local(days: 3, hour: 9).to_date.iso8601, pickup_time: "09:#{format("%02d", i)}")
    if spammer.redirected_to == "/#{FIRM}"
      spammer.follow
      limited = spammer.body.include?("Zu viele Anfragen")
      break
    end
  end
  check "rate limit kicks in", limited
  web = tenant.bookings.where(created_at: 10.minutes.ago.., source: %w[web return_trip empty_leg]).count
  check "at most 10 online bookings per client per 10 minutes", web <= 10, "#{web} created"
end

# --- summary ------------------------------------------------------------------
failed = $results.reject { |r| r[:ok] }
puts "\n#{"=" * 60}"
$results.group_by { |r| r[:scenario] }.each do |name, steps|
  bad = steps.count { |s| !s[:ok] }
  puts format("%-4s %-58s %2d/%-2d", bad.zero? ? "PASS" : "FAIL", name, steps.size - bad, steps.size)
end
puts "#{$results.size - failed.size}/#{$results.size} checks passed"
failed.each { |r| puts "  ✗ #{r[:scenario]}: #{r[:step]} #{r[:detail]}" }
exit(failed.empty? ? 0 : 1)
