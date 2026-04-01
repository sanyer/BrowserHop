import Foundation

actor RuleEngine {
    private var rules: [RuleModel] = []
    
    init() {}
    
    func setRules(_ newRules: [RuleModel]) async {
        self.rules = newRules.filter { $0.isEnabled }
    }
    
    func evaluate(url: URL, sourceApp: String?) async -> RuleAction? {
        for rule in rules {
            if await Self.evaluate(set: rule.rootSet, url: url, sourceApp: sourceApp) {
                return rule.action
            }
        }
        return nil
    }
    
    private static func evaluate(set: ConditionSet, url: URL, sourceApp: String?) async -> Bool {
        let criteriaResults = set.criteria.map { Self.evaluate(criterion: $0, url: url, sourceApp: sourceApp) }
        let subgroupResults = await withTaskGroup(of: Bool.self) { group in
            for subgroup in set.subgroups {
                group.addTask { await Self.evaluate(set: subgroup, url: url, sourceApp: sourceApp) }
            }
            return await group.reduce(into: [Bool]()) { $0.append($1) }
        }
        let results = criteriaResults + subgroupResults
        // Empty condition sets match everything for `.all` (vacuous truth),
        // but should NOT match for `.any` or `.none` (no evidence to match).
        if results.isEmpty {
            return set.logic == .all
        }
        switch set.logic {
        case .all: return results.allSatisfy { $0 }
        case .any: return results.contains(true)
        case .none: return results.allSatisfy { !$0 }
        }
    }
    
    private static func evaluate(criterion: Criteria, url: URL, sourceApp: String?) -> Bool {
        switch criterion.field {
        case .sourceApp:
            guard let source = sourceApp else { return false }
            return Self.match(value: source, pattern: criterion.value, op: criterion.op)
        case .domain:
            guard let host = url.host else { return false }
            return Self.match(value: host, pattern: criterion.value, op: criterion.op)
        case .regex:
            return Self.match(value: url.absoluteString, pattern: criterion.value, op: .matches)
        }
    }
    
    private static func match(value: String, pattern: String, op: Criteria.Operator) -> Bool {
        switch op {
        case .equals:
            return value.caseInsensitiveCompare(pattern) == .orderedSame
        case .notEquals:
            return value.caseInsensitiveCompare(pattern) != .orderedSame
        case .contains:
            return value.localizedCaseInsensitiveContains(pattern)
        case .notContains:
            return !value.localizedCaseInsensitiveContains(pattern)
        case .matches:
            return (try? NSRegularExpression(pattern: pattern)).map { regex in
                let range = NSRange(value.startIndex..<value.endIndex, in: value)
                return regex.firstMatch(in: value, options: [], range: range) != nil
            } ?? false
        }
    }
}
