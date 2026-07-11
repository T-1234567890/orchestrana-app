import Combine
import Foundation
import UniformTypeIdentifiers

enum NoteEditorStyle: String, Codable, CaseIterable, Identifiable {
    case `default`
    case minimal
    case compact
    case academic
    case technical
    case journal
    case focused

    var id: String { rawValue }
}

struct NoteEditorSettingsRecord: Codable, Equatable {
    var livePreviewEnabled = true
    var showsSyntaxInActiveRange = true
    var sourceModeEnabled = false
    var autosaveEnabled = true
    var editorLineWidth: Double = 760
    var paragraphSpacing: Double = 6
    var defaultNoteType: NoteRecord.NoteType = .quick
    var smartListContinuation = true
    var smartQuoteContinuation = true
    var continuesChecklists = true
    var checksSpelling = true
    var checksGrammar = true
    var correctsSpelling = false
    var usesSmartQuotes = true
    var usesSmartDashes = true
    var usesTextSubstitutions = true
    var syntaxAutocompleteEnabled = true
    var acceptsAutocompleteWithTab = true
    var acceptsAutocompleteWithReturn: Bool {
        get { acceptsAutocompleteWithTab }
        set { acceptsAutocompleteWithTab = newValue }
    }
    var showsSuggestionsAutomatically = true
    var suggestsMarkdown = true
    var suggestsOrchestranaLinks = true
    var suggestsTags = true
    var suggestsCustomSyntax = true
    var suggestsTemplates = true
    var selectedStyle: NoteEditorStyle = .default
    var convertsTablesOnPaste = true
    var preservesRichTextOnPaste = true
    var embedsPastedImages = true
    var safeEmbedsEnabled = true
    var markdownExportIncludesMetadata = true
    var plainTextExportRemovesSyntax = true

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case livePreviewEnabled, showsSyntaxInActiveRange, sourceModeEnabled, autosaveEnabled
        case editorLineWidth, paragraphSpacing, defaultNoteType
        case smartListContinuation, smartQuoteContinuation, continuesChecklists
        case checksSpelling, checksGrammar, correctsSpelling, usesSmartQuotes, usesSmartDashes, usesTextSubstitutions
        case syntaxAutocompleteEnabled, acceptsAutocompleteWithTab, showsSuggestionsAutomatically
        case suggestsMarkdown, suggestsOrchestranaLinks, suggestsTags, suggestsCustomSyntax, suggestsTemplates
        case selectedStyle, convertsTablesOnPaste, preservesRichTextOnPaste, embedsPastedImages, safeEmbedsEnabled
        case markdownExportIncludesMetadata, plainTextExportRemovesSyntax
    }

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        livePreviewEnabled = try container.decodeIfPresent(Bool.self, forKey: .livePreviewEnabled) ?? livePreviewEnabled
        showsSyntaxInActiveRange = try container.decodeIfPresent(Bool.self, forKey: .showsSyntaxInActiveRange) ?? showsSyntaxInActiveRange
        sourceModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .sourceModeEnabled) ?? sourceModeEnabled
        autosaveEnabled = try container.decodeIfPresent(Bool.self, forKey: .autosaveEnabled) ?? autosaveEnabled
        editorLineWidth = try container.decodeIfPresent(Double.self, forKey: .editorLineWidth) ?? editorLineWidth
        paragraphSpacing = try container.decodeIfPresent(Double.self, forKey: .paragraphSpacing) ?? paragraphSpacing
        defaultNoteType = try container.decodeIfPresent(NoteRecord.NoteType.self, forKey: .defaultNoteType) ?? defaultNoteType
        smartListContinuation = try container.decodeIfPresent(Bool.self, forKey: .smartListContinuation) ?? smartListContinuation
        smartQuoteContinuation = try container.decodeIfPresent(Bool.self, forKey: .smartQuoteContinuation) ?? smartQuoteContinuation
        continuesChecklists = try container.decodeIfPresent(Bool.self, forKey: .continuesChecklists) ?? continuesChecklists
        checksSpelling = try container.decodeIfPresent(Bool.self, forKey: .checksSpelling) ?? checksSpelling
        checksGrammar = try container.decodeIfPresent(Bool.self, forKey: .checksGrammar) ?? checksGrammar
        correctsSpelling = try container.decodeIfPresent(Bool.self, forKey: .correctsSpelling) ?? correctsSpelling
        usesSmartQuotes = try container.decodeIfPresent(Bool.self, forKey: .usesSmartQuotes) ?? usesSmartQuotes
        usesSmartDashes = try container.decodeIfPresent(Bool.self, forKey: .usesSmartDashes) ?? usesSmartDashes
        usesTextSubstitutions = try container.decodeIfPresent(Bool.self, forKey: .usesTextSubstitutions) ?? usesTextSubstitutions
        syntaxAutocompleteEnabled = try container.decodeIfPresent(Bool.self, forKey: .syntaxAutocompleteEnabled) ?? syntaxAutocompleteEnabled
        acceptsAutocompleteWithTab = try container.decodeIfPresent(Bool.self, forKey: .acceptsAutocompleteWithTab) ?? acceptsAutocompleteWithTab
        showsSuggestionsAutomatically = try container.decodeIfPresent(Bool.self, forKey: .showsSuggestionsAutomatically) ?? showsSuggestionsAutomatically
        suggestsMarkdown = try container.decodeIfPresent(Bool.self, forKey: .suggestsMarkdown) ?? suggestsMarkdown
        suggestsOrchestranaLinks = try container.decodeIfPresent(Bool.self, forKey: .suggestsOrchestranaLinks) ?? suggestsOrchestranaLinks
        suggestsTags = try container.decodeIfPresent(Bool.self, forKey: .suggestsTags) ?? suggestsTags
        suggestsCustomSyntax = try container.decodeIfPresent(Bool.self, forKey: .suggestsCustomSyntax) ?? suggestsCustomSyntax
        suggestsTemplates = try container.decodeIfPresent(Bool.self, forKey: .suggestsTemplates) ?? suggestsTemplates
        selectedStyle = try container.decodeIfPresent(NoteEditorStyle.self, forKey: .selectedStyle) ?? selectedStyle
        convertsTablesOnPaste = try container.decodeIfPresent(Bool.self, forKey: .convertsTablesOnPaste) ?? convertsTablesOnPaste
        preservesRichTextOnPaste = try container.decodeIfPresent(Bool.self, forKey: .preservesRichTextOnPaste) ?? preservesRichTextOnPaste
        embedsPastedImages = try container.decodeIfPresent(Bool.self, forKey: .embedsPastedImages) ?? embedsPastedImages
        safeEmbedsEnabled = try container.decodeIfPresent(Bool.self, forKey: .safeEmbedsEnabled) ?? safeEmbedsEnabled
        markdownExportIncludesMetadata = try container.decodeIfPresent(Bool.self, forKey: .markdownExportIncludesMetadata) ?? markdownExportIncludesMetadata
        plainTextExportRemovesSyntax = try container.decodeIfPresent(Bool.self, forKey: .plainTextExportRemovesSyntax) ?? plainTextExportRemovesSyntax
    }
}

