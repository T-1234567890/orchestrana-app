import AppKit
import AVKit
import Combine
import MarkdownUI
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private enum NotesSortOrder: String, CaseIterable, Identifiable {
    case manual
    case updated
    case created
    case title
    case pinned

    var id: String { rawValue }
}

private enum NotesLinkFilter: String, CaseIterable, Identifiable {
    case all
    case linked
    case unlinked

    var id: String { rawValue }
}

private enum NoteSaveState: Equatable {
    case saved
    case saving
    case failed
}

private enum MarkdownEditorMode: String, CaseIterable, Identifiable {
    case edit
    case preview

    var id: String { rawValue }
}

private enum NotesListEmptyState: Equatable {
    case notes
    case archived
    case results
}

private enum NotesFolderSelection: Equatable {
    case all
    case folder(UUID)
}

private enum NotesOutlineItemID: Hashable {
    case folder(UUID)
    case note(UUID)
}

private struct NotesOutlineDropDelegate: DropDelegate {
    let target: NotesOutlineItemID
    @Binding var draggedItem: NotesOutlineItemID?
    @Binding var targetedItem: NotesOutlineItemID?
    let onEntered: (NotesOutlineItemID, NotesOutlineItemID) -> Void
    let onDropped: (NotesOutlineItemID, NotesOutlineItemID) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        draggedItem != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem, draggedItem != target else { return }
        targetedItem = target
        onEntered(draggedItem, target)
    }

    func dropExited(info: DropInfo) {
        if targetedItem == target { targetedItem = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedItem else { return false }
        let handled = onDropped(draggedItem, target)
        self.draggedItem = nil
        targetedItem = nil
        return handled
    }
}

private enum MarkdownAction: Equatable {
    case heading
    case bold
    case italic
    case strikethrough
    case bulletList
    case numberedList
    case checklist
    case quote
    case inlineCode
    case codeBlock
    case link
    case image
    case embed
    case orchestranaLink(MarkdownLinkTarget.Kind)
    case table
    case tableRow
    case tableColumn
    case divider
    case insertText(String)
}

private struct MarkdownCommand: Equatable {
    let id = UUID()
    let action: MarkdownAction
}

private struct MarkdownEditorAttachment: Identifiable {
    let record: NoteAttachmentRecord
    let url: URL
    var id: UUID { record.id }
}

private struct MarkdownLinkTarget: Identifiable, Equatable {
    enum Kind: String, Equatable { case goal, task, event }
    let id: UUID
    let kind: Kind
    let title: String
    let detail: String
    let filters: Set<String>

    var replacement: String {
        let safeTitle = title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "]", with: ")")
            .replacingOccurrences(of: "|", with: "-")
        return "[[\(kind.rawValue):\(id.uuidString)|\(safeTitle)]]"
    }
}

private struct MarkdownEditorSuggestion: Identifiable, Equatable {
    enum Kind { case symbol, markdown, link, linkFilter, tag, customSyntax }
    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let symbolName: String
    let replacement: String
    let replacementRange: NSRange
    let ghostText: String
    let cursorOffset: Int?

    init(
        id: String,
        kind: Kind,
        title: String,
        detail: String,
        symbolName: String,
        replacement: String,
        replacementRange: NSRange,
        ghostText: String,
        cursorOffset: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
        self.replacement = replacement
        self.replacementRange = replacementRange
        self.ghostText = ghostText
        self.cursorOffset = cursorOffset
    }
}

private struct MarkdownEditorLocalization {
    let markdown: String
    let tag: String
    let customSyntax: String
    let template: String
    let pasteAsTable: String
    let pasteAsPlainText: String
    let filter: String
    let active: String
    let paused: String
    let completed: String
    let upcoming: String
    let past: String
    let goal: String
    let task: String
    let event: String
    let copy: String
    let cut: String
    let resize: String
    let showFrame: String
    let hideFrame: String
    let play: String
    let pause: String
}

private struct MarkdownLinkPill: Equatable {
    enum Tone: Equatable {
        case goal, task, event
        case active, paused, completed, upcoming, past
    }

    let range: NSRange
    let tone: Tone
    let label: String

    init(range: NSRange, kind: MarkdownLinkTarget.Kind, label: String) {
        self.range = range
        self.label = label
        switch kind {
        case .goal: tone = .goal
        case .task: tone = .task
        case .event: tone = .event
        }
    }

    init(range: NSRange, filterValue: String, label: String) {
        self.range = range
        self.label = label
        switch filterValue {
        case "active": tone = .active
        case "paused": tone = .paused
        case "completed": tone = .completed
        case "upcoming": tone = .upcoming
        default: tone = .past
        }
    }

    private var font: NSFont { .systemFont(ofSize: 11, weight: .semibold) }
    var width: CGFloat {
        ceil((label as NSString).size(withAttributes: [.font: font]).width) + 16
    }
    var layoutWidth: CGFloat { width + 4 }

    var color: NSColor {
        switch tone {
        case .goal, .upcoming: return .systemBlue
        case .task, .active: return .systemGreen
        case .event, .paused: return .systemOrange
        case .completed: return .systemPurple
        case .past: return .systemGray
        }
    }

    func frame(at caretRect: NSRect) -> NSRect {
        let height = min(17, max(15, caretRect.height))
        return NSRect(
            x: caretRect.minX,
            y: caretRect.minY + max(0, (caretRect.height - height) / 2),
            width: width,
            height: height
        )
    }

    func draw(at caretRect: NSRect) {
        let frame = frame(at: caretRect)
        let path = NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5)
        color.withAlphaComponent(0.16).setFill()
        path.fill()
        color.withAlphaComponent(0.32).setStroke()
        path.lineWidth = 0.75
        path.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let textSize = (label as NSString).size(withAttributes: attributes)
        label.draw(at: NSPoint(
            x: frame.minX + 8,
            y: frame.midY - textSize.height / 2
        ), withAttributes: attributes)
    }
}

private struct NoteJSONExport: Codable {
    let note: NoteRecord
    let tags: [NoteTagRecord]
    let attachments: [NoteAttachmentRecord]
}

private enum LinkedWorkDestination {
    case goal(UUID)
    case task(UUID)
    case event(UUID, Date?)
    case session(UUID)
    case day(Date)
}

private struct LinkedWorkDisplay: Identifiable {
    let id: String
    let title: String
    let icon: String
    let destination: LinkedWorkDestination
}

@MainActor
struct NotesWorkspaceView: View {
    @ObservedObject var noteStore: NoteStore
    @ObservedObject var goalStore: GoalStore
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var planningStore: PlanningStore
    @ObservedObject var sessionRecordStore: SessionRecordStore
    @ObservedObject var featureGate: FeatureGate

    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
    @AppStorage("notes.workspace.listCollapsed") private var isNotesListCollapsed = false

    @State private var selectedNoteID: UUID?
    @State private var selectedOutlineItems: Set<NotesOutlineItemID> = []
    @State private var outlineSelectionAnchor: NotesOutlineItemID?
    @State private var draggedOutlineItem: NotesOutlineItemID?
    @State private var outlineDropTarget: NotesOutlineItemID?
    @State private var outlineDropAfterTarget = false
    @State private var searchText = ""
    @State private var selectedTagID: UUID?
    @State private var selectedType: NoteRecord.NoteType?
    @State private var folderSelection = NotesFolderSelection.all
    @State private var linkFilter = NotesLinkFilter.all
    @State private var sortOrder = NotesSortOrder.manual
    @State private var showsArchived = false
    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var autosaveTask: Task<Void, Never>?
    @State private var saveState = NoteSaveState.saved
    @State private var isLoadingDraft = false
    @State private var rowTagPickerNoteID: UUID?
    @State private var editorTagPickerPresented = false
    @State private var pendingDeleteNoteID: UUID?
    @State private var markdownCommand: MarkdownCommand?
    @State private var markdownMode = MarkdownEditorMode.edit
    @State private var editingFolderID: UUID?
    @State private var newlyCreatedFolderID: UUID?
    @State private var folderNameDraft = ""
    @State private var collapsedFolderIDs: Set<UUID> = []
    @State private var pendingDeleteFolder: NoteFolderRecord?
    @State private var upgradePaywallContext: SubscriptionPaywallContext?
    @State private var isAttachmentImporterPresented = false
    @State private var isAINoticePresented = false

    private var appearanceMode: AppearanceMode {
        AppearanceMode.resolved(from: appearanceModeRawValue)
    }

    private var selectedNote: NoteRecord? {
        guard let selectedNoteID else { return nil }
        return noteStore.notes.first { $0.id == selectedNoteID }
    }

    private var filteredNotes: [NoteRecord] {
        var result = noteStore.notes.filter { note in
            (showsArchived ? note.isArchived : !note.isArchived)
                && (selectedTagID == nil || note.tagIDs.contains(selectedTagID!))
                && (selectedType == nil || note.noteType == selectedType)
                && linkFilter.includes(note)
                && matchesSearch(note)
        }

        switch sortOrder {
        case .manual:
            result.sort {
                if $0.folderID != $1.folderID {
                    return ($0.folderID?.uuidString ?? "") < ($1.folderID?.uuidString ?? "")
                }
                return $0.manualOrder < $1.manualOrder
            }
        case .updated:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .created:
            result.sort { $0.createdAt > $1.createdAt }
        case .title:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .pinned:
            result.sort {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.updatedAt > $1.updatedAt
            }
        }
        return result
    }

    private var visibleOutlineItemIDs: [NotesOutlineItemID] {
        var result: [NotesOutlineItemID] = []
        var visited: Set<UUID> = []

        func appendFolder(_ folder: NoteFolderRecord) {
            guard visited.insert(folder.id).inserted else { return }
            result.append(.folder(folder.id))
            guard !collapsedFolderIDs.contains(folder.id) else { return }
            for child in noteStore.folders.filter({ $0.parentFolderID == folder.id }) {
                appendFolder(child)
            }
            result.append(contentsOf: filteredNotes.filter { $0.folderID == folder.id }.map { .note($0.id) })
        }

        for folder in noteStore.folders(in: nil) { appendFolder(folder) }
        result.append(contentsOf: filteredNotes.filter { $0.folderID == nil }.map { .note($0.id) })
        return result
    }

    private var canCreateUnlimitedNotes: Bool {
        featureGate.canCreateUnlimitedNotes
    }

    private var activeNoteCount: Int {
        noteStore.notes.lazy.filter { !$0.isArchived }.count
    }

    private var canCreateAnotherNote: Bool {
        canCreateUnlimitedNotes || activeNoteCount < 10
    }

