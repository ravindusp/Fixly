/**
 * TimezoneClock Hook
 *
 * Displays a live-updating clock in the selected timezone.
 */
export const TimezoneClock = {
  mounted() {
    this.tz = this.el.dataset.timezone || "Asia/Colombo"
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)

    this.handleEvent("update_clock_timezone", ({ timezone }) => {
      this.tz = timezone
      this.tick()
    })
  },

  tick() {
    try {
      const now = new Date()
      const timeStr = now.toLocaleTimeString("en-US", {
        timeZone: this.tz,
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hour12: true
      })
      const dateStr = now.toLocaleDateString("en-US", {
        timeZone: this.tz,
        weekday: "short",
        month: "short",
        day: "numeric",
        year: "numeric"
      })
      const timeEl = this.el.querySelector("[data-clock-time]")
      const dateEl = this.el.querySelector("[data-clock-date]")
      if (timeEl) timeEl.textContent = timeStr
      if (dateEl) dateEl.textContent = dateStr
    } catch (e) {
      // Invalid timezone, show fallback
      const timeEl = this.el.querySelector("[data-clock-time]")
      if (timeEl) timeEl.textContent = "--:--:--"
    }
  },

  destroyed() {
    if (this.timer) clearInterval(this.timer)
  }
}
