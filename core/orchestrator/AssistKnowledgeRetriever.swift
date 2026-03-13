import Foundation

public struct AssistKnowledgeRetriever {
    public let maxResults: Int

    public init(maxResults: Int = 5) {
        self.maxResults = max(1, maxResults)
    }

    public func retrieve(input: AssistPredictionInput) -> AssistKnowledgeRetrievalResult {
        let candidates = buildCandidates(from: input)
        guard !candidates.isEmpty else {
            return AssistKnowledgeRetrievalResult(matches: [])
        }

        let frequencyBySignature = Dictionary(grouping: candidates, by: \.stepSignature)
            .mapValues(\.count)
        let maxFrequency = max(1, frequencyBySignature.values.max() ?? 1)

        let matches = candidates
            .map { candidate -> RankedCandidate in
                let preferenceCount = frequencyBySignature[candidate.stepSignature] ?? 1
                let signals = buildSignals(for: candidate, input: input, preferenceCount: preferenceCount, maxFrequency: maxFrequency)
                let score = combinedScore(for: signals)
                let evidence = AssistPredictionEvidence(
                    knowledgeItemId: candidate.item.knowledgeItemId,
                    taskId: candidate.item.taskId,
                    sessionId: candidate.item.sessionId,
                    stepId: candidate.step.stepId,
                    stepInstruction: candidate.step.instruction,
                    targetDescription: candidate.targetDescription,
                    score: rounded(score),
                    matchedSignals: signals.sorted { lhs, rhs in
                        if lhs.score == rhs.score {
                            return lhs.type.rawValue < rhs.type.rawValue
                        }
                        return lhs.score > rhs.score
                    },
                    reason: buildEvidenceReason(
                        candidate: candidate,
                        signals: signals,
                        preferenceCount: preferenceCount
                    )
                )
                return RankedCandidate(
                    evidence: evidence,
                    createdAt: candidate.item.createdAt,
                    stepSignature: candidate.stepSignature
                )
            }
            .sorted { lhs, rhs in
                if lhs.evidence.score == rhs.evidence.score {
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.evidence.knowledgeItemId < rhs.evidence.knowledgeItemId
                    }
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.evidence.score > rhs.evidence.score
            }

        return AssistKnowledgeRetrievalResult(matches: Array(matches.prefix(maxResults).map(\.evidence)))
    }

    private func buildCandidates(from input: AssistPredictionInput) -> [Candidate] {
        input.knowledgeItems.compactMap { item in
            guard input.completedStepCount < item.steps.count else {
                return nil
            }
            let step = item.steps[input.completedStepCount]
            return Candidate(
                item: item,
                step: step,
                stepIndex: input.completedStepCount,
                targetDescription: preferredTargetDescription(for: step),
                stepSignature: stepSignature(for: step)
            )
        }
    }

