import Foundation
import SwiftData

// MARK: - Summary helpers for UI display

extension RuleModel {
    var conditionsSummary: String {
        let crits = rootSet.criteria
        guard !crits.isEmpty else { return "No conditions" }

        let prefix: String
        switch rootSet.logic {
        case .all:  prefix = crits.count > 1 ? "If all: " : "If "
        case .any:  prefix = crits.count > 1 ? "If any: " : "If "
        case .none: prefix = crits.count > 1 ? "If none: " : "If not: "
        }

        return prefix + crits.map(\.summary).joined(separator: ", ")
    }

    var actionSummary: (text: String, browserBundleID: String?) {
        switch action {
        case .showPicker:
            return ("Show browser picker", nil)
        case .useDefault:
            return ("Use default browser", nil)
        case .openInApp(let bundleID):
            return ("Open in browser", bundleID)
        }
    }
}

extension Criteria {
    var summary: String {
        let fieldLabel: String
        switch field {
        case .sourceApp: fieldLabel = "source app"
        case .domain:    fieldLabel = "domain"
        case .regex:     fieldLabel = "URL"
        }

        let opLabel: String
        switch op {
        case .equals:      opLabel = "is"
        case .notEquals:   opLabel = "is not"
        case .contains:    opLabel = "contains"
        case .notContains: opLabel = "doesn't contain"
        case .matches:     opLabel = "matches"
        }

        let displayValue = value.isEmpty ? "(empty)" : value
        return "\(fieldLabel) \(opLabel) \(displayValue)"
    }
}

// The action the rule will perform
enum RuleAction: Codable, Sendable, Equatable, Hashable {
    case openInApp(bundleID: String)
    case showPicker
    case useDefault
}

@Model
final class RuleModel: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var isEnabled: Bool
    var order: Int
    var action: RuleAction
    var rootSet: ConditionSet

    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, order: Int = 0, action: RuleAction, rootSet: ConditionSet) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.order = order
        self.action = action
        self.rootSet = rootSet
    }
}

@Model
final class ConditionSet: Identifiable {
    enum Logic: String, Codable, Sendable, Equatable { case all, any, none }
    @Attribute(.unique) var id: UUID
    var logic: Logic
    var criteria: [Criteria]
    var subgroups: [ConditionSet]

    init(id: UUID = UUID(), logic: Logic, criteria: [Criteria] = [], subgroups: [ConditionSet] = []) {
        self.id = id
        self.logic = logic
        self.criteria = criteria
        self.subgroups = subgroups
    }
}

@Model
final class Criteria: Identifiable {
    enum Field: String, Codable, Sendable, Equatable { case sourceApp, domain, regex }
    enum Operator: String, Codable, Sendable, Equatable { case equals, notEquals, contains, notContains, matches }
    @Attribute(.unique) var id: UUID
    var field: Field
    var op: Operator
    var value: String

    init(id: UUID = UUID(), field: Field, op: Operator, value: String) {
        self.id = id
        self.field = field
        self.op = op
        self.value = value
    }
}

