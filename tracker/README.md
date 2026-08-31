# Daymark Tracker

Daymark is a browser-based personal productivity workspace built from the original yellow-and-black TimeTrack course project.

## Product model

- **Tasks** have a title, notes, due date/time, priority, completion state, and a calendar visibility setting.
- **Goals** have a title, notes, target date, and progress percentage.
- **Events** are standalone calendar commitments with a date and optional time.
- **Calendar entries** are derived from those records. Editing or deleting a dated task or goal updates the calendar automatically instead of maintaining a duplicate event.
- **Overview metrics** are derived from the same records: completion rate, open and overdue tasks, items due today, active goal progress, focus queue, and the next seven days.

## Persistence

The app stores its data in `localStorage` under `daymark-v1`. Export and import provide a JSON backup for moving between browsers or devices. Reset removes all tracker data from the current browser.

## Run locally

Serve the repository root with any static web server and open `/tracker/`.
