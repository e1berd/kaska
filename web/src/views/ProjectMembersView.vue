<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useSysStore } from '@/stores/sys'
import { useBoardStore, type ProjectInvite, type ProjectMember } from '@/stores/board'
import { PhPlus, PhMagnifyingGlass, PhCopy, PhDotsThreeVertical, PhUserMinus } from '@phosphor-icons/vue'

defineProps<{ slug?: string }>()

const route = useRoute()
const router = useRouter()
const sys = useSysStore()
const board = useBoardStore()

const slug = computed(() => route.params.slug as string)
const loading = ref(true)
const error = ref<string | null>(null)
const search = ref('')

const members = ref<ProjectMember[]>([])
const invites = ref<ProjectInvite[]>([])

const isOwner = computed(() => board.isOwner)

const filteredMembers = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return members.value
  return members.value.filter(
    (m) =>
      (m.display_name ?? '').toLowerCase().includes(q) ||
      (m.email ?? '').toLowerCase().includes(q),
  )
})

const inviteDialog = ref(false)
const inviteTab = ref('email')
const inviteEmail = ref('')
const inviteExpiration = ref<number | null>(10080)
const generatedLink = ref('')
const inviteLoading = ref(false)
const inviteError = ref<string | null>(null)

const expirationOptions = [
  { title: '1 час', value: 60 },
  { title: '1 день', value: 1440 },
  { title: '1 неделя', value: 10080 },
  { title: 'Неограниченно', value: null },
]

function inviteLink(invite: ProjectInvite) {
  return `${window.location.origin}/invite/${invite.token}`
}

function memberLabel(m: ProjectMember) {
  return m.display_name || m.email || '—'
}

const isOnline = (m: ProjectMember) => sys.isUserOnline(m.user_id)
const lastOnlineAt = (m: ProjectMember) => sys.userLastOnlineAt(m.user_id)

async function reload() {
  members.value = await board.listMembers()
  if (isOwner.value) invites.value = await board.listInvites()
}

onMounted(async () => {
  try {
    void sys.initPresence()
    await board.joinBySlug(slug.value)
    await reload()
  } catch (err: unknown) {
    const reason = (err as { reason?: string })?.reason
    if (reason === 'not_found') {
      router.replace({ name: 'not-found' })
      return
    }
    error.value = 'Нет доступа к участникам проекта'
  } finally {
    loading.value = false
  }
})

function openInviteDialog() {
  inviteDialog.value = true
  inviteTab.value = 'email'
  inviteEmail.value = ''
  generatedLink.value = ''
  inviteError.value = null
}

async function submitInvite() {
  inviteError.value = null
  inviteLoading.value = true
  try {
    if (inviteTab.value === 'email') {
      await board.inviteMember({ email: inviteEmail.value })
      inviteDialog.value = false
    } else {
      const invite = await board.inviteMember({ expires_in_minutes: inviteExpiration.value })
      generatedLink.value = invite.url ?? inviteLink(invite)
    }
    invites.value = await board.listInvites()
  } catch (e: unknown) {
    inviteError.value = (e as { message?: string })?.message || 'Не удалось создать приглашение'
  } finally {
    inviteLoading.value = false
  }
}

function copy(text: string) {
  if (navigator?.clipboard) void navigator.clipboard.writeText(text)
}

async function revoke(invite: ProjectInvite) {
  await board.revokeInvite(invite.id)
  invites.value = invites.value.filter((i) => i.id !== invite.id)
}

async function remove(member: ProjectMember) {
  if (!confirm('Убрать участника из проекта?')) return
  await board.removeMember(member.user_id)
  members.value = members.value.filter((m) => m.user_id !== member.user_id)
}
</script>

