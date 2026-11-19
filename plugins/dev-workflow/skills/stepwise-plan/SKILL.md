---
name: stepwise-plan
description: Write a step-by-step implementation plan file for a non-trivial change, then execute it one task at a time in the main session, stopping at a review checkpoint after every task. Use when the user asks to "plan this in steps", "write a stepwise plan", or "plan it so I can review each step", or to "start/resume the plan" or "do the next task" of a plan written by this skill. Do NOT use for one-step edits or quick fixes; use vet to challenge whether to build it at all, and adversarial-review to critique a written plan.
user-invocable: true
argument-hint: "[description of the change | path to plan file | task number]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Skill, AskUserQuestion
---

# Stepwise Plan

Turn a non-trivial change into a written plan of small, verifiable tasks, then build it **one task at a time**, stopping after each so the developer reviews the work while it's still small.

The point is control and reviewability, not ceremony. A 300-line diff reviewed in five 60-line pieces gets a real review; one big diff at the end gets skimmed. Stopping after each task also means a wrong assumption gets caught after one task instead of after five.

The skill has two modes. Work out which one the user wants:

- **Write** — there's no plan yet. Produce the plan file and stop.
- **Execute** — a plan exists. Do the next unchecked task (or the one the user names), then stop at its checkpoint.

If the user asks for both ("plan it and start"), write the plan, stop so they can review it, and begin Task 1 only after they've approved it. A plan nobody read before building started is a plan in name only.

---

## Write mode

### 1. Understand before planning

- Read the request, any linked ticket/spec/ADR, and the repo's own guidance (`CLAUDE.md`, `AGENTS.md`, contributing docs, team memory). These hold the conventions the plan must respect.
- Explore the code the change touches. The plan must name **real files, real functions, and real commands**: if you can't point at the file, you don't understand the change well enough to plan it.
- Interview the user about the design decisions before writing anything. Ask the open design questions with `AskUserQuestion`, **one at a time**, each with your recommended answer first. Work through them until no design decision is being silently assumed.
  - Don't ask about things you can look up or decide sensibly yourself; record those as assumptions in the plan instead.
  - If the request already comes with a reviewed spec or ADR that settles the design, limit the interview to whatever it leaves open. If it leaves nothing open, skip the interview: state in one message the decisions you're taking from the spec, and proceed unless the user objects.
  - Optional: if your available-skills list happens to include an interview skill such as `grilling` (or `<plugin>:grilling`), you may invoke it via the Skill tool to run this interview instead. Most installs won't have one, so never require it or tell the user to install it. If you use it, tell it the goal is an implementation plan and pass along what you've already learned from the code. A user's stated interview-style preference wins over its format.
- Don't start writing the plan until the user confirms the open questions are settled. Carry each decision into the plan: rules into **Global Constraints**, design choices into **Approach**, and defaults you picked without asking into **Assumptions**.

### 2. Shape the tasks

A good task:

- **Leaves the codebase working.** Build, lint, and tests pass at the end of it. Nothing half-wired is left for the next task to finish.
- **Is reviewable in one sitting.** Roughly one concern: a pure helper plus its tests, one query, one handler rewire, one docs sweep. If you'd struggle to summarize the diff in two sentences, split it.
- **Runs in dependency order.** Pure logic and types first, then the things that use them, then wiring, then docs, then full verification.
- **Says how it's verified.** Name the exact commands, discovered from `package.json`, `Makefile`, CI config, or CLAUDE.md. Don't guess them.

Where the project has tests, write each task test-first (the same red-green loop as the `tdd` skill): write the failing test, run it and see it fail, implement, run it and see it pass. A test you never saw fail proves nothing.

Mark steps only the user can do (deploys, applying DB migrations, production checks, anything needing credentials) as **user steps**. The plan says to stop and ask; it never quietly does them.

### 3. Write the file

- **Location:** follow the repo's convention if one exists (look for an existing `docs/plans/`, `plans/`, or similar). Otherwise use `docs/plans/<topic>.md`: kebab-case topic name, no date prefix. The plan file is part of the change set and will show up in every checkpoint's diff; if the repo has no plans convention, ask the user whether to keep it in the repo or gitignore it.
- **Format:** use [`references/plan-template.md`](references/plan-template.md). Fill every section; delete a section only if it truly doesn't apply.
- **Detail level:** concrete enough that a **fresh session with no memory of this conversation** can execute any task without re-deciding anything. Include the actual code for interfaces, tests, and non-obvious logic; exact before/after text for docs edits; exact commands. A plan full of vague steps like "update the handler accordingly" pushes all the thinking into execution, which is where it's least reviewable.
- **Review Focus** is the most valuable section for the reviewer: the edge cases and risky decisions most likely to be wrong, each tied to the task that tests it. Spend real thought here.

