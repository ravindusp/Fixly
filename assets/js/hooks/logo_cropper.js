/**
 * LogoCropper Hook
 *
 * Professional avatar/logo upload with crop & resize.
 * Flow: click avatar → file picker → crop modal → canvas resize → base64 push to server
 */
export const LogoCropper = {
  mounted() {
    this.cropSize = 256
    this.scale = 1
    this.panX = 0
    this.panY = 0
    this.dragging = false
    this.dragStart = { x: 0, y: 0 }
    this.img = null

    this.triggerEl = this.el.querySelector("[data-crop-trigger]")
    this.fileInput = this.el.querySelector("[data-crop-input]")
    this.modal = this.el.querySelector("[data-crop-modal]")
    this.canvas = this.el.querySelector("[data-crop-canvas]")
    this.zoomSlider = this.el.querySelector("[data-crop-zoom]")
    this.confirmBtn = this.el.querySelector("[data-crop-confirm]")
    this.cancelBtn = this.el.querySelector("[data-crop-cancel]")
    this.previewEl = this.el.querySelector("[data-crop-preview]")

    if (!this.canvas) return
    this.ctx = this.canvas.getContext("2d")
    this.canvas.width = 300
    this.canvas.height = 300

    this.triggerEl?.addEventListener("click", () => this.fileInput?.click())

    this.fileInput?.addEventListener("change", (e) => {
      const file = e.target.files[0]
      if (!file) return
      this.loadImage(file)
    })

    this.zoomSlider?.addEventListener("input", (e) => {
      this.scale = parseFloat(e.target.value)
      this.drawCrop()
    })

    // Mouse drag
    this.canvas?.addEventListener("mousedown", (e) => this.startDrag(e.clientX, e.clientY))
    document.addEventListener("mousemove", (e) => { if (this.dragging) this.onDrag(e.clientX, e.clientY) })
    document.addEventListener("mouseup", () => this.endDrag())

    // Touch drag
    this.canvas?.addEventListener("touchstart", (e) => { e.preventDefault(); this.startDrag(e.touches[0].clientX, e.touches[0].clientY) })
    document.addEventListener("touchmove", (e) => { if (this.dragging) this.onDrag(e.touches[0].clientX, e.touches[0].clientY) })
    document.addEventListener("touchend", () => this.endDrag())

    this.confirmBtn?.addEventListener("click", () => this.confirmCrop())

    // All cancel buttons
    this.el.querySelectorAll("[data-crop-cancel]").forEach(el => {
      el.addEventListener("click", () => this.closeModal())
    })
  },

  loadImage(file) {
    const reader = new FileReader()
    reader.onload = (e) => {
      this.img = new Image()
      this.img.onload = () => {
        this.scale = 1
        this.panX = 0
        this.panY = 0
        if (this.zoomSlider) this.zoomSlider.value = 1
        this.drawCrop()
        this.openModal()
      }
      this.img.src = e.target.result
    }
    reader.readAsDataURL(file)
  },

  drawCrop() {
    if (!this.img || !this.ctx) return
    const c = this.canvas, ctx = this.ctx
    const cw = c.width, ch = c.height

    ctx.clearRect(0, 0, cw, ch)

    // Fill background
    ctx.fillStyle = "#1a1a2e"
    ctx.fillRect(0, 0, cw, ch)

    const imgAspect = this.img.width / this.img.height
    let drawW, drawH
    if (imgAspect > 1) {
      drawH = ch * this.scale
      drawW = drawH * imgAspect
    } else {
      drawW = cw * this.scale
      drawH = drawW / imgAspect
    }

    const x = (cw - drawW) / 2 + this.panX
    const y = (ch - drawH) / 2 + this.panY
    ctx.drawImage(this.img, x, y, drawW, drawH)

    // Darken outside circle
    ctx.save()
    ctx.fillStyle = "rgba(0, 0, 0, 0.6)"
    ctx.fillRect(0, 0, cw, ch)
    const radius = Math.min(cw, ch) / 2 - 16
    ctx.globalCompositeOperation = "destination-out"
    ctx.beginPath()
    ctx.arc(cw / 2, ch / 2, radius, 0, Math.PI * 2)
    ctx.fill()
    ctx.restore()

    // Circle border
    ctx.strokeStyle = "rgba(255, 255, 255, 0.5)"
    ctx.lineWidth = 2
    ctx.beginPath()
    ctx.arc(cw / 2, ch / 2, radius, 0, Math.PI * 2)
    ctx.stroke()
  },

  startDrag(x, y) {
    this.dragging = true
    this.dragStart = { x: x - this.panX, y: y - this.panY }
    if (this.canvas) this.canvas.style.cursor = "grabbing"
  },
  onDrag(x, y) {
    this.panX = x - this.dragStart.x
    this.panY = y - this.dragStart.y
    this.drawCrop()
  },
  endDrag() {
    this.dragging = false
    if (this.canvas) this.canvas.style.cursor = "grab"
  },

  confirmCrop() {
    if (!this.img) return

    const c = this.canvas, cw = c.width, ch = c.height
    const radius = Math.min(cw, ch) / 2 - 16
    const cropX = cw / 2 - radius, cropY = ch / 2 - radius
    const cropDiameter = radius * 2

    // Redraw clean (no overlay) onto temp canvas
    const temp = document.createElement("canvas")
    temp.width = cw; temp.height = ch
    const tCtx = temp.getContext("2d")

    const imgAspect = this.img.width / this.img.height
    let drawW, drawH
    if (imgAspect > 1) { drawH = ch * this.scale; drawW = drawH * imgAspect }
    else { drawW = cw * this.scale; drawH = drawW / imgAspect }
    const x = (cw - drawW) / 2 + this.panX
    const y = (ch - drawH) / 2 + this.panY
    tCtx.drawImage(this.img, x, y, drawW, drawH)

    // Output canvas at target size
    const out = document.createElement("canvas")
    out.width = this.cropSize; out.height = this.cropSize
    const oCtx = out.getContext("2d")
    oCtx.drawImage(temp, cropX, cropY, cropDiameter, cropDiameter, 0, 0, this.cropSize, this.cropSize)

    // Get base64 and push to server
    const dataUrl = out.toDataURL("image/png", 0.92)

    // Update local preview immediately
    if (this.previewEl) {
      this.previewEl.src = dataUrl
      this.previewEl.classList.remove("hidden")
      const placeholder = this.el.querySelector("[data-crop-placeholder]")
      if (placeholder) placeholder.classList.add("hidden")
    }

    // Push to LiveView
    this.pushEvent("save_cropped_logo", { data: dataUrl })
    this.closeModal()
  },

  openModal() {
    this.modal?.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  },
  closeModal() {
    this.modal?.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
    if (this.fileInput) this.fileInput.value = ""
  }
}
