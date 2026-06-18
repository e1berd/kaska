import { ref, onBeforeUnmount } from 'vue'

export function useFileDrop(onFiles: (files: File[]) => void) {
  const dragCounter = ref(0)
  const isDragging = ref(false)

  function onDragEnter(e: DragEvent) {
    e.preventDefault()
    if (e.dataTransfer?.types.includes('Files')) {
      dragCounter.value++
      isDragging.value = true
    }
  }

  function onDragOver(e: DragEvent) {
    e.preventDefault()
    if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy'
  }

  function onDragLeave(e: DragEvent) {
    e.preventDefault()
    dragCounter.value--
    if (dragCounter.value <= 0) {
      dragCounter.value = 0
      isDragging.value = false
    }
  }

  function onDrop(e: DragEvent) {
    e.preventDefault()
    dragCounter.value = 0
    isDragging.value = false
    const files = Array.from(e.dataTransfer?.files ?? [])
    if (files.length) onFiles(files)
  }

  function reset() {
    dragCounter.value = 0
    isDragging.value = false
  }

  onBeforeUnmount(reset)

  return {
    isDragging,
    onDragEnter,
    onDragOver,
    onDragLeave,
    onDrop,
    reset,
  }
}
