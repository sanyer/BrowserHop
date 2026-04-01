import SwiftUI
import SwiftData
import AppKit

struct RuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var browserManager: BrowserManager
    @Query(sort: \RuleModel.order) private var allRules: [RuleModel]

    private enum ActionKind: Hashable {
        case showPicker
        case useDefault
        case openInApp
    }

    @State private var name: String = ""
    @State private var actionKind: ActionKind = .showPicker
    @State private var selectedBrowserID: String = ""
    @State private var conditionLogic: ConditionSet.Logic = .all
    @State private var criteria: [CriteriaState] = []

    var rule: RuleModel?

    init(rule: RuleModel? = nil) {
        self.rule = rule
        if let r = rule {
            self._name = State(initialValue: r.name)
            self._conditionLogic = State(initialValue: r.rootSet.logic)
            self._criteria = State(initialValue: r.rootSet.criteria.map { CriteriaState(from: $0) })
            switch r.action {
            case .showPicker:
                self._actionKind = State(initialValue: .showPicker)
            case .useDefault:
                self._actionKind = State(initialValue: .useDefault)
            case .openInApp(let bundleID):
                self._actionKind = State(initialValue: .openInApp)
                self._selectedBrowserID = State(initialValue: bundleID)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(rule == nil ? "New Rule" : "Edit Rule")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameSection
                    conditionsSection
                    actionSection
                }
                .padding(20)
            }

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveRule() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 480, maxWidth: 480, minHeight: 380)
    }

    // MARK: - Name

    @ViewBuilder
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            TextField("e.g. Work links to Chrome", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Conditions

    @ViewBuilder
    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Conditions")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                if criteria.count > 1 {
                    Picker("", selection: $conditionLogic) {
                        Text("Match all").tag(ConditionSet.Logic.all)
                        Text("Match any").tag(ConditionSet.Logic.any)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }

            if criteria.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text("No conditions")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("This rule will match all URLs.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }

            ForEach(Array(criteria.enumerated()), id: \.element.id) { index, _ in
                CriteriaRowView(
                    item: $criteria[index],
                    browserManager: browserManager,
                    onDelete: { criteria.remove(at: index) }
                )
            }

            Button(action: { criteria.append(CriteriaState()) }) {
                Label("Add Condition", systemImage: "plus.circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
    }

    // MARK: - Action

    @ViewBuilder
    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Action")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Picker("When matched", selection: $actionKind) {
                    Text("Show Browser Picker").tag(ActionKind.showPicker)
                    Text("Use Default Browser").tag(ActionKind.useDefault)
                    Text("Open in Specific Browser").tag(ActionKind.openInApp)
                }
                .labelsHidden()

                if actionKind == .openInApp {
                    browserPicker
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    @ViewBuilder
    private var browserPicker: some View {
        if browserManager.browsers.isEmpty {
            Text("No browsers detected")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Picker("Browser", selection: $selectedBrowserID) {
                Text("Select a browser...").tag("")
                ForEach(browserManager.browsers) { browser in
                    HStack(spacing: 6) {
                        Image(nsImage: browser.icon.resized(to: 16))
                        Text(browser.displayName)
                    }
                    .tag(browser.id)
                }
            }
            .pickerStyle(.menu)
        }
    }


    // MARK: - Validation

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if actionKind == .openInApp && selectedBrowserID.isEmpty { return false }
        return true
    }

    // MARK: - Save

    private func saveRule() {
        let validCriteria = sanitizedCriteria()

        let finalAction: RuleAction
        switch actionKind {
        case .showPicker:
            finalAction = .showPicker
        case .useDefault:
            finalAction = .useDefault
        case .openInApp:
            finalAction = .openInApp(bundleID: selectedBrowserID)
        }

        if let rule = rule {
            rule.name = name.trimmingCharacters(in: .whitespaces)
            rule.action = finalAction
            rule.rootSet.logic = conditionLogic
            for c in rule.rootSet.criteria {
                modelContext.delete(c)
            }
            rule.rootSet.criteria = validCriteria.map { $0.toModel() }
        } else {
            let conditionSet = ConditionSet(
                logic: conditionLogic,
                criteria: validCriteria.map { $0.toModel() }
            )
            let nextOrder = (allRules.map(\.order).max() ?? -1) + 1
            let newRule = RuleModel(
                name: name.trimmingCharacters(in: .whitespaces),
                order: nextOrder,
                action: finalAction,
                rootSet: conditionSet
            )
            modelContext.insert(newRule)
        }
        dismiss()
    }

    /// Strips out any criteria that would be no-ops at evaluation time.
    private func sanitizedCriteria() -> [CriteriaState] {
        criteria.filter { item in
            let trimmed = item.value.trimmingCharacters(in: .whitespaces)
            // An empty value makes the condition meaningless
            guard !trimmed.isEmpty else { return false }
            // For regex, verify the pattern is compilable
            if item.field == .regex {
                return (try? NSRegularExpression(pattern: trimmed)) != nil
            }
            return true
        }
    }
}

// MARK: - Criteria Row

private struct CriteriaRowView: View {
    @Binding var item: CriteriaState
    var browserManager: BrowserManager
    var onDelete: () -> Void

    @State private var appSearchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: field picker, operator picker, delete button
            HStack(spacing: 6) {
                Picker("", selection: $item.field) {
                    Text("Source App").tag(Criteria.Field.sourceApp)
                    Text("Domain").tag(Criteria.Field.domain)
                    Text("URL Regex").tag(Criteria.Field.regex)
                }
                .labelsHidden()
                .frame(width: 110)
                .onChange(of: item.field) { _, newField in
                    switch newField {
                    case .sourceApp:
                        item.op = .equals
                    case .domain:
                        if item.op == .matches { item.op = .contains }
                    case .regex:
                        item.op = .matches
                    }
                }

                operatorPicker

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("Remove condition")
            }

            // Value editor
            valueEditor
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Operator

    @ViewBuilder
    private var operatorPicker: some View {
        switch item.field {
        case .sourceApp:
            Picker("", selection: $item.op) {
                Text("is").tag(Criteria.Operator.equals)
                Text("is not").tag(Criteria.Operator.notEquals)
            }
            .labelsHidden()
            .frame(width: 80)
        case .domain:
            Picker("", selection: $item.op) {
                Text("is").tag(Criteria.Operator.equals)
                Text("is not").tag(Criteria.Operator.notEquals)
                Text("contains").tag(Criteria.Operator.contains)
                Text("doesn't contain").tag(Criteria.Operator.notContains)
            }
            .labelsHidden()
            .frame(width: 130)
        case .regex:
            Picker("", selection: $item.op) {
                Text("matches").tag(Criteria.Operator.matches)
            }
            .labelsHidden()
            .frame(width: 90)
        }
    }

    // MARK: - Value

    @ViewBuilder
    private var valueEditor: some View {
        switch item.field {
        case .sourceApp:
            sourceAppPicker
        case .domain:
            TextField("e.g. example.com", text: $item.value)
                .textFieldStyle(.roundedBorder)
        case .regex:
            TextField("e.g. ^https://.*\\.example\\.com", text: $item.value)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }

    // MARK: - Source App Picker

    @ViewBuilder
    private var sourceAppPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !item.value.isEmpty,
               let app = browserManager.installedApps.first(where: { $0.id == item.value }) {
                HStack(spacing: 6) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(app.displayName)
                        .font(.callout)
                    Text(app.id)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer()
                    Button(action: { item.value = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Clear selection")
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                )
            }

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                TextField("Search apps...", text: $appSearchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            if !appSearchText.isEmpty {
                let filtered = filteredApps
                if filtered.isEmpty {
                    Text("No apps found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(filtered.prefix(30))) { app in
                                AppSearchRow(app: app, isSelected: app.id == item.value) {
                                    item.value = app.id
                                    appSearchText = ""
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
            }
        }
    }

    private var filteredApps: [InstalledApp] {
        guard !appSearchText.isEmpty else { return browserManager.installedApps }
        let query = appSearchText.lowercased()
        return browserManager.installedApps.filter {
            $0.displayName.lowercased().contains(query) || $0.id.lowercased().contains(query)
        }
    }
}

// MARK: - Criteria editing state

private struct CriteriaState: Identifiable {
    let id: UUID
    var field: Criteria.Field
    var op: Criteria.Operator
    var value: String

    init(id: UUID = UUID(), field: Criteria.Field = .domain, op: Criteria.Operator = .contains, value: String = "") {
        self.id = id
        self.field = field
        self.op = op
        self.value = value
    }

    init(from model: Criteria) {
        self.id = model.id
        self.field = model.field
        self.op = model.op
        self.value = model.value
    }

    func toModel() -> Criteria {
        Criteria(field: field, op: op, value: value.trimmingCharacters(in: .whitespaces))
    }
}

// MARK: - App search result row

private struct AppSearchRow: View {
    let app: InstalledApp
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(app.displayName)
                    .font(.callout)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