struct NoteCustomSyntaxDefinition: Identifiable, Codable, Equatable {
    enum SyntaxType: String, Codable, CaseIterable, Identifiable { case inline, block; var id: String { rawValue } }
    enum RenderingStyle: String, Codable, CaseIterable, Identifiable { case accent, badge, callout, highlight; var id: String { rawValue } }

    let id: UUID
    var name: String
    var trigger: String
    var syntaxType: SyntaxType
    var closingDelimiter: String?
    var color: NoteTagColor
    var symbolName: String?
    var renderingStyle: RenderingStyle
    var autocompleteText: String
    var exportText: String
    var appliedTagID: UUID?
    var remainsVisibleInSourceMode: Bool
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, trigger: String, syntaxType: SyntaxType = .block,
         closingDelimiter: String? = nil, color: NoteTagColor = .blue, symbolName: String? = nil,
         renderingStyle: RenderingStyle = .callout, autocompleteText: String = "", exportText: String = "",
         appliedTagID: UUID? = nil, remainsVisibleInSourceMode: Bool = true,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.trigger = trigger; self.syntaxType = syntaxType
        self.closingDelimiter = closingDelimiter; self.color = color; self.symbolName = symbolName
        self.renderingStyle = renderingStyle; self.autocompleteText = autocompleteText; self.exportText = exportText
        self.appliedTagID = appliedTagID; self.remainsVisibleInSourceMode = remainsVisibleInSourceMode
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

struct NoteSyntaxTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var trigger: String
    var content: String
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, trigger: String, content: String,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.trigger = trigger; self.content = content
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

struct NoteEditorStylePreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var contentWidth: Double
    var paragraphSpacing: Double
    var compactMetadata: Bool
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, contentWidth: Double = 760, paragraphSpacing: Double = 6,
         compactMetadata: Bool = true, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.contentWidth = contentWidth; self.paragraphSpacing = paragraphSpacing
        self.compactMetadata = compactMetadata; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

struct NoteAttachmentRecord: Identifiable, Codable, Equatable {
    enum MediaType: String, Codable { case image, audio, video, pdf, file }
    let id: UUID
    var fileName: String
    var localRelativePath: String
    var externalBookmarkData: Data?
    var originalFilePath: String?
    var mediaType: MediaType
    var fileSize: Int64
    var displayWidth: Double?
    var naturalAspectRatio: Double?
    var showsFrame: Bool?
    let createdAt: Date

    var isExternallyLinked: Bool { externalBookmarkData != nil || originalFilePath != nil }
    var isFrameVisible: Bool { showsFrame ?? true }
}

enum NoteTagColor: String, Codable, CaseIterable, Identifiable {
    case red
    case purple
    case orange
    case yellow
    case blue
    case green
    case gray

    var id: String { rawValue }
}

struct NoteTagRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var color: NoteTagColor
    var symbolName: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        color: NoteTagColor,
        symbolName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.symbolName = symbolName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct NoteFolderRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var parentFolderID: UUID?
    var manualOrder: Int
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        parentFolderID: UUID? = nil,
        manualOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.parentFolderID = parentFolderID
        self.manualOrder = manualOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, parentFolderID, manualOrder, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "New Folder"
        parentFolderID = try container.decodeIfPresent(UUID.self, forKey: .parentFolderID)
        manualOrder = try container.decodeIfPresent(Int.self, forKey: .manualOrder) ?? .max
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

struct NoteRecord: Identifiable, Codable, Equatable {
    enum Source: String, Codable, CaseIterable {
        case manual
        case task
        case event
        case goal
        case session
        case day
    }

    enum NoteType: String, Codable, CaseIterable, Identifiable {
        case quick
        case session
        case goal
        case task
        case daily
        case contextDraft

        var id: String { rawValue }
    }

    let id: UUID
    var title: String
    var body: String
    var tagIDs: [UUID]
    var noteType: NoteType
    var isPinned: Bool
    var isArchived: Bool
    var folderID: UUID?
    var manualOrder: Int
    var attachmentIDs: [UUID]
    var source: Source
    var linkedTaskID: UUID?
    var linkedEventID: UUID?
    var linkedGoalID: UUID?
    var linkedSessionID: UUID?
    var linkedDay: Date?
    let createdAt: Date
    var updatedAt: Date

    // Used only while decoding the first string-tag storage format.
    var legacyTagNames: [String] = []

    init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        tagIDs: [UUID] = [],
        noteType: NoteType = .quick,
        isPinned: Bool = false,
        isArchived: Bool = false,
        folderID: UUID? = nil,
        manualOrder: Int = 0,
        attachmentIDs: [UUID] = [],
        source: Source = .manual,
        linkedTaskID: UUID? = nil,
        linkedEventID: UUID? = nil,
        linkedGoalID: UUID? = nil,
        linkedSessionID: UUID? = nil,
        linkedDay: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tagIDs = tagIDs
        self.noteType = noteType
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.folderID = folderID
        self.manualOrder = manualOrder
        self.attachmentIDs = attachmentIDs
        self.source = source
        self.linkedTaskID = linkedTaskID
        self.linkedEventID = linkedEventID
        self.linkedGoalID = linkedGoalID
        self.linkedSessionID = linkedSessionID
        self.linkedDay = linkedDay
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case tags
        case tagIDs
        case noteType
        case isPinned
        case isArchived
        case folderID
        case manualOrder
        case attachmentIDs
        case source
        case linkedTaskID
        case linkedEventID
        case linkedGoalID
        case linkedSessionID
        case linkedDay
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Note"
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        tagIDs = try container.decodeIfPresent([UUID].self, forKey: .tagIDs) ?? []
        legacyTagNames = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        source = try container.decodeIfPresent(Source.self, forKey: .source) ?? .manual
        noteType = try container.decodeIfPresent(NoteType.self, forKey: .noteType) ?? Self.defaultType(for: source)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        manualOrder = try container.decodeIfPresent(Int.self, forKey: .manualOrder) ?? .max
        attachmentIDs = try container.decodeIfPresent([UUID].self, forKey: .attachmentIDs) ?? []
        linkedTaskID = try container.decodeIfPresent(UUID.self, forKey: .linkedTaskID)
        linkedEventID = try container.decodeIfPresent(UUID.self, forKey: .linkedEventID)
        linkedGoalID = try container.decodeIfPresent(UUID.self, forKey: .linkedGoalID)
        linkedSessionID = try container.decodeIfPresent(UUID.self, forKey: .linkedSessionID)
        linkedDay = try container.decodeIfPresent(Date.self, forKey: .linkedDay)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(tagIDs, forKey: .tagIDs)
        try container.encode(noteType, forKey: .noteType)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encodeIfPresent(folderID, forKey: .folderID)
        try container.encode(manualOrder, forKey: .manualOrder)
        try container.encode(attachmentIDs, forKey: .attachmentIDs)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(linkedTaskID, forKey: .linkedTaskID)
        try container.encodeIfPresent(linkedEventID, forKey: .linkedEventID)
        try container.encodeIfPresent(linkedGoalID, forKey: .linkedGoalID)
        try container.encodeIfPresent(linkedSessionID, forKey: .linkedSessionID)
        try container.encodeIfPresent(linkedDay, forKey: .linkedDay)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    static func defaultType(for source: Source) -> NoteType {
        switch source {
        case .manual, .event:
            return .quick
        case .task:
            return .task
        case .goal:
            return .goal
        case .session:
            return .session
        case .day:
            return .daily
        }
    }
}

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [NoteRecord] = []
    @Published private(set) var tags: [NoteTagRecord] = []
    @Published private(set) var folders: [NoteFolderRecord] = []
    @Published private(set) var editorSettings = NoteEditorSettingsRecord()
    @Published private(set) var customSyntaxDefinitions: [NoteCustomSyntaxDefinition] = []
    @Published private(set) var syntaxTemplates: [NoteSyntaxTemplate] = []
    @Published private(set) var editorStylePresets: [NoteEditorStylePreset] = []
    @Published private(set) var attachments: [NoteAttachmentRecord] = []

