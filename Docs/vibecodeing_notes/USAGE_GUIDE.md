# Calendar, Reminders, and Todo System - Usage Guide

## Quick Start

The Orchestrana app now includes a unified Calendar, Reminders, and Todo system. Here's how to use it:

### Tasks View (Always Accessible)

The Tasks view is your primary task management interface. It works without any permissions.

**Features:**
- Add, edit, complete, and delete tasks
- Set task priorities (None, Low, Medium, High)
- Add notes and due dates
- Optional sync with Apple Reminders (when authorized)

**To access:**
1. Click "Tasks" in the sidebar
2. Click "Add Task" button to create a new task
3. Click the circle to mark tasks complete
4. Use the menu (•••) for more options

**Reminders Sync:**
- If Reminders access is not granted, you'll see an orange banner at the top
- Tasks still work fully without Reminders access
- To enable sync: Click "Enable" button or go to Settings
- Once authorized, use the menu to sync individual tasks

### Calendar View (Requires Permission)

The Calendar view displays your time-based events from the system Calendar.

**When Unauthorized:**
- Shows an unavailable state with explanation
- "Enable Calendar Access" button opens System Settings
- Calendar feature is blocked until permission is granted

**When Authorized:**
- View today's events or the current week
- See event details (title, time, calendar)
- Events are read-only (viewing only)

**To access:**
1. Click "Calendar" in the sidebar
2. If unauthorized, click "Enable Calendar Access"
3. Grant permission in System Settings
4. Return to the app - calendar will load automatically

### Settings (Permission Overview)

The Settings view provides a centralized permission overview.

**Shows status for:**
- Notifications (for session-end alerts)
- Calendar (for viewing events)
- Reminders (for optional task sync)

**Permission Status:**
- Green checkmark = Authorized
- Orange/Gray = Not authorized
- "Enable" button = Opens System Settings

**To manage permissions:**
1. Click "Settings" in the sidebar
2. Review current permission statuses
3. Click "Enable" for any unauthorized permission
4. Grant permission in System Settings
5. Return to app - status updates automatically

## Permission Behavior Summary

### Notifications
- **Purpose:** Session-end alerts and reminders
- **Behavior:** Request shows once, then opens System Settings
- **Impact:** App works without notifications

### Calendar
- **Purpose:** View time-based events and schedules
- **Behavior:** Calendar view is blocked without permission
- **Impact:** Can't use Calendar feature without authorization

### Reminders
- **Purpose:** Optional sync with Apple Reminders
- **Behavior:** Non-blocking banner in Tasks view
- **Impact:** Tasks work fully without Reminders access

## Design Principles

1. **Todo First:** Tasks work without any permissions
2. **Reminders as Optional:** Sync is convenience, not requirement
3. **Calendar Separate:** Time-based events are distinct from tasks
4. **Clear Status:** Permission state always visible
5. **System Settings:** Primary UX for permission management

## Common Workflows

### Basic Task Management (No Permissions)
1. Open Tasks view
2. Add tasks with "Add Task" button
3. Complete tasks by clicking the circle
4. Manage tasks with the menu

### Task + Reminders Sync
1. Enable Reminders in Settings
2. Open Tasks view
3. Click menu on a task
4. Select "Sync to Reminders"
5. Task appears in Apple Reminders app

### Calendar + Tasks Together
1. Enable Calendar in Settings
2. View events in Calendar view
3. Switch to Tasks view to manage tasks
4. Both features work independently

### Full Integration
1. Enable all permissions in Settings
2. View events in Calendar
3. Manage tasks in Tasks with Reminders sync
4. Get notifications for session-end

## Troubleshooting

**"Calendar Unavailable" shown:**
- Calendar permission not granted
- Click "Enable Calendar Access" button
- Grant permission in System Settings

**"Reminders Sync Disabled" banner:**
- Reminders permission not granted
- Tasks still work normally
- Click "Enable" to open System Settings

**Permission status not updating:**
- Close and reopen the app
- Settings view refreshes on appear
- Or click the view again to refresh

**Task not syncing to Reminders:**
- Check Reminders permission in Settings
- Use menu on task → "Sync to Reminders"
- Check Apple Reminders app

## Architecture Overview

```
App Structure:
├── Tasks (TodoStore)
│   ├── Always accessible
│   ├── Stored locally
│   └── Optional → Reminders sync
│
├── Calendar (CalendarManager)
│   ├── Requires permission
│   ├── Read-only events
│   └── Separate from tasks
│
└── Settings (PermissionsManager)
    ├── Notifications status
    ├── Calendar status
    └── Reminders status
```

## macOS-Specific Notes

- Uses EventKit framework for Calendar and Reminders
- System Settings opened via URL scheme
- No iOS-specific concepts used
- Native macOS permissions flow

## Future Enhancements

Potential additions in future versions:
- Bidirectional Reminders sync (Reminders → Tasks)
- Calendar event creation from app
- Recurring tasks
- Task categories and tags
- Search and filtering
- Task attachments
- Calendar integration with tasks (tasks with time)
