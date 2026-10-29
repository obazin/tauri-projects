# @name@

@description@

Tauri 2 (Rust) + Svelte 5 + Tailwind 4. The dev shell comes from [tauri-projects](https://github.com/obazin/tauri-projects): the Rust pin, cross targets, Node and the webview stack. Describe the architecture in `docs/` and point to it here as the project grows.

## Mandatory rules

> Break any of these and the task is not done.

1. **Svelte MCP after every `.svelte` edit.** Call `mcp__svelte__svelte-autofixer` on the changed file, fix every reported issue, and repeat until clean.
2. **Svelte 5 runes only.** Never use Svelte 4 syntax (`$:`, `export let`, `on:event`, `<slot>`, `createEventDispatcher`).
3. **Live docs over memory.** Before writing against Svelte 5, Tailwind v4, Tauri v2 (core or plugins) or any other library, look the API up with `mcp__svelte__get-documentation` or context7 (`resolve-library-id` then `query-docs`).
4. **Run `rust-ipc-reviewer` after IPC-surface changes.** Any edit to a `#[tauri::command]`, to `generate_handler!` or managed state, or to `src-tauri/capabilities/*.json` is followed by the `rust-ipc-reviewer` subagent, and its findings are fixed or answered.
5. **Keep the docs current.** A user-facing change is described in the user documentation in the same commit; a change to how the frontend and backend fit together updates the architecture documentation.
6. **Documentation describes the present, concisely.** Doc comments, module headers and `docs/*.md` answer what a thing is, why it exists and how it is used. No "used to be", "was renamed from" or refactor history: that belongs in commit messages.
7. **Every mechanism is cross-platform, or hides behind one facade.** The app ships on macOS, Windows and Linux (WebKitGTK is the weakest renderer). Choose something that works on all three, or put the per-OS implementations behind `#[cfg(target_os = …)]` in a single module that every caller goes through. The dev shell carries the standard library of every shipped triple, so `cargo check --target <triple>` type-checks the other platforms from any host.
8. **AST / LSP over string-pattern search for code.** Use `ast-grep` (`ast-grep run --lang ts -p '<pattern>'`, also `rust`) for structural search and refactors, and the LSP tool (TypeScript and rust-analyzer) for definitions, references and renames. Quote `$`-patterns in single quotes. `ast-grep --lang ts` does not parse `.svelte` files: fall back to Grep or LSP there. Plain text, logs and config stay with Grep.
9. **Green before done.** Type checks, formatting, frontend tests, `cargo fmt --check`, Clippy with warnings denied and `cargo test` all pass before a task is reported complete.
10. **Never edit lock files by hand.** Change `pnpm-lock.yaml` with `pnpm`, `Cargo.lock` with `cargo`.
11. **Tailwind with semantic tokens only.** Style components with Tailwind v4 utilities built from the `@theme` tokens in `src/app.css`, named for their role (`bg-surface`, `text-muted`, `text-caption`, `rounded-control`), never for their value. Clear Tailwind's stock palette with `--color-*: initial`. No `<style>` blocks, hex or palette colours (`sky-500`), arbitrary bracket values (`text-[13px]`) or `dark:` variants: themes override the tokens (`[data-theme]` blocks or properties set at runtime), and when no token fits, add one with a semantic name to `@theme`.

## Tools to use

| Tool                                           | When                                                                |
| ---------------------------------------------- | ------------------------------------------------------------------- |
| `mcp__svelte__svelte-autofixer`                | After every `.svelte` edit (rule 1)                                 |
| `mcp__svelte__get-documentation`               | Before writing Svelte 5 code                                        |
| context7 (`resolve-library-id` + `query-docs`) | Tailwind v4, Tauri v2, its plugins, other libraries and Rust crates |
| `ast-grep`                                     | Structural code search and refactors (rule 8)                       |
| LSP tool                                       | Definition, references, rename, type at point (rule 8)              |
| `rust-ipc-reviewer` agent                      | After any IPC-surface change (rule 4)                               |
| `/implement-issue #<number>`                   | Taking a GitHub issue from branch to reviewed commits               |

## Quick reference

```sh
run                   # just run: launch the app in dev
```

Run inside the dev shell (`direnv allow` once, or `nix develop`). Flakes only see files tracked by git: `git add` a new file before Nix needs it.