    private struct NoteFileReference: Codable {
        let id: UUID
        let relativePath: String
    }

    private struct Archive: Codable {
        var version: Int
        var notes: [NoteRecord]?
        var noteFiles: [NoteFileReference]?
        var tags: [NoteTagRecord]
        var folders: [NoteFolderRecord]?
        var editorSettings: NoteEditorSettingsRecord?
        var customSyntaxDefinitions: [NoteCustomSyntaxDefinition]?
        var syntaxTemplates: [NoteSyntaxTemplate]?
        var editorStylePresets: [NoteEditorStylePreset]?
        var attachments: [NoteAttachmentRecord]?
    }

    private let fileURL: URL
    private let markdownNotesDirectoryURL: URL
    private let attachmentsDirectoryURL: URL
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var noteFilePaths: [UUID: String] = [:]
    private var markdownFilesNeedRewrite = false

    var storageFileURL: URL { fileURL }
    var storageDirectoryURL: URL { markdownNotesDirectoryURL }

    init(storageURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let storageURL {
            fileURL = storageURL
            markdownNotesDirectoryURL = storageURL.deletingLastPathComponent().appendingPathComponent("Markdown Notes", isDirectory: true)
            attachmentsDirectoryURL = storageURL.deletingLastPathComponent().appendingPathComponent("NoteAttachments", isDirectory: true)
            try? fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } else {
            let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let notesDirectory = supportDirectory.appendingPathComponent("PomodoroApp", isDirectory: true)
            try? fileManager.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            fileURL = notesDirectory.appendingPathComponent("notes.json")
            markdownNotesDirectoryURL = notesDirectory.appendingPathComponent("Markdown Notes", isDirectory: true)
            attachmentsDirectoryURL = notesDirectory.appendingPathComponent("NoteAttachments", isDirectory: true)
        }
        try? fileManager.createDirectory(at: markdownNotesDirectoryURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: attachmentsDirectoryURL, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    @discardableResult
    func addNote(
        title: String,
        body: String = "",
        tags legacyTags: [String] = [],
        source: NoteRecord.Source = .manual,
        folderID: UUID? = nil,
        linkedTaskID: UUID? = nil,
        linkedEventID: UUID? = nil,
        linkedGoalID: UUID? = nil,
        linkedSessionID: UUID? = nil,
        linkedDay: Date? = nil
    ) -> NoteRecord {
        let now = Date()
        let resolvedFolderID = validFolderID(folderID)
        let resolvedTagIDs = legacyTags.compactMap { resolveOrCreateTagID(named: $0) }
        let note = NoteRecord(
            title: normalizedTitle(title),
            body: body,
            tagIDs: uniqueIDs(resolvedTagIDs),
            noteType: NoteRecord.defaultType(for: source),
            folderID: resolvedFolderID,
            manualOrder: nextNoteOrder(in: resolvedFolderID),
            source: source,
            linkedTaskID: linkedTaskID,
            linkedEventID: linkedEventID,
            linkedGoalID: linkedGoalID,
            linkedSessionID: linkedSessionID,
            linkedDay: linkedDay,
            createdAt: now,
            updatedAt: now
        )
        notes.insert(note, at: 0)
        _ = save()
        return note
    }

    @discardableResult
    func updateNote(_ note: NoteRecord) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return false }
        let previousTitle = notes[index].title
        var updated = note
        updated.title = normalizedTitle(updated.title)
        updated.tagIDs = uniqueIDs(updated.tagIDs.filter { tagID in tags.contains { $0.id == tagID } })
        updated.folderID = validFolderID(updated.folderID)
        updated.legacyTagNames = []
        updated.updatedAt = Date()
        notes[index] = updated
        if previousTitle != updated.title {
            relocateMarkdownFile(for: updated)
        }
        sortNotes()
        return save()
    }

    @discardableResult
    func deleteNote(_ note: NoteRecord) -> Bool {
        if let fileURL = markdownFileURL(for: note) {
            try? fileManager.removeItem(at: fileURL)
        }
        noteFilePaths.removeValue(forKey: note.id)
        notes.removeAll { $0.id == note.id }
        return save()
    }

    @discardableResult
    func duplicateNote(_ note: NoteRecord, title: String) -> NoteRecord {
        let now = Date()
        let duplicate = NoteRecord(
            title: normalizedTitle(title),
            body: note.body,
            tagIDs: note.tagIDs,
            noteType: note.noteType,
            isPinned: false,
            isArchived: false,
            folderID: note.folderID,
            manualOrder: nextNoteOrder(in: note.folderID),
            attachmentIDs: note.attachmentIDs,
            source: note.source,
            linkedTaskID: note.linkedTaskID,
            linkedEventID: note.linkedEventID,
            linkedGoalID: note.linkedGoalID,
            linkedSessionID: note.linkedSessionID,
            linkedDay: note.linkedDay,
            createdAt: now,
            updatedAt: now
        )
        notes.insert(duplicate, at: 0)
        _ = save()
        return duplicate
    }

    func persist() -> Bool {
        save()
    }

    @discardableResult
    func updateEditorSettings(_ update: (inout NoteEditorSettingsRecord) -> Void) -> Bool {
        var settings = editorSettings
        update(&settings)
        settings.editorLineWidth = min(max(settings.editorLineWidth, 480), 1200)
        settings.paragraphSpacing = min(max(settings.paragraphSpacing, 0), 24)
        editorSettings = settings
        return save()
    }

