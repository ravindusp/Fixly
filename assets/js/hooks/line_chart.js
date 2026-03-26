import { Chart, LineController, LineElement, PointElement, LinearScale, CategoryScale, Filler, Tooltip } from "chart.js"

Chart.register(LineController, LineElement, PointElement, LinearScale, CategoryScale, Filler, Tooltip)

export const LineChart = {
  mounted() {
    const canvas = this.el.querySelector("canvas")
    const labels = JSON.parse(this.el.dataset.labels)
    const values = JSON.parse(this.el.dataset.values)

    const primaryColor = getComputedStyle(document.documentElement)
      .getPropertyValue("--p")
      .trim()

    // Convert oklch to a usable color, fallback to a nice blue
    const lineColor = "oklch(55% .2 260)"
    const fillColor = "oklch(55% .2 260 / 0.08)"

    this.chart = new Chart(canvas, {
      type: "line",
      data: {
        labels,
        datasets: [{
          data: values,
          borderColor: lineColor,
          backgroundColor: fillColor,
          borderWidth: 2.5,
          pointRadius: 4,
          pointBackgroundColor: "#fff",
          pointBorderColor: lineColor,
          pointBorderWidth: 2,
          pointHoverRadius: 6,
          pointHoverBackgroundColor: lineColor,
          pointHoverBorderColor: "#fff",
          pointHoverBorderWidth: 2,
          fill: true,
          tension: 0.3,
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: {
          intersect: false,
          mode: "index",
        },
        plugins: {
          tooltip: {
            backgroundColor: "oklch(20% .02 260)",
            titleFont: { size: 12, weight: "600" },
            bodyFont: { size: 13, weight: "700" },
            padding: { x: 12, y: 8 },
            cornerRadius: 8,
            displayColors: false,
            callbacks: {
              title: (items) => items[0].label,
              label: (item) => `${item.raw} ticket${item.raw !== 1 ? "s" : ""}`,
            }
          },
          legend: { display: false },
        },
        scales: {
          x: {
            grid: { display: false },
            ticks: {
              font: { size: 10 },
              color: "oklch(50% .01 260 / 0.4)",
              maxTicksLimit: 7,
              maxRotation: 0,
            },
            border: { display: false },
          },
          y: {
            beginAtZero: true,
            grid: {
              color: "oklch(50% .01 260 / 0.06)",
            },
            ticks: {
              font: { size: 10 },
              color: "oklch(50% .01 260 / 0.4)",
              precision: 0,
              maxTicksLimit: 5,
            },
            border: { display: false },
          }
        }
      }
    })
  },

  updated() {
    const labels = JSON.parse(this.el.dataset.labels)
    const values = JSON.parse(this.el.dataset.values)
    this.chart.data.labels = labels
    this.chart.data.datasets[0].data = values
    this.chart.update()
  },

  destroyed() {
    if (this.chart) this.chart.destroy()
  }
}
