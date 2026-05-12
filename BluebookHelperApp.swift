import SwiftUI
import SwiftData
import Foundation

// 1. 枚举与模型
enum CitationType: String, CaseIterable, Codable, Identifiable {
    case caseCitation = "Case", statute = "Statute", lawReview = "Law Review", book = "Book", website = "Website"
    var id: String { rawValue }
}

@Model
final class CitationRecord {
    var id: UUID = UUID()
    var type: CitationType
    var fieldsJSON: String
    var formattedText: String
    var createdAt: Date = Date.now
    init(type: CitationType, fields: [String: String], output: String) {
        self.type = type
        self.fieldsJSON = try? JSONEncoder().encode(fields).map { String($0) } ?? "{}"
        self.formattedText = output
    }
    var decodedFields: [String: String] {
        guard let data = fieldsJSON.data(using: .utf8), let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }
}

// 2. 格式化逻辑
struct CitationFormatter {
    static func format(type: CitationType, fields: [String: String]) -> String {
        switch type {
        case .caseCitation:
            let name = fields["Case Name"] ?? "", vol = fields["Volume"] ?? "", rep = fields["Reporter"] ?? ""
            let page = fields["Page"] ?? "", court = fields["Court"] ?? "", year = fields["Year"] ?? ""
            let parts = [vol, rep, page].filter { !$0.isEmpty }.joined(separator: " ")
            let paren = [court, year].filter { !$0.isEmpty }.joined(separator: " ")
            return name.isEmpty ? "\(parts) (\(paren))" : "\(name), \(parts) (\(paren))"
        case .statute:
            let title = fields["Title"] ?? "", section = fields["Section"] ?? ""
            let code = fields["Code"] ?? "U.S.C.", year = fields["Year"] ?? ""
            return year.isEmpty ? "\(title) \(code) § \(section)" : "\(title) \(code) § \(section) (\(year))"
        case .lawReview:
            let author = fields["Author"] ?? "", title = fields["Title"] ?? ""
            let journal = fields["Journal"] ?? "", vol = fields["Volume"] ?? ""
            let page = fields["Page"] ?? "", year = fields["Year"] ?? ""
            let cite = "\(vol) \(journal) \(page) (\(year))"
            return author.isEmpty ? "\"\(title)\", \(cite)" : "\(author), \"\(title)\", \(cite)"
        case .book:
            let author = fields["Author"] ?? "", title = fields["Title"] ?? ""
            let edition = fields["Edition"] ?? "", publisher = fields["Publisher"] ?? ""
            let year = fields["Year"] ?? ""
            var parts: [String] = []
            if !author.isEmpty { parts.append(author) }
            if !title.isEmpty { parts.append(title) }
            if !edition.isEmpty { parts.append("\(edition) ed.") }
            return publisher.isEmpty ? parts.joined(separator: ", ") : "\(parts.joined(separator: ", ")) (\(publisher) \(year))"
        case .website:
            let author = fields["Author"] ?? "", title = fields["Title"] ?? ""
            let site = fields["Site"] ?? "", url = fields["URL"] ?? ""
            let date = fields["Access Date"] ?? ""
            var parts: [String] = []
            if !author.isEmpty { parts.append(author) }
            if !title.isEmpty { parts.append(title) }
            if !site.isEmpty { parts.append(site) }
            return date.isEmpty ? "\(parts.joined(separator: ", ")), \(url)" : "\(parts.joined(separator: ", ")), \(url) (last visited \(date))"
        }
    }
}

// 3. 视图：生成器
struct GeneratorView: View {
    @Environment(\.modelContext) private var context
    @State private var selectedType: CitationType = .caseCitation
    @State private var fields: [String: String] = [:]
    @State private var preview: String = ""
    @State private var showCopied = false
    var body: some View {
        Form {
            Section("Citation Type") {
                Picker("Type", selection: $selectedType) { ForEach(CitationType.allCases, id: \.id) { Text($0.rawValue) } }
                    .pickerStyle(.segmented)
            }
            Section("Input Fields") {
                ForEach(fields.keys.sorted(), id: \.self) { key in
                    HStack { Text(key).frame(width: 100, alignment: .leading)
                        TextField(key, text: Binding(get: { fields[key] ?? "" }, set: { fields[key] = $0; updatePreview() }))
                            .textInputAutocapitalization(.none) }
                }
            }
            Section("Preview") {
                Text(preview.isEmpty ? "Fill fields to generate..." : preview)
                    .font(.system(.body, design: .monospaced)).padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground)).cornerRadius(8)
            }
            Button(action: {
                UIPasteboard.general.string = preview
                context.insert(CitationRecord(type: selectedType, fields: fields, output: preview))
                try? context.save(); showCopied = true
            }) { Label("Copy & Save", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).disabled(preview.isEmpty)
        }.navigationTitle("Generator")
        .onAppear { resetForm() }.onChange(of: selectedType) { resetForm() }
        .alert("Copied to Clipboard", isPresented: $showCopied) { Button("OK", role: .cancel) {} }
    }
    private func resetForm() {
        switch selectedType {
        case .caseCitation: fields = ["Case Name": "", "Volume": "", "Reporter": "", "Page": "", "Court": "", "Year": ""]
        case .statute: fields = ["Title": "", "Section": "", "Code": "U.S.C.", "Year": ""]
        case .lawReview: fields = ["Author": "", "Title": "", "Journal": "", "Volume": "", "Page": "", "Year": ""]
        case .book: fields = ["Author": "", "Title": "", "Edition": "", "Publisher": "", "Year": ""]
        case .website: fields = ["Author": "", "Title": "", "Site": "", "URL": "", "Access Date": ""]
        }
        updatePreview()
    }
    private func updatePreview() { preview = CitationFormatter.format(type: selectedType, fields: fields) }
}

// 4. 视图：历史
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CitationRecord.createdAt, order: .reverse) var records: [CitationRecord]
    @State private var showClear = false
    var body: some View {
        NavigationStack {
            List(records) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.type.rawValue).font(.caption).foregroundColor(.secondary)
                    Text(record.formattedText).font(.system(.body, design: .monospaced)).lineLimit(3)
                    Text(record.createdAt, style: .date).font(.caption2).foregroundColor(.tertiary)
                }.onTapGesture { UIPasteboard.general.string = record.formattedText }
            }.navigationTitle("History")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear", role: .destructive) { showClear = true }.disabled(records.isEmpty) } }
            .alert("Delete All History?", isPresented: $showClear) {
                Button("Delete", role: .destructive) { for r in records { context.delete(r) }; try? context.save() }
                Button("Cancel", role: .cancel) {} }
        }
    }
}

// 5. 视图：设置
struct SettingsView: View {
    var body: some View {
        NavigationStack { Form {
            Section("App Info") { Text("Bluebook Citation Helper v1.0.0"); Text("100% Offline Utility") }
            Section("Legal") { Text("Educational purposes only. Verify against Bluebook 21st Ed.")
                .font(.caption).foregroundColor(.secondary) }
        }.navigationTitle("Settings") }
    }
}

// 6. App 入口
@main
struct BluebookHelperApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                GeneratorView().tabItem { Label("Generator", systemImage: "doc.text.magnifyingglass") }
                HistoryView().tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                SettingsView().tabItem { Label("Settings", systemImage: "gear") }
            }.modelContainer(for: CitationRecord.self)
        }
    }
}
