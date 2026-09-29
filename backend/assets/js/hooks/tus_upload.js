import * as tus from "tus-js-client"

/**
 * Resumable upload straight to Bunny Stream (RF08). The server only signs:
 * `request_upload` returns {endpoint, library_id, video_id, signature, expires}
 * bound to one video. Progress fingerprints live in localStorage, so picking
 * the same file after closing the tab resumes from the last chunk.
 */
const CHUNK_SIZE = 64 * 1024 * 1024

export const TusUpload = {
  mounted() {
    this.fileInput = this.el.querySelector("[data-role=file]")
    this.startButton = this.el.querySelector("[data-role=start]")
    this.startButton.addEventListener("click", () => this.start())
    this.beforeUnload = (e) => {
      if (this.upload) e.preventDefault()
    }
    window.addEventListener("beforeunload", this.beforeUnload)
  },

  destroyed() {
    window.removeEventListener("beforeunload", this.beforeUnload)
    this.upload?.abort()
  },

  start() {
    const file = this.fileInput.files[0]
    if (!file) return this.fileInput.click()

    this.setBusy(true)
    this.pushEvent("request_upload", {}, (reply) => {
      if (reply.error) {
        this.setBusy(false)
        return this.pushEvent("upload_error", {message: reply.error})
      }
      this.run(file, reply.credentials)
    })
  },

  run(file, c) {
    let lastPush = 0

    const upload = new tus.Upload(file, {
      endpoint: c.endpoint,
      chunkSize: CHUNK_SIZE,
      retryDelays: [0, 3000, 5000, 10000, 20000, 60000],
      removeFingerprintOnSuccess: true,
      headers: {
        AuthorizationSignature: c.signature,
        AuthorizationExpire: String(c.expires),
        VideoId: c.video_id,
        LibraryId: String(c.library_id),
      },
      metadata: {filetype: file.type, title: c.title},
      onProgress: (sent, total) => {
        const now = Date.now()
        if (now - lastPush > 1000 || sent === total) {
          lastPush = now
          this.pushEvent("upload_progress", {pct: (sent / total) * 100})
        }
      },
      onSuccess: () => {
        this.upload = null
        this.setBusy(false)
        this.pushEvent("upload_complete", {})
      },
      onError: (err) => {
        this.upload = null
        this.setBusy(false)
        this.pushEvent("upload_error", {message: String(err.message || err).slice(0, 200)})
      },
    })

    // Fingerprint includes the endpoint + file; resume only uploads for this video.
    upload.findPreviousUploads().then((previous) => {
      const match = previous.find((p) => p.metadata?.title === c.title)
      if (match) upload.resumeFromPreviousUpload(match)
      this.upload = upload
      upload.start()
    })
  },

  setBusy(busy) {
    this.startButton.disabled = busy
    this.fileInput.disabled = busy
    this.el.querySelector("[data-role=label]").textContent = busy ? "Enviando…" : "Enviar para o Bunny"
  },
}
