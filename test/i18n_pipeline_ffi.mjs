// Test-only FFI: read a pipeline artifact from disk (gleam test runs from
// the project root on the JavaScript target).
import { readFileSync } from "node:fs";

export function readFile(path) {
  return readFileSync(path, "utf8");
}
