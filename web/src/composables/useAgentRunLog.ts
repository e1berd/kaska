import { onScopeDispose, ref, watch, type Ref } from 'vue'
import type { Channel } from 'phoenix'
import { useSocketStore } from '@/stores/socket'
import type { AgentRun } from '@/stores/board'

const MAX_LOG_CHARS = 200_000

interface JoinReply {
  run: AgentRun
  log_tail: string
}

export function useAgentRunLog(runId: Ref<string | null>) {
  const sock = useSocketStore()
  const log = ref('')
  const run = ref<AgentRun | null>(null)
  const error = ref<string | null>(null)
  let topic: string | null = null
  let channel: Channel | null = null

  function append(chunk: string) {
    const next = log.value + chunk
    log.value = next.length > MAX_LOG_CHARS ? next.slice(next.length - MAX_LOG_CHARS) : next
  }

  function leave() {
    if (topic) sock.leaveChannel(topic)
    topic = null
    channel = null
  }

  async function follow(id: string | null) {
    leave()
    log.value = ''
    run.value = null
    error.value = null
    if (!id) return

    const nextTopic = `agent_run:${id}`
    topic = nextTopic
    try {
      const { channel: ch, reply } = await sock.joinChannel<JoinReply>(nextTopic)
      if (topic !== nextTopic) return
      channel = ch
      if (reply.run) {
        run.value = reply.run
        log.value = reply.log_tail ?? ''
      }
      channel.on('log', ({ chunk }: { chunk: string }) => append(chunk))
      channel.on('run', (updated: AgentRun) => {
        run.value = updated
      })
    } catch (e: unknown) {
      console.error('agent run log join failed', e)
      if (topic === nextTopic) error.value = 'Лог прогона недоступен'
    }
  }

  watch(runId, (id) => void follow(id), { immediate: true })
  onScopeDispose(leave)

  return { log, run, error }
}
