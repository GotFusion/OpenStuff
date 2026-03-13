import Foundation

public struct RetrievalBasedAssistPredictor: AssistNextActionPredicting {
    public let retriever: AssistKnowledgeRetriever
    public let minimumScore: Double
    public let evidenceLimit: Int

    public init(
        retriever: AssistKnowledgeRetriever = AssistKnowledgeRetriever(),
        minimumScore: Double = 0.18,
        evidenceLimit: Int = 3
    ) {
        self.retriever = retriever
        self.minimumScore = minimumScore
        self.evidenceLimit = max(1, evidenceLimit)
    }

    public func predict(input: AssistPredictionInput) -> AssistSuggestion? {
        let retrieval = retriever.retrieve(input: input)
        guard let primary = retrieval.matches.first, primary.score >= minimumScore else {
            return nil
        }

        let selectedEvidence = selectEvidence(from: retrieval.matches, primary: primary)
        let action = AssistSuggestedAction(
            type: inferActionType(from: primary.stepInstruction),
            instruction: primary.stepInstruction,
            reason: buildReason(
                primary: primary,
                evidence: selectedEvidence,
                input: input
            )
        )

        return AssistSuggestion(
            suggestionId: "assist-\(primary.taskId)-\(primary.stepId)",
            knowledgeItemId: primary.knowledgeItemId,
            taskId: primary.taskId,
            stepId: primary.stepId,
            action: action,
            confidence: primary.score,
            evidence: selectedEvidence,
            predictorVersion: AssistPredictionStrategy.retrievalV1.rawValue
        )
    }

    private func selectEvidence(
        from matches: [AssistPredictionEvidence],
        primary: AssistPredictionEvidence
    ) -> [AssistPredictionEvidence] {
        let primaryKey = normalized(primary.targetDescription ?? primary.stepInstruction)
        let grouped = matches.filter { candidate in
            normalized(candidate.targetDescription ?? candidate.stepInstruction) == primaryKey
        }
        let source = grouped.isEmpty ? [primary] : grouped
        return Array(source.prefix(evidenceLimit))
    }

    private func buildReason(
        primary: AssistPredictionEvidence,
        evidence: [AssistPredictionEvidence],
        input: AssistPredictionInput
    ) -> String {
        let target = primary.targetDescription ?? conciseInstruction(primary.stepInstruction)
        let historyCount = evidence.count

        let environment: String
        if let windowTitle = input.currentWindowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !windowTitle.isEmpty {
            environment = "在“\(windowTitle)”窗口里"
        } else if let appName = input.currentAppName?.trimmingCharacters(in: .whitespacesAndNewlines), !appName.isEmpty {
            environment = "在 \(appName) 中"
        } else {
            environment = "在类似场景下"
        }

        let sequenceHint = input.recentStepInstructions.isEmpty ? "" : "完成类似前序步骤后"
        let prefix = sequenceHint.isEmpty ? "过去你\(environment)通常会" : "过去你\(environment)\(sequenceHint)通常会"

        if historyCount > 1 {
            return "\(prefix)执行「\(target)」，参考了 \(historyCount) 条历史知识。"
        }

        return "\(prefix)执行「\(target)」，来源知识 \(primary.knowledgeItemId)。"
    }

    private func inferActionType(from instruction: String) -> AssistActionType {
        if instruction.contains("点击") {
            return .click
        }
        if instruction.contains("输入") {
            return .input
        }
        if instruction.contains("快捷键") {
            return .shortcut
        }
        return .generic
    }

    private func conciseInstruction(_ instruction: String) -> String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 48 else {
            return trimmed
        }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 48)
        return "\(trimmed[..<index])..."
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
