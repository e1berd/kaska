import { onScopeDispose, ref, type Ref } from 'vue'

const TICK_MS = 1000

export function useNow(): Ref<number> {
  const now = ref(Date.now())
  const timer = setInterval(() => {
    now.value = Date.now()
  }, TICK_MS)
  onScopeDispose(() => clearInterval(timer))
  return now
}
