// SLA Countdown Timer Hook
// Usage: <span phx-hook="SLATimer" data-deadline="2026-03-25T14:00:00Z" data-paused="false">
export const SLATimer = {
  mounted() {
    this.tick()
    this.interval = setInterval(() => this.tick(), 1000)
  },

  updated() {
    this.tick()
  },

  destroyed() {
    clearInterval(this.interval)
  },

  tick() {
    const deadline = this.el.dataset.deadline
    const paused = this.el.dataset.paused === "true"

    if (!deadline) {
      this.el.textContent = "No deadline"
      this.el.className = this.baseClass("text-base-content/50")
      return
    }

    if (paused) {
      this.el.textContent = "⏸ Paused"
      this.el.className = this.baseClass("text-warning")
      return
    }

    const now = new Date()
    const end = new Date(deadline)
    const diffMs = end - now
    const diffMin = Math.floor(diffMs / 60000)

    if (diffMin < 0) {
      const overdue = Math.abs(diffMin)
      if (overdue < 60) {
        this.el.textContent = `${overdue}m overdue`
      } else if (overdue < 1440) {
        this.el.textContent = `${Math.floor(overdue / 60)}h ${overdue % 60}m overdue`
      } else {
        this.el.textContent = `${Math.floor(overdue / 1440)}d overdue`
      }
      this.el.className = this.baseClass("text-error font-semibold")
    } else if (diffMin < 60) {
      this.el.textContent = `${diffMin}m left`
      this.el.className = this.baseClass("text-error")
    } else if (diffMin < 480) {
      const h = Math.floor(diffMin / 60)
      const m = diffMin % 60
      this.el.textContent = `${h}h ${m}m left`
      this.el.className = this.baseClass("text-warning")
    } else if (diffMin < 1440) {
      this.el.textContent = `${Math.floor(diffMin / 60)}h left`
      this.el.className = this.baseClass("text-success")
    } else {
      this.el.textContent = `${Math.floor(diffMin / 1440)}d left`
      this.el.className = this.baseClass("text-success")
    }
  },

  baseClass(color) {
    return `text-sm font-medium ${color}`
  }
}
