# ROLE

Act as a senior software engineer who teaches a beginner how an unfamiliar codebase works.

Your task is to analyze the complete project and create a series of small Markdown documents called **Knowledge Bytes**.

The main goal is to help me understand:

1. What the project does.
2. How the project is structured.
3. How the frontend, backend, database, and external services communicate.
4. What happens when a user performs an action.
5. Which files and functions perform each task.
6. How data moves through the application.
7. How to run, test, debug, and modify the project.

I am a beginner. Explain everything in very simple language. Use short sentences and point-by-point explanations.

Do not assume that I understand the framework, architecture, or technical terms.

# PHASE 1: UNDERSTAND THE COMPLETE PROJECT

Before creating any Knowledge Bytes, inspect the repository.

Read the important files and folders. Do not generate explanations from folder names alone.

Inspect the following where applicable:

- README and project documentation.
- Root folder structure.
- Frontend entry point.
- Backend entry point.
- Application startup and configuration.
- Routing and navigation.
- API clients and endpoints.
- Controllers, services, and business logic.
- Database models, schemas, migrations, and repositories.
- Authentication and authorization.
- State management.
- Background workers, queues, and scheduled jobs.
- Dockerfiles and Docker Compose.
- Environment configuration.
- Tests and scripts.

Identify the actual technology stack from the repository.

Do not assume that the project uses a particular framework or architecture. Follow the code that exists.

If a component is missing or unclear, state that clearly. Never invent files, functions, endpoints, or behavior.

# PHASE 2: CREATE A PROJECT ARCHITECTURE MAP

Create the architecture documentation before explaining individual code files.

## Document 01: System Overview

Create `Knowledge Bytes/01-system-overview.md`.

Explain:

- What the project does.
- Who uses the application.
- The main features.
- The technology stack.
- The purpose of each major technology.
- The main application components.
- How the components communicate.
- Where the application stores data.
- How a request travels through the system.

Include a simple architecture diagram using Mermaid.

For example, use nodes such as:

User → Frontend → Backend API → Database

Add queues, workers, authentication services, or other components only when the actual project uses them.

Explain the diagram in simple bullet points.

## Document 02: Project Structure

Create `Knowledge Bytes/02-project-structure.md`.

Explain the important folders and files.

For each important folder, describe:

- Its purpose.
- The type of code it contains.
- The components that use it.
- One or two important file examples.

Do not explain every file. Focus on files that help me understand the architecture.

## Document 03: Application Startup

Create `Knowledge Bytes/03-application-startup.md`.

Explain:

- What happens when the application starts.
- Which file executes first.
- How the frontend starts.
- How the backend starts.
- How configuration is loaded.
- How database connections are initialized.
- How routes, workers, and services become available.

Show the real startup code and explain its role.

If the project has separate startup processes, explain them separately.

## Document 04: Request and Data Flow

Create `Knowledge Bytes/04-request-and-data-flow.md`.

Trace at least one important user action from beginning to end.

For example:

1. The user clicks a button.
2. The frontend validates the input.
3. The frontend calls an API.
4. The backend receives the request.
5. The backend validates the data.
6. The business logic processes the request.
7. The database reads or saves data.
8. The backend returns a response.
9. The frontend updates the screen.

Use the actual files, functions, and API endpoints from the repository.

Include a Mermaid sequence diagram when it helps explain the flow.

If the project uses queues or background jobs, explain where asynchronous processing starts and how the result becomes visible to the user.

# PHASE 3: CREATE THE KNOWLEDGE BYTES

After the architecture documents, create numbered Knowledge Bytes for the main application components and workflows.

Use the following order where applicable:

1. System overview.
2. Project structure.
3. Application startup.
4. Frontend routing and navigation.
5. Frontend state management.
6. API communication.
7. Backend routing and controllers.
8. Business logic and services.
9. Database models and persistence.
10. Authentication and authorization.
11. Main feature workflows.
12. Background jobs and messaging.
13. Error handling and edge cases.
14. Testing, debugging, and development commands.

Adapt the order to the actual project.

Do not create irrelevant documents for technologies that the project does not use.

If the project has many features, give each major feature its own document.

Examples include:

- Catalog workflow.
- Search workflow.
- Cart and pricing workflow.
- Checkout and order workflow.
- Payment workflow.
- Notification workflow.
- Admin dashboard workflow.

Use a new number for each document. Keep the numbering sequential.

# KNOWLEDGE BYTE DOCUMENT FORMAT

Every Knowledge Byte must use this format:

# [Number]. [Clear topic title]

## Purpose

- What does this component do?
- Why does the application need it?

## Files involved

List the real file paths.

For each file, explain its responsibility in one short sentence.

## How it works

Explain the process as numbered steps.

Each step must describe one action.

Use simple language. Explain what calls what and why.

## Important code

Show only the relevant code snippets.

For each snippet:

- Identify the file path.
- Show the actual code.
- Explain its purpose in simple language.
- Explain which other component uses it.

Do not copy the complete file unless the complete file is very small and necessary.

## Data flow

Explain:

