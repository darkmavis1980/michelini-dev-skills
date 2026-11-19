# Plan template

Copy the skeleton below into the plan file and fill it in. Text in `<angle brackets>` is a placeholder (in real code blocks, angle brackets are code, e.g. TypeScript generics, so don't strip them); the italic notes explain what each section is for, so remove them from the real plan.

---

```markdown
# <Feature / change name> Implementation Plan

> **How to execute:** Inline in the main session, one task at a time, in order. No subagents. Each task ends with a **checkpoint**: leave the changes uncommitted, report, and stop for review before starting the next task. Steps use checkboxes (`- [ ]`) to track progress; tick them as you go.
>
> **Status:** Not started

**Goal:** <One or two sentences: what changes for the user/system, and what must stay the same.>

**Approach:** <A short paragraph: the shape of the solution. Which new modules/functions exist, what each is responsible for, how they connect to existing code.>

**Tech stack:** <Languages, frameworks, DB, test runner: whatever the reviewer needs to read the tasks.>

**References:** <Links to the ticket, spec/ADR, related plans. Omit if none.>

## Global Constraints

_Rules every task must respect. These are what a fresh session most easily forgets._

- <Contracts that must not change, e.g. a response shape or a public API.>
- <Key business rules / thresholds, stated exactly.>
- <Repo conventions that apply (naming, where types live, lint/format rules, test conventions).>
- <Things the code must never do, e.g. "never calls X", "reader DB only".>

## Assumptions

_Decisions made without asking. The user can correct them before execution starts. Omit if none._

- <Assumption, and why it's the sensible default.>

## Review Focus

_The edge cases and risky decisions most likely to be wrong, each tied to where it's tested. This is where the reviewer should spend their attention._

1. **<Edge case>** (`<example input>`): <expected behavior>. Verified in Task <n> (<test / smoke check / user step>).
2. ...

---

### Task 1: <Name: one concern>

**Files:**

- Create: `<path>`
- Modify: `<path>` (<where, e.g. "after `FOO_CONST`, ~line 96">)
- Test: `<path>`

**Interfaces:**

- Produces: <types/functions/constants this task adds, with signatures>
- Consumes: <what it relies on from earlier tasks or existing code>

- [ ] **Step 1: <Write the failing tests>**

<What the tests cover, with the actual test code for anything non-trivial.>

- [ ] **Step 2: Run the tests to verify they fail**

Run: `<exact command>`. Expected: <which tests fail, and why>.

- [ ] **Step 3: <Implement …>**

<The actual code, or precise instructions for anything non-obvious.>

- [ ] **Step 4: Run the tests to verify they pass**

Run: `<exact command>`. Expected: all green.

- [ ] **Step 5: Checkpoint.** Run `<build>`, `<lint/format/type-check commands>`, and `<tests for the affected packages, or the full suite>`, and fix anything flagged. Leave the changes uncommitted and stop for review.

---

### Task <n>: Docs and stale comments

- [ ] **Step 1: `<file>`.** Replace "<exact old text>" with "<exact new text>".
- [ ] **Step 2: Checkpoint.** Run `<format check>`. Leave the changes uncommitted and stop for review.

---

### Task <last>: Verification

- [ ] **Step 1: Full local gate.** Run `<build>`, `<lint>`, `<full test suite>`. All must pass.
- [ ] **Step 2: <Smoke test, if applicable>.** <How to exercise the change for real, with expected result.>
- [ ] **Step 3 (user step): <Deploy / apply migration / QA check>.** Stop and ask the user to do this; then <what to check afterwards>.
- [ ] **Step 4: Checkpoint.** Summarize results and anything outstanding. The user commits and opens the PR.
```
