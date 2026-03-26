/**
 * LogoCropper Hook
 *
 * Professional avatar/logo upload with crop & resize.
 * Flow: click avatar → file picker → crop modal → canvas resize → upload
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

    // Elements
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

    // Click avatar to open file picker
    this.triggerEl?.addEventListener("click", () => this.fileInput?.click())

    // File selected
    this.fileInput?.addEventListener("change", (e) => {
      const file = e.target.files[0]
      if (!file) return
      this.loadImage(file)
    })

    // Zoom
    this.zoomSlider?.addEventListener("input", (e) => {
      this.scale = parseFloat(e.target.value)
      this.drawCrop()
    })

    // Pan - mouse
    this.canvas?.addEventListener("mousedown", (e) => this.startDrag(e.clientX, e.clientY))
    document.addEventListener("mousemove", (e) => this.onDrag(e.clientX, e.clientY))
    document.addEventListener("mouseup", () => this.endDrag())

    // Pan - touch
    this.canvas?.addEventListener("touchstart", (e) => {
      e.preventDefault()
      const t = e.touches[0]
      this.startDrag(t.clientX, t.clientY)
    })
    document.addEventListener("touchmove", (e) => {
      if (!this.dragging) return
      const t = e.touches[0]
      this.onDrag(t.clientX, t.clientY)
    })
    document.addEventListener("touchend", () => this.endDrag())

    // Confirm crop
    this.confirmBtn?.addEventListener("click", () => this.confirmCrop())

    // Cancel
    this.cancelBtn?.addEventListener("click", () => this.closeModal())
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
    const c = this.canvas
    const ctx = this.ctx
    const cw = c.width
    const ch = c.height

    // Clear
    ctx.clearRect(0, 0, cw, ch)

    // Calculate scaled dimensions maintaining aspect ratio
    const imgAspect = this.img.width / this.img.height
    let drawW, drawH

    if (imgAspect > 1) {
      // Landscape: fit height to canvas, scale width
      drawH = ch * this.scale
      drawW = drawH * imgAspect
    } else {
      // Portrait: fit width to canvas, scale height
      drawW = cw * this.scale
      drawH = drawW / imgAspect
    }

    const x = (cw - drawW) / 2 + this.panX
    const y = (ch - drawH) / 2 + this.panY

    // Draw image
    ctx.drawImage(this.img, x, y, drawW, drawH)

    // Draw circular mask overlay
    ctx.save()
    ctx.fillStyle = "rgba(0, 0, 0, 0.55)"
    ctx.fillRect(0, 0, cw, ch)

    // Cut out circle
    const radius = Math.min(cw, ch) / 2 - 10
    ctx.globalCompositeOperation = "destination-out"
    ctx.beginPath()
    ctx.arc(cw / 2, ch / 2, radius, 0, Math.PI * 2)
    ctx.fill()
    ctx.restore()

    // Draw circle border
    ctx.strokeStyle = "rgba(255, 255, 255, 0.6)"
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
    if (!this.dragging) return
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

    // Create a square crop from the circle center
    const c = this.canvas
    const cw = c.width
    const ch = c.height
    const radius = Math.min(cw, ch) / 2 - 10
    const cropX = cw / 2 - radius
    const cropY = ch / 2 - radius
    const cropSize = radius * 2

    // Offscreen canvas for final output
    const out = document.createElement("canvas")
    out.width = this.cropSize
    out.height = this.cropSize
    const outCtx = out.getContext("2d")

    // Draw the cropped region (without overlay) to the output canvas
    // First redraw without overlay
    const temp = document.createElement("canvas")
    temp.width = cw
    temp.height = ch
    const tempCtx = temp.getContext("2d")

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
    tempCtx.drawImage(this.img, x, y, drawW, drawH)

    // Crop and resize
    outCtx.drawImage(temp, cropX, cropY, cropSize, cropSize, 0, 0, this.cropSize, this.cropSize)

    // Convert to blob and push to LiveView
    out.toBlob((blob) => {
      if (!blob) return

      // Create a File from the blob
      const croppedFile = new File([blob], "logo.png", { type: "image/png" })

      // Use DataTransfer to set the file on the hidden upload input
      const dt = new DataTransfer()
      dt.items.add(croppedFile)

      // Find the LiveView file input (generated by live_file_input)
      const liveInput = this.el.querySelector("input[type='file'][data-phx-upload-ref]")
      if (liveInput) {
        liveInput.files = dt.files
        liveInput.dispatchEvent(new Event("change", { bubbles: true }))
      }

      // Update preview
      if (this.previewEl) {
        this.previewEl.src = URL.createObjectURL(blob)
        this.previewEl.classList.remove("hidden")
        const placeholder = this.el.querySelector("[data-crop-placeholder]")
        if (placeholder) placeholder.classList.add("hidden")
      }

      this.closeModal()
    }, "image/png", 0.92)
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
