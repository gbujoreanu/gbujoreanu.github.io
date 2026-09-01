# Daymark Tracker

Daymark is an account-based personal productivity workspace built from the original yellow-and-black TimeTrack course project.

## Product model

- **Tasks** have a title, notes, due date/time, priority, completion state, and a calendar visibility setting.
- **Goals** have a title, notes, target date, and progress percentage.
- **Events** are standalone calendar commitments with a date and optional time.
- **Calendar entries** are derived from those records. Editing or deleting a dated task or goal updates the calendar automatically instead of maintaining a duplicate event.
- **Overview metrics** are derived from the same records: completion rate, open and overdue tasks, items due today, active goal progress, focus queue, and the next seven days.

## Persistence

The app requires a confirmed Supabase account. Tasks, goals, and events are stored in user-owned tables protected by Row Level Security. The legacy `daymark-v1` browser record is read only as an optional one-time migration source. Export and guarded import provide portable JSON backups.

## Run locally

Serve the repository root with any static web server and open `/tracker/`.