    private func buildSignals(
        for candidate: Candidate,
        input: AssistPredictionInput,
        preferenceCount: Int,
        maxFrequency: Int
    ) -> [AssistPredictionSignalMatch] {
        var signals: [AssistPredictionSignalMatch] = []

        let normalizedAppBundle = normalized(input.currentAppBundleId)
        let normalizedAppName = normalized(input.currentAppName)
        let itemAppBundle = normalized(candidate.item.context.appBundleId)
        let itemAppName = normalized(candidate.item.context.appName)

        if !normalizedAppBundle.isEmpty, normalizedAppBundle == itemAppBundle {
            signals.append(AssistPredictionSignalMatch(
                type: .app,
                score: 1.0,
                detail: "前台应用匹配 \(candidate.item.context.appName)"
            ))
        } else if !normalizedAppName.isEmpty, normalizedAppName == itemAppName {
            signals.append(AssistPredictionSignalMatch(
                type: .app,
                score: 0.7,
                detail: "应用名匹配 \(candidate.item.context.appName)"
            ))
        }

        let windowScore = windowMatchScore(
            currentWindowTitle: input.currentWindowTitle,
            itemWindowTitle: candidate.item.context.windowTitle
        )
        if windowScore > 0 {
            let title = candidate.item.context.windowTitle ?? "未知窗口"
            signals.append(AssistPredictionSignalMatch(
                type: .window,
                score: rounded(windowScore),
                detail: "窗口上下文匹配 \(title)"
            ))
        }

        let recentScore = recentSequenceScore(
            recentInstructions: input.recentStepInstructions,
            candidate: candidate
        )
        if recentScore > 0 {
            signals.append(AssistPredictionSignalMatch(
                type: .recentSequence,
                score: rounded(recentScore),
                detail: "最近步骤序列与历史前缀匹配"
            ))
        }

        let goalScore = goalMatchScore(currentGoal: input.currentTaskGoal, itemGoal: candidate.item.goal)
        if goalScore > 0 {
            signals.append(AssistPredictionSignalMatch(
                type: .goal,
                score: rounded(goalScore),
                detail: "当前任务目标接近历史目标"
            ))
        }

        let preferenceScore = historicalPreferenceScore(preferenceCount: preferenceCount, maxFrequency: maxFrequency)
        if preferenceScore > 0 {
            signals.append(AssistPredictionSignalMatch(
                type: .historicalPreference,
                score: rounded(preferenceScore),
                detail: "老师历史上有 \(preferenceCount) 条相似知识在此处选择同一步"
            ))
        }

        return signals
    }

    private func combinedScore(for signals: [AssistPredictionSignalMatch]) -> Double {
        let app = signals.first(where: { $0.type == .app })?.score ?? 0
        let window = signals.first(where: { $0.type == .window })?.score ?? 0
        let recent = signals.first(where: { $0.type == .recentSequence })?.score ?? 0
        let goal = signals.first(where: { $0.type == .goal })?.score ?? 0
        let preference = signals.first(where: { $0.type == .historicalPreference })?.score ?? 0

        let score = (app * 0.34) + (window * 0.24) + (recent * 0.18) + (goal * 0.16) + (preference * 0.08)
        return min(0.98, score)
    }

    private func buildEvidenceReason(
        candidate: Candidate,
        signals: [AssistPredictionSignalMatch],
        preferenceCount: Int
    ) -> String {
        let target = candidate.targetDescription ?? conciseInstruction(candidate.step.instruction)
        let signalTypes = Set(signals.map(\.type))
        var segments: [String] = []

        if signalTypes.contains(.window), let windowTitle = candidate.item.context.windowTitle, !windowTitle.isEmpty {
            segments.append("窗口“\(windowTitle)”匹配")
        } else if signalTypes.contains(.app) {
            segments.append("应用 \(candidate.item.context.appName) 匹配")
        }

        if signalTypes.contains(.recentSequence) {
            segments.append("最近动作序列匹配")
        }

        if signalTypes.contains(.goal) {
            segments.append("目标接近")
        }

        if signalTypes.contains(.historicalPreference), preferenceCount > 1 {
            segments.append("历史上有 \(preferenceCount) 次相同步骤偏好")
        }

        if segments.isEmpty {
            return "历史知识建议下一步执行「\(target)」。"
        }

        return "\(segments.joined(separator: "，"))，因此推荐执行「\(target)」。"
    }

