import { onScopeDispose } from 'vue'
import type { useBoardStore } from '@/stores/board'

type BoardStore = ReturnType<typeof useBoardStore>

type Point = { left: number; top: number }

type Flight = {
  clone: HTMLElement
  columnId: string
  queue: Point[]
  running: boolean
  realEl: HTMLElement | null
  anim: Animation | null
}

const FLIGHT_MS = 400
const FLIGHT_EASING = 'cubic-bezier(0.2, 0, 0, 1)'
const MAX_CAPTURE_ATTEMPTS = 4

export function useCrossColumnFlight(board: BoardStore) {
  const flights = new Map<string, Flight>()

  function cardInColumn(id: string, columnId: string): HTMLElement | null {
    return document.querySelector(
      `.ks-col[data-column-id="${columnId}"] [data-task-id="${id}"]`,
    )
  }

  function settle(id: string) {
    const flight = flights.get(id)
    if (!flight) return
    if (flight.realEl) flight.realEl.style.visibility = ''
    flight.clone.remove()
    flights.delete(id)
  }

  function runFlight(id: string) {
    const flight = flights.get(id)
    if (!flight) return
    const next = flight.queue.shift()
    if (!next) {
      settle(id)
      return
    }
    flight.running = true
    const current = flight.clone.getBoundingClientRect()
    const end = `translate3d(${next.left}px, ${next.top}px, 0)`
    flight.clone.style.transform = end
    const anim = flight.clone.animate(
      [
        { transform: `translate3d(${current.left}px, ${current.top}px, 0)` },
        { transform: end },
      ],
      { duration: FLIGHT_MS, easing: FLIGHT_EASING },
    )
    flight.anim = anim
    anim.onfinish = () => {
      flight.running = false
      runFlight(id)
    }
    anim.oncancel = () => {
      flight.running = false
    }
  }

  function captureAndRun(id: string, attempt = 0) {
    const flight = flights.get(id)
    if (!flight) return
    const realEl = cardInColumn(id, flight.columnId)
    if (!realEl) {
      if (attempt < MAX_CAPTURE_ATTEMPTS) {
        requestAnimationFrame(() => captureAndRun(id, attempt + 1))
        return
      }
      if (!flight.running) settle(id)
      return
    }
    const rect = realEl.getBoundingClientRect()
    realEl.style.visibility = 'hidden'
    flight.realEl = realEl
    flight.queue.push({ left: rect.left, top: rect.top })
    if (!flight.running) runFlight(id)
  }

  board.onTaskMoving((task, prevColumnId) => {
    if (board.consumeLocalMove(task.id)) return
    const existing = flights.get(task.id)
    if (existing) {
      existing.columnId = task.column_id
    } else {
      const oldEl = cardInColumn(task.id, prevColumnId)
      if (!oldEl) return
      flights.set(task.id, {
        clone: makeClone(oldEl),
        columnId: task.column_id,
        queue: [],
        running: false,
        realEl: null,
        anim: null,
      })
      oldEl.style.visibility = 'hidden'
    }
    requestAnimationFrame(() => captureAndRun(task.id))
  })

  onScopeDispose(() => {
    board.onTaskMoving(null)
    for (const flight of flights.values()) {
      flight.anim?.cancel()
      if (flight.realEl) flight.realEl.style.visibility = ''
      flight.clone.remove()
    }
    flights.clear()
  })
}

function makeClone(el: HTMLElement): HTMLElement {
  const rect = el.getBoundingClientRect()
  const clone = el.cloneNode(true) as HTMLElement
  clone.removeAttribute('data-task-id')
  clone.classList.add('ks-card--ghost', 'ks-card--flying-clone')
  clone.classList.remove('ks-card--dragging')
  clone.style.visibility = ''
  clone.style.width = `${rect.width}px`
  clone.style.height = `${rect.height}px`
  clone.style.transform = `translate3d(${rect.left}px, ${rect.top}px, 0)`
  clone.querySelectorAll('.ks-card__edge').forEach((node) => node.remove())
  document.body.appendChild(clone)
  return clone
}
