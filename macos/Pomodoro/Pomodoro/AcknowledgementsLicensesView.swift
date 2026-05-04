import AppKit
import SwiftUI

struct AcknowledgementsLicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Acknowledgements & Licenses")
                    .font(.largeTitle.weight(.semibold))

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Orchestrana includes third-party resources and open-source components. The notices below are provided for attribution and license compliance.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Self.licenseSections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.title3.weight(.semibold))

                            if let note = section.note {
                                Text(note)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(section.paragraphs, id: \.self) { paragraph in
                                    Text(paragraph)
                                        .font(.system(.body, design: .default))
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        if section.id != Self.licenseSections.last?.id {
                            Divider()
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("License Links")
                            .font(.title3.weight(.semibold))

                        HStack(spacing: 10) {
                            ForEach(Self.licenseLinks) { link in
                                Link(link.title, destination: link.url)
                                    .buttonStyle(.bordered)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    static let shortAttribution = "Orchestrana includes third-party resources under open-source licenses. Full license details are available in Settings."

    private static let licenseSections: [LicenseSection] = [
        LicenseSection(
            title: "Orchestrana macOS Client",
            note: "The public client application is distributed under the MIT License.",
            paragraphs: Self.mitLicenseParagraphs(copyright: "Copyright (c) 2026 Tony and contributors")
        ),
        LicenseSection(
            title: "Orchestrana Cloud Services",
            note: "The server-side implementation is not part of the open-source client license.",
            paragraphs: ["© 2026 Orchestrana. All rights reserved."]
        ),
        LicenseSection(
            title: "Audio Pack Resources",
            note: "Bundled focus audio resources are provided under the Creative Commons CC0 public domain dedication from Freesound.org.",
            paragraphs: [
                "The bundled ambient audio packs include edited and compressed sound resources sourced from Freesound.org. These resources are marked as Creative Commons CC0/public domain by their original uploaders, allowing use, modification, and redistribution without attribution requirements.",
                "Orchestrana still provides this acknowledgement as a courtesy to the creators and the Freesound community. The audio resources are included only as optional focus ambience and are provided as-is, without warranty, endorsement, or guarantee of fitness for any particular purpose."
            ]
        ),
        LicenseSection(
            title: "App Icon Attribution",
            note: "Portions of the app icon include MIT-licensed Microsoft design resources.",
            paragraphs: Self.mitLicenseParagraphs(copyright: "Copyright (c) 2020 Microsoft Corporation")
        )
    ]

    private static func mitLicenseParagraphs(copyright: String) -> [String] {
        [
            "MIT License",
            copyright,
            "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:",
            "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.",
            "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."
        ]
    }

    private static let licenseLinks = [
        LicenseLink(title: "CC0 Summary", url: URL(string: "https://creativecommons.org/publicdomain/zero/1.0/deed.en")!),
        LicenseLink(title: "CC0 Legal Code", url: URL(string: "https://creativecommons.org/publicdomain/zero/1.0/legalcode.en")!),
        LicenseLink(title: "MIT License", url: URL(string: "https://opensource.org/license/mit")!)
    ]

    private struct LicenseLink: Identifiable {
        let id = UUID()
        let title: String
        let url: URL
    }

    private struct LicenseSection: Identifiable {
        let id = UUID()
        let title: String
        let note: String?
        let paragraphs: [String]
    }
}

struct AboutOrchestranaView: View {
    @State private var showAcknowledgements = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .cornerRadius(14)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Orchestrana")
                        .font(.title2.weight(.semibold))
                    Text(versionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(AcknowledgementsLicensesView.shortAttribution)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("View Acknowledgements & Licenses") {
                    showAcknowledgements = true
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(28)
        .frame(width: 420, alignment: .leading)
        .sheet(isPresented: $showAcknowledgements) {
            AcknowledgementsLicensesView()
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (version?, build?):
            return "Version \(version) (\(build))"
        case let (version?, nil):
            return "Version \(version)"
        case let (nil, build?):
            return "Build \(build)"
        default:
            return "Version unavailable"
        }
    }
}

@MainActor
enum AboutWindowPresenter {
    private static var windowController: NSWindowController?

    static func open() {
        if let window = windowController?.window {
            show(window)
            return
        }

        let hostingController = NSHostingController(rootView: AboutOrchestranaView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About Orchestrana"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 420, height: 220)
        window.contentMaxSize = NSSize(width: 420, height: 260)
        window.setContentSize(NSSize(width: 420, height: 240))
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        show(window)
    }

    private static func show(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }
}
