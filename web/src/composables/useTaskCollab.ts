import { onBeforeUnmount, shallowRef } from 'vue'
import * as Y from 'yjs'
import { Awareness } from 'y-protocols/awareness'
import { Presence } from 'phoenix'
import { useBoardStore, type TiptapDoc } from '@/stores/board'
import { useSocketStore, pushAsync } from '@/stores/socket'
import { base64ToUint8 } from '@/utils/collab'
import { PhoenixYProvider } from '@/utils/PhoenixYProvider'
import type { Ref } from 'vue'

type PresenceState = Record<string, { metas: Array<Record<string, unknown>> }>

export function useTaskCollab(opts: {
  taskTargetId: Ref<string | null>
  richEditorRef: Ref<{ getJSON: () => TiptapDoc; focus: () => boolean } | null>
  onLocalSettle?: () => void
}) {
  const board = useBoardStore()
  const socket = useSocketStore()

  const taskYDoc = shallowRef<Y.Doc | null>(null)
  const taskAwareness = shallowRef<Awareness | null>(null)
  let taskProvider: PhoenixYProvider | null = null
  let taskDocTopic: string | null = null
  const taskDocPresences = shallowRef<PresenceState>({})

  function tearDownCollab() {
    taskProvider?.destroy()
    taskProvider = null
    taskAwareness.value?.destroy()
    taskAwareness.value = null
    taskYDoc.value?.destroy()
    taskYDoc.value = null
    if (taskDocTopic) {
      socket.leaveChannel(taskDocTopic)
      taskDocTopic = null
    }
    taskDocPresences.value = {}
  }

  async function setupCollab(taskId: string) {
    tearDownCollab()
    const topic = `task_doc:${taskId}`
    try {
      const { channel, reply } = await socket.joinChannel<{ state?: string }>(topic)
      if (opts.taskTargetId.value !== taskId) {
        socket.leaveChannel(topic)
        return
      }
      const doc = new Y.Doc()
      if (reply.state) {
        const bytes = base64ToUint8(reply.state)
        if (bytes.byteLength > 0) Y.applyUpdate(doc, bytes)
      }
      const aw = new Awareness(doc)
      const provider = new PhoenixYProvider(channel, doc, aw, {
        onLocalSettle: () => {
          if (!board.canWrite) return
          const docJson = opts.richEditorRef.value?.getJSON()
          if (!docJson) return
          opts.onLocalSettle?.()
          pushAsync(channel, 'materialize_body_doc', { doc: docJson })
            .catch((e) => console.warn('[board] materialize failed', e))
        },
      })

      channel.on('presence_state', (state: PresenceState) => {
        taskDocPresences.value = Presence.syncState({}, state) as PresenceState
      })
      channel.on(
        'presence_diff',
        (diff: { joins: PresenceState; leaves: PresenceState }) => {
          Presence.syncDiff(taskDocPresences.value, diff)
          taskDocPresences.value = { ...taskDocPresences.value }
        },
      )

      taskYDoc.value = doc
      taskAwareness.value = aw
      taskProvider = provider
      taskDocTopic = topic
    } catch (e) {
      console.warn('[board] task_doc join failed', e)
    }
  }

  function onDescriptionBlur() {
    taskProvider?.flush()
  }

  onBeforeUnmount(() => {
    tearDownCollab()
  })

  return {
    taskYDoc,
    taskAwareness,
    taskDocPresences,
    setupCollab,
    tearDownCollab,
    onDescriptionBlur,
  }
}
