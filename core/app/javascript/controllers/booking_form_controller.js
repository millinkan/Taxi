import { Controller } from "@hotwired/stimulus"

// Public booking form: place quick-picks and a live, server-computed price.
// The price shown here is informational; the server re-quotes on submit.
// On the "Taxi now" page it can also use the phone's GPS for the pickup.
export default class extends Controller {
  static targets = [
    "pickupAddress", "pickupPlaceId", "dropoffAddress", "dropoffPlaceId",
    "quoteBox", "quotePrice", "quoteMeta",
    "pickupLat", "pickupLng", "locateButton", "locateStatus"
  ]
  static values = { quoteUrl: String }

  connect() {
    this.requestId = 0
    this.schedule()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  // Chip click: fill the address with a known place.
  pick(event) {
    const { field, placeId, name } = event.currentTarget.dataset
    this[`${field}AddressTarget`].value = name
    this[`${field}PlaceIdTarget`].value = placeId
    this.element.querySelectorAll(`.chip[data-field="${field}"]`).forEach((chip) => {
      chip.setAttribute("aria-pressed", chip === event.currentTarget ? "true" : "false")
    })
    this.schedule()
  }

  // GPS pickup: the driver navigates to the exact coordinates; the customer
  // can still overwrite the text with a street or a landmark.
  locate() {
    const button = this.locateButtonTarget
    if (!navigator.geolocation) return this.locateFailed()

    button.disabled = true
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        const lat = coords.latitude.toFixed(6)
        const lng = coords.longitude.toFixed(6)
        this.pickupLatTarget.value = lat
        this.pickupLngTarget.value = lng
        this.pickupPlaceIdTarget.value = ""
        this.pickupAddressTarget.value = `${button.dataset.label} (${lat}, ${lng})`
        button.disabled = false
        this.schedule()
      },
      () => this.locateFailed(),
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 60000 }
    )
  }

  locateFailed() {
    this.locateButtonTarget.disabled = false
    if (this.hasLocateStatusTarget) this.locateStatusTarget.textContent = this.locateButtonTarget.dataset.failed
    this.pickupAddressTarget.focus()
  }

  // Typing a free address unlinks any previously picked place or GPS fix.
  clearPlace(event) {
    const field = event.target.dataset.field
    this[`${field}PlaceIdTarget`].value = ""
    if (field === "pickup" && this.hasPickupLatTarget) {
      this.pickupLatTarget.value = ""
      this.pickupLngTarget.value = ""
    }
    this.element.querySelectorAll(`.chip[data-field="${field}"]`).forEach((chip) => chip.setAttribute("aria-pressed", "false"))
  }

  schedule() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.quote(), 450)
  }

  async quote() {
    const pickup = this.pickupAddressTarget.value.trim()
    const dropoff = this.dropoffAddressTarget.value.trim()
    if (pickup.length < 3 || dropoff.length < 3) return

    const form = new FormData(this.element)
    const body = new FormData()
    for (const [key, value] of form.entries()) {
      const match = key.match(/^booking\[(.+)\]$/)
      if (match) body.append(match[1], value)
    }

    const id = ++this.requestId
    try {
      const response = await fetch(this.quoteUrlValue, {
        method: "POST",
        body,
        headers: { "X-CSRF-Token": this.csrfToken, "Accept": "application/json" },
        credentials: "same-origin"
      })
      if (!response.ok || id !== this.requestId) return
      this.render(await response.json())
    } catch (_error) {
      // Offline or server hiccup: the form still submits; the price follows by SMS.
    }
  }

  render(quote) {
    this.quoteBoxTarget.hidden = false
    this.quotePriceTarget.textContent = quote.price_text || ""
    const parts = []
    if (quote.message) parts.push(quote.message)
    if (quote.distance_km) parts.push(`${quote.distance_km} km`)
    if (quote.duration_min) parts.push(`~${quote.duration_min} min`)
    this.quoteMetaTarget.textContent = parts.join(" · ")
  }

  get csrfToken() {
    return document.querySelector("meta[name=csrf-token]")?.content || ""
  }
}
