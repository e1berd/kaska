<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue'
import { useDisplay } from 'vuetify'
import { isRunActive, useBoardStore } from '@/stores/board'
import { useAgentRunLog } from '@/composables/useAgentRunLog'
import { useNow } from '@/composables/useNow'
import AgentRunStatusChip from '@/components/board/AgentRunStatusChip.vue'
import { RUN_STATUS, formatDuration, modelLine, runSeconds } from '@/utils/agents'

const props = defineProps<{ taskId: string }>()

const board = useBoardStore()
const now = useNow()
const { smAndDown } = useDisplay()
const stopping = ref(false)

const latest = computed(() => board.latestRunFor(props.taskId))
const runId = computed(() => latest.value?.id ?? null)
const { log, run, error } = useAgentRunLog(runId)

const console_ = ref<HTMLElement | null>(null)
const followTail = ref(true)

const current = computed(() => latest.value ?? run.value)
const agent = computed(() => board.userById(current.value?.agent_id))
const requester = computed(() => board.userById(current.value?.requested_by_id))
const statusLabel = computed(() => {
  if (!current.value) return null
  const seconds = runSeconds(current.value, now.value)
  const label = RUN_STATUS[current.value.status].label
  return seconds === null ? label : `${label} · ${formatDuration(seconds)}`
})
const caption = computed(() =>
  [
    agent.value?.display_name,
    agent.value?.agent ? modelLine(agent.value.agent.provider_preset, agent.value.agent.model) : null,
    requester.value ? `запустил ${requester.value.display_name || requester.value.email}` : null,
  ]
    .filter(Boolean)
    .join(' · '),
)

watch(log, async () => {
  if (!followTail.value) return
  await nextTick()
  if (console_.value) console_.value.scrollTop = console_.value.scrollHeight
})

function onScroll() {
  const el = console_.value
  if (!el) return
  followTail.value = el.scrollHeight - el.scrollTop - el.clientHeight < 24
}

async function stopRun() {
  if (!current.value) return
  stopping.value = true
  try {
    await board.stopAgentRun(current.value.id)
  } catch (e: unknown) {
    console.error('agent run stop failed', e)
  } finally {
    stopping.value = false
  }
}

function downloadLog() {
  if (!current.value) return
  const blob = new Blob([log.value], { type: 'text/plain;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `agent-run-${current.value.id.slice(0, 8)}.log`
  link.click()
  URL.revokeObjectURL(url)
}
</script>

<template>
  <section v-if="current" class="ks-run-log">
    <header class="ks-run-log__head">
      <v-icon size="20" class="text-on-surface-variant">mdi-console</v-icon>
      <span class="md-title-medium">Прогон агента</span>
      <AgentRunStatusChip :status="current.status" :label="statusLabel ?? undefined" />
      <v-spacer />
      <v-btn
        v-if="smAndDown && board.canWrite && isRunActive(current)"
        icon="mdi-stop"
        variant="outlined"
        color="error"
        size="small"
        aria-label="Остановить агента"
        :loading="stopping"
        @click="stopRun"
      />
      <v-btn
        variant="text"
        rounded="pill"
        size="small"
        prepend-icon="mdi-download"
        :disabled="!log"
        @click="downloadLog"
      >
        Скачать лог
      </v-btn>
    </header>

    <div ref="console_" class="ks-run-log__console md-body-small" @scroll="onScroll">
      <template v-if="log">{{ log }}</template>
      <span v-else-if="error" class="text-error">{{ error }}</span>
      <span v-else class="text-on-surface-variant">
        {{ current.status === 'pending' ? 'Готовим контейнер…' : 'Лог пуст.' }}
      </span>
      <span v-if="current.status === 'running'" class="ks-run-log__cursor" />
    </div>

    <div v-if="caption" class="md-body-small text-on-surface-variant">{{ caption }}</div>
  </section>
</template>

<style scoped>
.ks-run-log {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px;
  border-radius: var(--md-shape-l);
  background: rgb(var(--v-theme-surface-container-low));
}
.ks-run-log__head {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}
.ks-run-log__console {
  height: 260px;
  overflow-y: auto;
  padding: 12px 16px;
  border-radius: var(--md-shape-m);
  background: rgb(var(--v-theme-surface-container-highest));
  color: rgb(var(--v-theme-on-surface));
  font-family: 'Roboto Mono', ui-monospace, SFMono-Regular, Menlo, monospace;
  line-height: 18px;
  white-space: pre-wrap;
  word-break: break-word;
}
.ks-run-log__cursor {
  display: inline-block;
  width: 7px;
  height: 14px;
  margin-left: 2px;
  vertical-align: -2px;
  background: rgb(var(--v-theme-primary));
  animation: ks-run-cursor var(--md-duration-extra-long4) steps(1) infinite;
}

@keyframes ks-run-cursor {
  50% {
    opacity: 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .ks-run-log__cursor {
    animation: none;
  }
}
</style>
