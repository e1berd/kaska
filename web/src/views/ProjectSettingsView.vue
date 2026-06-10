<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useBoardStore } from '@/stores/board'
import { useProjectsStore } from '@/stores/projects'
import { PhUploadSimple, PhTrash } from '@phosphor-icons/vue'

defineProps<{ slug?: string }>()

const route = useRoute()
const router = useRouter()
const board = useBoardStore()
const projects = useProjectsStore()

const slug = computed(() => route.params.slug as string)
const loading = ref(true)
const error = ref<string | null>(null)
const saving = ref(false)

const name = ref('')
const description = ref('')
const avatarUploading = ref(false)
const backgroundUploading = ref(false)
const deleteConfirm = ref(false)
const deleting = ref(false)
const avatarInput = ref<HTMLInputElement | null>(null)
const backgroundInput = ref<HTMLInputElement | null>(null)

const project = computed(() => board.project)
const projectId = computed(() => board.project?.id ?? null)
const publicLink = ref(false)

const publicUrl = computed(() => `${window.location.origin}/p/${slug.value}`)

watch(project, (p) => {
  if (p) publicLink.value = p.public_link
})

onMounted(async () => {
  try {
    await projects.joinLobby()
    await board.joinBySlug(slug.value)
    if (!board.isOwner) {
      router.replace({ name: 'board', params: { slug: slug.value } })
      return
    }
    name.value = board.project?.name ?? ''
    description.value = board.project?.description ?? ''
    publicLink.value = board.project?.public_link ?? false
  } catch (err: unknown) {
    const reason = (err as { reason?: string })?.reason
    if (reason === 'not_found') {
      router.replace({ name: 'not-found' })
      return
    }
    error.value = 'Нет доступа к настройкам проекта'
  } finally {
    loading.value = false
  }
})

async function save() {
  if (!projectId.value) return
  saving.value = true
  error.value = null
  try {
    await projects.updateProject({
      id: projectId.value,
      name: name.value.trim(),
      description: description.value.trim(),
    })
  } catch (e: unknown) {
    error.value = (e as { message?: string })?.message ?? 'Не удалось сохранить'
  } finally {
    saving.value = false
  }
}

async function togglePublicLink(value: boolean | null) {
  publicLink.value = !!value
  try {
    await board.setPublicLink(!!value)
  } catch (e: unknown) {
    publicLink.value = !value
    error.value = (e as { message?: string })?.message ?? 'Не удалось изменить доступ'
  }
}

function pickMedia(kind: 'avatar' | 'background') {
  ;(kind === 'avatar' ? avatarInput.value : backgroundInput.value)?.click()
}

async function onMediaPicked(kind: 'avatar' | 'background', e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (!file || !projectId.value) return
  const flag = kind === 'avatar' ? avatarUploading : backgroundUploading
  flag.value = true
  error.value = null
  try {
    await projects.uploadProjectMedia(kind, projectId.value, file)
  } catch (err: unknown) {
    error.value = (err as { message?: string })?.message ?? 'Не удалось загрузить файл'
  } finally {
    flag.value = false
  }
}

async function clearMedia(kind: 'avatar' | 'background') {
  if (!projectId.value) return
  const flag = kind === 'avatar' ? avatarUploading : backgroundUploading
  flag.value = true
  try {
    await projects.clearProjectMedia(kind, projectId.value)
  } catch (err: unknown) {
    error.value = (err as { message?: string })?.message ?? 'Не удалось убрать файл'
  } finally {
    flag.value = false
  }
}

async function confirmDelete() {
  if (!projectId.value) return
  deleting.value = true
  try {
    await projects.deleteProject(projectId.value)
    await router.replace({ name: 'projects' })
  } catch (err: unknown) {
    error.value = (err as { message?: string })?.message ?? 'Не удалось удалить проект'
    deleting.value = false
    deleteConfirm.value = false
  }
}

function copyPublicUrl() {
  if (navigator?.clipboard) void navigator.clipboard.writeText(publicUrl.value)
}
</script>