<template>
  <div class="pa-4 pa-sm-6 pa-md-8 mx-auto" style="max-width: 1200px">
    <div class="d-flex align-center justify-space-between mb-6">
      <h1 class="md-headline-medium">Участники проекта</h1>
      <v-btn v-if="isOwner" color="primary" @click="openInviteDialog">
        <template #prepend><ph-plus :size="20" weight="bold" /></template>
        Пригласить
      </v-btn>
    </div>

    <v-alert v-if="error" type="error" variant="tonal" class="mb-4">{{ error }}</v-alert>

    <v-card variant="outlined" class="mb-4">
      <v-card-text>
        <v-text-field
          v-model="search"
          label="Поиск участников"
          variant="filled"
          density="comfortable"
          hide-details
          class="mb-4"
        >
          <template #prepend-inner><ph-magnifying-glass :size="20" weight="bold" /></template>
        </v-text-field>

        <v-data-table
          :headers="[
            { title: 'Имя / Email', value: 'name', sortable: false },
            { title: 'Роль', value: 'role', sortable: false },
            { title: 'Статус', value: 'status', sortable: false },
            { title: 'Действия', value: 'actions', sortable: false, align: 'end' },
          ]"
          :items="filteredMembers"
          :loading="loading"
          item-value="user_id"
        >
          <template #item.name="{ item }">
            <div class="d-flex align-center">
              <v-avatar size="32" class="mr-3" color="primary">
                <img v-if="item.avatar_url" width="32" height="32" :src="item.avatar_url" />
                <span v-else class="text-white">{{ memberLabel(item).slice(0, 1).toUpperCase() }}</span>
              </v-avatar>
              <div>
                <div class="font-weight-medium">{{ item.display_name || '—' }}</div>
                <div class="text-caption text-medium-emphasis">{{ item.email }}</div>
              </div>
            </div>
          </template>
          <template #item.role="{ item }">
            <v-chip size="small" :color="item.role === 'owner' ? 'primary' : 'default'">
              {{ item.role === 'owner' ? 'Владелец' : 'Участник' }}
            </v-chip>
          </template>
          <template #item.status="{ item }">
            <div class="d-flex align-center">
              <v-badge dot :color="isOnline(item) ? 'success' : 'grey'" class="mr-2" inline></v-badge>
              <span class="text-caption text-medium-emphasis">
                <template v-if="isOnline(item)">Онлайн</template>
                <template v-else-if="lastOnlineAt(item)">
                  Был(а) в сети: {{ lastOnlineAt(item)?.toLocaleString() }}
                </template>
                <template v-else>Оффлайн</template>
              </span>
            </div>
          </template>
          <template #item.actions="{ item }">
            <v-menu v-if="isOwner && item.role !== 'owner'">
              <template #activator="{ props }">
                <v-btn v-bind="props" variant="text" size="small" :icon="true">
                  <ph-dots-three-vertical :size="20" weight="bold" />
                </v-btn>
              </template>
              <v-list class="bg-surface elevation-3" :elevation="0" rounded="lg" density="compact">
                <v-list-item @click="remove(item)" class="md-state-layer text-error" base-color="error">
                  <template #prepend>
                    <ph-user-minus :size="20" class="mr-3" weight="regular" />
                  </template>
                  <v-list-item-title>Убрать из проекта</v-list-item-title>
                </v-list-item>
              </v-list>
            </v-menu>
          </template>
        </v-data-table>
      </v-card-text>
    </v-card>

    <template v-if="isOwner && invites.length">
      <h2 class="md-title-medium mb-2">Приглашения</h2>
      <v-card variant="outlined">
        <v-list class="bg-transparent">
          <v-list-item v-for="i in invites" :key="i.id" class="py-2">
            <v-list-item-title class="md-body-medium">
              {{ i.email || 'Ссылка-приглашение' }}
            </v-list-item-title>
            <v-list-item-subtitle>
              {{ i.expires_at ? `до ${new Date(i.expires_at).toLocaleString()}` : 'без срока' }}
            </v-list-item-subtitle>
            <template #append>
              <v-btn variant="text" size="small" :icon="true" title="Копировать ссылку" @click="copy(inviteLink(i))">
                <ph-copy :size="18" weight="regular" />
              </v-btn>
              <v-btn variant="text" size="small" :icon="true" color="error" title="Отозвать" @click="revoke(i)">
                <ph-user-minus :size="18" weight="regular" />
              </v-btn>
            </template>
          </v-list-item>
        </v-list>
      </v-card>
    </template>

    <v-dialog v-model="inviteDialog" max-width="500">
      <v-card>
        <v-card-title>Пригласить в проект</v-card-title>
        <v-tabs v-model="inviteTab" color="primary">
          <v-tab value="email">Email</v-tab>
          <v-tab value="link">Ссылка</v-tab>
        </v-tabs>
        <v-card-text class="pt-4">
          <v-window v-model="inviteTab">
            <v-window-item value="email">
              <p class="text-body-2 text-medium-emphasis mb-4">
                Письмо со ссылкой-приглашением придёт на указанный адрес.
              </p>
              <v-text-field v-model="inviteEmail" label="Email" type="email" variant="filled" density="comfortable" />
            </v-window-item>
            <v-window-item value="link">
              <p class="text-body-2 text-medium-emphasis mb-4">
                Сгенерируйте ссылку и отправьте её самостоятельно.
              </p>
              <v-select
                v-model="inviteExpiration"
                :items="expirationOptions"
                label="Срок действия"
                variant="filled"
                density="comfortable"
              />
              <v-text-field
                v-if="generatedLink"
                :model-value="generatedLink"
                readonly
                variant="filled"
                density="comfortable"
                class="mt-2"
              >
                <template #append-inner>
                  <v-btn variant="text" size="small" :icon="true" @click="copy(generatedLink)">
                    <ph-copy :size="18" weight="bold" />
                  </v-btn>
                </template>
              </v-text-field>
            </v-window-item>
          </v-window>
          <v-alert v-if="inviteError" type="error" variant="tonal" class="mt-4">{{ inviteError }}</v-alert>
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="inviteDialog = false">Закрыть</v-btn>
          <v-btn
            color="primary"
            :loading="inviteLoading"
            :disabled="inviteTab === 'email' && !inviteEmail"
            @click="submitInvite"
          >
            {{ inviteTab === 'email' ? 'Отправить' : 'Сгенерировать' }}
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>
