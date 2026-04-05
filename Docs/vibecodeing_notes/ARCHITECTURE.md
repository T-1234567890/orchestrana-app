# Calendar, Reminders, and Todo System Architecture

## Overview

This document describes the unified Calendar, Reminders, and Todo system for the Orchestrana macOS app. The design prioritizes clarity, user control, and proper separation of concerns.

## Core Design Principles

### 1. Todo as Primary Model
- **TodoItem** is the app's primary task data model
- App functions fully without any external permissions
- All task management happens within the app first

### 2. Reminders as Optional Sync Layer
- Apple Reminders is a **sync layer**, not a replacement
- Syncing is bidirectional when authorized
- Tasks can be created, edited, and completed without Reminders access
- Sync status is clearly indicated per task

### 3. Calendar as Separate Feature
- Calendar focuses on **time-based events** and schedules
- Calendar does NOT replace the Todo list
- Calendar is unavailable without authorization (blocking behavior)
- Clear unauthorized state with enable button

## Data Model Relationships

```
┌─────────────────────────────────────────────────────────────┐
│                    Orchestrana                             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐  │
│  │              TodoStore (Primary)                    │  │
│  │                                                      │  │
│  │  - Manages all TodoItem instances                   │  │
│  │  - Persists to UserDefaults                         │  │
│  │  - Always accessible                                │  │
│  │  - Source of truth for tasks                        │  │
│  └─────────────────────────────────────────────────────┘  │
│                         │                                   │
│                         │ (optional sync)                   │
│                         ▼                                   │
│  ┌─────────────────────────────────────────────────────┐  │
│  │          RemindersSync (Optional)                   │  │
│  │                                                      │  │
│  │  - Syncs TodoItems ↔ EKReminder                    │  │
│  │  - Only active when authorized                      │  │
│  │  - Links via remindersIdentifier                    │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐  │
│  │       CalendarManager (Separate Feature)            │  │
│  │                                                      │  │
│  │  - Reads EKEvent from system Calendar               │  │
│  │  - Displays time-based events                       │  │
│  │  - Blocked when unauthorized                        │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### TodoItem Structure
```swift
struct TodoItem {
    let id: UUID
    var title: String
    var notes: String?
    var isCompleted: Bool
    var dueDate: Date?
    var priority: Priority
    var createdAt: Date
    var modifiedAt: Date
    
    // Optional Reminders link
    var remindersIdentifier: String?
}
```

## Permission Management

### PermissionsManager
Centralized permission handling for:
- **Notifications** → UNUserNotificationCenter
- **Calendar** → EKEventStore.authorizationStatus(for: .event)
- **Reminders** → EKEventStore.authorizationStatus(for: .reminder)

### Permission Flow
1. Check authorization status via EventKit/UNUserNotificationCenter
2. If `.notDetermined`, `requestAccess` may show system prompt once
3. All other states → Open System Settings directly
4. Primary UX is System Settings, not in-app prompts

### Status Indicators Shown In:
1. **Settings View** - Centralized permission overview
2. **Calendar View** - Contextual status (blocking)
3. **Todo View** - Contextual status (non-blocking banner)

## UI Behavior

### Settings View
- Shows all three permissions (Notifications, Calendar, Reminders)
- Each permission shows current status
- "Enable" buttons open System Settings
- Authorized permissions show green checkmark and disabled button

### Calendar View
**When Authorized:**
- Displays events from system Calendar
- Toggle between Today / Week views
- Shows event details (title, time, calendar)

**When Unauthorized:**
- Blocking unavailable state
- Explanation text
- "Enable Calendar Access" button
- Opens System Settings on click

### Todo/Tasks View
**Always Accessible:**
- Add, edit, complete, delete tasks
- Works without any permissions
- Full task management functionality

**When Reminders Unauthorized:**
- Orange banner at top (non-blocking)
- Explains sync is disabled
- "Enable" button opens System Settings
- Tasks still fully functional

**When Reminders Authorized:**
- No banner shown
- Tasks can be individually synced to Reminders
- Sync status shown per task
- Menu option to sync/unsync

## Code Organization

### Core Models
- `TodoItem.swift` - Primary task data model
- `TodoStore.swift` - Task storage and CRUD operations
- `PermissionsManager.swift` - Centralized permission handling
- `RemindersSync.swift` - Optional Reminders sync layer
- `CalendarManager.swift` - Calendar event fetching

### Views
- `SettingsPermissionsView.swift` - Centralized permission overview
- `TodoListView.swift` - Task list with optional sync banner
- `CalendarView.swift` - Calendar events (blocking when unauthorized)

## Usage Examples

### Adding a Task
```swift
let store = TodoStore()
let item = TodoItem(title: "Focus session", priority: .high)
store.addItem(item)
```

### Syncing to Reminders (when authorized)
```swift
let sync = RemindersSync()
try await sync.syncToReminders(item)
```

### Fetching Calendar Events
```swift
let calendar = CalendarManager()
await calendar.fetchTodayEvents()
```

### Checking Permissions
```swift
let permissions = PermissionsManager.shared
if permissions.isCalendarAuthorized {
    // Show calendar
} else {
    // Show unauthorized state
}
```

## Testing Checklist

- [ ] Todo list works without any permissions
- [ ] Calendar view blocks without authorization
- [ ] Todo view shows banner without Reminders authorization
- [ ] Settings shows all three permission statuses
- [ ] Enable buttons open System Settings
- [ ] Tasks sync to Reminders when authorized
- [ ] Tasks show sync status indicator
- [ ] Calendar displays events when authorized
- [ ] Permission refresh on view appear

## macOS-Specific Notes

- Uses EventKit framework for Calendar and Reminders
- Uses UNUserNotificationCenter for Notifications
- System Settings opened via `x-apple.systempreferences:` URL scheme
- NSWorkspace.shared.open() for external URL opening
- No iOS-specific concepts (no UIKit, no iOS-only APIs)

## Future Enhancements

- Bidirectional sync (Reminders → Todo)
- Calendar event creation from app
- Recurring task support
- Task categories/tags
- Search and filtering
- Task attachments
