# Daymark Tracker

Daymark is an account-based personal productivity workspace built from the original yellow-and-black TimeTrack course project.

## Product model

- **Tasks** have a title, notes, due date/time, priority, completion state, and a calendar visibility setting.
- **Goals** have a title, notes, target date, and progress percentage.
- **Events** are standalone calendar commitments with a date and optional time.
- **Schedule entries** are timezone-aware blocks of planned or recorded time with a start, end, duration, and optional notes.
- **Scheduler** combines timed tasks and schedule entries on a 24-hour day view while keeping goals and untimed tasks above the timeline.
- **Calendar entries** are derived from those records. Editing a task or schedule entry updates every view automatically instead of maintaining duplicate records.
- **Overview metrics** are derived from the same records: completion rate, open and overdue tasks, items due today, active goal progress, focus queue, and the next seven days.

## Persistence

The app requires a confirmed Supabase account. Tasks, goals, events, and schedule entries are stored in user-owned tables protected by Row Level Security. The legacy `daymark-v1` browser record is read only as an optional one-time migration source. Interface preferences remain device-local.

## Run locally

Serve the repository root with any static web server and open `/tracker/`.
