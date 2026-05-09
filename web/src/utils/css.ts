export function supportsCssValue(property: string, value: string): boolean {
  if (typeof CSS === 'undefined' || typeof CSS.supports !== 'function') return true
  return CSS.supports(property, value)
}

export function cssColorOr(value: string | null | undefined, fallback: string): string {
  const color = value?.trim()
  if (!color) return fallback
  return supportsCssValue('color', color) ? color : fallback
}

export function cssUrlImageOr(value: string | null | undefined, fallback = 'none'): string {
  const url = value?.trim()
  if (!url) return fallback
  const image = `url(${JSON.stringify(url)})`
  return supportsCssValue('background-image', image) ? image : fallback
}
