import { Controller } from "@hotwired/stimulus"
import getConsumer from "channels/consumer"

// Driver's phone: streams the car's position over a WebSocket while a ride is
// active. Every fresh GPS fix is sent the moment it arrives (no cached fixes),
// once the car has moved 10 m, or every 10 s while standing as a sign of life.
// The server keeps at most one point per second. Battery: the GPS is on for
// the whole ride anyway; a ~100-byte frame per fix costs next to nothing.
// The screen is kept on (Wake Lock): browsers stop location updates when the
// phone locks, and a taxi phone is mounted and charging anyway.
const MIN_MOVE_M = 10
const HEARTBEAT_MS = 10000

export default class extends Controller {
  static targets = ["start", "stop", "status"]
  static values = { token: String, autostart: Boolean, texts: Object }

  connect() {
    if (this.autostartValue) this.start()
  }

  disconnect() {
    this.stop()
  }

  start() {
    if (!navigator.geolocation) return this.say("unsupported")

    this.subscription ||= getConsumer().subscriptions.create(
      { channel: "TripChannel", dispatch_token: this.tokenValue },
      { received: (data) => { if (data.ended) this.stop("ended") } }
    )
    this.watchId ??= navigator.geolocation.watchPosition(
      (position) => this.send(position),
      (error) => this.say(error.code === error.PERMISSION_DENIED ? "denied" : "waiting"),
      { enableHighAccuracy: true, maximumAge: 0, timeout: 20000 }
    )
    this.keepAwake()
    this.onVisible ||= () => { if (document.visibilityState === "visible" && this.watchId != null) this.keepAwake() }
    document.addEventListener("visibilitychange", this.onVisible)
    this.toggle(true)
    this.say("waiting")
  }

  stop(reason = "stopped") {
    if (this.watchId != null) navigator.geolocation.clearWatch(this.watchId)
    this.watchId = null
    this.subscription?.unsubscribe()
    this.subscription = null
    this.wakeLock?.release().catch(() => {})
    this.wakeLock = null
    if (this.onVisible) document.removeEventListener("visibilitychange", this.onVisible)
    this.toggle(false)
    this.say(reason)
  }

  send({ coords }) {
    const now = Date.now()
    const moved = this.last ? distanceM(this.last, coords) : Infinity
    if (moved < MIN_MOVE_M && now - (this.lastSentAt || 0) < HEARTBEAT_MS) return

    this.subscription?.perform("update", {
      lat: coords.latitude, lng: coords.longitude,
      heading: Number.isFinite(coords.heading) ? coords.heading : null,
      accuracy: coords.accuracy
    })
    this.last = coords
    this.lastSentAt = now
    this.say("sharing")
  }

  async keepAwake() {
    try {
      this.wakeLock = await navigator.wakeLock?.request("screen")
    } catch (_error) {
      // Not supported or battery saver: tracking still works while the screen is on.
    }
  }

  toggle(running) {
    if (this.hasStartTarget) this.startTarget.hidden = running
    if (this.hasStopTarget) this.stopTarget.hidden = !running
  }

  say(key) {
    if (this.hasStatusTarget) this.statusTarget.textContent = this.textsValue[key] || ""
  }
}

function distanceM(a, b) {
  const rad = Math.PI / 180
  const dLat = (b.latitude - a.latitude) * rad
  const dLng = (b.longitude - a.longitude) * rad
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.latitude * rad) * Math.cos(b.latitude * rad) * Math.sin(dLng / 2) ** 2
  return 2 * 6371000 * Math.asin(Math.sqrt(h))
}
