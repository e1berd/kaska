import { reactive } from 'vue'
import type { Task } from '@/stores/board'

export type DropEdge = 'top' | 'bottom'

export interface TaskPlacement {
  columnId: string
  beforeId: string | null
  afterId: string | null
}

export type TaskDropTarget =
  | { kind: 'task'; task: Task; edge: DropEdge }
  | { kind: 'column'; columnId: string }

export function computeTaskPlacement(
  tasksFor: (columnId: string) => Task[],
  sourceTask: Task,
  target: TaskDropTarget,
): TaskPlacement | null {
  if (target.kind === 'task') {
    const overTask = target.task
    if (overTask.id === sourceTask.id) return null
    const columnId = overTask.column_id
    const ordered = tasksFor(columnId)
    const idx = ordered.findIndex((t) => t.id === overTask.id)
    if (target.edge === 'top') {
      return {
        columnId,
        beforeId: idx > 0 ? ordered[idx - 1].id : null,
        afterId: overTask.id,
      }
    }
    return {
      columnId,
      beforeId: overTask.id,
      afterId: idx + 1 < ordered.length ? ordered[idx + 1].id : null,
    }
  }

  const ordered = tasksFor(target.columnId).filter((t) => t.id !== sourceTask.id)
  return {
    columnId: target.columnId,
    beforeId: ordered.length ? ordered[ordered.length - 1].id : null,
    afterId: null,
  }
}

export const touchDrag = reactive({
  active: false,
  sourceTaskId: null as string | null,
  overTaskId: null as string | null,
  edge: null as DropEdge | null,
  overColumnId: null as string | null,
})

export function resetTouchDrag() {
  touchDrag.active = false
  touchDrag.sourceTaskId = null
  touchDrag.overTaskId = null
  touchDrag.edge = null
  touchDrag.overColumnId = null
}