    private func windowMatchScore(currentWindowTitle: String?, itemWindowTitle: String?) -> Double {
        let lhs = normalized(currentWindowTitle)
        let rhs = normalized(itemWindowTitle)
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return 0
        }
        if lhs == rhs {
            return 1.0
        }
        if lhs.contains(rhs) || rhs.contains(lhs) {
            return 0.82
        }
        return max(0, bigramSimilarity(lhs, rhs) - 0.2)
    }

    private func goalMatchScore(currentGoal: String?, itemGoal: String) -> Double {
        let lhs = normalized(currentGoal)
        let rhs = normalized(itemGoal)
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return 0
        }
        if lhs == rhs {
            return 1.0
        }
        if lhs.contains(rhs) || rhs.contains(lhs) {
            return 0.88
        }
        return max(0, bigramSimilarity(lhs, rhs) - 0.1)
    }

    private func recentSequenceScore(recentInstructions: [String], candidate: Candidate) -> Double {
        let recent = recentInstructions.map(normalized).filter { !$0.isEmpty }
        guard !recent.isEmpty, candidate.stepIndex > 0 else {
            return 0
        }

        let history = candidate.item.steps[..<candidate.stepIndex]
            .map(\.instruction)
            .map(normalized)
            .filter { !$0.isEmpty }
        guard !history.isEmpty else {
            return 0
        }

        let comparableHistory = Array(history.suffix(recent.count))
        let pairs = zip(recent.suffix(comparableHistory.count), comparableHistory)
        let matchedCount = pairs.reduce(into: 0) { count, pair in
            if pair.0 == pair.1 || bigramSimilarity(pair.0, pair.1) >= 0.76 {
                count += 1
            }
        }
        guard matchedCount > 0 else {
            return 0
        }
        return Double(matchedCount) / Double(recent.count)
    }

    private func historicalPreferenceScore(preferenceCount: Int, maxFrequency: Int) -> Double {
        guard preferenceCount > 1, maxFrequency > 1 else {
            return 0
        }
        return Double(preferenceCount - 1) / Double(maxFrequency - 1)
    }

    private func stepSignature(for step: KnowledgeStep) -> String {
        let target = preferredTargetDescription(for: step) ?? step.instruction
        return normalized(target)
    }

    private func preferredTargetDescription(for step: KnowledgeStep) -> String? {
        guard let target = step.target else {
            return nil
        }

        let preferredLocator = target.preferredLocatorType
        let semanticTarget = target.semanticTargets.first { semantic in
            guard let preferredLocator else {
                return !semantic.summaryText.isEmpty
            }
            return semantic.locatorType == preferredLocator && !semantic.summaryText.isEmpty
        } ?? target.semanticTargets.first { !$0.summaryText.isEmpty }

        if let semanticTarget, !semanticTarget.summaryText.isEmpty {
            return semanticTarget.summaryText
        }

        if let coordinate = target.coordinate {
            return "坐标 (\(Int(coordinate.x)), \(Int(coordinate.y)))"
        }

        return nil
    }

    private func conciseInstruction(_ instruction: String) -> String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 48 else {
            return trimmed
        }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 48)
        return "\(trimmed[..<index])..."
    }

    private func normalized(_ value: String?) -> String {
        guard let value else {
            return ""
        }
        let lowered = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else {
            return ""
        }

        let filteredScalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }

        return String(filteredScalars)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func bigramSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsBigrams = bigrams(for: lhs)
        let rhsBigrams = bigrams(for: rhs)

        guard !lhsBigrams.isEmpty, !rhsBigrams.isEmpty else {
            return lhs == rhs && !lhs.isEmpty ? 1.0 : 0
        }

        let lhsSet = Set(lhsBigrams)
        let rhsSet = Set(rhsBigrams)
        let intersectionCount = lhsSet.intersection(rhsSet).count
        let unionCount = lhsSet.union(rhsSet).count
        guard unionCount > 0 else {
            return 0
        }
        return Double(intersectionCount) / Double(unionCount)
    }

    private func bigrams(for value: String) -> [String] {
        let characters = Array(value)
        guard characters.count > 1 else {
            return value.isEmpty ? [] : [value]
        }
        return (0..<(characters.count - 1)).map { index in
            String(characters[index...index + 1])
        }
    }

    private func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }
}

private struct Candidate {
    let item: KnowledgeItem
    let step: KnowledgeStep
    let stepIndex: Int
    let targetDescription: String?
    let stepSignature: String
}

private struct RankedCandidate {
    let evidence: AssistPredictionEvidence
    let createdAt: String
    let stepSignature: String
}

private extension SemanticTarget {
    var summaryText: String {
        if let elementTitle, !elementTitle.isEmpty {
            return elementTitle
        }
        if let elementIdentifier, !elementIdentifier.isEmpty {
            return elementIdentifier
        }
        if let axPath, !axPath.isEmpty {
            return axPath
        }
        return elementRole ?? locatorType.rawValue
    }
}