<template>
  <div class="pa-4 pa-sm-6 pa-md-8 mx-auto" style="max-width: 720px">
    <h1 class="md-headline-medium mb-6">Настройки проекта</h1>

    <v-alert v-if="error" type="error" variant="tonal" class="mb-4">{{ error }}</v-alert>
    <v-progress-linear v-if="loading" indeterminate color="primary" class="mb-4" />

    <v-card variant="outlined" rounded="lg" class="mb-6">
      <v-card-text>
        <div class="d-flex align-center mb-4" style="gap: 16px">
          <v-avatar size="64" color="primary-container">
            <v-img v-if="project?.avatar_url" :src="project.avatar_url" cover alt="" />
            <span v-else class="md-headline-small">{{ (name || '?').slice(0, 1).toUpperCase() }}</span>
          </v-avatar>
          <div class="d-flex" style="gap: 8px">
            <v-btn variant="tonal" size="small" :loading="avatarUploading" @click="pickMedia('avatar')">
              <template #prepend><ph-upload-simple :size="18" weight="bold" /></template>
              Аватар
            </v-btn>
            <v-btn
              v-if="project?.avatar_url"
              variant="text"
              size="small"
              color="error"
              @click="clearMedia('avatar')"
            >
              Убрать
            </v-btn>
          </div>
        </div>

        <v-text-field v-model="name" label="Название" variant="filled" density="comfortable" class="mb-2" />
        <v-textarea v-model="description" label="Описание" variant="filled" density="comfortable" rows="3" auto-grow />

        <div class="d-flex mt-2" style="gap: 8px">
          <v-btn variant="tonal" size="small" :loading="backgroundUploading" @click="pickMedia('background')">
            <template #prepend><ph-upload-simple :size="18" weight="bold" /></template>
            Фон
          </v-btn>
          <v-btn
            v-if="project?.background_url"
            variant="text"
            size="small"
            color="error"
            @click="clearMedia('background')"
          >
            Убрать фон
          </v-btn>
          <v-spacer />
          <v-btn color="primary" rounded="pill" :loading="saving" @click="save">Сохранить</v-btn>
        </div>

        <input ref="avatarInput" type="file" accept="image/*" hidden @change="onMediaPicked('avatar', $event)" />
        <input ref="backgroundInput" type="file" accept="image/*" hidden @change="onMediaPicked('background', $event)" />
      </v-card-text>
    </v-card>

    <v-card variant="outlined" rounded="lg" class="mb-6">
      <v-card-text>
        <v-switch
          :model-value="publicLink"
          color="primary"
          hide-details
          label="Доска доступна по ссылке"
          @update:model-value="togglePublicLink"
        />
        <p class="md-body-small text-medium-emphasis mt-1 mb-0">
          Когда включено, любой с прямой ссылкой может просматривать доску (только чтение).
        </p>
        <v-text-field
          v-if="publicLink"
          :model-value="publicUrl"
          readonly
          variant="filled"
          density="compact"
          class="mt-3"
          hide-details
        >
          <template #append-inner>
            <v-btn variant="text" size="small" @click="copyPublicUrl">Копировать</v-btn>
          </template>
        </v-text-field>
      </v-card-text>
    </v-card>

    <v-card variant="outlined" rounded="lg" color="error" class="border-error">
      <v-card-text class="d-flex align-center justify-space-between">
        <div>
          <div class="md-title-small">Удалить проект</div>
          <div class="md-body-small text-medium-emphasis">Действие необратимо.</div>
        </div>
        <v-btn color="error" variant="flat" @click="deleteConfirm = true">
          <template #prepend><ph-trash :size="18" weight="regular" /></template>
          Удалить
        </v-btn>
      </v-card-text>
    </v-card>

    <v-dialog v-model="deleteConfirm" max-width="420">
      <v-card rounded="lg">
        <v-card-title>Удалить проект?</v-card-title>
        <v-card-text>Проект «{{ project?.name }}» и все его задачи будут удалены безвозвратно.</v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="deleteConfirm = false">Отмена</v-btn>
          <v-btn color="error" variant="flat" :loading="deleting" @click="confirmDelete">Удалить</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>
