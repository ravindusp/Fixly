/**
 * LocationPicker Hook
 *
 * Leaflet map with draggable pin for setting organization location.
 * Supports: drag-to-set, browser geolocation fetch, reverse geocoding.
 */
export const LocationPicker = {
  mounted() {
    this.initMap()

    // Fetch location button
    this.el.querySelector("[data-fetch-location]")?.addEventListener("click", () => {
      this.fetchLocation()
    })

    // Set on map button (re-centers to current pin)
    this.el.querySelector("[data-set-on-map]")?.addEventListener("click", () => {
      if (this.marker) {
        const pos = this.marker.getLatLng()
        this.map.setView(pos, 17, { animate: true })
      }
    })

    // Listen for server-side coordinate updates
    this.handleEvent("set_map_location", ({ lat, lng }) => {
      if (this.marker && this.map) {
        const latlng = L.latLng(lat, lng)
        this.marker.setLatLng(latlng)
        this.map.setView(latlng, 16, { animate: true })
        this.reverseGeocode(lat, lng)
      }
    })
  },

  initMap() {
    const mapEl = this.el.querySelector("[data-map]")
    if (!mapEl || typeof L === "undefined") return

    const lat = parseFloat(mapEl.dataset.lat) || 6.9271
    const lng = parseFloat(mapEl.dataset.lng) || 79.8612
    const hasLocation = mapEl.dataset.lat && mapEl.dataset.lng
    const zoom = hasLocation ? 16 : 13

    // Create map
    this.map = L.map(mapEl, {
      zoomControl: false,
      attributionControl: false
    }).setView([lat, lng], zoom)

    // Add zoom control to bottom-right
    L.control.zoom({ position: "bottomright" }).addTo(this.map)

    // Attribution
    L.control.attribution({ position: "bottomleft", prefix: false })
      .addAttribution('&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank">OpenStreetMap</a>')
      .addTo(this.map)

    // Tile layer
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19
    }).addTo(this.map)

    // Custom pin icon
    const pinIcon = L.divIcon({
      className: "custom-pin",
      html: `
        <div style="position:relative;width:40px;height:52px;">
          <svg width="40" height="52" viewBox="0 0 40 52" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M20 0C8.954 0 0 8.954 0 20c0 14 20 32 20 32s20-18 20-32C40 8.954 31.046 0 20 0z" fill="#2563eb"/>
            <circle cx="20" cy="18" r="8" fill="white"/>
          </svg>
          <div style="position:absolute;bottom:-4px;left:50%;transform:translateX(-50%);width:12px;height:4px;background:rgba(0,0,0,0.2);border-radius:50%;filter:blur(2px);"></div>
        </div>
      `,
      iconSize: [40, 52],
      iconAnchor: [20, 52],
      popupAnchor: [0, -52]
    })

    // Draggable marker
    this.marker = L.marker([lat, lng], {
      draggable: true,
      icon: pinIcon,
      autoPan: true
    }).addTo(this.map)

    // On drag end → push coordinates
    this.marker.on("dragend", () => {
      const pos = this.marker.getLatLng()
      this.pushCoordinates(pos.lat, pos.lng)
      this.reverseGeocode(pos.lat, pos.lng)
    })

    // Click map to move pin
    this.map.on("click", (e) => {
      this.marker.setLatLng(e.latlng)
      this.pushCoordinates(e.latlng.lat, e.latlng.lng)
      this.reverseGeocode(e.latlng.lat, e.latlng.lng)
    })

    // If we have a saved location, reverse geocode it
    if (hasLocation) {
      this.reverseGeocode(lat, lng)
    }

    // Fix map rendering in hidden/late-rendered containers
    setTimeout(() => this.map.invalidateSize(), 200)
  },

  fetchLocation() {
    const btn = this.el.querySelector("[data-fetch-location]")
    if (!navigator.geolocation) {
      this.pushEvent("location_error", { message: "Geolocation is not supported by your browser" })
      return
    }

    // Show loading state
    if (btn) {
      btn.disabled = true
      btn.innerHTML = `<span class="loading loading-spinner loading-xs"></span> Fetching...`
    }

    navigator.geolocation.getCurrentPosition(
      (position) => {
        const { latitude, longitude } = position.coords
        const latlng = L.latLng(latitude, longitude)
        this.marker.setLatLng(latlng)
        this.map.setView(latlng, 17, { animate: true })
        this.pushCoordinates(latitude, longitude)
        this.reverseGeocode(latitude, longitude)

        if (btn) {
          btn.disabled = false
          btn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="size-4" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"/></svg> Fetch My Location`
        }
      },
      (error) => {
        if (btn) {
          btn.disabled = false
          btn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="size-4" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"/></svg> Fetch My Location`
        }
        this.pushEvent("location_error", { message: error.message })
      },
      { enableHighAccuracy: true, timeout: 10000 }
    )
  },

  pushCoordinates(lat, lng) {
    this.pushEvent("update_coordinates", {
      latitude: Math.round(lat * 1000000) / 1000000,
      longitude: Math.round(lng * 1000000) / 1000000
    })
  },

  reverseGeocode(lat, lng) {
    const addressEl = this.el.querySelector("[data-location-address]")
    if (!addressEl) return

    addressEl.textContent = "Loading address..."

    fetch(`https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json&zoom=18&addressdetails=1`, {
      headers: { "Accept-Language": "en" }
    })
      .then(r => r.json())
      .then(data => {
        if (data.display_name) {
          addressEl.textContent = data.display_name
        } else {
          addressEl.textContent = `${lat.toFixed(6)}, ${lng.toFixed(6)}`
        }
      })
      .catch(() => {
        addressEl.textContent = `${lat.toFixed(6)}, ${lng.toFixed(6)}`
      })
  },

  destroyed() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }
}
