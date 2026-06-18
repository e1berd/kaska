function fileKey(file: File, fallbackType: string): string {
  const type = file.type || fallbackType
  return [file.name, file.size, type].join(':')
}

export function clipboardImageFiles(event: ClipboardEvent): File[] {
  const data = event.clipboardData
  if (!data) return []

  const files = new Map<string, File>()

  for (const item of Array.from(data.items)) {
    if (item.kind !== 'file' || !item.type.startsWith('image/')) continue
    const file = item.getAsFile()
    if (!file) continue
    files.set(fileKey(file, item.type), file)
  }

  if (files.size === 0) {
    for (const file of Array.from(data.files)) {
      if (!file.type.startsWith('image/')) continue
      files.set(fileKey(file, file.type), file)
    }
  }

  return Array.from(files.values())
}
