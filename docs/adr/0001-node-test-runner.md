# 0001. Node's built-in test runner for frontend tests, not Vitest

- **Date:** 2026-11-23
- **Status:** Accepted

## Context

The frontend got its first tests: the pure logic in `src/board.ts` and helpers like `dropPreview` and `cleanupFor`. None of them need a browser or React. The project is on Vite 5.

Vitest is the usual choice for Vite projects. But the last Vitest that works with Vite 5 (3.x) pulls in packages with published security advisories, one rated critical (`tinypool`). The fixed versions (Vitest 4 and 5) require Vite 6.4 or newer.

## Decision

Use Node's built-in test runner (`node --test` with `node:assert`). Node 22 runs `.test.ts` files directly by stripping the types, so there's no build step and no test dependency beyond `@types/node`.

## Alternatives considered

- **Vitest 3:** works with Vite 5, but brings in the advisories above.
- **Upgrade Vite to 6+, then Vitest 5:** the standard setup, and it would also fix the existing `esbuild` advisory in Vite 5. But it's a build-tool upgrade, which shouldn't be hidden inside "add tests".

## Consequences

- No test framework to maintain or update, and no new advisories.
- Test files import with the `.ts` extension (`./board.ts`), and CI needs Node 22 or newer.
- No component tests: Node has no DOM. Components are checked by hand (see GUIDELINES.md, section 9).
- Revisit when upgrading Vite to 6+, or when we want component tests. Vitest with jsdom covers both, and the tests port over almost line by line (`assert.equal` → `expect().toBe`).