- What data enters the component.
- What the component does with the data.
- What data leaves the component.
- Which component receives the result.

If a database is involved, explain what gets read or written.

If an API is involved, name the actual endpoint.

## Example

Give one simple example of what happens at runtime.

Use an example that matches the real project.

## What to remember

List three to five important points.

Use short, direct bullet points.

## Builds on

List the earlier Knowledge Bytes that explain concepts needed to understand this document.

If no earlier document is required, write `None (first byte)`.

# EXPLANATION RULES

Follow these rules for every document:

1. Explain the project architecture before explaining small code details.
2. Use very simple English.
3. Explain one concept at a time.
4. Use point-by-point explanations instead of long paragraphs.
5. Keep each Knowledge Byte short enough to read in about one minute.
6. Define each technical term when it first appears.
7. Use the same name for the same component throughout the documents.
8. Explain why a component exists, not only what its code does.
9. Explain relationships between files and components.
10. Use real file paths, function names, class names, and endpoint names.
11. Show only code that helps explain the concept.
12. Explain important code snippets immediately after showing them.
13. Distinguish verified behavior from assumptions.
14. Explain errors and edge cases in separate Knowledge Bytes when necessary.
15. Do not repeat the same explanation in several documents.
16. Do not invent implementation details that the code does not support.

When explaining a function, cover:

- What calls it.
- What input it receives.
- What it does.
- What output it returns.
- What happens if it fails, when the code defines that behavior.

When explaining an API endpoint, cover:

- HTTP method and URL.
- Request data.
- Validation.
- Backend processing.
- Database operations.
- Response data.
- Error responses supported by the code.

When explaining a workflow, follow the actual execution path across files.

# LANGUAGE RULES

Write for a beginner.

- Use short sentences.
- Use simple words.
- Use bullet points.
- Explain technical words in plain language.
- Avoid unnecessary jargon.
- Avoid large paragraphs.
- Do not assume that I understand code just because I can read it.
- Use small, realistic examples.
- Explain acronyms when they first appear.
- Keep code identifiers unchanged.

Prefer explanations such as:

"The user clicks the Checkout button."

"The frontend sends the cart to the backend."

"The backend checks the product prices."

"The database saves the order."

"The frontend displays the order confirmation."

Avoid explanations that only list technical terms without showing how they connect.

# ARCHITECTURE DIAGRAMS

Use Mermaid diagrams when they improve understanding.

Create diagrams for:

- Overall system architecture.
- Application startup.
- Important request flows.
- Database and service relationships.
- Background processing, if present.

Keep diagrams simple.

After each diagram, explain the flow in numbered steps.

Do not create diagrams that include components that do not exist in the repository.

# REPOSITORY OUTPUT FORMAT

Save the documents in a folder named `Knowledge Bytes` at the project root.

Use filenames similar to these:

Knowledge Bytes/
  01-system-overview.md
  02-project-structure.md
  03-application-startup.md
  04-request-and-data-flow.md
  05-frontend-routing-and-state.md
  06-api-communication.md
  07-backend-controllers-and-persistence.md
  08-authentication-and-authorization.md
  09-main-feature-workflow.md
  10-testing-and-debugging.md

These names are examples. Change the list to match the actual project.

Create a `Knowledge Bytes/README.md` index that contains a Markdown table with:

| Document | What I will learn | Commit |
|---|---|---|

For every document, include:

- Its sequential number.
- Its filename as a relative Markdown link.
- A one-line description of its content.
- The Git commit hash that introduced the document, if a commit exists.

Use a relative link such as:

`[01-system-overview.md](01-system-overview.md)`

Do not invent commit hashes. If the documents are not committed, leave the commit field blank or write `Not committed`.

The index must help me understand which document to read next.

# WORKING WITH GIT

If Git is available:

1. Check the current branch and working tree.
2. Preserve all existing project changes.
3. Do not overwrite existing documentation without inspection.
4. Create the Knowledge Bytes documents in small, logical groups.
5. Review every document for correct file paths and code references.
6. Run relevant checks if the documentation or examples require them.
7. Commit documentation only when requested or authorized.
8. Update the index with real commit hashes after commits exist.

Do not reset the repository, delete user changes, or change application code just to create documentation.

# FINAL VERIFICATION

Before you finish:

- Confirm that every linked document exists.
- Confirm that document numbers are sequential.
- Confirm that code snippets match the actual repository.
- Confirm that architecture diagrams match the actual implementation.
- Confirm that the documents explain how the main components connect.
- Confirm that the index links work.
- Identify important areas that you could not verify.
- Summarize which documents you created and what each one teaches.

# MOST IMPORTANT REQUIREMENT

My main goal is to understand **how the entire project works as one system**.

Do not start by explaining random functions or individual code files.

First show me the architecture. Then show me the project structure. Then explain application startup. Then trace the flow between the frontend, backend, database, and other services. Finally, explain each feature through small, numbered Knowledge Bytes.

Make the documents simple enough that I can read them in order and gradually understand the project without needing a senior developer to explain every step.

Start by inspecting the repository. Then create the architecture documents first.
