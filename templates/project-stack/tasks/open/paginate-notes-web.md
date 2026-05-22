<!--
TEMPLATE — example task file. The folder this file lives in is the task's
state: open/ -> doing/ -> done/. Move the file between folders to change state.
`title` is what the backlog scan reads — keep it a short, specific imperative.
`goal` links to a goal in README.md. `issue` is optional — link a GitHub issue
rather than duplicating its content. Keep the body to one paragraph (~4-5
sentences). Delete these comments in real files.
-->
---
title: Paginate the notes list in notes-web
created: 2026-01-15
goal: primary — ship the notes app
issue: https://github.com/example/notes-web/issues/42
---

Update `notes-web` to send the new `page` query parameter on the notes-list
endpoint so long lists are paginated instead of loaded all at once. The API
side already supports it — `notes-api` accepts `page` and returns a `total`
count in the response, so this is a client-only change. Add prev/next controls
to the list view and keep the current page in the URL so it survives a reload.
Done when a list of 200+ notes loads one page at a time and the controls work.
