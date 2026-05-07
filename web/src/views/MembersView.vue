<script setup lang="ts">
import { computed, ref, onBeforeUnmount, onMounted } from 'vue'
import { useSysStore } from '../stores/sys'
import { useAuthStore } from '../stores/auth'
import type { User } from '../stores/auth'
import { useSocketStore } from '../stores/socket'
import type { Channel } from 'phoenix'
import { PhPlus, PhMagnifyingGlass, PhDotsThreeVertical, PhCopy, PhCheckCircle, PhProhibit } from '@phosphor-icons/vue'

const sys = useSysStore()
const auth = useAuthStore()
const socket = useSocketStore()

const loading = ref(false)
const users = ref<User[]>([])
const search = ref('')
const canManageMembers = computed(() => auth.user?.role === 'admin' || auth.user?.role === 'superadmin')

const isInviteModalOpen = ref(false)
const inviteTab = ref('email')
const inviteEmail = ref('')
const inviteLink = ref('')
const inviteExpiration = ref<number | null>(60)
const inviteLoading = ref(false)
const inviteError = ref<string | null>(null)
const usersChannel = ref<Channel | null>(null)
const userCreatedRef = ref<number | null>(null)

const expirationOptions = [
  { title: '5 минут', value: 5 },
  { title: '30 минут', value: 30 },
  { title: '1 час', value: 60 },
  { title: '1 неделя', value: 10080 },
  { title: 'Неограниченно', value: null },
]

async function loadUsers() {
  loading.value = true
  try {
    const res = await sys.getUsers(search.value)
    users.value = res
  } catch (e) {
    console.error("Failed to get users", e)
  } finally {
    loading.value = false
  }
}

async function sendInvite() {
  inviteError.value = null
  inviteLoading.value = true
  inviteLink.value = ''
  try {
    if (inviteTab.value === 'email') {
      await sys.createInvite({ email: inviteEmail.value })
      isInviteModalOpen.value = false
      inviteEmail.value = ''
    } else {
      const res = await sys.createInvite({ expires_in_minutes: inviteExpiration.value })
      inviteLink.value = `${window.location.origin}/register?token=${res.token}`
    }
  } catch (e: any) {
    inviteError.value = e?.reason === 'forbidden'
      ? 'Недостаточно прав для создания приглашений'
      : (e?.message || 'Failed to create invite')
  } finally {
    inviteLoading.value = false
  }
}

function openInviteModal() {
  isInviteModalOpen.value = true
  inviteError.value = null
  inviteLink.value = ''
  inviteEmail.value = ''
}

onMounted(() => {
  void sys.initPresence()
  loadUsers()
  void subscribeUsersRealtime()
})

onBeforeUnmount(() => {
  if (usersChannel.value && userCreatedRef.value !== null) {
    usersChannel.value.off('user_created', userCreatedRef.value)
  }
  usersChannel.value = null
  userCreatedRef.value = null
})

async function subscribeUsersRealtime() {
  const { channel } = await socket.joinChannel('sys:lobby')
  usersChannel.value = channel
  userCreatedRef.value = channel.on('user_created', () => {
    void loadUsers()
  })
}

const onSearchInput = () => {
  loadUsers()
}

const copyInviteLink = () => {
  if (navigator && navigator.clipboard) {
    navigator.clipboard.writeText(inviteLink.value)
  }
}

const changeRole = async (user: User) => {
  if (user.role === 'superadmin') return
  const newRole = user.role === 'admin' ? 'user' : 'admin'
  try {
    await sys.changeUserRole(user.id, newRole)
    await loadUsers()
  } catch (e) {
    console.error("Failed to change user role", e)
  }
}

const confirmUser = async (user: User) => {
  try {
    await sys.confirmUser(user.id)
    await loadUsers()
  } catch (e) {
    console.error("Failed to confirm user", e)
  }
}

const deleteUser = async (user: User) => {
  if (!confirm('Вы уверены, что хотите удалить пользователя?')) return
  try {
    await sys.deleteUser(user.id)
    await loadUsers()
  } catch (e) {
    console.error("Failed to delete user", e)
  }
}

const isUserOnline = (user: User) => sys.isUserOnline(user.id)
const userLastOnlineAt = (user: User) => sys.userLastOnlineAt(user.id)
</script>

