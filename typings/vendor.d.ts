declare module "micromatch" {
  interface Micromatch {
    (filename: string & string[], pattern: string & string[]): string[]
    isMatch(filename: string, pattern: string): boolean
  }

  var mm: Micromatch
  export = mm
}
