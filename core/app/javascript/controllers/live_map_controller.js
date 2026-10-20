import { Controller } from "@hotwired/stimulus"
import getConsumer from "channels/consumer"

// Live map, fed over a WebSocket.
//   customer status page: one car (TripChannel, public token) + the pickup
//   dispatcher live page: every car of the firm (FleetChannel)
// Markers are drawn as circles, so no marker images have to be loaded.
export default class extends Controller {
  static targets = ["map", "info"]
  static values = {
    channel: Object, pickup: Array, cars: Array, texts: Object
  }

  async connect() {
    const L = await import("leaflet")
    if (!this.element.isConnected) return
    this.L = L
    this.markers = new Map()

    const center = this.pickupValue.length ? this.pickupValue : [47.141, 9.5209]
    this.map = L.map(this.mapTarget, { zoomControl: true }).setView(center, 14)
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19, attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      // The pages send no referrer, but OSM blocks tile requests without one.
      // Origin only, so the tracking token in the page URL never leaves.
      referrerPolicy: "strict-origin-when-cross-origin"
    }).addTo(this.map)
    if (this.pickupValue.length) {
      L.circleMarker(this.pickupValue, { radius: 8, color: "#b42318", fillOpacity: 0.9 }).addTo(this.map)
    }
    this.carsValue.forEach((car) => this.place(car))

    this.subscription = getConsumer().subscriptions.create(this.channelValue, {
      received: (data) => (data.ended ? this.remove(data) : this.place(data))
    })
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.map?.remove()
  }

  place(car) {
    if (car.lat == null) return
    let marker = this.markers.get(car.booking_id)
    if (marker) {
      this.glide(marker, [car.lat, car.lng])
    } else {
      marker = this.L.circleMarker([car.lat, car.lng], { radius: 10, color: "#0f766e", fillOpacity: 0.95 }).addTo(this.map)
      this.markers.set(car.booking_id, marker)
    }
    if (car.reference) marker.bindTooltip(car.reference)
    this.fit()
    this.describe(car)
  }

  // Positions arrive about once a second; gliding over that second makes the
  // car move continuously instead of jumping from point to point.
  glide(marker, target) {
    cancelAnimationFrame(marker.glideFrame)
    const from = marker.getLatLng()
    const started = performance.now()
    const step = (now) => {
      const t = Math.min(1, (now - started) / 900)
      marker.setLatLng([from.lat + (target[0] - from.lat) * t, from.lng + (target[1] - from.lng) * t])
      if (t < 1) marker.glideFrame = requestAnimationFrame(step)
    }
    marker.glideFrame = requestAnimationFrame(step)
  }

  remove(data) {
    this.markers.get(data.booking_id)?.remove()
    this.markers.delete(data.booking_id)
    if (this.pickupValue.length && this.hasInfoTarget) this.infoTarget.textContent = this.textsValue.ended || ""
  }

  fit() {
    const points = [...this.markers.values()].map((m) => m.getLatLng())
    if (this.pickupValue.length) points.push(this.L.latLng(this.pickupValue))
    if (points.length > 1) this.map.fitBounds(this.L.latLngBounds(points), { padding: [40, 40], maxZoom: 16 })
    else if (points.length === 1) this.map.setView(points[0])
  }

  describe(car) {
    if (!this.hasInfoTarget || !this.pickupValue.length || car.eta_min == null) return
    const km = (car.distance_m / 1000).toFixed(1)
    this.infoTarget.textContent = (this.textsValue.eta || "")
      .replace("%{minutes}", car.eta_min).replace("%{km}", km)
  }
}
