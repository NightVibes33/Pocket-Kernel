import Foundation

enum TemplateCatalog {
    static let all: [MicroAppBlueprint] = [taskBoardBlueprint, habitTrackerBlueprint, quickJournalBlueprint, inventoryBlueprint, serviceLogBlueprint]

    static let taskBoardBlueprint = MicroAppBlueprint(
        name: "Task Board",
        summary: "Plan work, track status, and review completed tasks.",
        screens: [
            .init(id: "dashboard", title: "Task Board", collectionID: "tasks"),
            .init(id: "all-tasks", title: "All Tasks", collectionID: "tasks")
        ],
        collections: [
            .init(id: "tasks", title: "Tasks", fields: [
                .init(id: "title", title: "Title", kind: .text),
                .init(id: "status", title: "Status", kind: .choice),
                .init(id: "dueDate", title: "Due Date", kind: .date),
                .init(id: "notes", title: "Notes", kind: .multilineText)
            ])
        ],
        actions: [.init(id: "add-task", title: "Add Task", kind: .createRecord, target: "tasks")]
    )

    static let habitTrackerBlueprint = MicroAppBlueprint(
        name: "Habit Tracker",
        summary: "Track daily habits and completed check-ins.",
        screens: [.init(id: "habits", title: "Habits", collectionID: "habits")],
        collections: [.init(id: "habits", title: "Habits", fields: [
            .init(id: "name", title: "Habit", kind: .text),
            .init(id: "completed", title: "Completed", kind: .boolean),
            .init(id: "checkInDate", title: "Check-in Date", kind: .date)
        ])],
        actions: [.init(id: "add-habit", title: "Add Habit", kind: .createRecord, target: "habits")]
    )

    static let quickJournalBlueprint = MicroAppBlueprint(
        name: "Quick Journal",
        summary: "Keep private dated journal entries on device.",
        screens: [.init(id: "journal", title: "Journal", collectionID: "entries")],
        collections: [.init(id: "entries", title: "Entries", fields: [
            .init(id: "date", title: "Date", kind: .date),
            .init(id: "title", title: "Title", kind: .text),
            .init(id: "entry", title: "Entry", kind: .multilineText)
        ])],
        actions: [.init(id: "add-entry", title: "New Entry", kind: .createRecord, target: "entries")]
    )

    static let inventoryBlueprint = MicroAppBlueprint(
        name: "Inventory List",
        summary: "Track items, quantities, locations, and notes.",
        screens: [.init(id: "inventory", title: "Inventory", collectionID: "items")],
        collections: [.init(id: "items", title: "Items", fields: [
            .init(id: "name", title: "Item", kind: .text),
            .init(id: "quantity", title: "Quantity", kind: .number),
            .init(id: "location", title: "Location", kind: .text),
            .init(id: "notes", title: "Notes", kind: .multilineText)
        ])],
        actions: [.init(id: "add-item", title: "Add Item", kind: .createRecord, target: "items")]
    )

    static let serviceLogBlueprint = MicroAppBlueprint(
        name: "Service Log",
        summary: "Track vehicle maintenance, cost, mileage, and reminders.",
        screens: [
            .init(id: "overview", title: "Service Overview", collectionID: "services"),
            .init(id: "history", title: "Service History", collectionID: "services")
        ],
        collections: [.init(id: "services", title: "Services", fields: [
            .init(id: "mileage", title: "Mileage", kind: .number),
            .init(id: "serviceDate", title: "Service Date", kind: .date),
            .init(id: "cost", title: "Cost", kind: .number),
            .init(id: "notes", title: "Notes", kind: .multilineText),
            .init(id: "nextService", title: "Next Service", kind: .date)
        ])],
        actions: [.init(id: "add-service", title: "Add Service", kind: .createRecord, target: "services")]
    )
}
