# PocketKernel Automation Rebuild

## Product target

PocketKernel becomes an original iPhone-first automation agent with the same publicly advertised capability class as PocketBot, while retaining PocketKernel branding, original source, original UI assets, and an independently designed implementation.

The current declarative micro-app host is a prototype and is not the release product.

## User promise

Describe work in plain English. PocketKernel connects approved services, creates a typed automation or actionable task, tests it, asks for approval where needed, and executes it deterministically on demand or from a trigger.

## Verified public PocketBot parity surface

PocketKernel 1.0 must cover the complete publicly documented behavior set:

1. Natural-language automation creation through conversational iteration.
2. Cloud-hosted chained workflows created once and executed deterministically without regenerating the workflow on every run.
3. Manual, cron/schedule, webhook, upstream-workflow, account-event, live-web-data, time-zone, and location-aware triggers.
4. OAuth connections for Gmail, Outlook, Google Calendar, Google Drive, Docs, Sheets, Slides, Slack, Discord, Reddit, LinkedIn, plus generic HTTPS APIs and RSS.
5. Email reply, forward, summarize, label/sort, digest, reminder, and inbox-triage actions.
6. Slack, Discord, Reddit, and LinkedIn posting, monitoring, keyword alerts, scheduling, and cross-posting.
7. Calendar event creation, reminders, availability checks, meeting preparation, and calendar-to-sheet/task synchronization.
8. Data movement and transformation between connected services.
9. Price, market, weather, RSS, and API endpoint condition monitoring with notifications.
10. A categorized todo inbox inferred from connected email, calendar, and messages.
11. User-created todos alongside inferred work.
12. Actions agent that reads full context, drafts replies, schedules meetings, prepares documents, and returns the result for review.
13. Explicit approval before any externally visible or destructive action.
14. Editable inferred categories and manual recategorization.
15. Reusable automation templates, fast template discovery, deterministic template adaptation, and safe auto-repair.
16. Complete execution history, retries, failures, approvals, connection health, and privacy controls.

## Non-copying boundary

PocketKernel will not copy PocketBot's name, icon, mascot, exact wording, screenshots, proprietary code, private APIs, or undisclosed implementation. Product behavior is implemented independently from public descriptions and normal automation-platform patterns.

## System architecture

### PocketKernel iOS app

- SwiftUI iPhone/iPad client targeting iOS/iPadOS 26.0.
- Apple Foundation Models builder using `SystemLanguageModel` when available.
- Guided generation into `AutomationBlueprint` rather than source code.
- Conversational draft refinement.
- Native workflow timeline and typed step inspector.
- OAuth connection handoff through `ASWebAuthenticationSession`.
- Inbox and categorized todo experience.
- Approval queue for outbound/destructive operations.
- Run history, logs, connection health, templates, settings, and Siri/App Intents.
- SQLite cache and offline draft editing.

### PocketKernel service

- TypeScript API and worker service.
- PostgreSQL persistence.
- Encrypted OAuth token vault with per-connection key wrapping.
- Schedule engine, webhook ingress, event polling, retries, idempotency, and rate limiting.
- APNs notifications.
- Registered connector/action catalog.
- Deterministic workflow interpreter; no arbitrary shell execution.
- Auditable approval state machine.
- Template registry and versioned repair migrations.

### Apple model boundary

Apple Foundation Models may:

- understand the request;
- select registered operations;
- generate a typed draft;
- infer safe transformations and conditions;
- explain the plan;
- repair invalid drafts;
- summarize/classify/extract content in explicitly configured AI steps.

It may not:

- store credentials;
- grant OAuth scopes;
- execute outbound operations before approval;
- invent unsupported connectors;
- change an enabled workflow without versioning and review;
- act as the scheduler or webhook server.

## Core domain

- `AutomationManifest`
- `AutomationTrigger`
- `WorkflowStep`
- `WorkflowOperation`
- `ConnectionRequirement`
- `ApprovalPolicy`
- `RetryPolicy`
- `WorkflowRun`
- `StepRun`
- `AutomationTemplate`
- `ActionableTask`
- `TaskCategory`

Every operation is selected from a versioned catalog and has a typed input/output schema.

## Initial operation catalog

### Gmail

- search/read message and thread
- draft/send/reply/forward
- label/archive/mark read
- attachment metadata and approved download

### Outlook

- search/read mail
- draft/send/reply/forward
- folders/categories

### Google Calendar

- search events
- free/busy
- create/update/delete event
- attendee and reminder handling

### Google Drive and Workspace

- search/read/create Drive files
- create/update Docs
- read/append/update Sheets
- create/update Slides content

### Slack