    private var editableFreeNoteIDs: Set<UUID> {
        Set(
            noteStore.notes
                .filter { !$0.isArchived }
                .sorted { lhs, rhs in
                    if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .prefix(10)
                .map(\.id)
        )
    }

    private func isNoteEditable(_ note: NoteRecord) -> Bool {
        guard !note.isArchived else { return false }
        return canCreateUnlimitedNotes || editableFreeNoteIDs.contains(note.id)
    }

    private var canUseSyntaxAutocomplete: Bool {
        featureGate.canUseNotesSyntaxAutocomplete
    }

    private var canUseCustomSyntax: Bool {
        featureGate.canUseNotesProFeatures
    }

    private var markdownLinkTargets: [MarkdownLinkTarget] {
        let goals = goalStore.goals.map {
            MarkdownLinkTarget(
                id: $0.id,
                kind: .goal,
                title: $0.outcome,
                detail: $0.status.title + ($0.targetDate.map { " · " + $0.formatted(date: .abbreviated, time: .omitted) } ?? ""),
                filters: [$0.status.rawValue]
            )
        }
        let tasks = todoStore.items.map {
            MarkdownLinkTarget(
                id: $0.id,
                kind: .task,
                title: $0.title,
                detail: $0.isCompleted ? languageManager.text("workspace.notes.link.completed") : languageManager.text("workspace.notes.link.active"),
                filters: [$0.isCompleted ? "completed" : "active"]
            )
        }
        let events = planningStore.items.filter(\.isCalendarEvent).map {
            let referenceDate = $0.endDate ?? $0.startDate
            let timeFilter = referenceDate.map { $0 < Date() ? "past" : "upcoming" }
            return MarkdownLinkTarget(
                id: $0.id,
                kind: .event,
                title: $0.title,
                detail: $0.startDate?.formatted(date: .abbreviated, time: .shortened) ?? languageManager.text("workspace.notes.link.no_date"),
                filters: timeFilter.map { Set([$0]) } ?? []
            )
        }
        return goals + tasks + events
    }

    private var effectiveEditorSettings: NoteEditorSettingsRecord {
        var settings = noteStore.editorSettings
        if !canUseCustomSyntax { settings.sourceModeEnabled = false }
        switch settings.selectedStyle {
        case .default: break
        case .minimal: settings.editorLineWidth = 680; settings.paragraphSpacing = 8
        case .compact: settings.editorLineWidth = 920; settings.paragraphSpacing = 2
        case .academic: settings.editorLineWidth = 720; settings.paragraphSpacing = 11
        case .technical: settings.editorLineWidth = 900; settings.paragraphSpacing = 4
        case .journal: settings.editorLineWidth = 640; settings.paragraphSpacing = 13
        case .focused: settings.editorLineWidth = 600; settings.paragraphSpacing = 9
        }
        return settings
    }

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            Divider()
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    if !isNotesListCollapsed {
                        notesColumn
                            .frame(width: min(430, max(300, proxy.size.width * 0.34)))
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Divider()
                    }

                    editorColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0),
                    value: isNotesListCollapsed
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 560, maxHeight: .infinity, alignment: .topLeading)
        .appRoundedSurface(
            mode: appearanceMode,
            cornerRadius: 10,
            standardLevel: .panel,
            showsShadow: false
        )
        .onAppear {
            if selectedNoteID == nil {
                let initialNote = filteredNotes.first ?? noteStore.notes.first
                selectNote(initialNote)
                if let initialNote {
                    selectedOutlineItems = [.note(initialNote.id)]
                    outlineSelectionAnchor = .note(initialNote.id)
                }
            }
        }
        .onDisappear {
            if let editingFolderID,
               let folder = noteStore.folder(withID: editingFolderID) {
                commitFolderRename(folder)
            }
            autosaveTask?.cancel()
            _ = saveDraft()
        }
        .onChange(of: draftTitle) { _, _ in scheduleAutosave() }
        .onChange(of: draftBody) { _, _ in scheduleAutosave() }
        .onChange(of: featureGate.tier) { _, _ in
            autosaveTask?.cancel()
            editorTagPickerPresented = false
            rowTagPickerNoteID = nil
            if let selectedNote {
                if !isNoteEditable(selectedNote) {
                    markdownMode = .preview
                }
                isLoadingDraft = true
                draftTitle = selectedNote.title
                draftBody = selectedNote.body
                saveState = .saved
                DispatchQueue.main.async { isLoadingDraft = false }
            }
        }
        .onChange(of: filteredNotes.map(\.id)) { _, visibleIDs in
            guard let selectedNoteID, !visibleIDs.contains(selectedNoteID) else { return }
            let replacement = filteredNotes.first
            selectNote(replacement)
            if let replacement {
                selectedOutlineItems = [.note(replacement.id)]
                outlineSelectionAnchor = .note(replacement.id)
            }
        }
        .onChange(of: visibleOutlineItemIDs) { _, visibleItems in
            let visibleSet = Set(visibleItems)
            selectedOutlineItems.formIntersection(visibleSet)
            if let outlineSelectionAnchor, !visibleSet.contains(outlineSelectionAnchor) {
                self.outlineSelectionAnchor = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceNoteFocusItem)) { notification in
            guard let rawID = notification.userInfo?["noteID"] as? String,
                  let noteID = UUID(uuidString: rawID),
                  let note = noteStore.notes.first(where: { $0.id == noteID }) else {
                return
            }
            showsArchived = showsArchived || note.isArchived
            selectNote(note)
            selectedOutlineItems = [.note(note.id)]
            outlineSelectionAnchor = .note(note.id)
        }
        .alert(
            languageManager.text("workspace.notes.delete.title"),
            isPresented: Binding(
                get: { pendingDeleteNoteID != nil },
                set: { if !$0 { pendingDeleteNoteID = nil } }
            )
        ) {
            Button(languageManager.text("common.cancel"), role: .cancel) {
                pendingDeleteNoteID = nil
            }
            Button(languageManager.text("common.delete"), role: .destructive) {
                confirmDelete()
            }
        } message: {
            Text(languageManager.text("workspace.notes.delete.message"))
        }
        .confirmationDialog(
            languageManager.text("workspace.notes.folders.delete.title"),
            isPresented: Binding(
                get: { pendingDeleteFolder != nil },
                set: { if !$0 { pendingDeleteFolder = nil } }
            )
        ) {
            Button(languageManager.text("common.delete"), role: .destructive) {
                deletePendingFolder()
            }
            Button(languageManager.text("common.cancel"), role: .cancel) {
                pendingDeleteFolder = nil
            }
        } message: {
            Text(languageManager.text("workspace.notes.folders.delete.message"))
        }
        .sheet(item: $upgradePaywallContext) { context in
            SubscriptionUpgradeSheetView(
                context: context,
                featureGate: featureGate,
                subscriptionStore: SubscriptionStore.shared
            )
        }
        .fileImporter(
            isPresented: $isAttachmentImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard let noteID = selectedNoteID, case let .success(urls) = result else { return }
            for url in urls { importAttachment(from: url, to: noteID) }
        }
    }

    private var pageHeader: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(selectedNotePath.enumerated()), id: \.offset) { index, component in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Text(component)
                            .fontWeight(index == selectedNotePath.count - 1 ? .semibold : .regular)
                            .foregroundStyle(index == selectedNotePath.count - 1 ? Color.primary : Color.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .contextMenu {
                    Button(languageManager.text("workspace.notes.path.show_in_finder")) {
                        revealNotesFileInFinder()
                    }
                    Button(languageManager.text("workspace.notes.path.copy")) {
                        copySelectedNotePath()
                    }
                }
            }
            .help(selectedMarkdownFileURL?.path ?? noteStore.storageDirectoryURL.path)

            Button {
                createBlankNote()
            } label: {
                Label(languageManager.text("workspace.notes.new"), systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private var selectedNotePath: [String] {
        var components = [
            languageManager.text(
                NotesNavigationFeature.mode == .thinking
                    ? "main.sidebar.thinking"
                    : "main.sidebar.workspace"
            ),
            languageManager.text("workspace.section.notes")
        ]
        guard let note = selectedNote else { return components }
        if let folder = noteStore.folder(withID: note.folderID) {
            components.append(contentsOf: folderPathComponents(folder))
        }
        components.append(note.title)
        return components
    }

    private var selectedMarkdownFileURL: URL? {
        guard let selectedNote else { return nil }
        return noteStore.markdownFileURL(for: selectedNote)
    }

    private var notesColumn: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                searchField
                listControlBar
            }
            .padding(10)

            Divider()
            notesOutline
        }
        .background(Color.primary.opacity(0.022))
    }

    private var notesOutline: some View {
        GeometryReader { proxy in
            let rowWidth = max(proxy.size.width - 12, 288)

            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(noteStore.folders(in: nil)) { folder in
                        NoteFolderTreeNode(
                            folder: folder,
                            folders: noteStore.folders,
                            notes: filteredNotes,
                            editingFolderID: $editingFolderID,
                            folderNameDraft: $folderNameDraft,
                            collapsedFolderIDs: $collapsedFolderIDs,
                            selectedOutlineItems: selectedOutlineItems,
                            draggedOutlineItem: $draggedOutlineItem,
                            outlineDropTarget: $outlineDropTarget,
                            rowWidth: rowWidth,
                            onSelect: selectOutlineFolder,
                            onDragStarted: beginOutlineDrag,
                            onDragEntered: handleOutlineDragEntered,
                            onDropItem: completeOutlineDrop,
                            onCreateNote: { createBlankNote(in: $0.id) },
                            onCreateChild: { beginCreatingFolder(parentFolderID: $0.id) },
                            onRename: beginRenamingFolder,
                            onCommitRename: commitFolderRename,
                            onCancelRename: cancelFolderRename,
                            onDelete: { pendingDeleteFolder = $0 },
                            languageManager: languageManager,
                            noteRow: { note, depth in
                                AnyView(outlineNoteRow(note, depth: depth, rowWidth: rowWidth))
                            }
                        )
                    }

                    ForEach(unfiledNotes) { note in
                        outlineNoteRow(note, depth: 0, rowWidth: rowWidth)
                    }

                    if filteredNotes.isEmpty {
                        listEmptyState
                            .frame(width: rowWidth)
                            .frame(minHeight: 150)
                    }
                }
                .frame(
                    minWidth: rowWidth,
                    minHeight: max(proxy.size.height - 12, 0),
                    alignment: .topLeading
                )
                .padding(6)
            }
            .defaultScrollAnchor(.topLeading)
        }
    }

    private var unfiledNotes: [NoteRecord] {
        filteredNotes.filter { $0.folderID == nil }
    }

    private func outlineNoteRow(_ note: NoteRecord, depth: Int, rowWidth: CGFloat) -> some View {
        let tags = noteStore.tags(for: note)

        return HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(note.title)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: true, vertical: false)

            ForEach(tags.prefix(2)) { tag in
                NoteTagChip(tag: tag, compact: true)
            }
            if tags.count > 2 {
                Text("+\(tags.count - 2)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                rowTagPickerNoteID = note.id
            } label: {
                Image(systemName: tags.isEmpty ? "tag" : "plus.circle")
                    .font(.caption)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(languageManager.text("workspace.notes.tags.edit"))
            .accessibilityLabel(languageManager.text("workspace.notes.tags.edit"))
            .disabled(!isNoteEditable(note))

            if note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !isNoteEditable(note) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 14)

            Text(lastEditedText(note.updatedAt))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .padding(.leading, depth == 0 ? 8 : CGFloat(depth) * 22 + 27)
        .padding(.trailing, 6)
        .frame(minWidth: rowWidth + CGFloat(depth) * 22, minHeight: 32, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            selectedOutlineItems.contains(.note(note.id))
                ? Color.accentColor.opacity(0.12)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(alignment: .leading) {
            NoteTreeIndentationGuides(depth: depth)
        }
        .overlay {
            if outlineDropTarget == .note(note.id), draggedOutlineItem != .note(note.id) {
                VStack(spacing: 0) {
                    if outlineDropAfterTarget { Spacer(minLength: 0) }
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .padding(.horizontal, 5)
                    if !outlineDropAfterTarget { Spacer(minLength: 0) }
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectOutlineNote(note)
        }
        .accessibilityAddTraits(selectedOutlineItems.contains(.note(note.id)) ? .isSelected : [])
        .contextMenu { noteContextMenu(note) }
        .popover(isPresented: rowTagPickerBinding(for: note.id), arrowEdge: .leading) {
            NoteTagPicker(
                noteID: note.id,
                noteStore: noteStore,
                languageManager: languageManager,
                onChange: { saved in deferredSaveStateUpdate(saved, noteID: note.id) }
            )
            .disabled(!isNoteEditable(note))
        }
        .onDrag {
            beginOutlineDrag(.note(note.id))
            return NSItemProvider(object: "note:\(note.id.uuidString)" as NSString)
        } preview: {
            Color.clear.frame(width: 1, height: 1)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: NotesOutlineDropDelegate(
                target: .note(note.id),
                draggedItem: $draggedOutlineItem,
                targetedItem: $outlineDropTarget,
                onEntered: handleOutlineDragEntered,
                onDropped: completeOutlineDrop
            )
        )
    }

    private var notesListToggleButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isNotesListCollapsed.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(languageManager.text(
            isNotesListCollapsed
                ? "workspace.notes.list.show"
                : "workspace.notes.list.hide"
        ))
        .accessibilityLabel(languageManager.text(
            isNotesListCollapsed
                ? "workspace.notes.list.show"
                : "workspace.notes.list.hide"
        ))
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(languageManager.text("workspace.notes.search"), text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel(languageManager.text("workspace.notes.search"))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(languageManager.text("workspace.notes.clear_search"))
                .accessibilityLabel(languageManager.text("workspace.notes.clear_search"))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Color.primary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var listControlBar: some View {
        HStack(spacing: 5) {
            filterMenu
            sortMenu

            Button {
                beginCreatingFolder(parentFolderID: selectedFolderIDForCreation)
            } label: {
                Image(systemName: "folder.badge.plus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(languageManager.text("workspace.notes.folders.new"))
            .accessibilityLabel(languageManager.text("workspace.notes.folders.new"))

            Spacer()

            Button {
                showsArchived.toggle()
            } label: {
                Image(systemName: showsArchived ? "archivebox.fill" : "archivebox")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(languageManager.text("workspace.notes.show_archived"))
            .accessibilityLabel(languageManager.text("workspace.notes.show_archived"))
        }
        .controlSize(.small)
        .tint(Color.secondary)
        .foregroundStyle(.secondary)
    }

    private var filterMenu: some View {
        Menu {
            Menu(languageManager.text("workspace.notes.filter.type")) {
                Button(languageManager.text("workspace.notes.filter.all_types")) { selectedType = nil }
                Divider()
                ForEach(NoteRecord.NoteType.allCases) { type in
                    Button {
                        selectedType = type
                    } label: {
                        Label(noteTypeTitle(type), systemImage: noteTypeIcon(type))
                    }
                }
            }

            Menu(languageManager.text("workspace.notes.filter.tag")) {
                Button(languageManager.text("workspace.notes.all_tags")) { selectedTagID = nil }
                Divider()
                ForEach(noteStore.tags) { tag in
                    Button {
                        selectedTagID = tag.id
                    } label: {
                        Label(tag.name, systemImage: tag.symbolName ?? "tag")
                    }
                }
            }

            Menu(languageManager.text("workspace.notes.filter.linked")) {
                ForEach(NotesLinkFilter.allCases) { filter in
                    Button(linkFilterTitle(filter)) { linkFilter = filter }
                }
            }

            if selectedType != nil || selectedTagID != nil || linkFilter != .all {
                Divider()
                Button(languageManager.text("workspace.notes.filter.clear")) {
                    selectedType = nil
                    selectedTagID = nil
                    linkFilter = .all
                }
            }
        } label: {
            Label(languageManager.text("workspace.notes.filter"), systemImage: hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(.secondary)
        .help(languageManager.text("workspace.notes.filter"))
        .accessibilityLabel(languageManager.text("workspace.notes.filter"))
    }

    private var sortMenu: some View {
        Menu {
            ForEach(NotesSortOrder.allCases) { order in
                Button {
                    sortOrder = order
                } label: {
                    if sortOrder == order {
                        Label(sortTitle(order), systemImage: "checkmark")
                    } else {
                        Text(sortTitle(order))
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(languageManager.text("workspace.notes.sort"))
        .accessibilityLabel(languageManager.text("workspace.notes.sort"))
    }

    private var listEmptyState: some View {
        let state = notesListEmptyState
        return VStack(spacing: 8) {
            Image(systemName: emptyStateIcon(state))
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(emptyStateTitle(state))
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
            if state == .notes {
                Button(languageManager.text("workspace.notes.new")) { createBlankNote() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }

    private var notesListEmptyState: NotesListEmptyState {
        if showsArchived, !noteStore.notes.contains(where: \.isArchived) {
            return .archived
        }
        if !showsArchived, !noteStore.notes.contains(where: { !$0.isArchived }) {
            return .notes
        }
        return .results
    }

    private func emptyStateIcon(_ state: NotesListEmptyState) -> String {
        switch state {
        case .notes: return "square.and.pencil"
        case .archived: return "archivebox"
        case .results: return "line.3.horizontal.decrease.circle"
        }
    }

    private func emptyStateTitle(_ state: NotesListEmptyState) -> String {
        switch state {
        case .notes: return languageManager.text("workspace.notes.empty.compact")
        case .archived: return languageManager.text("workspace.notes.empty.archived")
        case .results: return languageManager.text("workspace.notes.no_results")
        }
    }

    @ViewBuilder
    private var editorColumn: some View {
        if let note = selectedNote {
            let isEditable = isNoteEditable(note)
            VStack(spacing: 0) {
                editorHeader(note)
                Divider()
                if !isEditable {
                    readOnlyBanner(note)
                }
                titleField(note)
                markdownToolbar(isEditable: isEditable)
                Divider()
                if markdownMode == .edit && isEditable {
                    MarkdownTextEditor(
                        text: $draftBody,
                        command: $markdownCommand,
                        settings: effectiveEditorSettings,
                        autocompleteEnabled: canUseSyntaxAutocomplete,
                        customSyntaxEnabled: canUseCustomSyntax,
                        linkTargets: markdownLinkTargets,
                        tags: noteStore.tags,
                        customSyntaxDefinitions: noteStore.customSyntaxDefinitions,
                        syntaxTemplates: noteStore.syntaxTemplates,
                        attachments: noteStore.attachments.map {
                            MarkdownEditorAttachment(record: $0, url: noteStore.attachmentURL(for: $0))
                        },
                        localization: MarkdownEditorLocalization(
                            markdown: languageManager.text("workspace.notes.suggestion.markdown"),
                            tag: languageManager.text("workspace.notes.suggestion.tag"),
                            customSyntax: languageManager.text("workspace.notes.suggestion.custom_syntax"),
                            template: languageManager.text("workspace.notes.suggestion.template"),
                            pasteAsTable: languageManager.text("workspace.notes.paste_as_table"),
                            pasteAsPlainText: languageManager.text("workspace.notes.paste_as_plain_text"),
                            filter: languageManager.text("workspace.notes.filter"),
                            active: languageManager.text("workspace.notes.link.active"),
                            paused: languageManager.text("workspace.notes.link.paused"),
                            completed: languageManager.text("workspace.notes.link.completed"),
                            upcoming: languageManager.text("workspace.notes.link.upcoming"),
                            past: languageManager.text("workspace.notes.link.past"),
                            goal: languageManager.text("workspace.notes.source.goal"),
                            task: languageManager.text("workspace.notes.source.task"),
                            event: languageManager.text("workspace.notes.source.event"),
                            copy: languageManager.text("workspace.notes.attachments.copy"),
                            cut: languageManager.text("workspace.notes.attachments.cut"),
                            resize: languageManager.text("workspace.notes.attachments.resize"),
                            showFrame: languageManager.text("workspace.notes.attachments.show_frame"),
                            hideFrame: languageManager.text("workspace.notes.attachments.hide_frame"),
                            play: languageManager.text("workspace.notes.attachments.play"),
                            pause: languageManager.text("workspace.notes.attachments.pause")
                        ),
                        onOpenURL: openAppLinkURL,
                        onPasteImage: { data in importPastedImage(data, to: note.id) },
                        onPasteFile: { url in importPastedFile(url, to: note.id) },
                        onResizeAttachment: { attachmentID, width in
                            _ = noteStore.updateAttachmentDisplayWidth(attachmentID, width: width)
                        },
                        onSetAttachmentFrameVisible: { attachmentID, isVisible in
                            _ = noteStore.setAttachmentFrameVisible(attachmentID, isVisible: isVisible)
                        },
                        onUpdateAttachmentAspectRatio: { attachmentID, aspectRatio in
                            _ = noteStore.updateAttachmentAspectRatio(attachmentID, aspectRatio: aspectRatio)
                        },
                        onReferencedAttachmentsChanged: { attachmentIDs in
                            _ = noteStore.ensureAttachmentReferences(attachmentIDs, on: note.id)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(languageManager.text("workspace.notes.body"))
                } else {
                    NotesMarkdownPreview(
                        markdown: renderedMarkdown(draftBody),
                        emptyText: languageManager.text("workspace.notes.markdown.preview_empty"),
                        safeEmbedsEnabled: effectiveEditorSettings.safeEmbedsEnabled,
                        loadEmbedText: languageManager.text("workspace.notes.embed.load"),
                        unloadEmbedText: languageManager.text("workspace.notes.embed.unload"),
                        blockedEmbedText: languageManager.text("workspace.notes.embed.blocked"),
                        embedSecurityText: languageManager.text("workspace.notes.embed.security"),
                        copyAttachmentText: languageManager.text("workspace.notes.attachments.copy"),
                        cutAttachmentText: languageManager.text("workspace.notes.attachments.cut"),
                        resizeAttachmentText: languageManager.text("workspace.notes.attachments.resize"),
                        showFrameText: languageManager.text("workspace.notes.attachments.show_frame"),
                        hideFrameText: languageManager.text("workspace.notes.attachments.hide_frame"),
                        playAttachmentText: languageManager.text("workspace.notes.attachments.play"),
                        pauseAttachmentText: languageManager.text("workspace.notes.attachments.pause"),
                        attachments: noteStore.attachments.map {
                            MarkdownEditorAttachment(record: $0, url: noteStore.attachmentURL(for: $0))
                        },
                        canEditAttachments: isEditable,
                        onResizeAttachment: { attachmentID, width in
                            _ = noteStore.updateAttachmentDisplayWidth(attachmentID, width: width)
                        },
                        onSetAttachmentFrameVisible: { attachmentID, isVisible in
                            _ = noteStore.setAttachmentFrameVisible(attachmentID, isVisible: isVisible)
                        },
                        onUpdateAttachmentAspectRatio: { attachmentID, aspectRatio in
                            _ = noteStore.updateAttachmentAspectRatio(attachmentID, aspectRatio: aspectRatio)
                        },
                        onCutAttachment: { attachmentID in
                            guard isEditable else { return }
                            let pattern = "!?\\[[^\\]]*\\]\\(attachment://\(attachmentID.uuidString)\\)"
                            draftBody = draftBody.replacingOccurrences(
                                of: pattern,
                                with: "",
                                options: .regularExpression
                            )
                        },
                        onOpenURL: openAppLinkURL
                    )
                }
                Divider()
                editorFooter(note)
            }
        } else {
            VStack(spacing: 0) {
                editorEmptyState
                Divider()
                HStack {
                    notesListToggleButton
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
            }
        }
    }

    private func editorHeader(_ note: NoteRecord) -> some View {
        HStack(spacing: 6) {
            noteTypeMenu(for: note, compact: true, monochrome: true)
                .disabled(!isNoteEditable(note))
            folderMoveMenu(for: note)
                .disabled(!isNoteEditable(note))

            Button {
                editorTagPickerPresented = true
            } label: {
                Image(systemName: note.tagIDs.isEmpty ? "tag" : "tag.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
            .help(note.tagIDs.isEmpty
                  ? languageManager.text("workspace.notes.tags.add")
                  : languageManager.format("workspace.notes.tags.count", note.tagIDs.count))
            .accessibilityLabel(languageManager.text("workspace.notes.tags.edit"))
            .disabled(!isNoteEditable(note))
            .popover(isPresented: $editorTagPickerPresented, arrowEdge: .top) {
                NoteTagPicker(
                    noteID: note.id,
                    noteStore: noteStore,
                    languageManager: languageManager,
                    onChange: { saved in deferredSaveStateUpdate(saved, noteID: note.id) }
                )
                .disabled(!isNoteEditable(note))
            }

            Button {
                isAttachmentImporterPresented = true
            } label: {
                Image(systemName: "paperclip")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(languageManager.text("workspace.notes.attachments.add"))
            .accessibilityLabel(languageManager.text("workspace.notes.attachments.add"))
            .disabled(!isNoteEditable(note))

            aiComingSoonButton

            Spacer()

            saveStatusView

            Button {
                togglePinned(note)
            } label: {
                Image(systemName: note.isPinned ? "pin.fill" : "pin")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(note.isPinned
                  ? languageManager.text("workspace.notes.unpin")
                  : languageManager.text("workspace.notes.pin"))
            .accessibilityLabel(note.isPinned
                                ? languageManager.text("workspace.notes.unpin")
                                : languageManager.text("workspace.notes.pin"))
            .disabled(!isNoteEditable(note))

            Button {
                toggleArchived(note)
            } label: {
                Image(systemName: note.isArchived ? "archivebox.fill" : "archivebox")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(note.isArchived
                  ? languageManager.text("workspace.notes.unarchive")
                  : languageManager.text("workspace.notes.archive"))
            .accessibilityLabel(note.isArchived
                                ? languageManager.text("workspace.notes.unarchive")
                                : languageManager.text("workspace.notes.archive"))

            noteMoreMenu(note)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .tint(.secondary)
        .foregroundStyle(.secondary)
    }

    private func titleField(_ note: NoteRecord) -> some View {
        TextField(languageManager.text("workspace.notes.title"), text: $draftTitle)
            .font(.title2.weight(.semibold))
            .textFieldStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .disabled(!isNoteEditable(note))
            .accessibilityLabel(languageManager.text("workspace.notes.title"))
    }

    private func readOnlyBanner(_ note: NoteRecord) -> some View {
        Label(
            languageManager.text(
                note.isArchived
                    ? "workspace.notes.read_only.archived"
                    : "workspace.notes.read_only.subscription"
            ),
            systemImage: "lock.fill"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background(Color.primary.opacity(0.025))
    }

    private func markdownToolbar(isEditable: Bool) -> some View {
        HStack(spacing: 2) {
            if markdownMode == .edit && isEditable {
                markdownButton("textformat.size", helpKey: "workspace.notes.markdown.heading", action: .heading)
                markdownButton("bold", helpKey: "workspace.notes.markdown.bold", action: .bold, shortcut: "b")
                markdownButton("italic", helpKey: "workspace.notes.markdown.italic", action: .italic, shortcut: "i")
                markdownButton("strikethrough", helpKey: "workspace.notes.markdown.strikethrough", action: .strikethrough)
                Divider().frame(height: 18).padding(.horizontal, 3)
                markdownButton("list.bullet", helpKey: "workspace.notes.markdown.bullets", action: .bulletList)
                markdownButton("list.number", helpKey: "workspace.notes.markdown.numbered", action: .numberedList)
                markdownButton("checklist", helpKey: "workspace.notes.markdown.checklist", action: .checklist)
                markdownButton("text.quote", helpKey: "workspace.notes.markdown.quote", action: .quote)
                Divider().frame(height: 18).padding(.horizontal, 3)
                markdownButton("chevron.left.forwardslash.chevron.right", helpKey: "workspace.notes.markdown.code", action: .inlineCode)
                markdownButton("curlybraces.square", helpKey: "workspace.notes.markdown.code_block", action: .codeBlock)
                markdownButton("link", helpKey: "workspace.notes.markdown.link", action: .link, shortcut: "k")
                markdownButton("photo", helpKey: "workspace.notes.markdown.image", action: .image)
                markdownButton("safari", helpKey: "workspace.notes.markdown.embed", action: .embed)
                orchestranaLinkMenu
                markdownTableMenu
                markdownButton("minus.rectangle", helpKey: "workspace.notes.markdown.divider", action: .divider)
            }
            Spacer()
            HStack(spacing: 4) {
                markdownModeButton(
                    .edit,
                    titleKey: "workspace.notes.markdown.edit",
                    systemImage: "pencil",
                    color: .blue
                )
                .disabled(!isEditable)
                markdownModeButton(
                    .preview,
                    titleKey: "workspace.notes.markdown.preview",
                    systemImage: "eye",
                    color: .green
                )
            }
            .accessibilityLabel(languageManager.text("workspace.notes.markdown.mode"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.018))
    }

    private var orchestranaLinkMenu: some View {
        Menu {
            Button {
                markdownCommand = MarkdownCommand(action: .orchestranaLink(.goal))
            } label: {
                Label(languageManager.text("workspace.notes.link.goals"), systemImage: "target")
            }
            Button {
                markdownCommand = MarkdownCommand(action: .orchestranaLink(.task))
            } label: {
                Label(languageManager.text("workspace.notes.link.tasks"), systemImage: "checklist")
            }
            Button {
                markdownCommand = MarkdownCommand(action: .orchestranaLink(.event))
            } label: {
                Label(languageManager.text("workspace.notes.link.events"), systemImage: "calendar")
            }
        } label: {
            Image(systemName: "link.badge.plus")
                .frame(width: 25, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(Color.secondary)
        .foregroundStyle(.secondary)
        .help(languageManager.text("workspace.notes.link.insert"))
        .accessibilityLabel(languageManager.text("workspace.notes.link.insert"))
    }

    private var markdownTableMenu: some View {
        Menu {
            Button {
                markdownCommand = MarkdownCommand(action: .table)
            } label: {
                Label(languageManager.text("workspace.notes.markdown.table.insert"), systemImage: "tablecells")
            }
            Divider()
            Button {
                markdownCommand = MarkdownCommand(action: .tableRow)
            } label: {
                Label(languageManager.text("workspace.notes.markdown.table.add_row"), systemImage: "rectangle.split.1x2")
            }
            Button {
                markdownCommand = MarkdownCommand(action: .tableColumn)
            } label: {
                Label(languageManager.text("workspace.notes.markdown.table.add_column"), systemImage: "rectangle.split.2x1")
            }
        } label: {
            Image(systemName: "tablecells")
                .frame(width: 25, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(Color.secondary)
        .foregroundStyle(.secondary)
        .help(languageManager.text("workspace.notes.markdown.table"))
        .accessibilityLabel(languageManager.text("workspace.notes.markdown.table"))
    }

    private func markdownModeButton(
        _ mode: MarkdownEditorMode,
        titleKey: String,
        systemImage: String,
        color: Color
    ) -> some View {
        let isSelected = markdownMode == mode
        return Button {
            markdownMode = mode
        } label: {
            Label(languageManager.text(titleKey), systemImage: systemImage)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .frame(height: 25)
                .foregroundStyle(isSelected ? color : Color.secondary)
                .background(isSelected ? color.opacity(0.16) : Color.primary.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isSelected ? color.opacity(0.35) : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(languageManager.text(titleKey))
        .accessibilityLabel(languageManager.text(titleKey))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func markdownButton(
        _ systemImage: String,
        helpKey: String,
        action: MarkdownAction,
        shortcut: KeyEquivalent? = nil
    ) -> some View {
        let button = Button {
            markdownCommand = MarkdownCommand(action: action)
        } label: {
            Image(systemName: systemImage)
                .frame(width: 25, height: 24)
        }
        .buttonStyle(.borderless)
        .help(languageManager.text(helpKey))
        .accessibilityLabel(languageManager.text(helpKey))

        return Group {
            if let shortcut {
                button.keyboardShortcut(shortcut, modifiers: .command)
            } else {
                button
            }
        }
    }

    private func editorFooter(_ note: NoteRecord) -> some View {
        HStack(spacing: 12) {
            notesListToggleButton
            Divider().frame(height: 16)
            Text(languageManager.format("workspace.notes.words", wordCount(draftBody)))
            Text(languageManager.format("workspace.notes.characters", draftBody.count))
            Spacer()
            Text(languageManager.format(
                "workspace.notes.created",
                note.createdAt.formatted(date: .abbreviated, time: .shortened)
            ))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    private var editorEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.cursor")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(languageManager.text("workspace.notes.empty"))
                .font(.headline)
            Text(languageManager.text("workspace.notes.empty.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(languageManager.text("workspace.notes.new")) { createBlankNote() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(32)
    }

    private var saveStatusView: some View {
        HStack(spacing: 5) {
            switch saveState {
            case .saved:
                Image(systemName: "checkmark")
                Text(languageManager.text("workspace.notes.saved"))
            case .saving:
                ProgressView().controlSize(.mini)
                Text(languageManager.text("workspace.notes.saving"))
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                Text(languageManager.text("workspace.notes.save_failed"))
            }
        }
        .font(.caption2)
        .foregroundStyle(saveState == .failed ? Color.orange : Color.secondary)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: saveStateLabel)
    }

    private var aiComingSoonButton: some View {
        Button {
            isAINoticePresented.toggle()
        } label: {
            Image(systemName: "sparkles")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
        .help(languageManager.text("workspace.notes.ai.unavailable"))
        .accessibilityLabel(languageManager.text("workspace.notes.ai.unavailable"))
        .popover(isPresented: $isAINoticePresented, arrowEdge: .top) {
            Text(languageManager.text("workspace.notes.ai.unavailable"))
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    private func noteTypeMenu(
        for note: NoteRecord,
        compact: Bool,
        monochrome: Bool = false
    ) -> some View {
        Menu {
            ForEach(NoteRecord.NoteType.allCases) { type in
                Button {
                    changeType(type, for: note)
                } label: {
                    if type == note.noteType {
                        Label(noteTypeTitle(type), systemImage: "checkmark")
                    } else {
                        Label(noteTypeTitle(type), systemImage: noteTypeIcon(type))
                    }
                }
            }
        } label: {
            if compact {
                Image(systemName: noteTypeIcon(note.noteType))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(monochrome ? Color.secondary : noteTypeColor(note.noteType))
                    .frame(width: 24, height: 24)
            } else {
                Label(noteTypeTitle(note.noteType), systemImage: noteTypeIcon(note.noteType))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .help(languageManager.text("workspace.notes.change_type"))
        .accessibilityLabel(languageManager.text("workspace.notes.change_type"))
    }

    private func folderMoveMenu(for note: NoteRecord, compact: Bool = true) -> some View {
        Menu {
            Button {
                moveNote(note, toFolderID: nil)
            } label: {
                if note.folderID == nil {
                    Label(languageManager.text("workspace.notes.folders.unfiled"), systemImage: "checkmark")
                } else {
                    Text(languageManager.text("workspace.notes.folders.unfiled"))
                }
            }

            if !noteStore.folders.isEmpty {
                Divider()
                ForEach(sortedFolderDestinations) { folder in
                    Button {
                        moveNote(note, toFolderID: folder.id)
                    } label: {
                        if note.folderID == folder.id {
                            Label(folderPath(folder), systemImage: "checkmark")
                        } else {
                            Text(folderPath(folder))
                        }
                    }
                }
            }
        } label: {
            if compact {
                Image(systemName: note.folderID == nil ? "folder" : "folder.fill")
                    .frame(width: 24, height: 24)
            } else {
                Label(
                    languageManager.text("workspace.notes.folders.move"),
                    systemImage: note.folderID == nil ? "folder" : "folder.fill"
                )
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .foregroundStyle(.secondary)
        .help(languageManager.text("workspace.notes.folders.move"))
        .accessibilityLabel(languageManager.text("workspace.notes.folders.move"))
    }

    private var sortedFolderDestinations: [NoteFolderRecord] {
        noteStore.folders.sorted {
            folderPath($0).localizedStandardCompare(folderPath($1)) == .orderedAscending
        }
    }

    private func folderPath(_ folder: NoteFolderRecord) -> String {
        folderPathComponents(folder).joined(separator: " / ")
    }

    private func folderPathComponents(_ folder: NoteFolderRecord) -> [String] {
        var names = [folder.name]
        var parentID = folder.parentFolderID
        var visited: Set<UUID> = [folder.id]
        while let currentID = parentID,
              !visited.contains(currentID),
              let parent = noteStore.folder(withID: currentID) {
            names.insert(parent.name, at: 0)
            visited.insert(currentID)
            parentID = parent.parentFolderID
        }
        return names
    }

    private func revealNotesFileInFinder() {
        _ = noteStore.persist()
        if let selectedMarkdownFileURL {
            NSWorkspace.shared.activateFileViewerSelecting([selectedMarkdownFileURL])
        } else {
            NSWorkspace.shared.open(noteStore.storageDirectoryURL)
        }
    }

    private func copySelectedNotePath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            selectedMarkdownFileURL?.path ?? noteStore.storageDirectoryURL.path,
            forType: .string
        )
    }

    private func noteMoreMenu(_ note: NoteRecord) -> some View {
        Menu {
            noteContextMenu(note)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(languageManager.text("workspace.notes.more"))
        .accessibilityLabel(languageManager.text("workspace.notes.more"))
    }

    @ViewBuilder
    private func noteContextMenu(_ note: NoteRecord) -> some View {
        Button(languageManager.text("workspace.notes.open")) { selectOutlineNote(note) }
        Button(note.isPinned
               ? languageManager.text("workspace.notes.unpin")
               : languageManager.text("workspace.notes.pin")) {
            togglePinned(note)
        }
        .disabled(!isNoteEditable(note))
        Button(languageManager.text("workspace.notes.tags.edit")) {
            rowTagPickerNoteID = note.id
        }
        .disabled(!isNoteEditable(note))
        Menu(languageManager.text("workspace.notes.change_type")) {
            ForEach(NoteRecord.NoteType.allCases) { type in
                Button(noteTypeTitle(type)) { changeType(type, for: note) }
            }
        }
        .disabled(!isNoteEditable(note))
        folderMoveMenu(for: note, compact: false)
            .disabled(!isNoteEditable(note))
        Divider()
        Button(note.isArchived
               ? languageManager.text("workspace.notes.unarchive")
               : languageManager.text("workspace.notes.archive")) {
            toggleArchived(note)
        }
        Button(languageManager.text("workspace.notes.duplicate")) { duplicate(note) }
            .disabled(!canCreateAnotherNote)
        Button(languageManager.text("workspace.notes.copy_markdown")) { copyMarkdown(note) }
        Button(languageManager.text("workspace.notes.copy_plain_text")) { copyPlainText(note) }
        Menu(languageManager.text("workspace.notes.export")) {
            Button(languageManager.text("workspace.notes.export_markdown")) { exportMarkdown(note) }
            Button(languageManager.text("workspace.notes.export_json")) { exportJSON(note) }
        }
        Divider()
        Button(languageManager.text("common.delete"), role: .destructive) {
            pendingDeleteNoteID = note.id
        }
    }

    private func createBlankNote() {
        createBlankNote(in: selectedFolderIDForCreation)
    }

    private func createBlankNote(in folderID: UUID?) {
        guard canCreateAnotherNote else {
            upgradePaywallContext = SubscriptionPaywallContext(
                requiredTier: .plus,
                title: languageManager.text("workspace.notes.limit.title"),
                message: languageManager.text("workspace.notes.limit.message")
            )
            return
        }
        let note = noteStore.addNote(
            title: languageManager.text("workspace.notes.untitled"),
            folderID: folderID
        )
        if note.noteType != noteStore.editorSettings.defaultNoteType {
            var configured = note
            configured.noteType = noteStore.editorSettings.defaultNoteType
            _ = noteStore.updateNote(configured)
        }
        showsArchived = false
        if let folderID {
            folderSelection = .folder(folderID)
        }
        selectNote(note)
        selectedOutlineItems = [.note(note.id)]
        outlineSelectionAnchor = .note(note.id)
    }

    private var selectedFolderIDForCreation: UUID? {
        if case let .folder(folderID) = folderSelection { return folderID }
        return nil
    }

    private func beginCreatingFolder(parentFolderID: UUID?) {
        var resolvedParentFolderID = parentFolderID
        if let newlyCreatedFolderID,
           let pendingFolder = noteStore.folder(withID: newlyCreatedFolderID) {
            let pendingName = folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if pendingName.isEmpty {
                if newlyCreatedFolderID == parentFolderID {
                    resolvedParentFolderID = pendingFolder.parentFolderID
                }
                discardPendingNewFolder()
            } else {
                guard noteStore.renameFolder(pendingFolder, name: pendingName) else { return }
                self.newlyCreatedFolderID = nil
                editingFolderID = nil
                folderNameDraft = ""
            }
        }

        if let resolvedParentFolderID {
            expandFolderPath(startingAt: resolvedParentFolderID)
        }
        if isNotesListCollapsed {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isNotesListCollapsed = false
            }
        }
        guard let folder = noteStore.addFolder(
            name: availableFolderName(parentFolderID: resolvedParentFolderID),
            parentFolderID: resolvedParentFolderID
        ) else { return }
        folderSelection = .folder(folder.id)
        selectedOutlineItems = [.folder(folder.id)]
        outlineSelectionAnchor = .folder(folder.id)
        folderNameDraft = ""
        newlyCreatedFolderID = folder.id
        editingFolderID = folder.id
    }

    private func expandFolderPath(startingAt folderID: UUID) {
        var currentID: UUID? = folderID
        var visited: Set<UUID> = []
        while let id = currentID,
              visited.insert(id).inserted,
              let folder = noteStore.folder(withID: id) {
            collapsedFolderIDs.remove(id)
            currentID = folder.parentFolderID
        }
    }

    private func beginRenamingFolder(_ folder: NoteFolderRecord) {
        folderNameDraft = folder.name
        editingFolderID = folder.id
    }

    private func commitFolderRename(_ folder: NoteFolderRecord) {
        guard editingFolderID == folder.id else { return }
        let name = folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty, newlyCreatedFolderID == folder.id {
            discardPendingNewFolder()
            return
        }
        if !name.isEmpty, !noteStore.renameFolder(folder, name: name) {
            return
        }
        if newlyCreatedFolderID == folder.id { newlyCreatedFolderID = nil }
        editingFolderID = nil
        folderNameDraft = ""
    }

    private func cancelFolderRename() {
        if newlyCreatedFolderID != nil {
            discardPendingNewFolder()
            return
        }
        editingFolderID = nil
        folderNameDraft = ""
    }

    private func discardPendingNewFolder() {
        guard let folderID = newlyCreatedFolderID,
              let folder = noteStore.folder(withID: folderID) else {
            newlyCreatedFolderID = nil
            return
        }
        if folderSelection == .folder(folderID) {
            folderSelection = folder.parentFolderID.map(NotesFolderSelection.folder) ?? .all
        }
        collapsedFolderIDs.remove(folderID)
        selectedOutlineItems.remove(.folder(folderID))
        editingFolderID = nil
        folderNameDraft = ""
        newlyCreatedFolderID = nil
        _ = noteStore.deleteFolder(folder)
    }

    private func availableFolderName(parentFolderID: UUID?) -> String {
        let baseName = languageManager.text("workspace.notes.folders.new")
        let siblingNames = Set(
            noteStore.folders(in: parentFolderID).map { $0.name.lowercased() }
        )
        guard siblingNames.contains(baseName.lowercased()) else { return baseName }
        var suffix = 2
        while siblingNames.contains("\(baseName) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }

    private func deletePendingFolder() {
        guard let folder = pendingDeleteFolder else { return }
        pendingDeleteFolder = nil
        if folderSelection == .folder(folder.id) {
            if let parentID = folder.parentFolderID {
                folderSelection = .folder(parentID)
            } else {
                folderSelection = .all
            }
        }
        collapsedFolderIDs.remove(folder.id)
        selectedOutlineItems.remove(.folder(folder.id))
        _ = noteStore.deleteFolder(folder)
    }

    private func moveNote(_ note: NoteRecord, toFolderID folderID: UUID?) {
        guard isNoteEditable(note) else { return }
        updateSaveState(noteStore.moveNote(note.id, toFolderID: folderID), noteID: note.id)
    }

    private func beginOutlineDrag(_ item: NotesOutlineItemID) {
        if case .note(let noteID) = item,
           let note = noteStore.notes.first(where: { $0.id == noteID }),
           !isNoteEditable(note) {
            draggedOutlineItem = nil
            return
        }
        draggedOutlineItem = item
        outlineDropTarget = nil
        outlineDropAfterTarget = false
        if !selectedOutlineItems.contains(item) {
            selectedOutlineItems = [item]
            outlineSelectionAnchor = item
        }
    }

    private func draggedNoteIDs(startingWith noteID: UUID) -> [UUID] {
        guard selectedOutlineItems.contains(.note(noteID)) else { return [noteID] }
        let selectedIDs = visibleOutlineItemIDs.compactMap { item -> UUID? in
            guard case .note(let id) = item, selectedOutlineItems.contains(item) else { return nil }
            return id
        }
        return selectedIDs.isEmpty ? [noteID] : selectedIDs
    }

    private func handleOutlineDragEntered(_ source: NotesOutlineItemID, _ target: NotesOutlineItemID) {
        guard source != target else { return }
        switch (source, target) {
        case let (.note(sourceID), .note(targetID)):
            outlineDropAfterTarget = false
            let movingIDs = draggedNoteIDs(startingWith: sourceID)
            guard !movingIDs.contains(targetID),
                  movingIDs.allSatisfy({ id in
                      noteStore.notes.first(where: { $0.id == id }).map(isNoteEditable) == true
                  }),
                  let sourceNote = noteStore.notes.first(where: { $0.id == sourceID }),
                  let targetNote = noteStore.notes.first(where: { $0.id == targetID }),
                  sourceNote.folderID == targetNote.folderID else { return }
            let siblingIDs = noteStore.notes
                .filter { $0.folderID == sourceNote.folderID }
                .sorted {
                    if $0.manualOrder != $1.manualOrder { return $0.manualOrder < $1.manualOrder }
                    return $0.id.uuidString < $1.id.uuidString
                }
                .map(\.id)
            guard let sourceIndex = siblingIDs.firstIndex(of: sourceID),
                  let targetIndex = siblingIDs.firstIndex(of: targetID) else { return }
            let placeAfter = targetIndex > sourceIndex
            outlineDropAfterTarget = placeAfter
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2, extraBounce: 0)) {
                if noteStore.reorderNotes(movingIDs, relativeTo: targetID, placeAfter: placeAfter) {
                    sortOrder = .manual
                }
            }
        case let (.folder(sourceID), .folder(targetID)):
            guard let sourceFolder = noteStore.folder(withID: sourceID),
                  let targetFolder = noteStore.folder(withID: targetID),
                  sourceFolder.parentFolderID == targetFolder.parentFolderID else { return }
            let siblingIDs = noteStore.folders(in: sourceFolder.parentFolderID).map(\.id)
            guard let sourceIndex = siblingIDs.firstIndex(of: sourceID),
                  let targetIndex = siblingIDs.firstIndex(of: targetID) else { return }
            let placeAfter = targetIndex > sourceIndex
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2, extraBounce: 0)) {
                if noteStore.reorderFolder(sourceID, relativeTo: targetID, placeAfter: placeAfter) {
                    sortOrder = .manual
                }
            }
        default:
            break
        }
    }

    private func completeOutlineDrop(_ source: NotesOutlineItemID, _ target: NotesOutlineItemID) -> Bool {
        switch (source, target) {
        case let (.note(sourceID), .folder(folderID)):
            let movingIDs = draggedNoteIDs(startingWith: sourceID)
            guard movingIDs.allSatisfy({ id in
                noteStore.notes.first(where: { $0.id == id }).map(isNoteEditable) == true
            }) else { return false }
            let moved = noteStore.moveNotes(movingIDs, toFolderID: folderID)
            if moved {
                sortOrder = .manual
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    _ = collapsedFolderIDs.remove(folderID)
                }
                if let selectedNoteID, movingIDs.contains(selectedNoteID) {
                    updateSaveState(true, noteID: selectedNoteID)
                }
            }
            return moved
        case let (.note(sourceID), .note(targetID)):
            let movingIDs = draggedNoteIDs(startingWith: sourceID)
            guard !movingIDs.contains(targetID),
                  movingIDs.allSatisfy({ id in
                      noteStore.notes.first(where: { $0.id == id }).map(isNoteEditable) == true
                  }),
                  let targetNote = noteStore.notes.first(where: { $0.id == targetID }) else { return false }
            let movingNotes = noteStore.notes.filter { movingIDs.contains($0.id) }
            if movingNotes.count == movingIDs.count,
               movingNotes.allSatisfy({ $0.folderID == targetNote.folderID }) {
                sortOrder = .manual
                return true
            }
            let moved = noteStore.moveNotes(movingIDs, toFolderID: targetNote.folderID, before: targetID)
            if moved {
                sortOrder = .manual
                if let folderID = targetNote.folderID {
                    collapsedFolderIDs.remove(folderID)
                }
                if let selectedNoteID, movingIDs.contains(selectedNoteID) {
                    updateSaveState(true, noteID: selectedNoteID)
                }
            }
            return moved
        case let (.folder(sourceID), .folder(targetID)):
            guard let sourceFolder = noteStore.folder(withID: sourceID),
                  let targetFolder = noteStore.folder(withID: targetID),
                  sourceFolder.parentFolderID == targetFolder.parentFolderID else { return false }
            sortOrder = .manual
            return true
        default:
            return false
        }
    }

    private func selectOutlineNote(_ note: NoteRecord) {
        updateOutlineSelection(.note(note.id))
        selectNote(note)
    }

    private func selectOutlineFolder(_ folder: NoteFolderRecord) {
        let item = NotesOutlineItemID.folder(folder.id)
        updateOutlineSelection(item)
        folderSelection = selectedOutlineItems.contains(item) ? .folder(folder.id) : .all
    }

    private func updateOutlineSelection(_ item: NotesOutlineItemID) {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.shift),
           let anchor = outlineSelectionAnchor,
           let anchorIndex = visibleOutlineItemIDs.firstIndex(of: anchor),
           let itemIndex = visibleOutlineItemIDs.firstIndex(of: item) {
            let range = min(anchorIndex, itemIndex)...max(anchorIndex, itemIndex)
            let rangeItems = Set(range.map { visibleOutlineItemIDs[$0] })
            if modifiers.contains(.command) {
                selectedOutlineItems.formUnion(rangeItems)
            } else {
                selectedOutlineItems = rangeItems
            }
            return
        }

        if modifiers.contains(.command) {
            if selectedOutlineItems.contains(item) {
                selectedOutlineItems.remove(item)
            } else {
                selectedOutlineItems.insert(item)
            }
        } else if selectedOutlineItems == [item], case .folder = item {
            selectedOutlineItems.removeAll()
        } else {
            selectedOutlineItems = [item]
        }
        outlineSelectionAnchor = item
    }

    private func selectNote(_ note: NoteRecord?) {
        autosaveTask?.cancel()
        _ = saveDraft()
        rowTagPickerNoteID = nil
        editorTagPickerPresented = false
        selectedNoteID = note?.id
        if let note, !isNoteEditable(note) {
            markdownMode = .preview
        }
        isLoadingDraft = true
        draftTitle = note?.title ?? ""
        draftBody = note?.body ?? ""
        saveState = .saved
        DispatchQueue.main.async {
            isLoadingDraft = false
        }
    }

    private func scheduleAutosave() {
        guard selectedNoteID != nil, !isLoadingDraft else { return }
        guard let selectedNote, isNoteEditable(selectedNote) else { return }
        guard noteStore.editorSettings.autosaveEnabled else {
            saveState = .saving
            return
        }
        saveState = .saving
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            saveState = saveDraft() ? .saved : .failed
        }
    }

    @discardableResult
    private func saveDraft() -> Bool {
        guard var note = selectedNote else { return true }
        guard isNoteEditable(note) else { return true }
        let changed = note.title != draftTitle || note.body != draftBody
        if changed {
            note.title = draftTitle
            note.body = draftBody
            return noteStore.updateNote(note)
        }
        return saveState == .failed ? noteStore.persist() : true
    }

    private func updateSaveState(_ saved: Bool, noteID: UUID) {
        if selectedNoteID == noteID {
            saveState = saved ? .saved : .failed
        }
    }

    private func deferredSaveStateUpdate(_ saved: Bool, noteID: UUID) {
        DispatchQueue.main.async {
            updateSaveState(saved, noteID: noteID)
        }
    }

    private func mutateNote(
        _ note: NoteRecord,
        requiresEditing: Bool = true,
        mutation: (inout NoteRecord) -> Void
    ) {
        if requiresEditing && !isNoteEditable(note) { return }
        if selectedNoteID == note.id {
            autosaveTask?.cancel()
            _ = saveDraft()
        }
        guard var updated = noteStore.notes.first(where: { $0.id == note.id }) else { return }
        mutation(&updated)
        updateSaveState(noteStore.updateNote(updated), noteID: note.id)
    }

    private func changeType(_ type: NoteRecord.NoteType, for note: NoteRecord) {
        mutateNote(note) { $0.noteType = type }
    }

    private func togglePinned(_ note: NoteRecord) {
        mutateNote(note) { $0.isPinned.toggle() }
    }

    private func toggleArchived(_ note: NoteRecord) {
        let willHide = !note.isArchived && !showsArchived
        mutateNote(note, requiresEditing: false) { $0.isArchived.toggle() }
        if !note.isArchived, selectedNoteID == note.id {
            markdownMode = .preview
        }
        if willHide && selectedNoteID == note.id {
            selectNote(filteredNotes.first { $0.id != note.id })
        }
    }

    private func duplicate(_ note: NoteRecord) {
        guard canCreateAnotherNote else {
            upgradePaywallContext = SubscriptionPaywallContext(
                requiredTier: .plus,
                title: languageManager.text("workspace.notes.limit.title"),
                message: languageManager.text("workspace.notes.limit.message")
            )
            return
        }
        let copy = noteStore.duplicateNote(
            note,
            title: languageManager.format("workspace.notes.copy_title", note.title)
        )
        selectNote(copy)
        selectedOutlineItems = [.note(copy.id)]
        outlineSelectionAnchor = .note(copy.id)
    }

    private func copyMarkdown(_ note: NoteRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdownForExport(note), forType: .string)
    }

    private func copyPlainText(_ note: NoteRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plainTextForExport(note), forType: .string)
    }

    private func exportMarkdown(_ note: NoteRecord) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeExportFileName(note.title) + ".md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? markdownForExport(note).write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportJSON(_ note: NoteRecord) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeExportFileName(note.title) + ".json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let envelope = NoteJSONExport(
            note: note,
            tags: noteStore.tags(for: note),
            attachments: noteStore.attachments(for: note)
        )
        if let data = try? encoder.encode(envelope) { try? data.write(to: url, options: .atomic) }
    }

    private func markdownForExport(_ note: NoteRecord) -> String {
        var body = readableBody(note.body, preservesMarkdown: true)
        if noteStore.editorSettings.markdownExportIncludesMetadata {
            let tagNames = noteStore.tags(for: note).map(\.name).joined(separator: ", ")
            let metadata = [
                "type: \(note.noteType.rawValue)",
                "tags: \(tagNames)",
                "created: \(note.createdAt.formatted(.iso8601))",
                "updated: \(note.updatedAt.formatted(.iso8601))"
            ].joined(separator: "\n")
            body = "---\n\(metadata)\n---\n\n" + body
        }
        return "# \(note.title)\n\n\(body)"
    }

    private func plainTextForExport(_ note: NoteRecord) -> String {
        var body = readableBody(note.body, preservesMarkdown: false)
        if noteStore.editorSettings.plainTextExportRemovesSyntax {
            let replacements: [(String, String)] = [
                (#"(?m)^#{1,6}\s+"#, ""), (#"\*\*([^*]+)\*\*"#, "$1"),
                (#"(?<!\*)\*([^*]+)\*(?!\*)"#, "$1"), (#"_([^_]+)_"#, "$1"),
                (#"~~([^~]+)~~"#, "$1"), (#"`([^`]+)`"#, "$1"),
                (#"\[([^\]]+)\]\([^\)]+\)"#, "$1")
            ]
            for (pattern, replacement) in replacements {
                body = body.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
            }
        }
        return note.title + "\n\n" + body
    }

    private func readableBody(_ body: String, preservesMarkdown: Bool) -> String {
        var result = body
        let linkPattern = #"\[\[(goal|task|event):[0-9A-Fa-f-]{36}\|([^\]]+)\]\]"#
        let linkReplacement = preservesMarkdown ? "**$1:** $2" : "$1: $2"
        result = result.replacingOccurrences(of: linkPattern, with: linkReplacement, options: .regularExpression)
        let attachmentPattern = #"(!?)\[([^\]]+)\]\(attachment://[0-9A-Fa-f-]{36}\)"#
        result = result.replacingOccurrences(of: attachmentPattern, with: "$2", options: .regularExpression)
        if canUseCustomSyntax {
            for definition in noteStore.customSyntaxDefinitions where !definition.exportText.isEmpty {
                let replacement = definition.exportText == "__remove__" ? "" : definition.exportText
                result = result.replacingOccurrences(of: definition.trigger, with: replacement)
            }
        }
        return result
    }

    private func safeExportFileName(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Note" : cleaned
    }

    private func confirmDelete() {
        guard let pendingDeleteNoteID,
              let note = noteStore.notes.first(where: { $0.id == pendingDeleteNoteID }) else {
            self.pendingDeleteNoteID = nil
            return
        }
        let wasSelected = selectedNoteID == note.id
        selectedOutlineItems.remove(.note(note.id))
        _ = noteStore.deleteNote(note)
        self.pendingDeleteNoteID = nil
        if wasSelected {
            selectNote(filteredNotes.first)
        }
    }

    private func linkGoal(_ goalID: UUID, to note: NoteRecord) {
        mutateNote(note) {
            $0.linkedGoalID = goalID
            $0.source = .goal
            if $0.noteType == .quick { $0.noteType = .goal }
        }
    }

    private func linkTask(_ taskID: UUID, to note: NoteRecord) {
        mutateNote(note) {
            $0.linkedTaskID = taskID
            $0.source = .task
            if $0.noteType == .quick { $0.noteType = .task }
        }
    }

    private func linkEvent(_ eventID: UUID, to note: NoteRecord) {
        mutateNote(note) {
            $0.linkedEventID = eventID
            $0.source = .event
        }
    }

    private func linkSession(_ sessionID: UUID, to note: NoteRecord) {
        mutateNote(note) {
            $0.linkedSessionID = sessionID
            $0.source = .session
            if $0.noteType == .quick { $0.noteType = .session }
        }
    }

    private func linkDay(_ day: Date, to note: NoteRecord) {
        mutateNote(note) {
            $0.linkedDay = Calendar.current.startOfDay(for: day)
            $0.source = .day
            if $0.noteType == .quick { $0.noteType = .daily }
        }
    }

    private func removeGoalLink(from note: NoteRecord) { mutateNote(note) { $0.linkedGoalID = nil } }
    private func removeTaskLink(from note: NoteRecord) { mutateNote(note) { $0.linkedTaskID = nil } }
    private func removeEventLink(from note: NoteRecord) { mutateNote(note) { $0.linkedEventID = nil } }
    private func removeSessionLink(from note: NoteRecord) { mutateNote(note) { $0.linkedSessionID = nil } }
    private func removeDayLink(from note: NoteRecord) { mutateNote(note) { $0.linkedDay = nil } }

    private func matchesSearch(_ note: NoteRecord) -> Bool {
        let terms = searchText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return true }
        let tagNames = noteStore.tags(for: note).map(\.name)
        let linkedNames = linkedWorkDisplays(for: note).map(\.title)
        let folderName = noteStore.folder(withID: note.folderID).map(folderPath) ?? ""
        let searchable = ([note.title, note.body, noteTypeTitle(note.noteType), folderName] + tagNames + linkedNames)
            .joined(separator: " ")
        return terms.allSatisfy { searchable.localizedStandardContains($0) }
    }

    private var hasActiveFilter: Bool {
        selectedType != nil || selectedTagID != nil || linkFilter != .all
    }

    private func hasLinkedWork(_ note: NoteRecord) -> Bool {
        note.linkedGoalID != nil
            || note.linkedTaskID != nil
            || note.linkedEventID != nil
            || note.linkedSessionID != nil
            || note.linkedDay != nil
    }

    private func linkedWorkDisplays(for note: NoteRecord) -> [LinkedWorkDisplay] {
        var result: [LinkedWorkDisplay] = []
        if let id = note.linkedGoalID,
           let goal = goalStore.goals.first(where: { $0.id == id }) {
            result.append(LinkedWorkDisplay(id: "goal-\(id)", title: goal.outcome, icon: "target", destination: .goal(id)))
        }
        if let id = note.linkedTaskID,
           let task = todoStore.items.first(where: { $0.id == id }) {
            result.append(LinkedWorkDisplay(id: "task-\(id)", title: task.title, icon: "checklist", destination: .task(id)))
        }
        if let id = note.linkedEventID,
           let event = planningStore.items.first(where: { $0.id == id }) {
            result.append(LinkedWorkDisplay(id: "event-\(id)", title: event.title, icon: "calendar", destination: .event(id, event.startDate)))
        }
        if let id = note.linkedSessionID,
           let session = sessionRecordStore.records.first(where: { $0.id == id }) {
            result.append(LinkedWorkDisplay(
                id: "session-\(id)",
                title: session.startTime.formatted(date: .abbreviated, time: .shortened),
                icon: "timer",
                destination: .session(id)
            ))
        }
        if let day = note.linkedDay {
            result.append(LinkedWorkDisplay(
                id: "day-\(day.timeIntervalSince1970)",
                title: day.formatted(date: .abbreviated, time: .omitted),
                icon: "calendar.day.timeline.left",
                destination: .day(day)
            ))
        }
        return result
    }

    private func openLinkedWork(_ link: LinkedWorkDisplay) {
        switch link.destination {
        case .goal(let goalID):
            NotificationCenter.default.post(name: .navigateToWorkspaceGoals, object: nil)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .workspaceGoalFocusItem,
                    object: nil,
                    userInfo: ["goalID": goalID.uuidString]
                )
            }
        case .task(let taskID):
            NotificationCenter.default.post(name: .navigateToTasks, object: nil)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .taskFocusItem,
                    object: nil,
                    userInfo: ["taskID": taskID.uuidString]
                )
            }
        case .event(let eventID, let date):
            NotificationCenter.default.post(name: .navigateToCalendar, object: nil)
            DispatchQueue.main.async {
                var userInfo: [String: Any] = ["localEventID": eventID.uuidString]
                if let date { userInfo["date"] = date }
                NotificationCenter.default.post(name: .calendarFocusItem, object: nil, userInfo: userInfo)
            }
        case .session:
            NotificationCenter.default.post(name: .navigateToInsights, object: nil)
        case .day(let day):
            NotificationCenter.default.post(name: .navigateToCalendar, object: nil)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .calendarFocusItem,
                    object: nil,
                    userInfo: ["date": day]
                )
            }
        }
    }

    private func rowTagPickerBinding(for noteID: UUID) -> Binding<Bool> {
        Binding(
            get: { rowTagPickerNoteID == noteID },
            set: { isPresented in
                if !isPresented && rowTagPickerNoteID == noteID {
                    DispatchQueue.main.async {
                        if rowTagPickerNoteID == noteID {
                            rowTagPickerNoteID = nil
                        }
                    }
                }
            }
        )
    }

    private func noteTypeTitle(_ type: NoteRecord.NoteType) -> String {
        languageManager.text("workspace.notes.type.\(type.rawValue)")
    }

    private func noteTypeIcon(_ type: NoteRecord.NoteType) -> String {
        switch type {
        case .quick: return "bolt.fill"
        case .session: return "timer"
        case .goal: return "target"
        case .task: return "checkmark.circle"
        case .daily: return "calendar"
        case .contextDraft: return "square.stack.3d.up"
        }
    }

    private func noteTypeColor(_ type: NoteRecord.NoteType) -> Color {
        switch type {
        case .quick: return .yellow
        case .session: return .mint
        case .goal: return .blue
        case .task: return .green
        case .daily: return .orange
        case .contextDraft: return .purple
        }
    }

    private func sortTitle(_ order: NotesSortOrder) -> String {
        languageManager.text("workspace.notes.sort.\(order.rawValue)")
    }

    private func linkFilterTitle(_ filter: NotesLinkFilter) -> String {
        languageManager.text("workspace.notes.filter.linked.\(filter.rawValue)")
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func lastEditedText(_ date: Date) -> String {
        let value = Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
        return languageManager.format("workspace.notes.last_edited", value)
    }

    private func importAttachment(from url: URL, to noteID: UUID) {
        guard let note = noteStore.notes.first(where: { $0.id == noteID }), isNoteEditable(note) else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let attachment = noteStore.addAttachment(from: url, toNoteID: noteID) else { return }
        let reference = attachment.mediaType == .image
            ? "![\(attachment.fileName)](attachment://\(attachment.id.uuidString))"
            : "[\(attachment.fileName)](attachment://\(attachment.id.uuidString))"
        appendReferenceToDraft(reference, noteID: noteID)
    }

    private func importPastedImage(_ data: Data, to noteID: UUID) -> String? {
        guard let note = noteStore.notes.first(where: { $0.id == noteID }), isNoteEditable(note) else { return nil }
        guard let attachment = noteStore.addAttachment(
            data: data,
            fileName: "Pasted Image \(Date().formatted(date: .numeric, time: .shortened)).png",
            toNoteID: noteID
        ) else { return nil }
        return "![\(attachment.fileName)](attachment://\(attachment.id.uuidString))"
    }

    private func importPastedFile(_ url: URL, to noteID: UUID) -> String? {
        guard let note = noteStore.notes.first(where: { $0.id == noteID }), isNoteEditable(note) else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let attachment = noteStore.addAttachment(from: url, toNoteID: noteID) else { return nil }
        return attachment.mediaType == .image
            ? "![\(attachment.fileName)](attachment://\(attachment.id.uuidString))"
            : "[\(attachment.fileName)](attachment://\(attachment.id.uuidString))"
    }

    private func appendReferenceToDraft(_ reference: String, noteID: UUID) {
        guard selectedNoteID == noteID else { return }
        let separator = draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        draftBody += separator + reference
    }

    private func renderedMarkdown(_ source: String) -> String {
        var result = source
        let pattern = #"\[\[(goal|task|event):([0-9A-Fa-f-]{36})\|([^\]]+)\]\]"#
        if let expression = try? NSRegularExpression(pattern: pattern) {
            let nsSource = result as NSString
            for match in expression.matches(in: result, range: NSRange(location: 0, length: nsSource.length)).reversed() {
                let kind = nsSource.substring(with: match.range(at: 1))
                let id = nsSource.substring(with: match.range(at: 2))
                let title = nsSource.substring(with: match.range(at: 3))
                let isAvailable = UUID(uuidString: id).map { linkID in
                    markdownLinkTargets.contains { $0.id == linkID && $0.kind.rawValue == kind }
                } ?? false
                let readable = isAvailable
                    ? "[\(kind.capitalized): \(title)](orchestrana://\(kind)/\(id))"
                    : "~~\(kind.capitalized): \(title) (\(languageManager.text("workspace.notes.link.unavailable")))~~"
                result = (result as NSString).replacingCharacters(in: match.range, with: readable)
            }
        }
        return result
    }

    private func openAppLinkURL(_ url: URL) -> Bool {
        if url.isFileURL {
            NSWorkspace.shared.open(url)
            return true
        }
        guard url.scheme == "orchestrana",
              let kind = url.host,
              let id = UUID(uuidString: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            return false
        }
        switch kind {
        case "goal":
            openLinkedWork(LinkedWorkDisplay(id: "goal-\(id)", title: "", icon: "target", destination: .goal(id)))
        case "task":
            openLinkedWork(LinkedWorkDisplay(id: "task-\(id)", title: "", icon: "checklist", destination: .task(id)))
        case "event":
            let date = planningStore.items.first(where: { $0.id == id })?.startDate
            openLinkedWork(LinkedWorkDisplay(id: "event-\(id)", title: "", icon: "calendar", destination: .event(id, date)))
        default:
            return false
        }
        return true
    }

    private var saveStateLabel: String {
        switch saveState {
        case .saved: return "saved"
        case .saving: return "saving"
        case .failed: return "failed"
        }
    }
}

private struct NoteTreeIndentationGuides: View {
    let depth: Int

    var body: some View {
        if depth > 0 {
            HStack(spacing: 0) {
                ForEach(0..<depth, id: \.self) { index in
                    Rectangle()
                        .fill(Color.secondary.opacity(index == depth - 1 ? 0.28 : 0.14))
                        .frame(width: 1)
                        .frame(width: 22, alignment: .center)
                }
            }
            .padding(.leading, 4)
            .frame(maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct NoteFolderTreeNode: View {
    let folder: NoteFolderRecord
    let folders: [NoteFolderRecord]
    let notes: [NoteRecord]
    @Binding var editingFolderID: UUID?
    @Binding var folderNameDraft: String
    @Binding var collapsedFolderIDs: Set<UUID>
    let selectedOutlineItems: Set<NotesOutlineItemID>
    @Binding var draggedOutlineItem: NotesOutlineItemID?
    @Binding var outlineDropTarget: NotesOutlineItemID?
    let rowWidth: CGFloat
    let onSelect: (NoteFolderRecord) -> Void
    let onDragStarted: (NotesOutlineItemID) -> Void
    let onDragEntered: (NotesOutlineItemID, NotesOutlineItemID) -> Void
    let onDropItem: (NotesOutlineItemID, NotesOutlineItemID) -> Bool
    let onCreateNote: (NoteFolderRecord) -> Void
    let onCreateChild: (NoteFolderRecord) -> Void
    let onRename: (NoteFolderRecord) -> Void
    let onCommitRename: (NoteFolderRecord) -> Void
    let onCancelRename: () -> Void
    let onDelete: (NoteFolderRecord) -> Void
    let languageManager: LanguageManager
    let noteRow: (NoteRecord, Int) -> AnyView
    var depth = 0
    var ancestorIDs: Set<UUID> = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isNameFieldFocused: Bool

    private var childFolders: [NoteFolderRecord] {
        folders
            .filter { $0.parentFolderID == folder.id && !ancestorIDs.contains($0.id) }
    }

    private var isSelected: Bool {
        selectedOutlineItems.contains(.folder(folder.id))
    }

    private var folderNotes: [NoteRecord] {
        notes.filter { $0.folderID == folder.id }
    }

    private var hasChildren: Bool {
        !childFolders.isEmpty || !folderNotes.isEmpty
    }

    private var isExpanded: Bool {
        !collapsedFolderIDs.contains(folder.id)
    }

    private var descendantNoteCount: Int {
        countNotes(in: folder.id, visited: [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        if isExpanded {
                            collapsedFolderIDs.insert(folder.id)
                        } else {
                            collapsedFolderIDs.remove(folder.id)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 18, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(isExpanded
                      ? languageManager.text("workspace.notes.folders.collapse")
                      : languageManager.text("workspace.notes.folders.expand"))
                .accessibilityLabel(isExpanded
                                    ? languageManager.text("workspace.notes.folders.collapse")
                                    : languageManager.text("workspace.notes.folders.expand"))

                if editingFolderID == folder.id {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .frame(width: 16)

                        TextField(
                            languageManager.text("workspace.notes.folders.name"),
                            text: $folderNameDraft
                        )
                        .textFieldStyle(.plain)
                        .font(.subheadline.weight(.medium))
                        .focused($isNameFieldFocused)
                        .onSubmit { onCommitRename(folder) }
                        .onExitCommand { onCancelRename() }
                        .task { isNameFieldFocused = true }
                        .onChange(of: isNameFieldFocused) { wasFocused, isFocused in
                            if wasFocused, !isFocused, editingFolderID == folder.id {
                                onCommitRename(folder)
                            }
                        }

                        Spacer(minLength: 14)

                        Text("\(descendantNoteCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .frame(
                        minWidth: max(rowWidth + CGFloat(depth) * 22 - 31, 220),
                        alignment: .leading
                    )
                } else {
                    Button {
                        onSelect(folder)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .frame(width: 16)

                            Text(folder.name)
                                .font(.subheadline.weight(.medium))
                                .fixedSize(horizontal: true, vertical: false)

                            Spacer(minLength: 14)

                            Text("\(descendantNoteCount)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(
                        minWidth: max(rowWidth + CGFloat(depth) * 22 - 31, 220),
                        alignment: .leading
                    )
                }
            }
            .padding(.leading, CGFloat(depth) * 22 + 4)
            .padding(.trailing, 8)
            .frame(minWidth: rowWidth + CGFloat(depth) * 22, minHeight: 32, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .background(outlineDropTarget == .folder(folder.id)
                        ? Color.accentColor.opacity(0.18)
                        : (isSelected ? Color.accentColor.opacity(0.12) : Color.clear))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .overlay(alignment: .leading) {
                NoteTreeIndentationGuides(depth: depth)
            }
            .contextMenu {
                Button(languageManager.text("workspace.notes.new")) {
                    onCreateNote(folder)
                }
                Button(languageManager.text("workspace.notes.folders.new_subfolder")) {
                    onCreateChild(folder)
                }
                Button(languageManager.text("common.rename")) {
                    onRename(folder)
                }
                Divider()
                Button(languageManager.text("common.delete"), role: .destructive) {
                    onDelete(folder)
                }
            }
            .help(hasChildren
                  ? (isExpanded
                     ? languageManager.text("workspace.notes.folders.collapse")
                     : languageManager.text("workspace.notes.folders.expand"))
                  : languageManager.text("workspace.notes.folders.actions"))
            .onDrag {
                onDragStarted(.folder(folder.id))
                return NSItemProvider(object: "folder:\(folder.id.uuidString)" as NSString)
            } preview: {
                Color.clear.frame(width: 1, height: 1)
            }
            .onDrop(
                of: [UTType.plainText],
                delegate: NotesOutlineDropDelegate(
                    target: .folder(folder.id),
                    draggedItem: $draggedOutlineItem,
                    targetedItem: $outlineDropTarget,
                    onEntered: onDragEntered,
                    onDropped: onDropItem
                )
            )

            if isExpanded {
                ForEach(childFolders) { child in
                    NoteFolderTreeNode(
                        folder: child,
                        folders: folders,
                        notes: notes,
                        editingFolderID: $editingFolderID,
                        folderNameDraft: $folderNameDraft,
                        collapsedFolderIDs: $collapsedFolderIDs,
                        selectedOutlineItems: selectedOutlineItems,
                        draggedOutlineItem: $draggedOutlineItem,
                        outlineDropTarget: $outlineDropTarget,
                        rowWidth: rowWidth,
                        onSelect: onSelect,
                        onDragStarted: onDragStarted,
                        onDragEntered: onDragEntered,
                        onDropItem: onDropItem,
                        onCreateNote: onCreateNote,
                        onCreateChild: onCreateChild,
                        onRename: onRename,
                        onCommitRename: onCommitRename,
                        onCancelRename: onCancelRename,
                        onDelete: onDelete,
                        languageManager: languageManager,
                        noteRow: noteRow,
                        depth: depth + 1,
                        ancestorIDs: ancestorIDs.union([folder.id])
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                ForEach(folderNotes) { note in
                    noteRow(note, depth + 1)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isExpanded)
    }

    private func countNotes(in folderID: UUID, visited: Set<UUID>) -> Int {
        guard !visited.contains(folderID) else { return 0 }
        let nextVisited = visited.union([folderID])
        let directCount = notes.count { $0.folderID == folderID }
        let childCount = folders
            .filter { $0.parentFolderID == folderID }
            .reduce(0) { result, child in
                result + countNotes(in: child.id, visited: nextVisited)
            }
        return directCount + childCount
    }
}

private extension NotesLinkFilter {
    func includes(_ note: NoteRecord) -> Bool {
        let linked = note.linkedGoalID != nil
            || note.linkedTaskID != nil
            || note.linkedEventID != nil
            || note.linkedSessionID != nil
            || note.linkedDay != nil
        switch self {
        case .all: return true
        case .linked: return linked
        case .unlinked: return !linked
        }
    }
}

private extension NoteTagColor {
    var displayColor: Color {
        switch self {
        case .red: return .red
        case .purple: return .purple
        case .orange: return .orange
        case .yellow: return .yellow
        case .blue: return .blue
        case .green: return .green
        case .gray: return .gray
        }
    }
}

private struct NoteTagChip: View {
    let tag: NoteTagRecord
    let compact: Bool

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(tag.color.displayColor)
                .frame(width: 6, height: 6)
            if let symbolName = tag.symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: compact ? 8 : 9, weight: .semibold))
            }
            Text(tag.name)
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(tag.color.displayColor)
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, 2)
        .background(tag.color.displayColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

@MainActor
private struct NoteTagPicker: View {
    private struct SymbolChoice: Identifiable {
        let symbolName: String
        let titleKey: String

        var id: String { symbolName }
    }

    let noteID: UUID
    @ObservedObject var noteStore: NoteStore
    let languageManager: LanguageManager
    let onChange: (Bool) -> Void

    @State private var searchText = ""
    @State private var newTagName = ""
    @State private var newTagColor = NoteTagColor.blue
    @State private var newTagSymbol: String? = "tag"
    @State private var showsCreateTag = false
    @State private var editingTagID: UUID?
    @State private var renameDraft = ""

    private let symbolChoices = [
        SymbolChoice(symbolName: "tag", titleKey: "workspace.notes.tags.symbol.tag"),
        SymbolChoice(symbolName: "exclamationmark", titleKey: "workspace.notes.tags.symbol.exclamation"),
        SymbolChoice(symbolName: "arrow.triangle.branch", titleKey: "workspace.notes.tags.symbol.decision"),
        SymbolChoice(symbolName: "exclamationmark.triangle", titleKey: "workspace.notes.tags.symbol.warning"),
        SymbolChoice(symbolName: "lightbulb", titleKey: "workspace.notes.tags.symbol.idea"),
        SymbolChoice(symbolName: "book.closed", titleKey: "workspace.notes.tags.symbol.book"),
        SymbolChoice(symbolName: "person", titleKey: "workspace.notes.tags.symbol.person"),
        SymbolChoice(symbolName: "flag", titleKey: "workspace.notes.tags.symbol.flag"),
        SymbolChoice(symbolName: "star", titleKey: "workspace.notes.tags.symbol.star"),
        SymbolChoice(symbolName: "bookmark", titleKey: "workspace.notes.tags.symbol.bookmark")
    ]

    private var note: NoteRecord? {
        noteStore.notes.first { $0.id == noteID }
    }

    private var filteredTags: [NoteTagRecord] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return noteStore.tags
        }
        return noteStore.tags.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(languageManager.text("workspace.notes.tags.manage"))
                .font(.headline)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(languageManager.text("workspace.notes.tags.search"), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color.primary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(filteredTags) { tag in
                        tagRow(tag)
                    }
                }
            }
            .frame(maxHeight: 230)

            Divider()

            DisclosureGroup(
                languageManager.text("workspace.notes.tags.create"),
                isExpanded: $showsCreateTag
            ) {
                VStack(alignment: .leading, spacing: 9) {
                    TextField(languageManager.text("workspace.notes.tags.name"), text: $newTagName)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 7) {
                        ForEach(NoteTagColor.allCases) { color in
                            Button {
                                newTagColor = color
                            } label: {
                                Circle()
                                    .fill(color.displayColor)
                                    .frame(width: 15, height: 15)
                                    .overlay {
                                        if color == newTagColor {
                                            Circle().stroke(Color.primary, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.rawValue)
                        }

                        Spacer()

                        Menu {
                            Button(languageManager.text("workspace.notes.tags.no_symbol")) {
                                newTagSymbol = nil
                            }
                            Divider()
                            ForEach(symbolChoices) { choice in
                                Button {
                                    newTagSymbol = choice.symbolName
                                } label: {
                                    Label(
                                        languageManager.text(choice.titleKey),
                                        systemImage: choice.symbolName
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: newTagSymbol ?? "nosign")
                                .frame(width: 24, height: 24)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .help(languageManager.text("workspace.notes.tags.choose_symbol"))
                        .accessibilityLabel(languageManager.text("workspace.notes.tags.choose_symbol"))
                    }

                    Button(languageManager.text("workspace.notes.tags.create_action")) {
                        createTag()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 8)
            }
            .font(.subheadline)
        }
        .padding(14)
        .frame(width: 320, height: 430)
    }

    private func tagRow(_ tag: NoteTagRecord) -> some View {
        HStack(spacing: 8) {
            if editingTagID == tag.id {
                TextField(languageManager.text("workspace.notes.tags.name"), text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename(tag) }
                Button {
                    commitRename(tag)
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(languageManager.text("common.save"))
            } else {
                Button {
                    reportChange(noteStore.toggleTag(tag.id, on: noteID))
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(tag.color.displayColor)
                            .frame(width: 8, height: 8)
                        Image(systemName: tag.symbolName ?? "tag")
                            .foregroundStyle(tag.color.displayColor)
                            .frame(width: 16)
                        Text(tag.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: note?.tagIDs.contains(tag.id) == true ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(note?.tagIDs.contains(tag.id) == true ? Color.accentColor : Color.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button(languageManager.text("common.rename")) {
                        editingTagID = tag.id
                        renameDraft = tag.name
                    }
                    Button(languageManager.text("common.delete"), role: .destructive) {
                        reportChange(noteStore.deleteTag(tag))
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 30)
        .background(note?.tagIDs.contains(tag.id) == true ? Color.accentColor.opacity(0.07) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func createTag() {
        guard let tag = noteStore.addTag(
            name: newTagName,
            color: newTagColor,
            symbolName: newTagSymbol
        ) else { return }
        reportChange(noteStore.toggleTag(tag.id, on: noteID))
        newTagName = ""
        showsCreateTag = false
    }

    private func commitRename(_ tag: NoteTagRecord) {
        var updated = tag
        updated.name = renameDraft
        reportChange(noteStore.updateTag(updated))
        editingTagID = nil
        renameDraft = ""
    }

    private func reportChange(_ saved: Bool) {
        DispatchQueue.main.async {
            onChange(saved)
        }
    }
}

private struct InlineNoteAttachmentView: View {
    let attachment: MarkdownEditorAttachment
    let availableWidth: CGFloat
    let copyTitle: String
    let cutTitle: String
    let resizeTitle: String
    let showFrameTitle: String
    let hideFrameTitle: String
    let playTitle: String
    let pauseTitle: String
    let canCut: Bool
    let canResize: Bool
    let onCopy: () -> Void
    let onCut: () -> Void
    let onResize: (Double) -> Void
    let onSetFrameVisible: (Bool) -> Void
    let onUpdateAspectRatio: (Double) -> Void
    @State private var width: CGFloat
    @State private var resizeStartWidth: CGFloat?

    init(
        attachment: MarkdownEditorAttachment,
        availableWidth: CGFloat,
        copyTitle: String,
        cutTitle: String,
        resizeTitle: String,
        showFrameTitle: String,
        hideFrameTitle: String,
        playTitle: String,
        pauseTitle: String,
        canCut: Bool,
        canResize: Bool,
        onCopy: @escaping () -> Void,
        onCut: @escaping () -> Void,
        onResize: @escaping (Double) -> Void,
        onSetFrameVisible: @escaping (Bool) -> Void,
        onUpdateAspectRatio: @escaping (Double) -> Void
    ) {
        self.attachment = attachment
        self.availableWidth = availableWidth
        self.copyTitle = copyTitle
        self.cutTitle = cutTitle
        self.resizeTitle = resizeTitle
        self.showFrameTitle = showFrameTitle
        self.hideFrameTitle = hideFrameTitle
        self.playTitle = playTitle
        self.pauseTitle = pauseTitle
        self.canCut = canCut
        self.canResize = canResize
        self.onCopy = onCopy
        self.onCut = onCut
        self.onResize = onResize
        self.onSetFrameVisible = onSetFrameVisible
        self.onUpdateAspectRatio = onUpdateAspectRatio
        _width = State(initialValue: CGFloat(attachment.record.displayWidth ?? 360))
    }

    var body: some View {
        Group {
            if supportsFrameToggle && !attachment.record.isFrameVisible {
                content
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    content
                    if attachment.record.mediaType == .pdf {
                        HStack(spacing: 6) {
                            Image(nsImage: fileIcon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 17, height: 17)
                            Text(attachment.record.fileName)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                    }
                }
                .frame(width: resolvedWidth, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
            }
        }
        .frame(width: resolvedWidth, alignment: .leading)
        .overlay {
            if canResize && supportsCornerResize {
                resizeCornerTargets
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button(copyTitle, action: onCopy)
            Button(cutTitle, action: onCut)
                .disabled(!canCut)
            if supportsFrameToggle {
                Divider()
                Button(
                    attachment.record.isFrameVisible ? hideFrameTitle : showFrameTitle
                ) {
                    onSetFrameVisible(!attachment.record.isFrameVisible)
                }
                .disabled(!canCut)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch attachment.record.mediaType {
        case .image:
            SecurityScopedImage(url: attachment.url, onAspectRatio: onUpdateAspectRatio)
                .frame(width: resolvedWidth, height: mediaHeight)
                .background(Color.black.opacity(0.04))
        case .video:
            SecurityScopedMediaPlayer(
                url: attachment.url,
                audioOnly: false,
                playTitle: playTitle,
                pauseTitle: pauseTitle,
                onAspectRatio: onUpdateAspectRatio
            )
            .frame(width: resolvedWidth, height: mediaHeight)
        case .audio:
            SecurityScopedMediaPlayer(
                url: attachment.url,
                audioOnly: true,
                playTitle: playTitle,
                pauseTitle: pauseTitle,
                onAspectRatio: { _ in }
            )
                .frame(width: resolvedWidth, height: resolvedWidth + 42)
        case .pdf:
            SecurityScopedPDFView(url: attachment.url)
                .frame(width: resolvedWidth, height: min(460, max(210, resolvedWidth * 1.05)))
        case .file:
            HStack(spacing: 10) {
                Image(nsImage: fileIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.record.fileName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    if attachment.record.fileSize > 0 {
                        Text(ByteCountFormatter.string(
                            fromByteCount: attachment.record.fileSize,
                            countStyle: .file
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(10)
            .frame(width: resolvedWidth, alignment: .leading)
            .frame(minHeight: 64, alignment: .leading)
        }
    }

    private enum ResizeCorner {
        case topLeft, topRight, bottomLeft, bottomRight

        var horizontalDirection: CGFloat {
            switch self {
            case .topLeft, .bottomLeft: return -1
            case .topRight, .bottomRight: return 1
            }
        }

        var verticalDirection: CGFloat {
            switch self {
            case .topLeft, .topRight: return -1
            case .bottomLeft, .bottomRight: return 1
            }
        }
    }

    private var resizeCornerTargets: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                resizeCorner(.topLeft)
                Spacer(minLength: 0)
                resizeCorner(.topRight)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                resizeCorner(.bottomLeft)
                Spacer(minLength: 0)
                resizeCorner(.bottomRight)
            }
        }
    }

    private func resizeCorner(_ corner: ResizeCorner) -> some View {
        Color.clear
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = resizeStartWidth ?? width
                        resizeStartWidth = start
                        let aspectRatio = max(0.1, resolvedWidth / max(1, renderedHeight))
                        let verticalScale = 1 / aspectRatio
                        let projectedChange = (
                            value.translation.width * corner.horizontalDirection
                            + value.translation.height * corner.verticalDirection * verticalScale
                        ) / (1 + verticalScale * verticalScale)
                        width = min(
                            max(220, start + projectedChange),
                            min(720, availableWidth)
                        )
                    }
                    .onEnded { _ in
                        resizeStartWidth = nil
                        onResize(Double(width))
                    }
            )
            .onHover { hovering in
                (hovering ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
            }
            .help(resizeTitle)
            .accessibilityHidden(true)
    }

    private var resolvedWidth: CGFloat {
        min(max(220, width), min(720, availableWidth))
    }

    private var mediaHeight: CGFloat {
        resolvedWidth / CGFloat(attachment.record.naturalAspectRatio ?? (16.0 / 9.0))
    }

    private var renderedHeight: CGFloat {
        switch attachment.record.mediaType {
        case .image, .video: return mediaHeight
        case .audio: return resolvedWidth + 42
        case .pdf: return min(460, max(210, resolvedWidth * 1.05)) + 30
        case .file: return 64
        }
    }

    private var supportsCornerResize: Bool {
        attachment.record.mediaType != .file
    }

    private var supportsFrameToggle: Bool {
        attachment.record.mediaType == .image || attachment.record.mediaType == .video
    }

    private var fileIcon: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: attachment.url.path)
        icon.size = NSSize(width: 38, height: 38)
        return icon
    }
}

private struct SecurityScopedImage: View {
    let url: URL
    let onAspectRatio: (Double) -> Void
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: url) {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let loadedImage = NSImage(contentsOf: url)
            image = loadedImage
            if let size = loadedImage?.size, size.width > 0, size.height > 0 {
                let aspectRatio = size.width / size.height
                DispatchQueue.main.async {
                    onAspectRatio(aspectRatio)
                }
            }
        }
    }
}

private struct SecurityScopedMediaPlayer: View {
    let url: URL
    let audioOnly: Bool
    let playTitle: String
    let pauseTitle: String
    let onAspectRatio: (Double) -> Void
    @State private var player: AVPlayer?
    @State private var isAccessingURL = false
    @State private var artwork: NSImage?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    private let playbackTicker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let player, audioOnly {
                VStack(spacing: 0) {
                    ZStack {
                        if let artwork {
                            Image(nsImage: artwork)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "music.note")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.primary.opacity(0.055))
                        }
                        Button {
                            if isPlaying {
                                player.pause()
                                isPlaying = false
                            } else {
                                if duration > 0, currentTime >= duration - 0.2 {
                                    player.seek(to: .zero)
                                }
                                player.play()
                                isPlaying = true
                            }
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(.black.opacity(0.62))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPlaying ? pauseTitle : playTitle)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    Slider(
                        value: Binding(
                            get: { min(currentTime, max(duration, 0)) },
                            set: { value in
                                currentTime = value
                                player.seek(
                                    to: CMTime(seconds: value, preferredTimescale: 600),
                                    toleranceBefore: .zero,
                                    toleranceAfter: .zero
                                )
                            }
                        ),
                        in: 0...max(duration, 1)
                    )
                    .controlSize(.small)
                    .padding(.horizontal, 8)
                    .frame(height: 42)
                }
            } else if let player {
                SystemAVPlayerView(player: player)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard player == nil else { return }
            isAccessingURL = url.startAccessingSecurityScopedResource()
            player = AVPlayer(url: url)
        }
        .task(id: url) {
            if audioOnly {
                await loadArtwork()
            } else {
                await loadVideoAspectRatio()
            }
        }
        .onReceive(playbackTicker) { _ in
            guard let player else { return }
            let seconds = player.currentTime().seconds
            if seconds.isFinite { currentTime = max(0, seconds) }
            isPlaying = player.timeControlStatus == .playing
        }
        .onDisappear {
            player?.pause()
            player = nil
            artwork = nil
            isPlaying = false
            currentTime = 0
            duration = 0
            if isAccessingURL {
                url.stopAccessingSecurityScopedResource()
                isAccessingURL = false
            }
        }
    }

    private func loadArtwork() async {
        let targetURL = url
        let asset = AVURLAsset(url: targetURL)
        let metadata = try? await asset.load(.commonMetadata)
        let loadedDuration = try? await asset.load(.duration)
        let image = try? await metadata?.first(where: {
            $0.commonKey?.rawValue == AVMetadataKey.commonKeyArtwork.rawValue
        })?.load(.dataValue).flatMap(NSImage.init(data:))
        guard !Task.isCancelled else { return }
        await MainActor.run {
            if url == targetURL {
                artwork = image ?? nil
                let seconds = loadedDuration?.seconds ?? 0
                duration = seconds.isFinite ? max(0, seconds) : 0
            }
        }
    }

    private func loadVideoAspectRatio() async {
        let targetURL = url
        let asset = AVURLAsset(url: targetURL)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else { return }
        let transformedSize = naturalSize.applying(transform)
        let width = abs(transformedSize.width)
        let height = abs(transformedSize.height)
        guard !Task.isCancelled, width > 0, height > 0 else { return }
        await MainActor.run {
            if url == targetURL {
                let aspectRatio = width / height
                DispatchQueue.main.async {
                    onAspectRatio(aspectRatio)
                }
            }
        }
    }
}

private struct SystemAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        view.showsFrameSteppingButtons = false
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player = nil
    }
}

private struct SecurityScopedPDFView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        context.coordinator.beginAccessing(url)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.endAccessing()
        context.coordinator.beginAccessing(url)
        view.document = PDFDocument(url: url)
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        view.document = nil
        coordinator.endAccessing()
    }

    final class Coordinator {
        private(set) var url: URL?
        private var isAccessing = false

        func beginAccessing(_ url: URL) {
            self.url = url
            isAccessing = url.startAccessingSecurityScopedResource()
        }

        func endAccessing() {
            if isAccessing, let url { url.stopAccessingSecurityScopedResource() }
            isAccessing = false
            url = nil
        }
    }
}

private struct NotesMarkdownPreview: View {
    let markdown: String
    let emptyText: String
    let safeEmbedsEnabled: Bool
    let loadEmbedText: String
    let unloadEmbedText: String
    let blockedEmbedText: String
    let embedSecurityText: String
    let copyAttachmentText: String
    let cutAttachmentText: String
    let resizeAttachmentText: String
    let showFrameText: String
    let hideFrameText: String
    let playAttachmentText: String
    let pauseAttachmentText: String
    let attachments: [MarkdownEditorAttachment]
    let canEditAttachments: Bool
    let onResizeAttachment: (UUID, Double) -> Void
    let onSetAttachmentFrameVisible: (UUID, Bool) -> Void
    let onUpdateAttachmentAspectRatio: (UUID, Double) -> Void
    let onCutAttachment: (UUID) -> Void
    let onOpenURL: (URL) -> Bool

    private enum BlockContent {
        case markdown(String)
        case embed(URL)
        case blocked(String)
        case attachment(MarkdownEditorAttachment, String)
    }

    private struct Block: Identifiable {
        let id: Int
        let content: BlockContent
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var markdownLines: [String] = []

        func flushMarkdown() {
            guard !markdownLines.isEmpty else { return }
            result.append(Block(id: result.count, content: .markdown(markdownLines.joined(separator: "\n"))))
            markdownLines.removeAll(keepingCapacity: true)
        }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let attachment = attachment(in: trimmed) {
                flushMarkdown()
                result.append(Block(
                    id: result.count,
                    content: .attachment(attachment, trimmed)
                ))
                continue
            }
            guard trimmed.hasPrefix("@[embed]("), trimmed.hasSuffix(")") else {
                markdownLines.append(line)
                continue
            }
            flushMarkdown()
            let start = trimmed.index(trimmed.startIndex, offsetBy: 9)
            let end = trimmed.index(before: trimmed.endIndex)
            let rawURL = String(trimmed[start..<end])
            if safeEmbedsEnabled,
               let url = URL(string: rawURL),
               url.scheme?.lowercased() == "https",
               url.host != nil {
                result.append(Block(id: result.count, content: .embed(url)))
            } else {
                result.append(Block(id: result.count, content: .blocked(rawURL)))
            }
        }
        flushMarkdown()
        return result
    }

    private func attachment(in line: String) -> MarkdownEditorAttachment? {
        let pattern = #"^!?\[[^\]]*\]\(attachment://([0-9A-Fa-f-]{36})\)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: line,
                range: NSRange(location: 0, length: (line as NSString).length)
              ),
              let id = UUID(uuidString: (line as NSString).substring(with: match.range(at: 1))) else {
            return nil
        }
        return attachments.first { $0.id == id }
    }

    var body: some View {
        if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(emptyText)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(blocks) { block in
                        switch block.content {
                        case .markdown(let value):
                            Markdown(value)
                                .markdownTheme(.gitHub)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .embed(let url):
                            SafeNoteEmbed(
                                url: url,
                                loadText: loadEmbedText,
                                unloadText: unloadEmbedText,
                                securityText: embedSecurityText
                            )
                        case .blocked(let value):
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(blockedEmbedText)
                                    Text(value).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "lock.trianglebadge.exclamationmark")
                            }
                            .foregroundStyle(.orange)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        case .attachment(let attachment, let reference):
                            InlineNoteAttachmentView(
                                attachment: attachment,
                                availableWidth: 720,
                                copyTitle: copyAttachmentText,
                                cutTitle: cutAttachmentText,
                                resizeTitle: resizeAttachmentText,
                                showFrameTitle: showFrameText,
                                hideFrameTitle: hideFrameText,
                                playTitle: playAttachmentText,
                                pauseTitle: pauseAttachmentText,
                                canCut: canEditAttachments,
                                canResize: false,
                                onCopy: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(reference, forType: .string)
                                },
                                onCut: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(reference, forType: .string)
                                    onCutAttachment(attachment.id)
                                },
                                onResize: { onResizeAttachment(attachment.id, $0) },
                                onSetFrameVisible: {
                                    onSetAttachmentFrameVisible(attachment.id, $0)
                                },
                                onUpdateAspectRatio: {
                                    onUpdateAttachmentAspectRatio(attachment.id, $0)
                                }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .textSelection(.enabled)
            }
            .environment(\.openURL, OpenURLAction { url in
                onOpenURL(url) ? .handled : .systemAction
            })
        }
    }
}

private struct SafeNoteEmbed: View {
    let url: URL
    let loadText: String
    let unloadText: String
    let securityText: String
    @State private var isLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.host ?? url.absoluteString)
                        .font(.subheadline.weight(.medium))
                    Text(securityText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isLoaded ? unloadText : loadText) {
                    isLoaded.toggle()
                }
                .buttonStyle(.bordered)
            }

            if isLoaded {
                SecureNoteEmbedWebView(url: url)
                    .frame(minHeight: 280, idealHeight: 360, maxHeight: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .transition(.opacity)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(.easeInOut(duration: 0.18), value: isLoaded)
    }
}

private struct SecureNoteEmbedWebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController = WKUserContentController()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  url.scheme?.lowercased() == "https",
                  navigationAction.targetFrame != nil else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }
    }
}

private final class MarkdownSuggestionListView: NSView {
    var suggestions: [MarkdownEditorSuggestion] = [] { didSet { needsDisplay = true } }
    var selectedIndex = 0 { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.windowBackgroundColor.withAlphaComponent(0.98).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        border.lineWidth = 1
        border.stroke()

        for (index, suggestion) in suggestions.enumerated() {
            let row = NSRect(x: 4, y: 4 + CGFloat(index) * 28, width: bounds.width - 8, height: 27)
            if index == selectedIndex {
                NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
                NSBezierPath(roundedRect: row, xRadius: 5, yRadius: 5).fill()
            }
            if let image = NSImage(systemSymbolName: suggestion.symbolName, accessibilityDescription: nil) {
                image.draw(in: NSRect(x: row.minX + 7, y: row.minY + 6, width: 15, height: 15))
            }
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            let detailAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            suggestion.title.draw(at: NSPoint(x: row.minX + 28, y: row.minY + 5), withAttributes: titleAttributes)
            if !suggestion.detail.isEmpty {
                let detailSize = suggestion.detail.size(withAttributes: detailAttributes)
                suggestion.detail.draw(
                    at: NSPoint(x: row.maxX - detailSize.width - 7, y: row.minY + 6),
                    withAttributes: detailAttributes
                )
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = Int((point.y - 4) / 28)
        guard suggestions.indices.contains(index) else { return }
        onSelect?(index)
    }
}

private final class MarkdownEditorTextView: NSTextView {
    private static let emptySyntaxPairs: [(opening: String, closing: String)] = [
        ("[[goal:", "]]"),
        ("[[task:", "]]"),
        ("[[event:", "]]"),
        ("```\n", "\n```"),
        ("![", "](https://)"),
        ("[", "](https://)"),
        ("**", "**"),
        ("__", "__"),
        ("~~", "~~")
    ]

    private static let characterPairs: [(opening: String, closing: String)] = [
        ("'", "'"),
        ("\"", "\""),
        ("‘", "’"),
        ("“", "”"),
        ("{", "}"),
        ("[", "]"),
        ("(", ")"),
        ("「", "」"),
        ("【", "】"),
        ("《", "》")
    ]

    var ghostText = "" { didSet { needsDisplay = true } }
    var linkPills: [MarkdownLinkPill] = [] { didSet { needsDisplay = true } }
    var onAcceptSuggestion: (() -> Bool)?
    var onDismissSuggestion: (() -> Bool)?
    var onMoveSuggestion: ((Int) -> Bool)?
    var onSmartNewline: (() -> Bool)?
    var onTableTab: ((Bool) -> Bool)?
    var onTableReturn: (() -> Bool)?
    var onToggleChecklist: (() -> Bool)?
    var onAdjustTableSelection: (() -> Void)?
    var onPaste: (() -> Bool)?
    var onPasteAsTable: (() -> Void)?
    var onPasteAsPlainText: (() -> Void)?
    var onDropFiles: (([URL], Int) -> Bool)?
    var pasteAsTableTitle = "Paste as Table"
    var pasteAsPlainTextTitle = "Paste as Plain Text"

    override func deleteBackward(_ sender: Any?) {
        let range = selectedRange()
        let source = string as NSString
        if range.length == 0 {
            for pair in Self.emptySyntaxPairs {
                let openingLength = pair.opening.utf16.count
                let closingLength = pair.closing.utf16.count
                guard range.location >= openingLength,
                      range.location + closingLength <= source.length else { continue }
                let openingRange = NSRange(location: range.location - openingLength, length: openingLength)
                let closingRange = NSRange(location: range.location, length: closingLength)
                if source.substring(with: openingRange) == pair.opening,
                   source.substring(with: closingRange) == pair.closing {
                    insertText(
                        "",
                        replacementRange: NSRange(
                            location: openingRange.location,
                            length: openingLength + closingLength
                        )
                    )
                    setSelectedRange(NSRange(location: openingRange.location, length: 0))
                    return
                }
            }
            for pair in Self.characterPairs {
                let openingLength = pair.opening.utf16.count
                let closingLength = pair.closing.utf16.count
                guard range.location >= openingLength,
                      range.location + closingLength <= source.length else { continue }
                let openingRange = NSRange(location: range.location - openingLength, length: openingLength)
                let closingRange = NSRange(location: range.location, length: closingLength)
                if source.substring(with: openingRange) == pair.opening,
                   source.substring(with: closingRange) == pair.closing {
                    insertText(
                        "",
                        replacementRange: NSRange(
                            location: openingRange.location,
                            length: openingLength + closingLength
                        )
                    )
                    setSelectedRange(NSRange(location: openingRange.location, length: 0))
                    return
                }
            }
        }
        super.deleteBackward(sender)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53 where !ghostText.isEmpty:
            if onDismissSuggestion?() == true { return }
        case 125 where !ghostText.isEmpty:
            if onMoveSuggestion?(1) == true { return }
        case 126 where !ghostText.isEmpty:
            if onMoveSuggestion?(-1) == true { return }
        case 48:
            if onTableTab?(event.modifierFlags.contains(.shift)) == true { return }
        case 36, 76:
            if !ghostText.isEmpty, onAcceptSuggestion?() == true { return }
            if onTableReturn?() == true { return }
            if onSmartNewline?() == true { return }
        default:
            break
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if onPaste?() == true { return }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggedFileURLs(from: sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = draggedFileURLs(from: sender)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        let insertionIndex = characterIndexForInsertion(at: point)
        return onDropFiles?(urls, insertionIndex) ?? false
    }

    private func draggedFileURLs(from sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [NSURL])?.map { $0 as URL } ?? []
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 1 {
            if onToggleChecklist?() == true { return }
            onAdjustTableSelection?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())
        let table = NSMenuItem(title: pasteAsTableTitle, action: #selector(pasteAsTable(_:)), keyEquivalent: "")
        table.target = self
        menu.addItem(table)
        let plain = NSMenuItem(title: pasteAsPlainTextTitle, action: #selector(performPasteAsPlainText(_:)), keyEquivalent: "")
        plain.target = self
        menu.addItem(plain)
        return menu
    }

    @objc private func pasteAsTable(_ sender: Any?) { onPasteAsTable?() }
    @objc private func performPasteAsPlainText(_ sender: Any?) { onPasteAsPlainText?() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let window {
            for pill in linkPills {
                let screenRect = firstRect(
                    forCharacterRange: NSRange(location: pill.range.location, length: 0),
                    actualRange: nil
                )
                let localRect = convert(window.convertFromScreen(screenRect), from: nil)
                let pillRect = pill.frame(at: localRect)
                guard dirtyRect.intersects(pillRect) else { continue }
                pill.draw(at: localRect)
            }
        }
        guard !ghostText.isEmpty, selectedRange().length == 0, window != nil else { return }
        let screenRect = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        let windowRect = window!.convertFromScreen(screenRect)
        let localRect = convert(windowRect, from: nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        ghostText.draw(at: NSPoint(x: localRect.minX, y: localRect.minY), withAttributes: attributes)
    }
}

private final class AdaptiveMarkdownScrollView: NSScrollView {
    var onContentSizeChange: ((NSSize) -> Void)?

    override func layout() {
        super.layout()
        onContentSizeChange?(contentSize)
    }
}

private struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var command: MarkdownCommand?
    let settings: NoteEditorSettingsRecord
    let autocompleteEnabled: Bool
    let customSyntaxEnabled: Bool
    let linkTargets: [MarkdownLinkTarget]
    let tags: [NoteTagRecord]
    let customSyntaxDefinitions: [NoteCustomSyntaxDefinition]
    let syntaxTemplates: [NoteSyntaxTemplate]
    let attachments: [MarkdownEditorAttachment]
    let localization: MarkdownEditorLocalization
    let onOpenURL: (URL) -> Bool
    let onPasteImage: (Data) -> String?
    let onPasteFile: (URL) -> String?
    let onResizeAttachment: (UUID, Double) -> Void
    let onSetAttachmentFrameVisible: (UUID, Bool) -> Void
    let onUpdateAttachmentAspectRatio: (UUID, Double) -> Void
    let onReferencedAttachmentsChanged: (Set<UUID>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = AdaptiveMarkdownScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = MarkdownEditorTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        context.coordinator.configure(textView)
        scrollView.documentView = textView
        scrollView.onContentSizeChange = { [weak textView, weak coordinator = context.coordinator] size in
            guard let textView, let coordinator else { return }
            coordinator.configureLayout(textView, availableSize: size)
        }
        context.coordinator.configureLayout(textView, availableSize: scrollView.contentSize)
        context.coordinator.applyLiveMarkdown(to: textView)
        context.coordinator.attachmentSignature = context.coordinator.currentAttachmentSignature
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownEditorTextView else { return }
        context.coordinator.parent = self
        context.coordinator.configureTextChecking(textView)
        context.coordinator.configureLayout(textView, availableSize: scrollView.contentSize)
        let attachmentSignature = context.coordinator.currentAttachmentSignature
        if context.coordinator.attachmentSignature != attachmentSignature {
            context.coordinator.attachmentSignature = attachmentSignature
            context.coordinator.scheduleLiveMarkdown(in: textView)
        }
        if !context.coordinator.isApplyingCommand && textView.string != text {
            context.coordinator.isSynchronizingText = true
            textView.string = text
            context.coordinator.isSynchronizingText = false
            context.coordinator.scheduleLiveMarkdown(in: textView)
        }
        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            context.coordinator.schedule(command, in: textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        var lastCommandID: UUID?
        var isApplyingCommand = false
        var isSynchronizingText = false
        var isApplyingAttributes = false
        var isNormalizingTable = false
        var suggestions: [MarkdownEditorSuggestion] = []
        var selectedSuggestionIndex = 0
        let suggestionView = MarkdownSuggestionListView()
        var attachmentViews: [UUID: NSHostingView<InlineNoteAttachmentView>] = [:]
        var attachmentViewSignatures: [UUID: String] = [:]
        var attachmentSignature = ""

        var currentAttachmentSignature: String {
            parent.attachments.map {
                "\($0.id.uuidString):\($0.record.displayWidth ?? 360):\($0.record.naturalAspectRatio ?? 0):\($0.record.isFrameVisible)"
            }.joined(separator: "|")
        }

        private struct AttachmentLayout {
            let attachment: MarkdownEditorAttachment
            let range: NSRange
            let height: CGFloat
        }

        init(parent: MarkdownTextEditor) {
            self.parent = parent
            suggestionView.isHidden = true
            super.init()
            suggestionView.onSelect = { [weak self] index in
                self?.selectedSuggestionIndex = index
                _ = self?.acceptSuggestion()
            }
        }

        func configure(_ textView: MarkdownEditorTextView) {
            configureTextChecking(textView)
            textView.pasteAsTableTitle = parent.localization.pasteAsTable
            textView.pasteAsPlainTextTitle = parent.localization.pasteAsPlainText
            textView.onAcceptSuggestion = { [weak self] in self?.acceptSuggestion() ?? false }
            textView.onDismissSuggestion = { [weak self] in self?.dismissSuggestions() ?? false }
            textView.onMoveSuggestion = { [weak self] delta in self?.moveSuggestion(delta) ?? false }
            textView.onSmartNewline = { [weak self, weak textView] in
                guard let self, let textView else { return false }
                return self.insertSmartNewline(in: textView)
            }
            textView.onTableTab = { [weak self, weak textView] movesBackward in
                guard let self, let textView else { return false }
                return self.navigateTableHorizontally(in: textView, movesBackward: movesBackward)
            }
            textView.onTableReturn = { [weak self, weak textView] in
                guard let self, let textView else { return false }
                return self.exitTable(in: textView)
            }
            textView.onToggleChecklist = { [weak self, weak textView] in
                guard let self, let textView else { return false }
                return self.toggleChecklist(atSelectionIn: textView)
            }
            textView.onAdjustTableSelection = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.adjustTableSelection(in: textView)
            }
            textView.onPaste = { [weak self, weak textView] in
                guard let self, let textView else { return false }
                return self.handlePaste(in: textView, forceTable: false)
            }
            textView.onPasteAsTable = { [weak self, weak textView] in
                guard let self, let textView else { return }
                _ = self.handlePaste(in: textView, forceTable: true)
            }
            textView.onPasteAsPlainText = { [weak self, weak textView] in
                guard let self, let textView,
                      let value = NSPasteboard.general.string(forType: .string) else { return }
                self.insert(value, in: textView)
                self.publish(textView.string)
            }
            textView.registerForDraggedTypes([.fileURL])
            textView.onDropFiles = { [weak self, weak textView] urls, location in
                guard let self, let textView else { return false }
                return self.insertDroppedFiles(urls, at: location, in: textView)
            }
            suggestionView.removeFromSuperview()
            textView.addSubview(suggestionView)
        }

        func configureTextChecking(_ textView: MarkdownEditorTextView) {
            let settings = parent.settings
            textView.isContinuousSpellCheckingEnabled = settings.checksSpelling
            textView.isGrammarCheckingEnabled = settings.checksGrammar
            textView.isAutomaticSpellingCorrectionEnabled = settings.correctsSpelling
            textView.isAutomaticQuoteSubstitutionEnabled = settings.usesSmartQuotes
            textView.isAutomaticDashSubstitutionEnabled = settings.usesSmartDashes
            textView.isAutomaticTextReplacementEnabled = settings.usesTextSubstitutions
        }

        func configureLayout(_ textView: MarkdownEditorTextView, availableSize: NSSize) {
            let availableWidth = max(0, availableSize.width)
            let readableWidth = min(CGFloat(parent.settings.editorLineWidth), availableWidth)
            let horizontalInset = max(18, (availableWidth - readableWidth) / 2)
            let desiredInset = NSSize(width: horizontalInset, height: 16)
            guard textView.textContainerInset != desiredInset else { return }
            textView.textContainerInset = desiredInset
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingCommand,
                  !isSynchronizingText,
                  !isApplyingAttributes,
                  !isNormalizingTable,
                  let textView = notification.object as? MarkdownEditorTextView else { return }
            normalizeMarkdownTableIfNeeded(in: textView)
            publish(textView.string)
            publishAttachmentReferences(in: textView.string)
            scheduleLiveMarkdown(in: textView)
            updateSuggestions(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingAttributes, let textView = notification.object as? MarkdownEditorTextView else { return }
            scheduleLiveMarkdown(in: textView)
            updateSuggestions(in: textView)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }
            return parent.onOpenURL(url)
        }

        func schedule(_ command: MarkdownCommand, in textView: NSTextView) {
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.apply(command.action, to: textView)
                self.publish(textView.string)
                if self.parent.command?.id == command.id {
                    self.parent.command = nil
                }
            }
        }

        func scheduleLiveMarkdown(in textView: NSTextView) {
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.applyLiveMarkdown(to: textView)
            }
        }

        private func publish(_ value: String) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.text != value else { return }
                self.parent.text = value
            }
        }

        func apply(_ action: MarkdownAction, to textView: NSTextView) {
            isApplyingCommand = true
            defer { isApplyingCommand = false }

            switch action {
            case .heading:
                prefixSelectedLines(in: textView, prefix: { _ in "# " })
            case .bold:
                wrapSelection(in: textView, prefix: "**", suffix: "**")
            case .italic:
                wrapSelection(in: textView, prefix: "*", suffix: "*")
            case .strikethrough:
                wrapSelection(in: textView, prefix: "~~", suffix: "~~")
            case .bulletList:
                prefixSelectedLines(in: textView, prefix: { _ in "- " })
            case .numberedList:
                prefixSelectedLines(in: textView, prefix: { index in "\(index + 1). " })
            case .checklist:
                prefixSelectedLines(in: textView, prefix: { _ in "- [ ] " })
            case .quote:
                prefixSelectedLines(in: textView, prefix: { _ in "> " })
            case .inlineCode:
                wrapSelection(in: textView, prefix: "`", suffix: "`")
            case .codeBlock:
                wrapSelection(in: textView, prefix: "```\n", suffix: "\n```")
            case .link:
                wrapSelection(in: textView, prefix: "[", suffix: "](https://)")
            case .image:
                wrapSelection(in: textView, prefix: "![", suffix: "](https://)")
            case .embed:
                insert("@[embed](https://)", in: textView, cursorOffset: 17)
            case .orchestranaLink(let kind):
                let range = textView.selectedRange()
                let source = textView.string as NSString
                let selected = range.length > 0 ? source.substring(with: range) : ""
                let prefix = "[[\(kind.rawValue):"
                textView.insertText(prefix + selected, replacementRange: range)
                textView.setSelectedRange(NSRange(
                    location: range.location + prefix.utf16.count + selected.utf16.count,
                    length: 0
                ))
            case .table:
                insert("\n\n|   |   |\n| --- | --- |\n|   |   |\n\n", in: textView, cursorOffset: 4)
                if let editor = textView as? MarkdownEditorTextView {
                    normalizeMarkdownTableIfNeeded(in: editor)
                }
            case .tableRow:
                _ = addTableRow(in: textView)
            case .tableColumn:
                _ = addTableColumn(in: textView)
            case .divider:
                insert("\n\n---\n\n", in: textView)
            case .insertText(let value):
                insert(value, in: textView)
            }
            applyLiveMarkdown(to: textView)
            if let editor = textView as? MarkdownEditorTextView {
                updateSuggestions(in: editor)
            }
        }

        func applyLiveMarkdown(to textView: NSTextView) {
            guard !isApplyingAttributes, let storage = textView.textStorage else { return }
            isApplyingAttributes = true
            defer { isApplyingAttributes = false }
            let source = textView.string as NSString
            let fullRange = NSRange(location: 0, length: source.length)
            let baseFont = editorBaseFont
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacing = parent.settings.paragraphSpacing
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]

            storage.beginEditing()
            storage.setAttributes(baseAttributes, range: fullRange)
            var linkPills: [MarkdownLinkPill] = []
            var attachmentLayouts: [AttachmentLayout] = []
            if source.length > 0, parent.settings.livePreviewEnabled, !parent.settings.sourceModeEnabled {
                let selectedLocation = min(textView.selectedRange().location, source.length)
                let activeLineRange = source.lineRange(for: NSRange(location: selectedLocation, length: 0))
                var location = 0
                var isInCodeBlock = false

                while location < source.length {
                    let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
                    let rawLine = source.substring(with: lineRange)
                    let line = rawLine.trimmingCharacters(in: .newlines)
                    let contentRange = NSRange(location: lineRange.location, length: (line as NSString).length)
                    let trimmed = line.trimmingCharacters(in: .whitespaces)

                    if trimmed.hasPrefix("```") {
                        if !parent.settings.showsSyntaxInActiveRange || NSIntersectionRange(lineRange, activeLineRange).length == 0 {
                            conceal(contentRange, in: storage)
                        }
                        isInCodeBlock.toggle()
                    } else if isInCodeBlock {
                        storage.addAttributes([
                            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                            .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.18)
                        ], range: contentRange)
                    } else {
                        styleCompletedLine(
                            line,
                            range: contentRange,
                            activeLineRange: activeLineRange,
                            cursorLocation: selectedLocation,
                            in: storage
                        )
                    }

                    let nextLocation = NSMaxRange(lineRange)
                    if nextLocation <= location { break }
                    location = nextLocation
                }
                linkPills = styleOrchestranaTypePills(in: source, storage: storage)
                attachmentLayouts = styleAttachments(in: source, storage: storage)
            }
            storage.endEditing()
            if let editor = textView as? MarkdownEditorTextView {
                editor.linkPills = linkPills
                updateAttachmentOverlays(attachmentLayouts, in: editor)
            }
            textView.typingAttributes = baseAttributes
        }

        private var editorBaseFont: NSFont {
            switch parent.settings.selectedStyle {
            case .default: return .systemFont(ofSize: 14)
            case .minimal: return .systemFont(ofSize: 14, weight: .light)
            case .compact: return .systemFont(ofSize: 12.5)
            case .academic: return NSFont(name: "New York", size: 15) ?? .systemFont(ofSize: 15)
            case .technical: return .monospacedSystemFont(ofSize: 13, weight: .regular)
            case .journal: return .systemFont(ofSize: 15, weight: .regular)
            case .focused: return .systemFont(ofSize: 15, weight: .medium)
            }
        }

        private func editorHeadingFont(level: Int) -> NSFont {
            let baseSize: CGFloat = level == 1 ? 24 : (level == 2 ? 20 : (level == 3 ? 17 : 15))
            switch parent.settings.selectedStyle {
            case .academic:
                return NSFont(name: "New York", size: baseSize + 1) ?? .systemFont(ofSize: baseSize, weight: .bold)
            case .technical:
                return .monospacedSystemFont(ofSize: max(14, baseSize - 2), weight: .bold)
            case .compact:
                return .systemFont(ofSize: max(13, baseSize - 3), weight: .semibold)
            case .journal:
                return .systemFont(ofSize: baseSize + 1, weight: .semibold)
            case .focused:
                return .systemFont(ofSize: baseSize, weight: .bold)
            case .default, .minimal:
                return .systemFont(ofSize: baseSize, weight: .semibold)
            }
        }

        private func styleAttachments(
            in source: NSString,
            storage: NSTextStorage
        ) -> [AttachmentLayout] {
            let pattern = #"(?m)^!?\[[^\]\n]*\]\(attachment://([0-9A-Fa-f-]{36})\)[ \t]*$"#
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
            let attachmentByID = Dictionary(uniqueKeysWithValues: parent.attachments.map { ($0.id, $0) })
            var layouts: [AttachmentLayout] = []
            for match in expression.matches(
                in: source as String,
                range: NSRange(location: 0, length: source.length)
            ) {
                let rawID = source.substring(with: match.range(at: 1))
                guard let id = UUID(uuidString: rawID), let attachment = attachmentByID[id] else { continue }
                let width = CGFloat(attachment.record.displayWidth ?? 360)
                let height = attachmentHeight(for: attachment.record, width: width)
                let paragraph = NSMutableParagraphStyle()
                paragraph.minimumLineHeight = height
                paragraph.maximumLineHeight = height
                storage.addAttribute(.paragraphStyle, value: paragraph, range: match.range)
                conceal(match.range, in: storage)
                layouts.append(AttachmentLayout(attachment: attachment, range: match.range, height: height))
            }
            return layouts
        }

        private func attachmentHeight(
            for attachment: NoteAttachmentRecord,
            width: CGFloat
        ) -> CGFloat {
            switch attachment.mediaType {
            case .image, .video:
                return width / CGFloat(attachment.naturalAspectRatio ?? (16.0 / 9.0))
            case .audio: return width + 42
            case .pdf: return min(540, max(245, width * 1.05 + 34))
            case .file: return 82
            }
        }

        private func updateAttachmentOverlays(
            _ layouts: [AttachmentLayout],
            in textView: MarkdownEditorTextView
        ) {
            let activeIDs = Set(layouts.map(\.attachment.id))
            let staleIDs = attachmentViews.keys.filter { !activeIDs.contains($0) }
            for id in staleIDs {
                attachmentViews.removeValue(forKey: id)?.removeFromSuperview()
                attachmentViewSignatures.removeValue(forKey: id)
            }

            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let availableWidth = max(220, textView.bounds.width - textView.textContainerInset.width * 2)

            for layout in layouts {
                let attachmentID = layout.attachment.id
                let rootView = InlineNoteAttachmentView(
                    attachment: layout.attachment,
                    availableWidth: availableWidth,
                    copyTitle: parent.localization.copy,
                    cutTitle: parent.localization.cut,
                    resizeTitle: parent.localization.resize,
                    showFrameTitle: parent.localization.showFrame,
                    hideFrameTitle: parent.localization.hideFrame,
                    playTitle: parent.localization.play,
                    pauseTitle: parent.localization.pause,
                    canCut: true,
                    canResize: true,
                    onCopy: { [weak self, weak textView] in
                        guard let self, let textView else { return }
                        guard let range = self.attachmentRange(for: attachmentID, in: textView) else { return }
                        textView.setSelectedRange(range)
                        textView.copy(nil)
                        _ = self.dismissSuggestions()
                    },
                    onCut: { [weak self, weak textView] in
                        guard let self, let textView else { return }
                        guard let range = self.attachmentRange(for: attachmentID, in: textView) else { return }
                        textView.setSelectedRange(range)
                        textView.cut(nil)
                        self.publish(textView.string)
                    },
                    onResize: { [weak self] width in
                        self?.parent.onResizeAttachment(attachmentID, width)
                    },
                    onSetFrameVisible: { [weak self] isVisible in
                        self?.parent.onSetAttachmentFrameVisible(attachmentID, isVisible)
                    },
                    onUpdateAspectRatio: { [weak self] aspectRatio in
                        self?.parent.onUpdateAttachmentAspectRatio(attachmentID, aspectRatio)
                    }
                )
                let viewSignature = [
                    String(layout.attachment.record.displayWidth ?? 360),
                    String(layout.attachment.record.naturalAspectRatio ?? 0),
                    String(layout.attachment.record.isFrameVisible),
                    String(Int(availableWidth.rounded())),
                    parent.localization.copy,
                    parent.localization.cut,
                    parent.localization.resize,
                    parent.localization.showFrame,
                    parent.localization.hideFrame,
                    parent.localization.play,
                    parent.localization.pause
                ].joined(separator: "|")
                let hostingView: NSHostingView<InlineNoteAttachmentView>
                if let existing = attachmentViews[attachmentID] {
                    if attachmentViewSignatures[attachmentID] != viewSignature {
                        existing.rootView = rootView
                        attachmentViewSignatures[attachmentID] = viewSignature
                    }
                    hostingView = existing
                } else {
                    hostingView = NSHostingView(rootView: rootView)
                    hostingView.wantsLayer = true
                    hostingView.layer?.backgroundColor = .clear
                    attachmentViews[attachmentID] = hostingView
                    attachmentViewSignatures[attachmentID] = viewSignature
                    textView.addSubview(hostingView)
                }

                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: layout.range,
                    actualCharacterRange: nil
                )
                let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                hostingView.frame = NSRect(
                    x: textView.textContainerOrigin.x,
                    y: textView.textContainerOrigin.y + lineRect.minY,
                    width: availableWidth,
                    height: layout.height
                )
            }
        }

        private func attachmentRange(
            for attachmentID: UUID,
            in textView: NSTextView
        ) -> NSRange? {
            let pattern = "(?m)^!?\\[[^\\]\\n]*\\]\\(attachment://(attachmentID.uuidString)\\)[ \\t]*$"
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
            let source = textView.string as NSString
            return expression.firstMatch(
                in: textView.string,
                range: NSRange(location: 0, length: source.length)
            )?.range
        }

        private func publishAttachmentReferences(in value: String) {
            let pattern = #"attachment://([0-9A-Fa-f-]{36})"#
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
            let source = value as NSString
            let ids = Set(expression.matches(
                in: value,
                range: NSRange(location: 0, length: source.length)
            ).compactMap { UUID(uuidString: source.substring(with: $0.range(at: 1))) })
            parent.onReferencedAttachmentsChanged(ids)
        }

        private func styleOrchestranaTypePills(
            in source: NSString,
            storage: NSTextStorage
        ) -> [MarkdownLinkPill] {
            guard let expression = try? NSRegularExpression(pattern: #"\[\[(goal|task|event):"#) else {
                return []
            }
            var pills: [MarkdownLinkPill] = []
            for match in expression.matches(
                in: source as String,
                range: NSRange(location: 0, length: source.length)
            ) {
                let kindValue = source.substring(with: match.range(at: 1))
                guard let kind = MarkdownLinkTarget.Kind(rawValue: kindValue) else { continue }
                let label: String
                switch kind {
                case .goal: label = parent.localization.goal
                case .task: label = parent.localization.task
                case .event: label = parent.localization.event
                }
                let pill = MarkdownLinkPill(range: match.range, kind: kind, label: label)
                applyPillLayout(pill, source: source, storage: storage)
                pills.append(pill)

                let filterStart = NSMaxRange(match.range)
                if let filter = linkFilterOptions(for: kindValue).first(where: { option in
                    let tokenLength = option.syntaxToken.utf16.count
                    guard filterStart + tokenLength <= source.length else { return false }
                    return source.substring(with: NSRange(location: filterStart, length: tokenLength)) == option.syntaxToken
                }) {
                    let filterRange = NSRange(location: filterStart, length: filter.syntaxToken.utf16.count)
                    let filterPill = MarkdownLinkPill(
                        range: filterRange,
                        filterValue: filter.value,
                        label: filter.title
                    )
                    applyPillLayout(filterPill, source: source, storage: storage)
                    pills.append(filterPill)
                    let separatorLocation = NSMaxRange(filterRange)
                    if separatorLocation < source.length,
                       source.substring(with: NSRange(location: separatorLocation, length: 1)) == " " {
                        conceal(NSRange(location: separatorLocation, length: 1), in: storage)
                    }
                }

                let remainder = NSRange(
                    location: NSMaxRange(match.range),
                    length: source.length - NSMaxRange(match.range)
                )
                let lineEnd = source.range(of: "\n", options: [], range: remainder).location
                let nextToken = source.range(of: "[[", options: [], range: remainder).location
                let searchEnd = [lineEnd, nextToken]
                    .filter { $0 != NSNotFound }
                    .min() ?? source.length
                let closingSearchRange = NSRange(
                    location: remainder.location,
                    length: max(0, searchEnd - remainder.location)
                )
                let closingRange = source.range(of: "]]", options: [], range: closingSearchRange)
                if closingRange.location != NSNotFound {
                    conceal(closingRange, in: storage)
                }
            }
            return pills
        }

        private func applyPillLayout(
            _ pill: MarkdownLinkPill,
            source: NSString,
            storage: NSTextStorage
        ) {
            conceal(pill.range, in: storage)
            let anchorRange = NSRange(location: pill.range.location, length: 1)
            let anchorFont = NSFont.systemFont(ofSize: 14)
            let anchorText = source.substring(with: anchorRange)
            let anchorWidth = (anchorText as NSString).size(withAttributes: [.font: anchorFont]).width
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .font: anchorFont,
                    .kern: max(0, pill.layoutWidth - anchorWidth)
                ], range: anchorRange)
        }

        private func styleCompletedLine(
            _ line: String,
            range: NSRange,
            activeLineRange: NSRange,
            cursorLocation: Int,
            in storage: NSTextStorage
        ) {
            guard range.length > 0 else { return }
            let nsLine = line as NSString
            if isMarkdownTableLine(line) {
                storage.addAttribute(
                    .font,
                    value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    range: range
                )
                return
            }
            let headingExpression = try? NSRegularExpression(pattern: "^(#{1,6})\\s+")
            if let match = headingExpression?.firstMatch(
                in: line,
                range: NSRange(location: 0, length: nsLine.length)
            ) {
                let markerRange = offset(match.range, by: range.location)
                if !parent.settings.showsSyntaxInActiveRange || NSIntersectionRange(range, activeLineRange).length == 0 {
                    conceal(markerRange, in: storage)
                }
                let contentRange = NSRange(
                    location: markerRange.location + markerRange.length,
                    length: max(0, NSMaxRange(range) - NSMaxRange(markerRange))
                )
                let level = max(1, match.range(at: 1).length)
                storage.addAttribute(
                    .font,
                    value: editorHeadingFont(level: level),
                    range: contentRange
                )
            }

            if let quoteMatch = firstMatch("^>\\s+", in: line) {
                let markerRange = offset(quoteMatch.range, by: range.location)
                if !parent.settings.showsSyntaxInActiveRange || NSIntersectionRange(range, activeLineRange).length == 0 {
                    conceal(markerRange, in: storage)
                }
                let contentRange = NSRange(
                    location: NSMaxRange(markerRange),
                    length: max(0, NSMaxRange(range) - NSMaxRange(markerRange))
                )
                storage.addAttributes([
                    .font: NSFontManager.shared.convert(
                        editorBaseFont,
                        toHaveTrait: .italicFontMask
                    ),
                    .foregroundColor: NSColor.secondaryLabelColor
                ], range: contentRange)
            }

            styleInline("\\*\\*([^*]+)\\*\\*", contentGroup: 1, in: line, lineRange: range, cursorLocation: cursorLocation, storage: storage) {
                [.font: NSFontManager.shared.convert(self.editorBaseFont, toHaveTrait: .boldFontMask)]
            }
            styleInline("(?<!\\*)\\*([^*]+)\\*(?!\\*)", contentGroup: 1, in: line, lineRange: range, cursorLocation: cursorLocation, storage: storage) {
                [.font: NSFontManager.shared.convert(self.editorBaseFont, toHaveTrait: .italicFontMask)]
            }
            styleInline("_([^_]+)_", contentGroup: 1, in: line, lineRange: range, cursorLocation: cursorLocation, storage: storage) {
                [.font: NSFontManager.shared.convert(self.editorBaseFont, toHaveTrait: .italicFontMask)]
            }
            styleInline("~~([^~]+)~~", contentGroup: 1, in: line, lineRange: range, cursorLocation: cursorLocation, storage: storage) {
                [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
            }
            styleInline("(?<!`)``([^`]+)``(?!`)", contentGroup: 1, in: line, lineRange: range, cursorLocation: cursorLocation, storage: storage) {
                [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.25)
                ]
            }
            styleInline("(?<!`)`([^`]+)`(?!`)", contentGroup: 1, in: line, lineRange: range, cursorLocation: cursorLocation, storage: storage) {
                [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.25)
                ]
            }

            guard let linkExpression = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)") else {
                return
            }
            let matches = linkExpression.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches.reversed() {
                let full = offset(match.range, by: range.location)
                let label = offset(match.range(at: 1), by: range.location)
                let urlText = nsLine.substring(with: match.range(at: 2))
                if !parent.settings.showsSyntaxInActiveRange || !cursorIsInside(cursorLocation, range: full) {
                    conceal(NSRange(location: full.location, length: label.location - full.location), in: storage)
                    conceal(NSRange(location: NSMaxRange(label), length: NSMaxRange(full) - NSMaxRange(label)), in: storage)
                }
                var attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                if let url = URL(string: urlText) { attributes[.link] = url }
                storage.addAttributes(attributes, range: label)
            }

            styleOrchestranaLinks(in: line, lineRange: range, cursorLocation: cursorLocation, storage: storage)
            styleCustomSyntax(in: line, lineRange: range, storage: storage)
        }

        private func styleInline(
            _ pattern: String,
            contentGroup: Int,
            in line: String,
            lineRange: NSRange,
            cursorLocation: Int,
            storage: NSTextStorage,
            attributes: () -> [NSAttributedString.Key: Any]
        ) {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
            let lineLength = (line as NSString).length
            for match in expression.matches(
                in: line,
                range: NSRange(location: 0, length: lineLength)
            ).reversed() {
                let full = offset(match.range, by: lineRange.location)
                let content = offset(match.range(at: contentGroup), by: lineRange.location)
                if !parent.settings.showsSyntaxInActiveRange || !cursorIsInside(cursorLocation, range: full) {
                    conceal(NSRange(location: full.location, length: content.location - full.location), in: storage)
                    conceal(NSRange(location: NSMaxRange(content), length: NSMaxRange(full) - NSMaxRange(content)), in: storage)
                }
                storage.addAttributes(attributes(), range: content)
            }
        }

        private func styleOrchestranaLinks(
            in line: String,
            lineRange: NSRange,
            cursorLocation: Int,
            storage: NSTextStorage
        ) {
            let pattern = #"\[\[(goal|task|event):([0-9A-Fa-f-]{36})\|([^\]]+)\]\]"#
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
            let nsLine = line as NSString
            for match in expression.matches(in: line, range: NSRange(location: 0, length: nsLine.length)).reversed() {
                let full = offset(match.range, by: lineRange.location)
                let label = offset(match.range(at: 3), by: lineRange.location)
                let kind = nsLine.substring(with: match.range(at: 1))
                let id = nsLine.substring(with: match.range(at: 2))
                let isAvailable = UUID(uuidString: id).map { linkID in
                    parent.linkTargets.contains { $0.id == linkID && $0.kind.rawValue == kind }
                } ?? false
                let linkColor: NSColor
                switch MarkdownLinkTarget.Kind(rawValue: kind) {
                case .goal: linkColor = .systemBlue
                case .task: linkColor = .systemGreen
                case .event: linkColor = .systemOrange
                case nil: linkColor = .controlAccentColor
                }
                let typePrefixLength = "[[\(kind):".utf16.count
                let internalRange = NSRange(
                    location: full.location + typePrefixLength,
                    length: max(0, label.location - full.location - typePrefixLength)
                )
                conceal(internalRange, in: storage)
                conceal(NSRange(location: NSMaxRange(label), length: NSMaxRange(full) - NSMaxRange(label)), in: storage)
                var attributes: [NSAttributedString.Key: Any] = isAvailable
                    ? [
                        .foregroundColor: linkColor,
                        .backgroundColor: linkColor.withAlphaComponent(0.10),
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ]
                    : [
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue
                    ]
                if isAvailable,
                   !cursorIsInside(cursorLocation, range: full),
                   let url = URL(string: "orchestrana://\(kind)/\(id)") {
                    attributes[.link] = url
                }
                storage.addAttributes(attributes, range: label)
            }
        }

        private func styleCustomSyntax(in line: String, lineRange: NSRange, storage: NSTextStorage) {
            guard parent.customSyntaxEnabled else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let definition = parent.customSyntaxDefinitions.first(where: { trimmed.hasPrefix($0.trigger) }) else { return }
            let color = nsColor(definition.color)
            storage.addAttributes([
                .foregroundColor: color,
                .backgroundColor: color.withAlphaComponent(definition.renderingStyle == .highlight ? 0.18 : 0.09)
            ], range: lineRange)
        }

        private func nsColor(_ color: NoteTagColor) -> NSColor {
            switch color {
            case .red: return .systemRed
            case .purple: return .systemPurple
            case .orange: return .systemOrange
            case .yellow: return .systemYellow
            case .blue: return .systemBlue
            case .green: return .systemGreen
            case .gray: return .systemGray
            }
        }

        private func markdownSuggestions(
            in prefix: NSString,
            source: NSString,
            at location: Int
        ) -> [MarkdownEditorSuggestion] {
            let prefixString = prefix as String
            let currentLine = String(prefixString.split(separator: "\n", omittingEmptySubsequences: false).last ?? "")

            func closingSuggestion(
                pattern: String,
                id: String,
                title: String,
                symbolName: String,
                suffix: String,
                delimiter: String? = nil
            ) -> MarkdownEditorSuggestion? {
                if id == "italic-star",
                   currentLine.range(of: #"^\s*\*\s+"#, options: .regularExpression) != nil {
                    return nil
                }
                if let delimiter {
                    var delimiterLine = currentLine
                    if id == "italic-star" {
                        delimiterLine = delimiterLine.replacingOccurrences(of: "**", with: "")
                    } else if id == "code" {
                        delimiterLine = delimiterLine.replacingOccurrences(of: "```", with: "")
                    }
                    let delimiterCount = delimiterLine.components(separatedBy: delimiter).count - 1
                    guard delimiterCount % 2 == 1 else { return nil }
                }
                guard let expression = try? NSRegularExpression(pattern: pattern),
                      expression.firstMatch(
                        in: prefix as String,
                        range: NSRange(location: 0, length: prefix.length)
                      ) != nil else { return nil }
                let consumesBracket = (id == "link" || id == "image")
                    && location < source.length
                    && source.substring(with: NSRange(location: location, length: 1)) == "]"
                return MarkdownEditorSuggestion(
                    id: "markdown-close-\(id)-\(location)",
                    kind: .markdown,
                    title: title,
                    detail: parent.localization.markdown,
                    symbolName: symbolName,
                    replacement: suffix,
                    replacementRange: NSRange(location: location, length: consumesBracket ? 1 : 0),
                    ghostText: suffix
                )
            }

            let closingPatterns: [(String, String, String, String, String, String?)] = [
                (#"\*\*([^\n]+?)(?<!\*)$"#, "bold", "**...**", "bold", "**", "**"),
                (#"~~([^\n]+?)(?<!~)$"#, "strikethrough", "~~...~~", "strikethrough", "~~", "~~"),
                (#"(?<!`)``([^`\n]*)$"#, "code-double", "``...``", "chevron.left.forwardslash.chevron.right", "``", "``"),
                (#"(?<!`)`([^`\n]*)$"#, "code", "`...`", "chevron.left.forwardslash.chevron.right", "`", "`"),
                (#"!\[([^\[\]\n]+)$"#, "image", "![...](...)", "photo", "](https://)", nil),
                (#"(?<![!\[])\[([^\[\]\n]+)$"#, "link", "[...](...)", "link", "](https://)", nil),
                (#"(?<!\*)\*([^*\n]+)$"#, "italic-star", "*...*", "italic", "*", "*"),
                (#"(?<![\p{L}\p{N}_])_([^_\n]+)$"#, "italic-underscore", "_..._", "italic", "_", "_")
            ]
            let closing = closingPatterns.compactMap {
                closingSuggestion(
                    pattern: $0.0,
                    id: $0.1,
                    title: $0.2,
                    symbolName: $0.3,
                    suffix: $0.4,
                    delimiter: $0.5
                )
            }
            if !closing.isEmpty { return closing }

            if let symbolSuggestion = symbolClosingSuggestion(in: currentLine, at: location) {
                return [symbolSuggestion]
            }

            let lineLength = (currentLine as NSString).length
            let lineRange = NSRange(location: max(0, location - lineLength), length: lineLength)
            let fenceCount = prefixString.components(separatedBy: "```").count - 1

            if fenceCount % 2 == 1,
               currentLine.range(of: #"^```[A-Za-z0-9_+.-]*$"#, options: .regularExpression) != nil {
                return [MarkdownEditorSuggestion(
                    id: "markdown-open-fence-\(location)",
                    kind: .markdown,
                    title: "``` ... ```",
                    detail: parent.localization.markdown,
                    symbolName: "curlybraces.square",
                    replacement: "\n\n```",
                    replacementRange: NSRange(location: location, length: 0),
                    ghostText: "\n\n```",
                    cursorOffset: 1
                )]
            }

            let blocks: [(String, String, String, String)] = [
                ("#", "# ", "# Heading", "textformat.size"),
                ("##", "## ", "## Heading", "textformat.size"),
                ("###", "### ", "### Heading", "textformat.size"),
                ("-", "- ", "- List", "list.bullet"),
                ("1", "1. ", "1. List", "list.number"),
                (">", "> ", "> Quote", "text.quote"),
                ("- [", "- [ ] ", "- [ ] Checklist", "checklist")
            ]
            if let block = blocks.first(where: { $0.0 == currentLine }) {
                return [MarkdownEditorSuggestion(
                    id: "markdown-block-\(block.0)-\(location)",
                    kind: .markdown,
                    title: block.2,
                    detail: parent.localization.markdown,
                    symbolName: block.3,
                    replacement: block.1,
                    replacementRange: lineRange,
                    ghostText: String(block.1.dropFirst(currentLine.count))
                )]
            }

            if fenceCount % 2 == 1,
               let expression = try? NSRegularExpression(pattern: #"```[^\n]*\n[\s\S]+$"#),
               expression.firstMatch(in: prefixString, range: NSRange(location: 0, length: prefix.length)) != nil {
                return [MarkdownEditorSuggestion(
                    id: "markdown-close-fence-\(location)",
                    kind: .markdown,
                    title: "``` ... ```",
                    detail: parent.localization.markdown,
                    symbolName: "curlybraces.square",
                    replacement: "\n```",
                    replacementRange: NSRange(location: location, length: 0),
                    ghostText: "\n```"
                )]
            }
            return []
        }

        private func symbolClosingSuggestion(
            in currentLine: String,
            at location: Int
        ) -> MarkdownEditorSuggestion? {
            let pairs: [(opening: Character, closing: Character)] = [
                ("'", "'"), ("\"", "\""), ("‘", "’"), ("“", "”"),
                ("{", "}"), ("[", "]"), ("(", ")"),
                ("「", "」"), ("【", "】"), ("《", "》")
            ]
            let characters = Array(currentLine)
            var candidates: [(offset: Int, closing: Character)] = []

            for pair in pairs {
                if pair.opening == pair.closing {
                    var openingOffset: Int?
                    for (offset, character) in characters.enumerated() where character == pair.opening {
                        let previous = offset > 0 ? characters[offset - 1] : nil
                        let next = offset + 1 < characters.count ? characters[offset + 1] : nil
                        let isApostropheInWord = pair.opening == "'"
                            && previous?.isLetter == true
                            && next?.isLetter == true
                        if isApostropheInWord { continue }
                        if openingOffset != nil {
                            openingOffset = nil
                        } else if pair.opening != "'"
                            || previous == nil
                            || (previous?.isLetter != true && previous?.isNumber != true) {
                            openingOffset = offset
                        }
                    }
                    if let openingOffset {
                        candidates.append((openingOffset, pair.closing))
                    }
                } else {
                    var openingOffsets: [Int] = []
                    for (offset, character) in currentLine.enumerated() {
                        if character == pair.opening {
                            openingOffsets.append(offset)
                        } else if character == pair.closing, !openingOffsets.isEmpty {
                            openingOffsets.removeLast()
                        }
                    }
                    if let openingOffset = openingOffsets.last {
                        candidates.append((openingOffset, pair.closing))
                    }
                }
            }

            guard let candidate = candidates.max(by: { $0.offset < $1.offset }) else { return nil }
            let closing = String(candidate.closing)
            return MarkdownEditorSuggestion(
                id: "symbol-close-\(candidate.closing)-\(location)",
                kind: .symbol,
                title: closing,
                detail: "",
                symbolName: "character.cursor.ibeam",
                replacement: closing,
                replacementRange: NSRange(location: location, length: 0),
                ghostText: closing
            )
        }

        private func linkFilterOptions(for kindRaw: String) -> [(
            syntaxToken: String,
            value: String,
            title: String,
            symbol: String
        )] {
            switch kindRaw {
            case MarkdownLinkTarget.Kind.goal.rawValue:
                return [
                    ("status:active", "active", parent.localization.active, "play.circle"),
                    ("status:paused", "paused", parent.localization.paused, "pause.circle"),
                    ("status:completed", "completed", parent.localization.completed, "checkmark.circle")
                ]
            case MarkdownLinkTarget.Kind.task.rawValue:
                return [
                    ("status:active", "active", parent.localization.active, "circle.dashed"),
                    ("status:completed", "completed", parent.localization.completed, "checkmark.circle")
                ]
            case MarkdownLinkTarget.Kind.event.rawValue:
                return [
                    ("time:upcoming", "upcoming", parent.localization.upcoming, "calendar.badge.clock"),
                    ("time:past", "past", parent.localization.past, "clock.arrow.circlepath")
                ]
            default:
                return []
            }
        }

        private func updateSuggestions(in textView: MarkdownEditorTextView) {
            guard parent.autocompleteEnabled,
                  parent.settings.syntaxAutocompleteEnabled,
                  parent.settings.showsSuggestionsAutomatically,
                  textView.selectedRange().length == 0 else {
                _ = dismissSuggestions()
                return
            }
            let location = min(textView.selectedRange().location, (textView.string as NSString).length)
            let sourceNSString = textView.string as NSString
            let prefix = sourceNSString.substring(to: location)
            let prefixNSString = prefix as NSString
            var matches: [MarkdownEditorSuggestion] = []
            let markdownMatches = parent.settings.suggestsMarkdown
                ? markdownSuggestions(in: prefixNSString, source: sourceNSString, at: location)
                : []

            if parent.settings.suggestsOrchestranaLinks,
               let expression = try? NSRegularExpression(pattern: #"\[\[(goal|task|event):([^\]\n]*)$"#),
               let match = expression.firstMatch(in: prefix, range: NSRange(location: 0, length: prefixNSString.length)) {
                let kindRaw = prefixNSString.substring(with: match.range(at: 1))
                let rawQuery = prefixNSString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                let filterOptions = linkFilterOptions(for: kindRaw)
                let selectedFilter = filterOptions.first { rawQuery.hasPrefix($0.syntaxToken) }
                let searchQuery = selectedFilter.map {
                    String(rawQuery.dropFirst($0.syntaxToken.count)).trimmingCharacters(in: .whitespaces)
                } ?? rawQuery
                let searchTerms = searchQuery.split(whereSeparator: \.isWhitespace).map(String.init)
                let trailingAutoCloseLength = location + 2 <= sourceNSString.length
                    && sourceNSString.substring(with: NSRange(location: location, length: 2)) == "]]"
                    ? 2
                    : 0
                let lastQueryPart = rawQuery.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
                let isTypingFilter = lastQueryPart.hasPrefix("status:") || lastQueryPart.hasPrefix("time:")
                let visibleFilterOptions: [(syntaxToken: String, value: String, title: String, symbol: String)]
                if selectedFilter != nil {
                    visibleFilterOptions = []
                } else if rawQuery.isEmpty {
                    visibleFilterOptions = filterOptions
                } else if isTypingFilter {
                    visibleFilterOptions = filterOptions.filter { $0.syntaxToken.hasPrefix(lastQueryPart) }
                } else {
                    visibleFilterOptions = filterOptions
                }
                let filterSuggestions = visibleFilterOptions.map { option in
                    let preservedQuery = searchTerms.joined(separator: " ")
                    let replacement = "[[\(kindRaw):\(option.syntaxToken)\(preservedQuery)"
                    return MarkdownEditorSuggestion(
                        id: "link-filter-\(kindRaw)-\(option.value)",
                        kind: .linkFilter,
                        title: option.title,
                        detail: parent.localization.filter,
                        symbolName: option.symbol,
                        replacement: replacement,
                        replacementRange: match.range,
                        ghostText: searchTerms.isEmpty && option.syntaxToken.hasPrefix(lastQueryPart)
                            ? String(option.syntaxToken.dropFirst(lastQueryPart.count))
                            : "  \(option.title)"
                    )
                }
                let objectSuggestions = parent.linkTargets
                    .filter { target in
                        target.kind.rawValue == kindRaw
                            && (selectedFilter.map { target.filters.contains($0.value) } ?? true)
                            && searchTerms.allSatisfy {
                                [target.title, target.detail]
                                    .joined(separator: " ")
                                    .localizedStandardContains($0)
                            }
                    }
                    .prefix(6)
                    .map { target in
                        MarkdownEditorSuggestion(
                            id: "link-\(target.kind.rawValue)-\(target.id)",
                            kind: .link,
                            title: target.title,
                            detail: target.detail,
                            symbolName: target.kind == .goal ? "target" : (target.kind == .task ? "checklist" : "calendar"),
                            replacement: target.replacement,
                            replacementRange: NSRange(
                                location: match.range.location,
                                length: match.range.length + trailingAutoCloseLength
                            ),
                            ghostText: " → \(target.title)"
                        )
                    }
                if selectedFilter == nil, !searchTerms.isEmpty, !isTypingFilter {
                    matches = objectSuggestions + filterSuggestions
                } else {
                    matches = filterSuggestions + objectSuggestions
                }
            } else if !markdownMatches.isEmpty {
                matches = markdownMatches
            } else if parent.settings.suggestsTags,
                      let expression = try? NSRegularExpression(pattern: #"#([\p{L}\p{N}_-]*)$"#),
                      let match = expression.firstMatch(in: prefix, range: NSRange(location: 0, length: prefixNSString.length)) {
                let query = prefixNSString.substring(with: match.range(at: 1))
                matches = parent.tags
                    .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
                    .prefix(6)
                    .map { tag in
                        MarkdownEditorSuggestion(
                            id: "tag-\(tag.id)", kind: .tag, title: tag.name, detail: parent.localization.tag,
                            symbolName: tag.symbolName ?? "tag", replacement: "#\(tag.name.replacingOccurrences(of: " ", with: "-"))",
                            replacementRange: match.range, ghostText: String(tag.name.dropFirst(min(query.count, tag.name.count)))
                        )
                    }
            } else {
                let tokenRange = prefixNSString.range(of: #"[^\s\n]+$"#, options: .regularExpression)
                if tokenRange.location != NSNotFound {
                    let token = prefixNSString.substring(with: tokenRange)
                    if parent.settings.suggestsMarkdown {
                        let markdown: [(String, String, String, String)] = [
                            ("[[g", "[[goal:", "[[goal:", "target"),
                            ("[[t", "[[task:", "[[task:", "checklist"),
                            ("[[e", "[[event:", "[[event:", "calendar")
                        ]
                        matches.append(contentsOf: markdown.filter {
                            $0.1.hasPrefix(token) && $0.1 != token
                        }.map {
                            MarkdownEditorSuggestion(
                                id: "markdown-\($0.0)", kind: .markdown, title: $0.2, detail: parent.localization.markdown,
                                symbolName: $0.3, replacement: $0.1, replacementRange: tokenRange,
                                ghostText: String($0.1.dropFirst(token.count))
                            )
                        })
                    }
                    if parent.customSyntaxEnabled, parent.settings.suggestsCustomSyntax {
                        matches.append(contentsOf: parent.customSyntaxDefinitions.filter {
                            $0.trigger.hasPrefix(token)
                                && ($0.trigger != token || $0.closingDelimiter?.isEmpty == false)
                        }.prefix(6).map { definition in
                            let opening = definition.autocompleteText.isEmpty
                                ? definition.trigger
                                : definition.autocompleteText
                            let closing = definition.closingDelimiter?.trimmingCharacters(in: .whitespacesAndNewlines)
                            let hasClosing = closing?.isEmpty == false
                            let separator = definition.syntaxType == .block && hasClosing ? "\n\n" : ""
                            let replacement = opening + separator + (closing ?? "")
                            let cursorOffset = hasClosing
                                ? opening.utf16.count + (definition.syntaxType == .block ? 1 : 0)
                                : nil
                            return MarkdownEditorSuggestion(
                                id: "custom-\(definition.id)",
                                kind: .customSyntax,
                                title: definition.name,
                                detail: parent.localization.customSyntax,
                                symbolName: definition.symbolName ?? "text.badge.plus",
                                replacement: replacement,
                                replacementRange: tokenRange,
                                ghostText: token == definition.trigger && hasClosing
                                    ? (closing ?? "")
                                    : String(opening.dropFirst(token.count)),
                                cursorOffset: cursorOffset
                            )
                        })
                    }
                    if parent.customSyntaxEnabled, parent.settings.suggestsTemplates {
                        matches.append(contentsOf: parent.syntaxTemplates.filter {
                            $0.trigger.hasPrefix(token) && $0.trigger != token
                        }.prefix(6).map {
                            MarkdownEditorSuggestion(
                                id: "template-\($0.id)", kind: .customSyntax, title: $0.name, detail: parent.localization.template,
                                symbolName: "doc.text", replacement: $0.content, replacementRange: tokenRange,
                                ghostText: String($0.trigger.dropFirst(token.count))
                            )
                        })
                    }
                }
            }

            suggestions = Array(matches.prefix(6))
            selectedSuggestionIndex = min(selectedSuggestionIndex, max(0, suggestions.count - 1))
            updateSuggestionUI(in: textView)
        }

        private func updateSuggestionUI(in textView: MarkdownEditorTextView) {
            guard !suggestions.isEmpty else {
                textView.ghostText = ""
                suggestionView.isHidden = true
                return
            }
            let selected = suggestions[selectedSuggestionIndex]
            textView.ghostText = selected.ghostText
            if selected.kind == .symbol {
                suggestionView.isHidden = true
                return
            }
            suggestionView.suggestions = suggestions
            suggestionView.selectedIndex = selectedSuggestionIndex
            suggestionView.isHidden = false
            let screenRect = textView.firstRect(forCharacterRange: textView.selectedRange(), actualRange: nil)
            guard let window = textView.window else { return }
            let windowRect = window.convertFromScreen(screenRect)
            let localRect = textView.convert(windowRect, from: nil)
            let height = CGFloat(suggestions.count) * 28 + 8
            suggestionView.frame = NSRect(x: localRect.minX, y: localRect.maxY + 4, width: 340, height: height)
        }

        private func acceptSuggestion() -> Bool {
            guard parent.settings.acceptsAutocompleteWithReturn,
                  suggestions.indices.contains(selectedSuggestionIndex),
                  let textView = suggestionView.superview as? MarkdownEditorTextView else { return false }
            let suggestion = suggestions[selectedSuggestionIndex]
            textView.insertText(suggestion.replacement, replacementRange: suggestion.replacementRange)
            let cursorOffset = suggestion.cursorOffset ?? suggestion.replacement.utf16.count
            textView.setSelectedRange(NSRange(
                location: suggestion.replacementRange.location + cursorOffset,
                length: 0
            ))
            publish(textView.string)
            if suggestion.kind == .linkFilter {
                suggestions = []
                selectedSuggestionIndex = 0
                textView.ghostText = ""
                suggestionView.isHidden = true
                updateSuggestions(in: textView)
            } else {
                _ = dismissSuggestions()
            }
            scheduleLiveMarkdown(in: textView)
            return true
        }

        private func dismissSuggestions() -> Bool {
            let hadSuggestions = !suggestions.isEmpty
            suggestions = []
            selectedSuggestionIndex = 0
            if let textView = suggestionView.superview as? MarkdownEditorTextView { textView.ghostText = "" }
            suggestionView.isHidden = true
            return hadSuggestions
        }

        private func moveSuggestion(_ delta: Int) -> Bool {
            guard !suggestions.isEmpty, let textView = suggestionView.superview as? MarkdownEditorTextView else { return false }
            selectedSuggestionIndex = (selectedSuggestionIndex + delta + suggestions.count) % suggestions.count
            updateSuggestionUI(in: textView)
            return true
        }

        private typealias MarkdownTableLine = (range: NSRange, text: String)

        private func isMarkdownTableLine(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let pipes = pipeOffsets(in: trimmed)
            return pipes.count >= 2
                && pipes.first == 0
                && pipes.last == (trimmed as NSString).length - 1
        }

        private func markdownTableCells(in line: String) -> [String]? {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard isMarkdownTableLine(trimmed) else { return nil }
            let value = trimmed as NSString
            let pipes = pipeOffsets(in: trimmed)
            return (0..<(pipes.count - 1)).map { index in
                value.substring(with: NSRange(
                    location: pipes[index] + 1,
                    length: pipes[index + 1] - pipes[index] - 1
                )).trimmingCharacters(in: .whitespaces)
            }
        }

        private func isMarkdownTableSeparator(_ cells: [String]) -> Bool {
            guard !cells.isEmpty else { return false }
            return cells.allSatisfy {
                $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
            }
        }

        private func markdownTableBlock(
            in source: NSString,
            at location: Int
        ) -> (lines: [MarkdownTableLine], range: NSRange, selectedRow: Int)? {
            guard source.length > 0 else { return nil }
            var lines: [MarkdownTableLine] = []
            var offset = 0
            while offset < source.length {
                let range = source.lineRange(for: NSRange(location: offset, length: 0))
                let text = source.substring(with: range).trimmingCharacters(in: .newlines)
                lines.append((range, text))
                let next = NSMaxRange(range)
                guard next > offset else { break }
                offset = next
            }
            let safeLocation = min(location, source.length)
            guard let selectedIndex = lines.lastIndex(where: {
                let isInside = safeLocation >= $0.range.location && safeLocation < NSMaxRange($0.range)
                let isDocumentEnd = safeLocation == source.length
                    && safeLocation == NSMaxRange($0.range)
                    && !source.hasSuffix("\n")
                return isInside || isDocumentEnd
            }), isMarkdownTableLine(lines[selectedIndex].text) else { return nil }

            var lower = selectedIndex
            while lower > 0, isMarkdownTableLine(lines[lower - 1].text) { lower -= 1 }
            var upper = selectedIndex
            while upper + 1 < lines.count, isMarkdownTableLine(lines[upper + 1].text) { upper += 1 }
            let tableLines = Array(lines[lower...upper])
            guard tableLines.count >= 2,
                  tableLines.contains(where: {
                      markdownTableCells(in: $0.text).map(isMarkdownTableSeparator) == true
                  }) else { return nil }
            let range = NSRange(
                location: tableLines[0].range.location,
                length: NSMaxRange(tableLines[tableLines.count - 1].range) - tableLines[0].range.location
            )
            return (tableLines, range, selectedIndex - lower)
        }

        private func pipeOffsets(in line: String) -> [Int] {
            let value = line as NSString
            return (0..<value.length).filter { location in
                guard value.character(at: location) == 124 else { return false }
                var slashCount = 0
                var cursor = location - 1
                while cursor >= 0, value.character(at: cursor) == 92 {
                    slashCount += 1
                    cursor -= 1
                }
                return slashCount.isMultiple(of: 2)
            }
        }

        private func tableCellPosition(
            in line: String,
            at location: Int
        ) -> (index: Int, contentOffset: Int)? {
            let value = line as NSString
            let pipes = pipeOffsets(in: line)
            guard pipes.count >= 2 else { return nil }
            let safeLocation = min(max(location, pipes[0] + 1), pipes[pipes.count - 1] - 1)
            guard let index = (0..<(pipes.count - 1)).first(where: {
                safeLocation > pipes[$0] && safeLocation <= pipes[$0 + 1]
            }) else { return nil }
            let interior = NSRange(
                location: pipes[index] + 1,
                length: pipes[index + 1] - pipes[index] - 1
            )
            let rawCell = value.substring(with: interior)
            let trimmed = rawCell.trimmingCharacters(in: .whitespaces)
            let leading = rawCell.prefix { $0.isWhitespace }.utf16.count
            let contentStart = interior.location + leading
            let contentOffset = min(max(0, location - contentStart), trimmed.utf16.count)
            return (index, contentOffset)
        }

        private func normalizedTableLine(
            cells: [String],
            widths: [Int],
            isSeparator: Bool,
            indentation: String
        ) -> String {
            let values = widths.indices.map { index -> String in
                let cell = index < cells.count ? cells[index] : ""
                if isSeparator {
                    let leftAligned = cell.hasPrefix(":")
                    let rightAligned = cell.hasSuffix(":")
                    let markerCount = (leftAligned ? 1 : 0) + (rightAligned ? 1 : 0)
                    let dashes = String(repeating: "-", count: max(3, widths[index] - markerCount))
                    return (leftAligned ? ":" : "") + dashes + (rightAligned ? ":" : "")
                }
                return cell + String(repeating: " ", count: max(0, widths[index] - cell.count))
            }
            return indentation + "| " + values.joined(separator: " | ") + " |"
        }

        private func tableWidths(for rows: [[String]]) -> [Int] {
            let columnCount = rows.map(\.count).max() ?? 0
            var widths = Array(repeating: 3, count: columnCount)
            for cells in rows {
                let separator = isMarkdownTableSeparator(cells)
                for index in widths.indices {
                    let cell = index < cells.count ? cells[index] : ""
                    if separator {
                        let markers = (cell.hasPrefix(":") ? 1 : 0) + (cell.hasSuffix(":") ? 1 : 0)
                        widths[index] = max(widths[index], 3 + markers)
                    } else {
                        widths[index] = max(widths[index], cell.count)
                    }
                }
            }
            return widths
        }

        private func selectTableCell(
            in line: MarkdownTableLine,
            column: Int,
            textView: MarkdownEditorTextView
        ) -> Bool {
            let source = textView.string as NSString
            let pipes = pipeOffsets(in: line.text)
            guard column >= 0, pipes.count >= column + 2 else { return false }
            let interior = NSRange(
                location: line.range.location + pipes[column] + 1,
                length: pipes[column + 1] - pipes[column] - 1
            )
            let rawCell = source.substring(with: interior)
            let trimmed = rawCell.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                textView.setSelectedRange(interior)
            } else {
                let leading = rawCell.prefix { $0.isWhitespace }.utf16.count
                textView.setSelectedRange(NSRange(
                    location: interior.location + leading,
                    length: trimmed.utf16.count
                ))
            }
            return true
        }

        private func replaceTable(
            rows: [[String]],
            block: (lines: [MarkdownTableLine], range: NSRange, selectedRow: Int),
            selectingRow: Int,
            column: Int,
            in textView: MarkdownEditorTextView
        ) -> Bool {
            guard !rows.isEmpty else { return false }
            let source = textView.string as NSString
            let widths = tableWidths(for: rows)
            guard !widths.isEmpty else { return false }
            let indentation = String(block.lines[0].text.prefix { $0.isWhitespace })
            let lines = rows.map { cells in
                normalizedTableLine(
                    cells: cells,
                    widths: widths,
                    isSeparator: isMarkdownTableSeparator(cells),
                    indentation: indentation
                )
            }
            let original = source.substring(with: block.range)
            let trailingNewline = original.hasSuffix("\n")
            let replacement = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
            let targetRow = min(max(0, selectingRow), lines.count - 1)
            let targetLineOffset = lines.prefix(targetRow).reduce(0) { $0 + $1.utf16.count + 1 }
            let targetPipes = pipeOffsets(in: lines[targetRow])
            let targetColumn = min(max(0, column), max(0, targetPipes.count - 2))
            guard targetPipes.count >= targetColumn + 2 else { return false }
            let targetInterior = NSRange(
                location: block.range.location + targetLineOffset + targetPipes[targetColumn] + 1,
                length: targetPipes[targetColumn + 1] - targetPipes[targetColumn] - 1
            )

            isNormalizingTable = true
            textView.textStorage?.replaceCharacters(in: block.range, with: replacement)
            textView.setSelectedRange(targetInterior)
            isNormalizingTable = false
            return true
        }

        private func addTableRow(
            in textView: NSTextView,
            afterRow requestedRow: Int? = nil,
            selectingColumn requestedColumn: Int? = nil
        ) -> Bool {
            guard let editor = textView as? MarkdownEditorTextView else { return false }
            let source = editor.string as NSString
            let selection = editor.selectedRange()
            guard let block = markdownTableBlock(in: source, at: selection.location) else { return false }
            var rows = block.lines.compactMap { markdownTableCells(in: $0.text) }
            guard rows.count == block.lines.count else { return false }
            let columnCount = rows.map(\.count).max() ?? 0
            guard columnCount > 0 else { return false }
            let separatorRow = rows.firstIndex(where: isMarkdownTableSeparator) ?? 0
            let baseRow = requestedRow ?? block.selectedRow
            let insertionRow = min(rows.count, max(baseRow + 1, separatorRow + 1))
            rows.insert(Array(repeating: "", count: columnCount), at: insertionRow)
            return replaceTable(
                rows: rows,
                block: block,
                selectingRow: insertionRow,
                column: requestedColumn ?? 0,
                in: editor
            )
        }

        private func addTableColumn(in textView: NSTextView) -> Bool {
            guard let editor = textView as? MarkdownEditorTextView else { return false }
            let source = editor.string as NSString
            let selection = editor.selectedRange()
            guard let block = markdownTableBlock(in: source, at: selection.location) else { return false }
            var rows = block.lines.compactMap { markdownTableCells(in: $0.text) }
            guard rows.count == block.lines.count else { return false }
            let newColumn = rows.map(\.count).max() ?? 0
            for index in rows.indices {
                let separator = isMarkdownTableSeparator(rows[index])
                while rows[index].count < newColumn {
                    rows[index].append("")
                }
                rows[index].append(separator ? "---" : "")
            }
            let selectedRow = isMarkdownTableSeparator(rows[block.selectedRow])
                ? min(block.selectedRow + 1, rows.count - 1)
                : block.selectedRow
            return replaceTable(
                rows: rows,
                block: block,
                selectingRow: selectedRow,
                column: newColumn,
                in: editor
            )
        }

        private func navigateTableHorizontally(
            in textView: MarkdownEditorTextView,
            movesBackward: Bool
        ) -> Bool {
            let source = textView.string as NSString
            let selection = textView.selectedRange()
            guard let block = markdownTableBlock(in: source, at: selection.location),
                  let position = tableCellPosition(
                      in: block.lines[block.selectedRow].text,
                      at: selection.location - block.lines[block.selectedRow].range.location
                  ) else { return false }
            let rows = block.lines.compactMap { markdownTableCells(in: $0.text) }
            let dataRows = rows.indices.filter { !isMarkdownTableSeparator(rows[$0]) }
            guard let dataIndex = dataRows.firstIndex(of: block.selectedRow) else { return true }
            let columnCount = rows[block.selectedRow].count

            if movesBackward {
                if position.index > 0 {
                    return selectTableCell(in: block.lines[block.selectedRow], column: position.index - 1, textView: textView)
                }
                guard dataIndex > 0 else { return true }
                let previousRow = dataRows[dataIndex - 1]
                return selectTableCell(in: block.lines[previousRow], column: max(0, rows[previousRow].count - 1), textView: textView)
            }
            if position.index + 1 < columnCount {
                return selectTableCell(in: block.lines[block.selectedRow], column: position.index + 1, textView: textView)
            }
            if dataIndex + 1 < dataRows.count {
                return selectTableCell(in: block.lines[dataRows[dataIndex + 1]], column: 0, textView: textView)
            }
            let added = addTableRow(in: textView, afterRow: block.selectedRow, selectingColumn: 0)
            if added {
                publish(textView.string)
                scheduleLiveMarkdown(in: textView)
            }
            return added
        }

        private func exitTable(in textView: MarkdownEditorTextView) -> Bool {
            let source = textView.string as NSString
            let selection = textView.selectedRange()
            guard let block = markdownTableBlock(in: source, at: selection.location) else { return false }
            let insertionLocation = NSMaxRange(block.range)
            if insertionLocation < source.length, source.character(at: insertionLocation) == 10 {
                textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
                return true
            }
            let tableHasTrailingNewline = source.substring(with: block.range).hasSuffix("\n")
            isNormalizingTable = true
            textView.insertText("\n", replacementRange: NSRange(location: insertionLocation, length: 0))
            textView.setSelectedRange(NSRange(
                location: tableHasTrailingNewline ? insertionLocation : insertionLocation + 1,
                length: 0
            ))
            isNormalizingTable = false
            publish(textView.string)
            scheduleLiveMarkdown(in: textView)
            return true
        }

        private func normalizeMarkdownTableIfNeeded(in textView: MarkdownEditorTextView) {
            let source = textView.string as NSString
            let selection = textView.selectedRange()
            guard let block = markdownTableBlock(in: source, at: selection.location),
                  let selectedCells = markdownTableCells(in: block.lines[block.selectedRow].text),
                  let position = tableCellPosition(
                      in: block.lines[block.selectedRow].text,
                      at: selection.location - block.lines[block.selectedRow].range.location
                  ) else { return }

            let rows = block.lines.compactMap { markdownTableCells(in: $0.text) }
            guard rows.count == block.lines.count else { return }
            let widths = tableWidths(for: rows)
            guard !widths.isEmpty else { return }

            let normalizedLines = block.lines.enumerated().map { index, line -> String in
                let indentation = String(line.text.prefix { $0.isWhitespace })
                return normalizedTableLine(
                    cells: rows[index],
                    widths: widths,
                    isSeparator: isMarkdownTableSeparator(rows[index]),
                    indentation: indentation
                )
            }
            let original = source.substring(with: block.range)
            let trailingNewline = original.hasSuffix("\n")
            let normalized = normalizedLines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
            guard normalized != original else { return }

            let selectedRow = min(block.selectedRow, normalizedLines.count - 1)
            let normalizedLine = normalizedLines[selectedRow]
            let pipes = pipeOffsets(in: normalizedLine)
            let cellIndex = min(position.index, max(0, pipes.count - 2))
            guard pipes.count >= cellIndex + 2 else { return }
            let cell = cellIndex < selectedCells.count ? selectedCells[cellIndex] : ""
            let lineOffset = normalizedLines.prefix(selectedRow).reduce(0) { $0 + $1.utf16.count + 1 }
            let cursorInLine = pipes[cellIndex] + 2 + min(position.contentOffset, cell.utf16.count)

            isNormalizingTable = true
            textView.textStorage?.replaceCharacters(in: block.range, with: normalized)
            textView.setSelectedRange(NSRange(
                location: block.range.location + lineOffset + cursorInLine,
                length: 0
            ))
            isNormalizingTable = false
        }

        private func adjustTableSelection(in textView: MarkdownEditorTextView) {
            let source = textView.string as NSString
            let selection = textView.selectedRange()
            guard selection.length == 0,
                  let block = markdownTableBlock(in: source, at: selection.location) else { return }
            let line = block.lines[block.selectedRow]
            guard let cells = markdownTableCells(in: line.text),
                  !isMarkdownTableSeparator(cells),
                  let position = tableCellPosition(
                      in: line.text,
                      at: selection.location - line.range.location
                  ) else { return }
            let pipes = pipeOffsets(in: line.text)
            guard pipes.count >= position.index + 2 else { return }
            let interior = NSRange(
                location: line.range.location + pipes[position.index] + 1,
                length: pipes[position.index + 1] - pipes[position.index] - 1
            )
            let rawCell = source.substring(with: interior)
            let trimmed = rawCell.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                textView.setSelectedRange(interior)
                return
            }
            let leading = rawCell.prefix { $0.isWhitespace }.utf16.count
            let contentStart = interior.location + leading
            let contentEnd = contentStart + trimmed.utf16.count
            textView.setSelectedRange(NSRange(
                location: min(max(selection.location, contentStart), contentEnd),
                length: 0
            ))
        }

        private func toggleChecklist(atSelectionIn textView: MarkdownEditorTextView) -> Bool {
            let source = textView.string as NSString
            let selection = textView.selectedRange()
            guard selection.length == 0, selection.location <= source.length else { return false }
            let lineRange = source.lineRange(for: NSRange(
                location: min(selection.location, source.length),
                length: 0
            ))
            let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
            guard let match = firstMatch(#"^\s*[-*+]\s+\[([ xX])\]"#, in: line) else { return false }
            let valueRange = offset(match.range(at: 1), by: lineRange.location)
            let checkboxRange = NSRange(location: valueRange.location - 1, length: 3)
            guard cursorIsInside(selection.location, range: checkboxRange) else { return false }
            let replacement = source.substring(with: valueRange) == " " ? "x" : " "
            textView.insertText(replacement, replacementRange: valueRange)
            textView.setSelectedRange(NSRange(location: NSMaxRange(checkboxRange), length: 0))
            return true
        }

        private func insertSmartNewline(in textView: MarkdownEditorTextView) -> Bool {
            let settings = parent.settings
            guard settings.smartListContinuation || settings.smartQuoteContinuation || settings.continuesChecklists else { return false }
            let source = textView.string as NSString
            let selection = textView.selectedRange()
            let lineRange = source.lineRange(for: NSRange(location: min(selection.location, source.length), length: 0))
            let beforeCursorRange = NSRange(location: lineRange.location, length: max(0, selection.location - lineRange.location))
            let line = source.substring(with: beforeCursorRange)
            var continuation: String?

            if settings.continuesChecklists,
               let match = firstMatch(#"^(\s*)[-*+]\s+\[[ xX]\]\s+(.*)$"#, in: line) {
                continuation = (line as NSString).substring(with: match.range(at: 1)) + "- [ ] "
            } else if settings.smartListContinuation,
                      let match = firstMatch(#"^(\s*)[-*+]\s+(.*)$"#, in: line) {
                continuation = (line as NSString).substring(with: match.range(at: 1)) + "- "
            } else if settings.smartListContinuation,
                      let match = firstMatch(#"^(\s*)(\d+)\.\s+(.*)$"#, in: line) {
                let indent = (line as NSString).substring(with: match.range(at: 1))
                let number = Int((line as NSString).substring(with: match.range(at: 2))) ?? 0
                continuation = "\(indent)\(number + 1). "
            } else if settings.smartQuoteContinuation,
                      let match = firstMatch(#"^(\s*)>\s?(.*)$"#, in: line) {
                continuation = (line as NSString).substring(with: match.range(at: 1)) + "> "
            }
            guard let continuation else { return false }
            textView.insertText("\n" + continuation, replacementRange: selection)
            publish(textView.string)
            scheduleLiveMarkdown(in: textView)
            return true
        }

        private func insertDroppedFiles(
            _ urls: [URL],
            at location: Int,
            in textView: MarkdownEditorTextView
        ) -> Bool {
            let references = urls.compactMap(parent.onPasteFile)
            guard !references.isEmpty else { return false }

            let source = textView.string as NSString
            let safeLocation = min(max(0, location), source.length)
            let needsLeadingBreak = safeLocation > 0
                && source.substring(with: NSRange(location: safeLocation - 1, length: 1)) != "\n"
            let needsTrailingBreak = safeLocation < source.length
                && source.substring(with: NSRange(location: safeLocation, length: 1)) != "\n"
            let insertion = (needsLeadingBreak ? "\n\n" : "")
                + references.joined(separator: "\n\n")
                + (needsTrailingBreak ? "\n\n" : "")

            textView.insertText(insertion, replacementRange: NSRange(location: safeLocation, length: 0))
            textView.setSelectedRange(NSRange(location: safeLocation + insertion.utf16.count, length: 0))
            publish(textView.string)
            scheduleLiveMarkdown(in: textView)
            return true
        }

        private func handlePaste(in textView: MarkdownEditorTextView, forceTable: Bool) -> Bool {
            let pasteboard = NSPasteboard.general
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
               let url = urls.first,
               url.isFileURL,
               let reference = parent.onPasteFile(url) {
                insert(reference, in: textView)
                publish(textView.string)
                return true
            }
            if parent.settings.embedsPastedImages {
                let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
                if let data, let reference = parent.onPasteImage(pngData(from: data) ?? data) {
                    insert(reference, in: textView)
                    publish(textView.string)
                    return true
                }
            }
            if parent.settings.preservesRichTextOnPaste,
               let attributed = attributedClipboardValue(from: pasteboard) {
                var markdown = markdown(from: attributed)
                if forceTable || (parent.settings.convertsTablesOnPaste && markdown.contains("\t")) {
                    markdown = markdownTable(from: markdown)
                }
                if !markdown.isEmpty {
                    insert(markdown, in: textView)
                    publish(textView.string)
                    return true
                }
            }
            guard let value = pasteboard.string(forType: .string) else { return false }
            guard forceTable || (parent.settings.convertsTablesOnPaste && value.contains("\t")) else { return false }
            insert(markdownTable(from: value), in: textView)
            publish(textView.string)
            return true
        }

        private func attributedClipboardValue(from pasteboard: NSPasteboard) -> NSAttributedString? {
            if let html = pasteboard.data(forType: .html),
               let rawHTML = String(data: html, encoding: .utf8) ?? String(data: html, encoding: .utf16),
               let sanitizedHTML = sanitizedHTMLData(rawHTML),
               let value = try? NSAttributedString(
                   data: sanitizedHTML,
                   options: [.documentType: NSAttributedString.DocumentType.html],
                   documentAttributes: nil
               ) {
                return value
            }
            if let rtf = pasteboard.data(forType: .rtf),
               let value = try? NSAttributedString(
                   data: rtf,
                   options: [.documentType: NSAttributedString.DocumentType.rtf],
                   documentAttributes: nil
               ) {
                return value
            }
            return nil
        }

        private func sanitizedHTMLData(_ html: String) -> Data? {
            var sanitized = html
            let blockedElements = ["script", "style", "iframe", "object", "embed", "img"]
            for element in blockedElements {
                sanitized = sanitized.replacingOccurrences(
                    of: "(?is)<\(element)\\b[^>]*>.*?</\(element)\\s*>",
                    with: "",
                    options: .regularExpression
                )
                sanitized = sanitized.replacingOccurrences(
                    of: "(?is)<\(element)\\b[^>]*/?>",
                    with: "",
                    options: .regularExpression
                )
            }
            sanitized = sanitized.replacingOccurrences(
                of: #"(?is)\son[a-z]+\s*=\s*(['\"]).*?\1"#,
                with: "",
                options: .regularExpression
            )
            return sanitized.data(using: .utf8)
        }

        private func markdown(from attributed: NSAttributedString) -> String {
            var result = ""
            attributed.enumerateAttributes(
                in: NSRange(location: 0, length: attributed.length),
                options: []
            ) { attributes, range, _ in
                var value = attributed.attributedSubstring(from: range).string
                guard !value.isEmpty else { return }
                if let link = attributes[.link] as? URL {
                    value = "[\(value)](\(link.absoluteString))"
                }
                if let font = attributes[.font] as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    if traits.contains(.italicFontMask) { value = "_\(value)_" }
                    if traits.contains(.boldFontMask) { value = "**\(value)**" }
                    if font.pointSize >= 20, value.hasSuffix("\n") {
                        value = "# " + value
                    } else if font.pointSize >= 17, value.hasSuffix("\n") {
                        value = "## " + value
                    }
                }
                result += value
            }
            return result
                .replacingOccurrences(of: "\u{2028}", with: "\n")
                .replacingOccurrences(of: "\u{2029}", with: "\n\n")
        }

        private func markdownTable(from value: String) -> String {
            var rows = value.split(whereSeparator: \Character.isNewline).map {
                $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            }
            guard !rows.isEmpty else { return value }
            let columnCount = rows.map(\.count).max() ?? 1
            rows = rows.map { $0 + Array(repeating: "", count: max(0, columnCount - $0.count)) }
            func row(_ cells: [String]) -> String {
                "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>") }.joined(separator: " | ") + " |"
            }
            let header = row(rows[0])
            let separator = row(Array(repeating: "---", count: columnCount))
            return ([header, separator] + rows.dropFirst().map(row)).joined(separator: "\n")
        }

        private func pngData(from data: Data) -> Data? {
            guard let representation = NSBitmapImageRep(data: data) else { return nil }
            return representation.representation(using: .png, properties: [:])
        }

        private func conceal(_ range: NSRange, in storage: NSTextStorage) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            storage.addAttributes([
                .foregroundColor: NSColor.clear,
                .font: NSFont.systemFont(ofSize: 0.01),
                .kern: -0.01
            ], range: range)
        }

        private func firstMatch(_ pattern: String, in value: String) -> NSTextCheckingResult? {
            try? NSRegularExpression(pattern: pattern).firstMatch(
                in: value,
                range: NSRange(location: 0, length: (value as NSString).length)
            )
        }

        private func cursorIsInside(_ location: Int, range: NSRange) -> Bool {
            location >= range.location && location <= NSMaxRange(range)
        }

        private func offset(_ range: NSRange, by location: Int) -> NSRange {
            guard range.location != NSNotFound else { return range }
            return NSRange(location: range.location + location, length: range.length)
        }

        private func wrapSelection(
            in textView: NSTextView,
            prefix: String,
            suffix: String
        ) {
            let range = textView.selectedRange()
            let source = textView.string as NSString
            let selected = range.length > 0 ? source.substring(with: range) : ""
            let replacement = prefix + selected + suffix
            textView.insertText(replacement, replacementRange: range)
            let selectionStart = range.location + prefix.utf16.count
            textView.setSelectedRange(NSRange(location: selectionStart, length: range.length > 0 ? selected.utf16.count : 0))
        }

        private func prefixSelectedLines(
            in textView: NSTextView,
            prefix: (Int) -> String
        ) {
            let source = textView.string as NSString
            let selection = textView.selectedRange()
            let safeLocation = min(selection.location, source.length)
            let targetRange = source.lineRange(for: NSRange(location: safeLocation, length: selection.length))
            let target = source.substring(with: targetRange)
            let lines = target.split(separator: "\n", omittingEmptySubsequences: false)
            let replacement = lines.enumerated().map { prefix($0.offset) + String($0.element) }.joined(separator: "\n")
            textView.insertText(replacement, replacementRange: targetRange)
            if selection.length == 0 {
                let cursorOffsetInLine = safeLocation - targetRange.location
                let cursorLocation = targetRange.location + prefix(0).utf16.count + cursorOffsetInLine
                textView.setSelectedRange(NSRange(location: cursorLocation, length: 0))
            } else {
                textView.setSelectedRange(NSRange(location: targetRange.location, length: replacement.utf16.count))
            }
        }

        private func insert(_ value: String, in textView: NSTextView, cursorOffset: Int? = nil) {
            let range = textView.selectedRange()
            textView.insertText(value, replacementRange: range)
            let offset = min(cursorOffset ?? value.utf16.count, value.utf16.count)
            textView.setSelectedRange(NSRange(location: range.location + offset, length: 0))
        }
    }
}
