import { onBeforeUnmount, onMounted, type Ref } from 'vue'
import { monitorForElements } from '@atlaskit/pragmatic-drag-and-drop/element/adapter'
import { autoScrollForElements } from '@atlaskit/pragmatic-drag-and-drop-auto-scroll/element'
import { extractClosestEdge } from '@atlaskit/pragmatic-drag-and-drop-hitbox/closest-edge'
import { computeTaskPlacement, type TaskDropTarget } from '@/utils/boardDnd'
import { useBoardStore, type Column, type Task } from '@/stores/board'

export function useBoardDnd(colsScroll: Ref<HTMLElement | null>) {
  const board = useBoardStore()
  let monitorCleanup: (() => void) | null = null
  let columnsMonitorCleanup: (() => void) | null = null
  let scrollCleanup: (() => void) | null = null

  onMounted(() => {
    if (colsScroll.value) {
      scrollCleanup = autoScrollForElements({
        element: colsScroll.value,
        canScroll: ({ source }) => source.data.type === 'task',
      })
    }

    monitorCleanup = monitorForElements({
      canMonitor: ({ source }) => source.data.type === 'task',
      onDrop: ({ source, location }) => {
        const target = location.current.dropTargets[0]
        if (!target) return

        const sourceTask = source.data.task as Task
        const dropTarget: TaskDropTarget =
          target.data.type === 'task'
            ? {
                kind: 'task',
                task: target.data.task as Task,
                edge: extractClosestEdge(target.data) === 'top' ? 'top' : 'bottom',
              }
            : { kind: 'column', columnId: target.data.columnId as string }

        const placement = computeTaskPlacement(board.tasksFor, sourceTask, dropTarget)
        if (!placement) return

        board
          .moveTask(sourceTask.id, placement.columnId, placement.beforeId, placement.afterId)
          .catch((e) => {
            console.warn('[board] move failed', e)
          })
      },
    })

    columnsMonitorCleanup = monitorForElements({
      canMonitor: ({ source }) => source.data.type === 'column',
      onDrop: ({ source, location }) => {
        const target = location.current.dropTargets[0]
        if (!target || target.data.type !== 'column') return

        const sourceColumn = source.data.column as Column
        const overColumn = target.data.column as Column
        if (sourceColumn.id === overColumn.id) return

        const edge = extractClosestEdge(target.data)
        const ordered = board.orderedColumns.filter((c) => c.id !== sourceColumn.id)
        const idx = ordered.findIndex((c) => c.id === overColumn.id)
        if (idx < 0) return

        let beforeId: string | null = null
        let afterId: string | null = null

        if (edge === 'left') {
          beforeId = idx > 0 ? ordered[idx - 1].id : null
          afterId = overColumn.id
        } else {
          beforeId = overColumn.id
          afterId = idx + 1 < ordered.length ? ordered[idx + 1].id : null
        }

        board.moveColumn(sourceColumn.id, beforeId, afterId).catch((e) => {
          console.warn('[board] move column failed', e)
        })
      },
    })
  })

  onBeforeUnmount(() => {
    monitorCleanup?.()
    columnsMonitorCleanup?.()
    scrollCleanup?.()
  })
}
