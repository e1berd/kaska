<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { isRunActive, useBoardStore, type AgentRun } from '@/stores/board'
import { useNow } from '@/composables/useNow'
import AgentRunStatusChip from '@/components/board/AgentRunStatusChip.vue'
import { RUN_STATUS, formatDuration, modelLine, runSeconds, startErrorText } from '@/utils/agents'

const props = defineProps<{
  taskId: string
  assigneeId: string | null
  canWrite: boolean
}>()

const board = useBoardStore()
const now = useNow()

const history = ref<AgentRun[]>([])
const busy = ref(false)
const actionError = ref<string | null>(null)

const agent = computed(() => {
  const user = board.userById(props.assigneeId)
  return user?.is_agent ? user : null
})
const latest = computed(() => board.latestRunFor(props.taskId))
const active = computed(() => (isRunActive(latest.value) ? latest.value : null))
const lastFinished = computed(() => (active.value ? null : latest.value))
const pastRuns = computed(() => history.value.filter((r) => r.id !== latest.value?.id).slice(0, 3))
const walltime = computed(() => board.agentWalltimeSeconds)

const elapsed = computed(() => {
  if (!active.value) return null
  return runSeconds(active.value, now.value)
})
const progress = computed(() => {
  if (elapsed.value === null || !walltime.value) return null
  return Math.min(100, (elapsed.value / walltime.value) * 100)
})

async function loadHistory() {
  try {
    history.value = await board.listTaskRuns(props.taskId)
  } catch (e: unknown) {
    console.error('task runs load failed', e)
    history.value = []
  }
}

watch(
  () => [props.taskId, latest.value?.id, latest.value?.status],
  () => {
    if (agent.value) void loadHistory()
  },
  { immediate: true },
)

async function start() {
  busy.value = true
  actionError.value = null
  try {
    await board.startAgentRun(props.taskId)
  } catch (e: unknown) {
    actionError.value = startErrorText(e)
  } finally {
    busy.value = false
  }
}

async function stop() {
  if (!active.value) return
  busy.value = true
  actionError.value = null
  try {
    await board.stopAgentRun(active.value.id)
  } catch (e: unknown) {
    console.error('agent run stop failed', e)
    actionError.value = 'Не удалось остановить прогон.'
  } finally {
    busy.value = false
  }
}

function durationOf(run: AgentRun) {
  const seconds = runSeconds(run, now.value)
  return seconds === null ? null : formatDuration(seconds)
}

function whenOf(run: AgentRun) {
  return new Date(run.inserted_at).toLocaleString('ru-RU', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
}
</script>

<template>
  <div v-if="agent" class="ks-task-agent">
    <div class="ks-task-agent__title md-label-large">Агент</div>

    <v-card variant="flat" rounded="lg" class="ks-task-agent__card">
      <div class="d-flex align-center gap-3">
        <v-avatar size="40" color="secondary">
          <v-img v-if="agent.avatar_url" :src="agent.avatar_url" cover alt="" />
          <span v-else class="text-on-secondary md-title-small">
            {{ (agent.display_name ?? 'A').slice(0, 1).toUpperCase() }}
          </span>
        </v-avatar>
        <div class="min-w-0">
          <div class="md-title-medium text-on-surface text-truncate">{{ agent.display_name }}</div>
          <div class="md-body-small text-on-surface-variant text-truncate">
            {{ modelLine(agent.agent?.provider_preset, agent.agent?.model) }}
          </div>
        </div>
      </div>

      <template v-if="active">
        <div class="d-flex align-center gap-2 flex-wrap">
          <AgentRunStatusChip :status="active.status" />
          <span v-if="elapsed !== null" class="md-body-small text-on-surface-variant">
            {{ formatDuration(elapsed) }}{{ walltime ? ` из ${formatDuration(walltime)}` : '' }}
          </span>
        </div>
        <v-progress-linear
          :model-value="progress ?? undefined"
          :indeterminate="progress === null"
          color="primary"
          bg-color="secondary-container"
          bg-opacity="1"
          rounded
          height="4"
        />
        <v-btn
          v-if="canWrite"
          variant="outlined"
          color="error"
          rounded="pill"
          prepend-icon="mdi-stop"
          :loading="busy"
          @click="stop"
        >
          {{ active.status === 'pending' ? 'Отменить' : 'Остановить' }}
        </v-btn>
      </template>

      <template v-else>
        <div v-if="lastFinished" class="d-flex align-center gap-2 flex-wrap">
          <AgentRunStatusChip :status="lastFinished.status" />
          <span class="md-body-small text-on-surface-variant">
            {{ durationOf(lastFinished) ?? '' }}
          </span>
        </div>
        <p v-else class="md-body-medium text-on-surface-variant ma-0">
          Агент поднимет контейнер, поработает над задачей и отпишется в комментариях.
        </p>

        <template v-if="canWrite">
          <v-btn
            v-if="agent.agent?.ready"
            :variant="lastFinished ? 'tonal' : 'flat'"
            :color="lastFinished ? 'secondary' : 'primary'"
            rounded="pill"
            :prepend-icon="lastFinished ? 'mdi-refresh' : 'mdi-play'"
            :loading="busy"
            @click="start"
          >
            {{ lastFinished ? 'Запустить снова' : 'Запустить агента' }}
          </v-btn>
          <span v-else class="md-body-small text-error">
            Агент не настроен — владелец должен указать модель и ключ на странице «Агенты».
          </span>
        </template>
        <span v-else class="md-body-small text-on-surface-variant d-flex align-center gap-2">
          <v-icon size="16">mdi-lock-outline</v-icon>
          Запускать и останавливать могут участники проекта
        </span>
      </template>

      <span v-if="actionError" class="md-body-small text-error">{{ actionError }}</span>
    </v-card>

    <div v-if="pastRuns.length" class="ks-task-agent__history">
      <div class="md-label-medium text-on-surface-variant mb-1">Прошлые прогоны</div>
      <div v-for="run in pastRuns" :key="run.id" class="ks-task-agent__run">
        <v-avatar :color="RUN_STATUS[run.status].color" size="32">
          <v-icon size="18">{{ RUN_STATUS[run.status].icon }}</v-icon>
        </v-avatar>
        <div class="min-w-0">
          <div class="md-body-medium">
            {{ RUN_STATUS[run.status].label }}{{ durationOf(run) ? ` · ${durationOf(run)}` : '' }}
          </div>
          <div class="md-body-small text-on-surface-variant">{{ whenOf(run) }}</div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.ks-task-agent {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.ks-task-agent__title {
  color: rgb(var(--v-theme-on-surface-variant));
}
.ks-task-agent__card {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px;
  background: rgb(var(--v-theme-surface-container-lowest));
  border: 1px solid rgb(var(--v-theme-outline-variant));
}
.ks-task-agent__run {
  display: flex;
  align-items: center;
  gap: 12px;
  min-height: 48px;
}
</style>
