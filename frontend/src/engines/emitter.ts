type Handler = (payload?: unknown) => void

/** Minimal event hub shared by the engines. */
export class Emitter {
  private handlers = new Map<string, Set<Handler>>()

  on(event: string, cb: Handler) {
    if (!this.handlers.has(event)) this.handlers.set(event, new Set())
    this.handlers.get(event)!.add(cb)
  }

  emit(event: string, payload?: unknown) {
    this.handlers.get(event)?.forEach((cb) => cb(payload))
  }

  clear() {
    this.handlers.clear()
  }
}