<template>
  <div class="pa-4 pa-sm-6 pa-md-8 mx-auto" style="max-width: 1200px;">
    <div class="d-flex align-center justify-space-between mb-6">
      <h1 class="md-headline-medium">Участники</h1>
      <v-btn v-if="canManageMembers" color="primary" @click="openInviteModal">
        <template #prepend><ph-plus :size="20" weight="bold" /></template>
        Добавить
      </v-btn>
    </div>

    <v-card variant="outlined" class="mb-4">
      <v-card-text>
        <v-text-field
          v-model="search"
          label="Поиск пользователей"
          variant="filled"
          density="comfortable"
          hide-details
          class="mb-4"
          @input="onSearchInput"
        >
          <template #prepend-inner><ph-magnifying-glass :size="20" weight="bold" /></template>
        </v-text-field>

        <v-data-table
          :headers="[
            { title: 'Имя / Email', value: 'name', sortable: false },
            { title: 'Роль', value: 'role', sortable: false },
            { title: 'Статус', value: 'status', sortable: false },
            { title: 'Действия', value: 'actions', sortable: false, align: 'end' }
          ]"
          :items="users"
          :loading="loading"
          item-value="id"
        >
          <template #item.name="{ item }">
             <div class="d-flex align-center">
              <v-avatar size="32" class="mr-3" color="primary">
                 <img
                  v-if="item.avatar_url"
                  width="32"
                  height="32"
                  :src="item.avatar_url"
                 />
                 <span v-else class="text-white">{{ (item.display_name || item.email || '?').slice(0, 1).toUpperCase() }}</span>
              </v-avatar>
              <div>
                <div class="font-weight-medium">{{ item.display_name || '—' }}</div>
                <div class="text-caption text-medium-emphasis">{{ item.email }}</div>
              </div>
            </div>
          </template>
          <template #item.role="{ item }">
            <v-chip size="small" :color="item.role === 'superadmin' ? 'primary' : item.role === 'admin' ? 'secondary' : 'default'">
               {{ item.role === 'superadmin' ? 'Суперадмин' : item.role === 'admin' ? 'Администратор' : 'Пользователь' }}
            </v-chip>
          </template>
          <template #item.status="{ item }">
            <div class="d-flex align-center">
              <v-badge
                dot
                :color="isUserOnline(item) ? 'success' : 'grey'"
                class="mr-2"
                inline
              ></v-badge>
              <span class="text-caption text-medium-emphasis">
                <template v-if="isUserOnline(item)">
                  Онлайн
                </template>
                <template v-else-if="userLastOnlineAt(item)">
                  Был(а) в сети: {{ userLastOnlineAt(item)?.toLocaleString() }}
                </template>
                <template v-else>
                  Оффлайн
                </template>
              </span>
            </div>
          </template>
          <template #item.actions="{ item }">
            <v-menu v-if="canManageMembers && item.id !== auth.user?.id && item.role !== 'superadmin'">
              <template #activator="{ props }">
                <v-btn v-bind="props" variant="text" size="small" :icon="true">
                  <ph-dots-three-vertical :size="20" weight="bold" />
                </v-btn>
              </template>
              <v-list class="bg-surface elevation-3" :elevation="0" rounded="lg" density="compact">
                <v-list-item
                  @click="changeRole(item)"
                  class="md-state-layer"
                  base-color="on-surface"
                >
                  <v-list-item-title>Сделать {{ item.role === 'admin' ? 'пользователем' : 'администратором' }}</v-list-item-title>
                </v-list-item>
                <v-list-item
                  v-if="!item.confirmed_at"
                  @click="confirmUser(item)"
                  class="md-state-layer text-success"
                  base-color="success"
                >
                  <template #prepend>
                    <ph-check-circle :size="20" class="mr-3" weight="regular" />
                  </template>
                  <v-list-item-title>Подтвердить почту</v-list-item-title>
                </v-list-item>
                <v-divider class="my-1"></v-divider>
                <v-list-item
                  @click="deleteUser(item)"
                  class="md-state-layer text-error"
                  base-color="error"
                >
                  <template #prepend>
                    <ph-prohibit :size="20" class="mr-3" weight="regular" />
                  </template>
                  <v-list-item-title>Забанить</v-list-item-title>
                </v-list-item>
              </v-list>
            </v-menu>
          </template>
        </v-data-table>
      </v-card-text>
    </v-card>

    <v-dialog v-model="isInviteModalOpen" max-width="500">
      <v-card>
        <v-card-title>Добавить участника</v-card-title>

        <v-tabs v-model="inviteTab" color="primary">
          <v-tab value="email">Email</v-tab>
          <v-tab value="link">Ссылка</v-tab>
        </v-tabs>

        <v-card-text class="pt-4">
          <v-window v-model="inviteTab">
            <v-window-item value="email">
              <p class="text-body-2 text-medium-emphasis mb-4">
                Отправьте приглашение на email. Пользователь получит письмо со ссылкой для регистрации.
              </p>
              <v-text-field
                v-model="inviteEmail"
                label="Email"
                type="email"
                variant="filled"
                density="comfortable"
              ></v-text-field>
            </v-window-item>

            <v-window-item value="link">
              <p class="text-body-2 text-medium-emphasis mb-4">
                Сгенерируйте ссылку для приглашения и отправьте её самостоятельно.
              </p>

              <v-select
                v-model="inviteExpiration"
                :items="expirationOptions"
                label="Срок действия ссылки"
                variant="filled"
                density="comfortable"
              ></v-select>

              <div v-if="inviteLink" class="mt-4">
                <v-text-field
                  :model-value="inviteLink"
                  readonly
                  variant="filled"
                  density="comfortable"
                  @click:append-inner="copyInviteLink"
                >
                  <template #append-inner>
                    <v-btn variant="text" size="small" :icon="true" @click="copyInviteLink">
                      <ph-copy :size="20" weight="bold" />
                    </v-btn>
                  </template>
                </v-text-field>
              </div>
            </v-window-item>
          </v-window>

          <v-alert v-if="inviteError" type="error" variant="tonal" class="mt-4">{{ inviteError }}</v-alert>
        </v-card-text>

        <v-card-actions>
          <v-spacer></v-spacer>
          <v-btn variant="text" @click="isInviteModalOpen = false">Отмена</v-btn>
          <v-btn
             color="primary"
             @click="sendInvite"
             :loading="inviteLoading"
             :disabled="(inviteTab === 'email' && !inviteEmail) || (inviteTab === 'link' && inviteLink !== '')"
          >
            {{ inviteTab === 'email' ? 'Отправить' : 'Сгенерировать' }}
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>