### 4. Hand off

Tell the user where the plan is and summarize it in a few lines: the goal, the task list with one line each, and the review-focus items. Offer to run `adversarial-review` on the plan before execution. Then **stop**. Don't start Task 1 until they say so.

---

## Execute mode

The plan file is the source of truth, not your memory of an earlier conversation. Always read it fresh.

### 1. Orient

- Read the whole plan, including Global Constraints and Review Focus, not just the next task.
- Find the first task with unchecked steps, unless the user named one. If an earlier task is only half done, say so: finish it first if the user didn't name a task, otherwise ask whether to finish it or proceed with the named one.
- Run `git status`. Uncommitted changes from earlier tasks are expected, not drift; mention them so the user knows this task's diff will include them unless they commit or stage first.
- Check that the code is still in the state the plan expects (the files exist, the plan's assumptions still hold). If something has drifted (someone changed the code, an earlier task went differently), stop and say what's different before building on a false premise.
- Set the plan header's `**Status:**` to `In progress (Task <n> of <m>)`, and tell the user in one line which task you're starting.

### 2. Do the task, and only that task

- Work in the **main session**, step by step, in order. Don't hand tasks to subagents: the user wants to follow and review the work as it happens, and a subagent's summary hides the details they're there to see.
- Tick each step's checkbox (`- [ ]` → `- [x]`) in the plan file as you finish it, so the file always shows true progress.
- Run every verification command the plan specifies and **read the output**. A step isn't done because the code looks right; it's done because the check passed.
- On a **user step**, stop, tell the user exactly what to do and what to check afterwards, and tick it only after they confirm it's done. Never run it yourself.
- Don't wander into the next task, opportunistic refactors, or "while I'm here" fixes. If you spot something worth doing, mention it at the checkpoint.

### 3. When reality disagrees with the plan

Plans are written before the code pushes back. When a step turns out wrong (a wrong file, an API that doesn't exist, a test that can't pass as written, a better approach that's now obvious):

- **Small and clearly within the task's intent** (a typo in a path, a renamed import): fix it, correct the step text in the plan file, keep going, and mention it at the checkpoint.
- **Changes the design, the interfaces, or a later task:** stop and explain the problem and your proposed fix. Once the user agrees, update the plan file (the step text, and a short `> **Deviation:**` note under the task) so later tasks and future sessions see the change.

Never silently build something different from what the plan says. The plan is what the user reviewed, so quietly going off it defeats the whole exercise.

### 4. Checkpoint, then stop

Every task ends with a checkpoint. Report:

1. **What changed**: files touched, in a sentence or two each.
2. **Verification**: the commands you ran and their real results. If something failed or was skipped, say so plainly.
3. **Deviations**: anything that differs from the plan, and whether the plan file was updated.
4. **Review pointers**: the Review Focus items this task covered, and where to look.
5. **Next**: the next task's name, in one line.

Then **stop and wait**. Don't start the next task until the user says to. Leave changes **uncommitted**: committing, pushing, branching, and applying migrations are the user's calls unless they've explicitly told you otherwise for this plan. Suggest that the user commit or stage (`git add -A`) this task's changes before saying "next", so the next checkpoint's diff shows only the next task.

### 5. Finishing

When the last task's checkpoint is done, run the plan's full verification gate (build, lint, the whole test suite), report the results, and list any user steps still outstanding (deploy, QA check, PR). Set the plan header's `**Status:**` to `Complete`, or to what's still open.

---

## Common mistakes

| Mistake | Why it hurts |
| --- | --- |
| Continuing to the next task without being asked | Removes the review between tasks, which is the whole point. |
| A task that leaves the build red "until Task 4" | Every checkpoint should be safe to stop at for days. |
| "Tests pass" without running them | The user trusts the checkpoint report. Run the checks and report the real output. |
| Vague steps ("wire it up", "update docs as needed") | Pushes design decisions into execution, where they're hard to review. |
| Silently fixing the plan mid-task | The user approved a different plan. Raise it, then update the file. |
| Planning without reading the code | The plan names files and functions that don't exist, and Task 1 falls apart. |
