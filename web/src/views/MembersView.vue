<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useSysStore } from '../stores/sys'
import { useAuthStore } from '../stores/auth'
import type { User } from '../stores/auth'
import { PhPlus, PhMagnifyingGlass, PhDotsThreeVertical, PhCopy } from '@phosphor-icons/vue'

const sys = useSysStore()
const auth = useAuthStore()

const loading = ref(false)
const users = ref<User[]>([])
const search = ref('')

// Invite Modal
const isInviteModalOpen = ref(false)
const inviteTab = ref('email')
const inviteEmail = ref('')
const inviteLink = ref('')
const inviteExpiration = ref<number | null>(60) 
const inviteLoading = ref(false)
const inviteError = ref<string | null>(null)

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
      // For email, maybe show success state
      isInviteModalOpen.value = false
      inviteEmail.value = ''
    } else {
      const res = await sys.createInvite({ expire_in_minutes: inviteExpiration.value })
      // For now, let's construct the link based on the token
      inviteLink.value = `${window.location.origin}/register?token=${res.token}`
    }
  } catch (e: any) {
    inviteError.value = e?.message || 'Failed to create invite'
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
  loadUsers()
})

const onSearchInput = () => {
  loadUsers()
}

const copyInviteLink = () => {
  if (navigator && navigator.clipboard) {
    navigator.clipboard.writeText(inviteLink.value)
  }
}
</script>

<template>
  <div class="pa-4 pa-sm-6 pa-md-8 mx-auto" style="max-width: 1200px;">
    <div class="d-flex align-center justify-space-between mb-6">
      <h1 class="md-headline-medium">Участники</h1>
      <v-btn v-if="auth.isAuthed" color="primary" @click="openInviteModal">
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
            { title: 'Действия', value: 'actions', sortable: false, align: 'end' }
          ]"
          :items="users"
          :loading="loading"
          item-value="id"
        >
          <template #item.name="{ item }">
             <div class="d-flex align-center">
              <v-avatar size="32" class="mr-3" color="primary">
                 <img v-if="item.avatar_url" :src="item.avatar_url" />
                 <span v-else class="text-white">{{ (item.display_name || item.email || '?').slice(0, 1).toUpperCase() }}</span>
              </v-avatar>
              <div>
                <div class="font-weight-medium">{{ item.display_name || '—' }}</div>
                <div class="text-caption text-medium-emphasis">{{ item.email }}</div>
              </div>
            </div>
          </template>
          <template #item.role="{ item }">
            <v-chip size="small" :color="item.role === 'admin' ? 'secondary' : 'default'">
               {{ item.role === 'admin' ? 'Администратор' : 'Пользователь' }}
            </v-chip>
          </template>
          <template #item.actions>
            <v-btn variant="text" size="small" :icon="true">
              <ph-dots-three-vertical :size="20" weight="bold" />
            </v-btn>
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