    @discardableResult
    func addCustomSyntax(
        name: String,
        trigger: String,
        syntaxType: NoteCustomSyntaxDefinition.SyntaxType = .block
    ) -> NoteCustomSyntaxDefinition? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanTrigger.isEmpty,
              !customSyntaxDefinitions.contains(where: { $0.trigger == cleanTrigger }) else { return nil }
        let definition = NoteCustomSyntaxDefinition(
            name: cleanName,
            trigger: cleanTrigger,
            syntaxType: syntaxType,
            symbolName: "text.badge.plus",
            autocompleteText: cleanTrigger
        )
        customSyntaxDefinitions.append(definition)
        customSyntaxDefinitions.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        _ = save()
        return definition
    }

    @discardableResult
    func updateCustomSyntax(_ definition: NoteCustomSyntaxDefinition) -> Bool {
        guard let index = customSyntaxDefinitions.firstIndex(where: { $0.id == definition.id }) else { return false }
        var updated = definition
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.trigger = updated.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty, !updated.trigger.isEmpty,
              !customSyntaxDefinitions.contains(where: { $0.id != updated.id && $0.trigger == updated.trigger }) else { return false }
        updated.updatedAt = Date()
        customSyntaxDefinitions[index] = updated
        return save()
    }

    @discardableResult
    func deleteCustomSyntax(_ definition: NoteCustomSyntaxDefinition) -> Bool {
        customSyntaxDefinitions.removeAll { $0.id == definition.id }
        return save()
    }

    @discardableResult
    func addSyntaxTemplate(name: String, trigger: String, content: String) -> NoteSyntaxTemplate? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanTrigger.isEmpty, !content.isEmpty,
              !syntaxTemplates.contains(where: { $0.trigger == cleanTrigger }) else { return nil }
        let template = NoteSyntaxTemplate(name: cleanName, trigger: cleanTrigger, content: content)
        syntaxTemplates.append(template)
        _ = save()
        return template
    }

    @discardableResult
    func deleteSyntaxTemplate(_ template: NoteSyntaxTemplate) -> Bool {
        syntaxTemplates.removeAll { $0.id == template.id }
        return save()
    }

    @discardableResult
    func addEditorStylePreset(name: String) -> NoteEditorStylePreset? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              !editorStylePresets.contains(where: { $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame }) else { return nil }
        let preset = NoteEditorStylePreset(
            name: cleanName,
            contentWidth: editorSettings.editorLineWidth,
            paragraphSpacing: editorSettings.paragraphSpacing
        )
        editorStylePresets.append(preset)
        _ = save()
        return preset
    }

    @discardableResult
    func deleteEditorStylePreset(_ preset: NoteEditorStylePreset) -> Bool {
        editorStylePresets.removeAll { $0.id == preset.id }
        return save()
    }

    func attachments(for note: NoteRecord) -> [NoteAttachmentRecord] {
        note.attachmentIDs.compactMap { id in attachments.first { $0.id == id } }
    }

    func attachmentURL(for attachment: NoteAttachmentRecord) -> URL {
        if let bookmarkData = attachment.externalBookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        if let originalFilePath = attachment.originalFilePath {
            return URL(fileURLWithPath: originalFilePath)
        }
        return attachmentsDirectoryURL.appendingPathComponent(attachment.localRelativePath)
    }

    func markdownFileURL(for note: NoteRecord) -> URL? {
        guard let relativePath = noteFilePaths[note.id] else { return nil }
        return markdownNotesDirectoryURL.appendingPathComponent(relativePath)
    }

    @discardableResult
    func addAttachment(from sourceURL: URL, toNoteID noteID: UUID) -> NoteAttachmentRecord? {
        guard sourceURL.isFileURL,
              let noteIndex = notes.firstIndex(where: { $0.id == noteID }) else { return nil }
        let id = UUID()
        let cleanName = sourceURL.lastPathComponent.isEmpty ? "Attachment" : sourceURL.lastPathComponent
        do {
            let bookmarkData = try sourceURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: [.fileSizeKey, .contentTypeKey],
                relativeTo: nil
            )
            let resourceValues = try? sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            let attachment = NoteAttachmentRecord(
                id: id,
                fileName: cleanName,
                localRelativePath: "",
                externalBookmarkData: bookmarkData,
                originalFilePath: sourceURL.path,
                mediaType: Self.mediaType(for: cleanName, contentType: resourceValues?.contentType),
                fileSize: Int64(resourceValues?.fileSize ?? 0),
                displayWidth: nil,
                naturalAspectRatio: nil,
                showsFrame: nil,
                createdAt: Date()
            )
            attachments.append(attachment)
            notes[noteIndex].attachmentIDs.append(id)
            notes[noteIndex].updatedAt = Date()
            guard save() else {
                attachments.removeAll { $0.id == id }
                notes[noteIndex].attachmentIDs.removeAll { $0 == id }
                return nil
            }
            return attachment
        } catch {
            return nil
        }
    }

    @discardableResult
    func addAttachment(data: Data, fileName: String, toNoteID noteID: UUID) -> NoteAttachmentRecord? {
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteID }), !data.isEmpty else { return nil }
        let id = UUID()
        let cleanName = fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Attachment" : fileName
        let storedName = id.uuidString + (cleanName as NSString).pathExtension.withDotPrefix
        let destination = attachmentsDirectoryURL.appendingPathComponent(storedName)
        do {
            try data.write(to: destination, options: .atomic)
            let attachment = NoteAttachmentRecord(
                id: id,
                fileName: cleanName,
                localRelativePath: storedName,
                externalBookmarkData: nil,
                originalFilePath: nil,
                mediaType: Self.mediaType(for: cleanName),
                fileSize: Int64(data.count),
                displayWidth: nil,
                naturalAspectRatio: nil,
                showsFrame: nil,
                createdAt: Date()
            )
            attachments.append(attachment)
            notes[noteIndex].attachmentIDs.append(id)
            notes[noteIndex].updatedAt = Date()
            guard save() else {
                try? fileManager.removeItem(at: destination)
                attachments.removeAll { $0.id == id }
                notes[noteIndex].attachmentIDs.removeAll { $0 == id }
                return nil
            }
            return attachment
        } catch {
            return nil
        }
    }

    @discardableResult
    func removeAttachment(_ attachment: NoteAttachmentRecord, fromNoteID noteID: UUID) -> Bool {
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        notes[noteIndex].attachmentIDs.removeAll { $0 == attachment.id }
        notes[noteIndex].updatedAt = Date()
        let remainsReferenced = notes.contains { $0.attachmentIDs.contains(attachment.id) }
        if !remainsReferenced {
            if !attachment.isExternallyLinked {
                try? fileManager.removeItem(at: attachmentURL(for: attachment))
            }
            attachments.removeAll { $0.id == attachment.id }
        }
        return save()
    }

    @discardableResult
    func updateAttachmentDisplayWidth(_ attachmentID: UUID, width: Double) -> Bool {
        guard let index = attachments.firstIndex(where: { $0.id == attachmentID }) else { return false }
        attachments[index].displayWidth = min(max(width, 220), 720)
        return save()
    }

    @discardableResult
    func updateAttachmentAspectRatio(_ attachmentID: UUID, aspectRatio: Double) -> Bool {
        guard aspectRatio.isFinite, aspectRatio > 0,
              let index = attachments.firstIndex(where: { $0.id == attachmentID }) else { return false }
        let clampedRatio = min(max(aspectRatio, 0.1), 10)
        if let existing = attachments[index].naturalAspectRatio,
           abs(existing - clampedRatio) < 0.001 {
            return true
        }
        attachments[index].naturalAspectRatio = clampedRatio
        return save()
    }

    @discardableResult
    func setAttachmentFrameVisible(_ attachmentID: UUID, isVisible: Bool) -> Bool {
        guard let index = attachments.firstIndex(where: { $0.id == attachmentID }) else { return false }
        attachments[index].showsFrame = isVisible
        return save()
    }

    @discardableResult
    func ensureAttachmentReferences(_ attachmentIDs: Set<UUID>, on noteID: UUID) -> Bool {
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteID }) else { return false }
        let validIDs = attachmentIDs.filter { id in attachments.contains { $0.id == id } }
        let missingIDs = validIDs.filter { !notes[noteIndex].attachmentIDs.contains($0) }
        guard !missingIDs.isEmpty else { return true }
        notes[noteIndex].attachmentIDs.append(contentsOf: missingIDs)
        return save()
    }

    @discardableResult
    func cleanupOrphanedAttachments() -> Int {
        let referencedIDs = Set(notes.flatMap(\.attachmentIDs))
        let orphaned = attachments.filter { !referencedIDs.contains($0.id) }
        for attachment in orphaned {
            if !attachment.isExternallyLinked {
                try? fileManager.removeItem(at: attachmentURL(for: attachment))
            }
        }
        attachments.removeAll { !referencedIDs.contains($0.id) }
        let validPaths = Set(attachments.filter { !$0.isExternallyLinked }.map(\.localRelativePath))
        let strayFiles = (try? fileManager.contentsOfDirectory(
            at: attachmentsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { !validPaths.contains($0.lastPathComponent) } ?? []
        for url in strayFiles { try? fileManager.removeItem(at: url) }
        _ = save()
        return orphaned.count + strayFiles.count
    }

    @discardableResult
    func addTag(name: String, color: NoteTagColor, symbolName: String?) -> NoteTagRecord? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return nil }
        if let existing = tag(named: normalizedName) {
            return existing
        }
        let tag = NoteTagRecord(
            name: normalizedName,
            color: color,
            symbolName: normalizedSymbol(symbolName)
        )
        tags.append(tag)
        sortTags()
        _ = save()
        return tag
    }

    @discardableResult
    func updateTag(_ tag: NoteTagRecord) -> Bool {
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else { return false }
        let normalizedName = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              !tags.contains(where: {
                  $0.id != tag.id && $0.name.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
              }) else {
            return false
        }
        var updated = tag
        updated.name = normalizedName
        updated.symbolName = normalizedSymbol(updated.symbolName)
        updated.updatedAt = Date()
        tags[index] = updated
        sortTags()
        return save()
    }

    @discardableResult
    func deleteTag(_ tag: NoteTagRecord) -> Bool {
        tags.removeAll { $0.id == tag.id }
        let now = Date()
        for index in notes.indices where notes[index].tagIDs.contains(tag.id) {
            notes[index].tagIDs.removeAll { $0 == tag.id }
            notes[index].updatedAt = now
        }
        sortNotes()
        return save()
    }

    @discardableResult
    func toggleTag(_ tagID: UUID, on noteID: UUID) -> Bool {
        guard tags.contains(where: { $0.id == tagID }),
              let index = notes.firstIndex(where: { $0.id == noteID }) else {
            return false
        }
        if notes[index].tagIDs.contains(tagID) {
            notes[index].tagIDs.removeAll { $0 == tagID }
        } else {
            notes[index].tagIDs.append(tagID)
        }
        notes[index].updatedAt = Date()
        sortNotes()
        return save()
    }

    func tags(for note: NoteRecord) -> [NoteTagRecord] {
        note.tagIDs.compactMap { tagID in tags.first { $0.id == tagID } }
    }

    @discardableResult
    func addFolder(name: String, parentFolderID: UUID? = nil) -> NoteFolderRecord? {
        let normalizedName = normalizedFolderName(name)
        guard !normalizedName.isEmpty else { return nil }
        let resolvedParentID = validFolderID(parentFolderID)
        guard !folders.contains(where: {
            $0.parentFolderID == resolvedParentID
                && $0.name.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
        }) else {
            return nil
        }
        let folder = NoteFolderRecord(
            name: normalizedName,
            parentFolderID: resolvedParentID,
            manualOrder: nextFolderOrder(in: resolvedParentID)
        )
        folders.append(folder)
        sortFolders()
        _ = save()
        return folder
    }

    @discardableResult
    func renameFolder(_ folder: NoteFolderRecord, name: String) -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return false }
        let normalizedName = normalizedFolderName(name)
        guard !normalizedName.isEmpty,
              !folders.contains(where: {
                  $0.id != folder.id
                      && $0.parentFolderID == folder.parentFolderID
                      && $0.name.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
              }) else {
            return false
        }
        folders[index].name = normalizedName
        folders[index].updatedAt = Date()
        sortFolders()
        return save()
    }

    @discardableResult
    func deleteFolder(_ folder: NoteFolderRecord) -> Bool {
        guard folders.contains(where: { $0.id == folder.id }) else { return false }
        let parentID = validFolderID(folder.parentFolderID)
        let now = Date()
        for index in folders.indices where folders[index].parentFolderID == folder.id {
            folders[index].parentFolderID = parentID
            folders[index].manualOrder = nextFolderOrder(in: parentID)
            folders[index].updatedAt = now
        }
        for index in notes.indices where notes[index].folderID == folder.id {
            notes[index].folderID = parentID
            notes[index].manualOrder = nextNoteOrder(in: parentID)
            notes[index].updatedAt = now
        }
        folders.removeAll { $0.id == folder.id }
        sortFolders()
        sortNotes()
        return save()
    }

    @discardableResult
    func moveNote(_ noteID: UUID, toFolderID folderID: UUID?) -> Bool {
        moveNotes([noteID], toFolderID: folderID)
    }

    @discardableResult
    func moveNotes(_ noteIDs: [UUID], toFolderID folderID: UUID?, before targetID: UUID? = nil) -> Bool {
        let requestedIDs = uniqueIDs(noteIDs)
        let movingIDs = requestedIDs.filter { id in notes.contains(where: { $0.id == id }) }
        guard !movingIDs.isEmpty else { return false }

        let resolvedFolderID = validFolderID(folderID)
        let movingSet = Set(movingIDs)
        let sourceFolderIDs = Set(notes.filter { movingSet.contains($0.id) }.map(\.folderID))
        let now = Date()

        for index in notes.indices where movingSet.contains(notes[index].id) {
            notes[index].folderID = resolvedFolderID
            notes[index].updatedAt = now
        }

        var destinationIDs = notes
            .filter { $0.folderID == resolvedFolderID && !movingSet.contains($0.id) }
            .sorted(by: manualNoteOrder)
            .map(\.id)
        let insertionIndex = targetID
            .flatMap { destinationIDs.firstIndex(of: $0) }
            ?? destinationIDs.endIndex
        destinationIDs.insert(contentsOf: movingIDs, at: insertionIndex)
        applyNoteOrder(destinationIDs)

        for sourceFolderID in sourceFolderIDs where sourceFolderID != resolvedFolderID {
            let remainingIDs = notes
                .filter { $0.folderID == sourceFolderID && !movingSet.contains($0.id) }
                .sorted(by: manualNoteOrder)
                .map(\.id)
            applyNoteOrder(remainingIDs)
        }

        sortNotes()
        return save()
    }

    @discardableResult
    func reorderNote(_ noteID: UUID, before targetID: UUID) -> Bool {
        reorderNotes([noteID], relativeTo: targetID, placeAfter: false)
    }

    @discardableResult
    func reorderNotes(_ noteIDs: [UUID], before targetID: UUID) -> Bool {
        reorderNotes(noteIDs, relativeTo: targetID, placeAfter: false)
    }

    @discardableResult
    func reorderNotes(_ noteIDs: [UUID], relativeTo targetID: UUID, placeAfter: Bool) -> Bool {
        let requestedSet = Set(uniqueIDs(noteIDs))
        guard !requestedSet.isEmpty,
              !requestedSet.contains(targetID),
              let target = notes.first(where: { $0.id == targetID }) else { return false }

        var siblingIDs = notes
            .filter { $0.folderID == target.folderID }
            .sorted(by: manualNoteOrder)
            .map(\.id)
        let movingIDs = siblingIDs.filter { requestedSet.contains($0) }
        guard movingIDs.count == requestedSet.count else { return false }
        siblingIDs.removeAll { requestedSet.contains($0) }
        guard let targetIndex = siblingIDs.firstIndex(of: targetID) else { return false }
        siblingIDs.insert(contentsOf: movingIDs, at: targetIndex + (placeAfter ? 1 : 0))
        applyNoteOrder(siblingIDs)
        return save()
    }

    @discardableResult
    func reorderFolder(_ folderID: UUID, before targetID: UUID) -> Bool {
        reorderFolder(folderID, relativeTo: targetID, placeAfter: false)
    }

    @discardableResult
    func reorderFolder(_ folderID: UUID, relativeTo targetID: UUID, placeAfter: Bool) -> Bool {
        guard folderID != targetID,
              let folder = folders.first(where: { $0.id == folderID }),
              let target = folders.first(where: { $0.id == targetID }),
              folder.parentFolderID == target.parentFolderID else { return false }

        var siblingIDs = folders
            .filter { $0.parentFolderID == folder.parentFolderID }
            .sorted(by: manualFolderOrder)
            .map(\.id)
        guard let sourceIndex = siblingIDs.firstIndex(of: folderID) else { return false }
        siblingIDs.remove(at: sourceIndex)
        guard let targetIndex = siblingIDs.firstIndex(of: targetID) else { return false }
        siblingIDs.insert(folderID, at: targetIndex + (placeAfter ? 1 : 0))
        applyFolderOrder(siblingIDs)
        sortFolders()
        return save()
    }

    func folders(in parentFolderID: UUID?) -> [NoteFolderRecord] {
        let resolvedParentID = validFolderID(parentFolderID)
        return folders.filter { $0.parentFolderID == resolvedParentID }
    }

    func folder(withID folderID: UUID?) -> NoteFolderRecord? {
        guard let folderID else { return nil }
        return folders.first { $0.id == folderID }
    }

    func notes(forGoalID goalID: UUID) -> [NoteRecord] {
        notes.filter { !$0.isArchived && $0.linkedGoalID == goalID }
    }

    func notes(forTaskID taskID: UUID) -> [NoteRecord] {
        notes.filter { !$0.isArchived && $0.linkedTaskID == taskID }
    }

    func notes(forEventID eventID: UUID) -> [NoteRecord] {
        notes.filter { !$0.isArchived && $0.linkedEventID == eventID }
    }

    func notes(forSessionID sessionID: UUID) -> [NoteRecord] {
        notes.filter { !$0.isArchived && $0.linkedSessionID == sessionID }
    }

    func notes(forDay day: Date, calendar: Calendar = .current) -> [NoteRecord] {
        notes.filter { note in
            guard !note.isArchived, let linkedDay = note.linkedDay else { return false }
            return calendar.isDate(linkedDay, inSameDayAs: day)
        }
    }

    func search(query: String) -> [NoteRecord] {
        let terms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !terms.isEmpty else { return notes }

        return notes.filter { note in
            let tagNames = tags(for: note).map(\.name)
            let folderName = folder(withID: note.folderID)?.name ?? ""
            let searchableText = ([note.title, note.body, note.noteType.rawValue, note.source.rawValue, folderName] + tagNames)
                .joined(separator: " ")
            return terms.allSatisfy { searchableText.localizedStandardContains($0) }
        }
    }

    private func load() {
        tags = Self.defaultTags()
        folders = []
        var needsSave = false
        var decodedArchive = false
        var legacyNotes: [NoteRecord] = []
        if let data = try? Data(contentsOf: fileURL),
           let archive = try? decoder.decode(Archive.self, from: data) {
            decodedArchive = true
            legacyNotes = archive.notes ?? []
            tags = archive.tags
            folders = archive.folders ?? []
            editorSettings = archive.editorSettings ?? NoteEditorSettingsRecord()
            customSyntaxDefinitions = archive.customSyntaxDefinitions ?? []
            syntaxTemplates = archive.syntaxTemplates ?? []
            editorStylePresets = archive.editorStylePresets ?? []
            attachments = archive.attachments ?? []
            noteFilePaths = Dictionary(uniqueKeysWithValues: (archive.noteFiles ?? []).map { ($0.id, $0.relativePath) })
            needsSave = archive.version < 7 || archive.notes != nil || archive.noteFiles == nil
        } else if let data = try? Data(contentsOf: fileURL),
                  let decodedLegacyNotes = try? decoder.decode([NoteRecord].self, from: data) {
            legacyNotes = decodedLegacyNotes
            needsSave = true
        }

        markdownFilesNeedRewrite = false
        notes = loadMarkdownNotes()
        if markdownFilesNeedRewrite || (!decodedArchive && !notes.isEmpty) { needsSave = true }
        let loadedIDs = Set(notes.map(\.id))
        notes.append(contentsOf: legacyNotes.filter { !loadedIDs.contains($0.id) })
        if !legacyNotes.isEmpty { needsSave = true }

        if migrateLegacyTags() {
            needsSave = true
        }
        normalizeLoadedRecords()
        sortTags()
        sortFolders()
        sortNotes()
        if needsSave {
            _ = save()
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try persistMarkdownNotes()
            let archive = Archive(
                version: 7,
                notes: nil,
                noteFiles: notes.compactMap { note in
                    noteFilePaths[note.id].map { NoteFileReference(id: note.id, relativePath: $0) }
                },
                tags: tags,
                folders: folders,
                editorSettings: editorSettings,
                customSyntaxDefinitions: customSyntaxDefinitions,
                syntaxTemplates: syntaxTemplates,
                editorStylePresets: editorStylePresets,
                attachments: attachments
            )
            let data = try encoder.encode(archive)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func persistMarkdownNotes() throws {
        try fileManager.createDirectory(at: markdownNotesDirectoryURL, withIntermediateDirectories: true)
        let activeIDs = Set(notes.map(\.id))
        noteFilePaths = noteFilePaths.filter { activeIDs.contains($0.key) }

        for note in notes {
            let relativePath = noteFilePaths[note.id] ?? uniqueMarkdownFileName(for: note)
            noteFilePaths[note.id] = relativePath
            let destination = markdownNotesDirectoryURL.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let rendered = markdownDocument(for: note)
            let data = Data(rendered.utf8)
            if (try? Data(contentsOf: destination)) != data {
                try data.write(to: destination, options: .atomic)
            }
        }
    }

    private func loadMarkdownNotes() -> [NoteRecord] {
        guard let enumerator = fileManager.enumerator(
            at: markdownNotesDirectoryURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var loaded: [NoteRecord] = []
        var seenIDs: Set<UUID> = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  var note = parseMarkdownNote(at: url) else { continue }
            if !seenIDs.insert(note.id).inserted {
                note = reidentified(note)
                seenIDs.insert(note.id)
                markdownFilesNeedRewrite = true
            }
            let relativePath = url.path.replacingOccurrences(
                of: markdownNotesDirectoryURL.path + "/",
                with: ""
            )
            noteFilePaths[note.id] = relativePath
            loaded.append(note)
        }
        return loaded
    }

    private func reidentified(_ note: NoteRecord) -> NoteRecord {
        NoteRecord(
            id: UUID(),
            title: note.title,
            body: note.body,
            tagIDs: note.tagIDs,
            noteType: note.noteType,
            isPinned: note.isPinned,
            isArchived: note.isArchived,
            folderID: note.folderID,
            manualOrder: note.manualOrder,
            attachmentIDs: note.attachmentIDs,
            source: note.source,
            linkedTaskID: note.linkedTaskID,
            linkedEventID: note.linkedEventID,
            linkedGoalID: note.linkedGoalID,
            linkedSessionID: note.linkedSessionID,
            linkedDay: note.linkedDay,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt
        )
    }

    private func parseMarkdownNote(at url: URL) -> NoteRecord? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let parsed = parseFrontMatter(from: normalized)
        let metadata = parsed.metadata
        let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let fallbackCreated = resourceValues?.creationDate ?? Date()
        let fallbackUpdated = resourceValues?.contentModificationDate ?? fallbackCreated
        let source = stringValue(metadata["orchestrana_source"]).flatMap(NoteRecord.Source.init(rawValue:)) ?? .manual
        let storedID = stringValue(metadata["orchestrana_id"]).flatMap(UUID.init(uuidString:))
        if storedID == nil { markdownFilesNeedRewrite = true }
        let id = storedID ?? UUID()
        let title = stringValue(metadata["title"])
            ?? inferredTitle(from: parsed.body, fileName: url.deletingPathExtension().lastPathComponent)
        let storedTagIDs = stringArray(metadata["orchestrana_tag_ids"]).compactMap(UUID.init(uuidString:))
        let tagNames = stringArray(metadata["tags"])
        let resolvedTagIDs = uniqueIDs(storedTagIDs + tagNames.compactMap { resolveOrCreateTagID(named: $0) })

        return NoteRecord(
            id: id,
            title: title,
            body: parsed.body,
            tagIDs: resolvedTagIDs,
            noteType: stringValue(metadata["orchestrana_note_type"])
                .flatMap(NoteRecord.NoteType.init(rawValue:)) ?? NoteRecord.defaultType(for: source),
            isPinned: boolValue(metadata["orchestrana_pinned"]) ?? false,
            isArchived: boolValue(metadata["orchestrana_archived"]) ?? false,
            folderID: stringValue(metadata["orchestrana_folder_id"]).flatMap(UUID.init(uuidString:)),
            manualOrder: intValue(metadata["orchestrana_manual_order"]) ?? .max,
            attachmentIDs: stringArray(metadata["orchestrana_attachment_ids"]).compactMap(UUID.init(uuidString:)),
            source: source,
            linkedTaskID: stringValue(metadata["orchestrana_linked_task_id"]).flatMap(UUID.init(uuidString:)),
            linkedEventID: stringValue(metadata["orchestrana_linked_event_id"]).flatMap(UUID.init(uuidString:)),
            linkedGoalID: stringValue(metadata["orchestrana_linked_goal_id"]).flatMap(UUID.init(uuidString:)),
            linkedSessionID: stringValue(metadata["orchestrana_linked_session_id"]).flatMap(UUID.init(uuidString:)),
            linkedDay: dateValue(metadata["orchestrana_linked_day"]),
            createdAt: dateValue(metadata["created"]) ?? fallbackCreated,
            updatedAt: dateValue(metadata["updated"]) ?? fallbackUpdated
        )
    }

    private func parseFrontMatter(from document: String) -> (metadata: [String: Any], body: String) {
        guard document.hasPrefix("---\n"),
              let closingRange = document.range(of: "\n---\n", range: document.index(document.startIndex, offsetBy: 4)..<document.endIndex) else {
            return ([:], document)
        }
        let metadataStart = document.index(document.startIndex, offsetBy: 4)
        let metadataText = String(document[metadataStart..<closingRange.lowerBound])
        var metadata: [String: Any] = [:]
        for line in metadataText.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let valueStart = line.index(after: separator)
            let rawValue = line[valueStart...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, let data = rawValue.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            metadata[key] = value
        }
        return (metadata, String(document[closingRange.upperBound...]))
    }

    private func markdownDocument(for note: NoteRecord) -> String {
        let tagNames = tags(for: note).map(\.name)
        let folderName = folder(withID: note.folderID)?.name
        let attachmentNames = attachments(for: note).map(\.fileName)
        var lines = [
            "---",
            "title: \(jsonLiteral(note.title))",
            "tags: \(jsonLiteral(tagNames))",
            "created: \(jsonLiteral(iso8601String(note.createdAt)))",
            "updated: \(jsonLiteral(iso8601String(note.updatedAt)))",
            "orchestrana_version: 1",
            "orchestrana_id: \(jsonLiteral(note.id.uuidString))",
            "orchestrana_note_type: \(jsonLiteral(note.noteType.rawValue))",
            "orchestrana_source: \(jsonLiteral(note.source.rawValue))",
            "orchestrana_pinned: \(note.isPinned)",
            "orchestrana_archived: \(note.isArchived)",
            "orchestrana_manual_order: \(note.manualOrder)",
            "orchestrana_tag_ids: \(jsonLiteral(note.tagIDs.map(\.uuidString)))",
            "orchestrana_attachment_ids: \(jsonLiteral(note.attachmentIDs.map(\.uuidString)))",
            "attachments: \(jsonLiteral(attachmentNames))"
        ]
        appendFrontMatter("folder", value: folderName, to: &lines)
        appendFrontMatter("orchestrana_folder_id", value: note.folderID?.uuidString, to: &lines)
        appendFrontMatter("orchestrana_linked_task_id", value: note.linkedTaskID?.uuidString, to: &lines)
        appendFrontMatter("orchestrana_linked_event_id", value: note.linkedEventID?.uuidString, to: &lines)
        appendFrontMatter("orchestrana_linked_goal_id", value: note.linkedGoalID?.uuidString, to: &lines)
        appendFrontMatter("orchestrana_linked_session_id", value: note.linkedSessionID?.uuidString, to: &lines)
        appendFrontMatter(
            "orchestrana_linked_day",
            value: note.linkedDay.map(iso8601String),
            to: &lines
        )
        lines.append("---")
        return lines.joined(separator: "\n") + "\n" + note.body
    }

    private func appendFrontMatter(_ key: String, value: String?, to lines: inout [String]) {
        guard let value else { return }
        lines.append("\(key): \(jsonLiteral(value))")
    }

    private func jsonLiteral(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value]),
              var rendered = String(data: data, encoding: .utf8),
              rendered.count >= 2 else { return "null" }
        rendered.removeFirst()
        rendered.removeLast()
        return rendered
    }

    private func uniqueMarkdownFileName(for note: NoteRecord) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>\n\r\t")
        let cleaned = note.title.components(separatedBy: invalid).joined(separator: "-")
        let collapsed = cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let title = collapsed.isEmpty ? "Untitled Note" : String(collapsed.prefix(80))
        return "\(title) -- \(note.id.uuidString).md"
    }

    private func relocateMarkdownFile(for note: NoteRecord) {
        guard let oldRelativePath = noteFilePaths[note.id] else { return }
        let newRelativePath = uniqueMarkdownFileName(for: note)
        guard oldRelativePath != newRelativePath else { return }
        let oldURL = markdownNotesDirectoryURL.appendingPathComponent(oldRelativePath)
        let newURL = markdownNotesDirectoryURL.appendingPathComponent(newRelativePath)
        do {
            if fileManager.fileExists(atPath: oldURL.path) {
                try fileManager.moveItem(at: oldURL, to: newURL)
            }
            noteFilePaths[note.id] = newRelativePath
        } catch {
            // Keep the existing path; the next save still updates its Markdown contents.
        }
    }

    private func inferredTitle(from body: String, fileName: String) -> String {
        if let heading = body.split(separator: "\n", omittingEmptySubsequences: false)
            .first(where: { $0.hasPrefix("# ") }) {
            let title = heading.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
        }
        return normalizedTitle(fileName)
    }

    private func stringValue(_ value: Any?) -> String? { value as? String }
    private func stringArray(_ value: Any?) -> [String] { value as? [String] ?? [] }
    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        return (value as? NSNumber)?.boolValue
    }
    private func intValue(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
    private func dateValue(_ value: Any?) -> Date? {
        guard let raw = stringValue(value) else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }
    private func iso8601String(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private func migrateLegacyTags() -> Bool {
        var changed = false
        for index in notes.indices where !notes[index].legacyTagNames.isEmpty {
            let migratedIDs = notes[index].legacyTagNames.compactMap { resolveOrCreateTagID(named: $0) }
            notes[index].tagIDs = uniqueIDs(notes[index].tagIDs + migratedIDs)
            notes[index].legacyTagNames = []
            changed = true
        }
        return changed
    }

    private func normalizeLoadedRecords() {
        let validTagIDs = Set(tags.map(\.id))
        let validFolderIDs = Set(folders.map(\.id))
        let validAttachmentIDs = Set(attachments.map(\.id))
        for index in folders.indices where folders[index].parentFolderID == folders[index].id {
            folders[index].parentFolderID = nil
        }
        for index in folders.indices {
            if let parentID = folders[index].parentFolderID, !validFolderIDs.contains(parentID) {
                folders[index].parentFolderID = nil
            }
        }
        for index in notes.indices {
            notes[index].title = normalizedTitle(notes[index].title)
            notes[index].tagIDs = uniqueIDs(notes[index].tagIDs.filter { validTagIDs.contains($0) })
            notes[index].attachmentIDs = uniqueIDs(notes[index].attachmentIDs.filter { validAttachmentIDs.contains($0) })
            if let folderID = notes[index].folderID, !validFolderIDs.contains(folderID) {
                notes[index].folderID = nil
            }
            notes[index].legacyTagNames = []
        }
        normalizeManualOrders()
    }

    private func resolveOrCreateTagID(named rawName: String) -> UUID? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let existing = tag(named: name) {
            return existing.id
        }
        let created = NoteTagRecord(name: name, color: .gray, symbolName: "tag")
        tags.append(created)
        return created.id
    }

    private func tag(named name: String) -> NoteTagRecord? {
        tags.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }

    private func normalizedSymbol(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedFolderName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validFolderID(_ folderID: UUID?) -> UUID? {
        guard let folderID, folders.contains(where: { $0.id == folderID }) else { return nil }
        return folderID
    }

    private func uniqueIDs(_ ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
    }

    private func nextNoteOrder(in folderID: UUID?) -> Int {
        (notes.filter { $0.folderID == folderID }.map(\.manualOrder).filter { $0 != .max }.max() ?? -1) + 1
    }

    private func nextFolderOrder(in parentFolderID: UUID?) -> Int {
        (folders.filter { $0.parentFolderID == parentFolderID }.map(\.manualOrder).filter { $0 != .max }.max() ?? -1) + 1
    }

    private func normalizeManualOrders() {
        let noteGroups = Dictionary(grouping: notes.indices) { notes[$0].folderID?.uuidString ?? "root" }
        for indices in noteGroups.values {
            let ordered = indices.sorted {
                if notes[$0].manualOrder != notes[$1].manualOrder {
                    return notes[$0].manualOrder < notes[$1].manualOrder
                }
                return $0 < $1
            }
            applyNoteOrder(ordered.map { notes[$0].id })
        }

        let folderGroups = Dictionary(grouping: folders.indices) {
            folders[$0].parentFolderID?.uuidString ?? "root"
        }
        for indices in folderGroups.values {
            let ordered = indices.sorted {
                if folders[$0].manualOrder != folders[$1].manualOrder {
                    return folders[$0].manualOrder < folders[$1].manualOrder
                }
                return $0 < $1
            }
            applyFolderOrder(ordered.map { folders[$0].id })
        }
    }

    private func applyNoteOrder(_ orderedIDs: [UUID]) {
        for (order, id) in orderedIDs.enumerated() {
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index].manualOrder = order
            }
        }
    }

    private func applyFolderOrder(_ orderedIDs: [UUID]) {
        for (order, id) in orderedIDs.enumerated() {
            if let index = folders.firstIndex(where: { $0.id == id }) {
                folders[index].manualOrder = order
            }
        }
    }

    private func manualNoteOrder(_ lhs: NoteRecord, _ rhs: NoteRecord) -> Bool {
        if lhs.manualOrder != rhs.manualOrder { return lhs.manualOrder < rhs.manualOrder }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func manualFolderOrder(_ lhs: NoteFolderRecord, _ rhs: NoteFolderRecord) -> Bool {
        if lhs.manualOrder != rhs.manualOrder { return lhs.manualOrder < rhs.manualOrder }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func sortNotes() {
        notes.sort { $0.updatedAt > $1.updatedAt }
    }

    private func sortTags() {
        tags.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func sortFolders() {
        folders.sort { lhs, rhs in
            if lhs.parentFolderID != rhs.parentFolderID {
                return (lhs.parentFolderID?.uuidString ?? "") < (rhs.parentFolderID?.uuidString ?? "")
            }
            return manualFolderOrder(lhs, rhs)
        }
    }

    private static func defaultTags() -> [NoteTagRecord] {
        [
            NoteTagRecord(name: "Important", color: .red, symbolName: "exclamationmark"),
            NoteTagRecord(name: "Decision", color: .purple, symbolName: "arrow.triangle.branch"),
            NoteTagRecord(name: "Blocker", color: .orange, symbolName: "exclamationmark.triangle"),
            NoteTagRecord(name: "Idea", color: .yellow, symbolName: "lightbulb"),
            NoteTagRecord(name: "Research", color: .blue, symbolName: "book.closed"),
            NoteTagRecord(name: "Personal", color: .green, symbolName: "person")
        ]
    }

    private static func mediaType(
        for fileName: String,
        contentType suppliedType: UTType? = nil
    ) -> NoteAttachmentRecord.MediaType {
        let contentType = suppliedType ?? UTType(filenameExtension: (fileName as NSString).pathExtension)
        if contentType?.conforms(to: .image) == true { return .image }
        if contentType?.conforms(to: .audio) == true { return .audio }
        if contentType?.conforms(to: .movie) == true { return .video }
        if contentType?.conforms(to: .pdf) == true { return .pdf }
        return .file
    }
}

private extension String {
    var withDotPrefix: String { isEmpty ? "" : "." + self }
}
