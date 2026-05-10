/**
 * PUTs `file` to a pre-signed S3 URL. Resolves on 2xx, rejects otherwise.
 * `onProgress` receives a 0..1 fraction of bytes uploaded.
 *
 * We use XHR (not fetch) because fetch lacks an upload-progress event in
 * browsers. The server has already validated the metadata; here we just
 * carry the bytes.
 */
export function uploadToPresignedUrl(
  url: string,
  file: File,
  onProgress?: (fraction: number) => void,
): Promise<void> {
  return new Promise((resolve, reject) => {
    console.log('Starting upload to:', url)          // ← добавь
    console.log('File type:', file.type, 'size:', file.size)
    const xhr = new XMLHttpRequest()
    xhr.open('PUT', url)
    xhr.setRequestHeader('Content-Type', file.type || 'application/octet-stream')

    xhr.upload.addEventListener('progress', (e) => {
      if (e.lengthComputable && onProgress) {
        onProgress(e.loaded / e.total)
      }
    })

    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve()
      } else {
        reject(new Error(`upload failed: ${xhr.status} ${xhr.statusText}`))
      }
    }
    xhr.onerror = () => reject(new Error('upload network error'))
    xhr.onabort = () => reject(new Error('upload aborted'))

    xhr.send(file)
  })
}
