// Kanban Drag & Drop Hook
// Columns use phx-hook="KanbanDrop" with data-status attribute
// Cards have draggable="true" with data-ticket-id attribute
export const KanbanDrop = {
  mounted() {
    const dropzone = this.el.querySelector('.kanban-dropzone')
    if (!dropzone) return

    // Drag over — allow drop
    dropzone.addEventListener('dragover', (e) => {
      e.preventDefault()
      e.dataTransfer.dropEffect = 'move'
      dropzone.classList.add('bg-primary/5', 'border-2', 'border-dashed', 'border-primary/30')
    })

    // Drag leave — remove highlight
    dropzone.addEventListener('dragleave', (e) => {
      // Only remove if we actually left the dropzone (not entering a child)
      if (!dropzone.contains(e.relatedTarget)) {
        dropzone.classList.remove('bg-primary/5', 'border-2', 'border-dashed', 'border-primary/30')
      }
    })

    // Drop — send event to server
    dropzone.addEventListener('drop', (e) => {
      e.preventDefault()
      dropzone.classList.remove('bg-primary/5', 'border-2', 'border-dashed', 'border-primary/30')

      const ticketId = e.dataTransfer.getData('text/ticket-id')
      const newStatus = this.el.dataset.status

      if (ticketId && newStatus) {
        this.pushEvent('kanban_drop', {
          ticket_id: ticketId,
          new_status: newStatus
        })
      }
    })

    // Make cards draggable — delegate from the column
    this.el.addEventListener('dragstart', (e) => {
      const card = e.target.closest('.kanban-card')
      if (!card) return

      const ticketId = card.dataset.ticketId
      if (ticketId) {
        e.dataTransfer.setData('text/ticket-id', ticketId)
        e.dataTransfer.effectAllowed = 'move'
        // Add visual feedback
        requestAnimationFrame(() => {
          card.classList.add('opacity-40', 'scale-95')
        })
      }
    })

    this.el.addEventListener('dragend', (e) => {
      const card = e.target.closest('.kanban-card')
      if (card) {
        card.classList.remove('opacity-40', 'scale-95')
      }
    })
  }
}