- search/read channels and threads
- post/update messages
- reactions and approved file upload

### Discord, Reddit, LinkedIn

- registered posting, reading, monitoring, and approved update actions supported by each service's public API and OAuth policy

### Web and data

- HTTPS GET/POST/PUT/PATCH/DELETE with allowlisted domains
- webhook trigger and response
- RSS/Atom read
- JSON extraction, map, filter, sort, group, join, format, deduplicate
- conditions, branches, delay, fan-out, and child-workflow invocation

### Intelligence

- summarize
- classify
- extract fields
- rewrite
- draft response
- prioritize tasks

## Triggers

- manual
- schedule with IANA time zone
- webhook
- preceding workflow completion
- Gmail/Outlook polling event
- calendar threshold
- RSS or HTTP condition
- location/geofence signal initiated through supported iOS location mechanisms
- app-generated approval completion

Every trigger uses deduplication and persisted cursor state.

## Approval rules

Always require approval by default for:

- sending or posting content;
- deleting or moving external data;
- creating, updating, or cancelling calendar events with attendees;
- financial or purchase-related operations;
- broad file writes;
- first execution after a workflow version changes.

Users may explicitly grant a narrow recurring approval for an exact operation, connection, destination, and constraint set. Scope expansion invalidates that approval.

## iOS navigation

1. **Today** — inferred categorized tasks, user todos, approvals, and upcoming runs.
2. **Create** — conversational builder, generated plan, connections, test run, approval policy, enable action.
3. **Automations** — active, paused, drafts, templates, versions, duplicate/export/delete.
4. **Activity** — workflow and step runs, retries, redacted inputs/outputs, failures, approvals.
5. **Connections** — OAuth accounts, scopes, health, reconnect, revoke, privacy controls.

## Todo agent

A server-side ingestion workflow reads only user-approved sources and creates `ActionableTask` candidates. The app shows why each task was inferred and its source references. Opening a task loads the full authorized context and proposes an action plan. Nothing is sent or externally modified until approval.

## Template system

Templates are typed manifests, never executable source blobs. A successful user workflow can produce a privacy-scrubbed structural template only after explicit opt-in. Template adaptation replaces connection IDs, destinations, schedules, and variables. Validator and migration code repair obsolete operation versions; the model may propose a repair but cannot bypass validation.

## Security

- OAuth authorization-code flow with PKCE.
- Provider secrets and refresh tokens remain on the service, encrypted at rest.
- Least-privilege scopes and incremental authorization.
- HTTPS only and redirect revalidation.
- Connector-specific rate limits.
- Idempotency keys for mutating operations.
- Secret redaction in logs.
- Complete account revocation and data deletion.
- No arbitrary Swift, JavaScript, Python, shell, dylib, JIT, or downloaded native code in the iOS app.
- No unrestricted arbitrary code execution on workers in 1.0.

## Delivery sequence

### Gate A — Replace the domain

Add the automation, task, connection, approval, template, and execution models alongside compatibility adapters. Freeze new micro-app features.

### Gate B — Replace the shell

Ship the five automation tabs and remove Service Log/demo-first presentation from production launch.

### Gate C — Builder

Use Foundation Models guided generation with deterministic CI fixtures and a rule-based offline fallback that creates workflows, not canned apps.

### Gate D — Local deterministic engine

Execute transformations, branches, test adapters, validation, approval checks, and complete run logs locally in CI.

### Gate E — Service contract

Add API schemas, OAuth session protocol, remote execution protocol, webhook contract, scheduler contract, and mock service.

### Gate F — Real connectors

Implement Gmail, Google Calendar, Sheets/Drive, Slack, then Outlook and the remaining advertised integrations.

### Gate G — Todo agent

Implement authorized ingestion, task inference, categorization, full-context action preparation, and approval delivery.

### Gate H — IPA

Run unit/UI tests, ARM64 iphoneos build, package verification, checksum generation, and unsigned IPA publication.

## Acceptance scenario

A release candidate must:

1. connect a mock Gmail and Slack account in CI;
2. generate a typed weekday inbox-digest workflow from plain English;
3. show exact requested scopes;
4. test the workflow with deterministic fixtures;
5. require approval for the Slack post;
6. enable, pause, duplicate, export, import, and version the workflow;
7. execute a scheduled fixture exactly once with idempotency;
8. create categorized actionable tasks from message/calendar fixtures;
9. draft a reply and require approval before sending;
10. persist and reopen all state;
11. build and validate an unsigned ARM64 IPA.

## Current branch policy

The existing branch remains a draft until the automation shell, domain, deterministic test engine, and CI acceptance scenario replace the micro-app prototype. A green build of the old Service Log runtime does not qualify as completion.
