declare type Content = string | Buffer

interface Context {
  filename: string
}

interface Handler {
  (ctx: Context): Content | Promise<Content>
}

interface HandlerConfig {
  handler: Handler
}

interface Handlers {
  [pattern: string]: HandlerConfig
}

interface Config {
  handlers: Handlers
  root?: string
}

interface ContentCallback {
  (error: Error, content: Content)
}

