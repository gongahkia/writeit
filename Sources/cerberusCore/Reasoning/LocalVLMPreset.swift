import Foundation

public struct LocalVLMPreset: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable {
        case recommended
        case fallback
        case verifyBeforeUse
        case experimental
        case baselineOnly
    }

    public let id: String
    public let displayName: String
    public let licenseNote: String
    public let status: Status
    public let safetyNote: String
    public let runtimeNotes: [String]
    public let recommendedMaxTokens: Int
    public let recommendedTimeoutSeconds: Double

    public init(
        id: String,
        displayName: String,
        licenseNote: String,
        status: Status,
        safetyNote: String,
        runtimeNotes: [String],
        recommendedMaxTokens: Int = 256,
        recommendedTimeoutSeconds: Double = 45
    ) {
        self.id = id
        self.displayName = displayName
        self.licenseNote = licenseNote
        self.status = status
        self.safetyNote = safetyNote
        self.runtimeNotes = runtimeNotes
        self.recommendedMaxTokens = max(1, recommendedMaxTokens)
        self.recommendedTimeoutSeconds = max(1, recommendedTimeoutSeconds)
    }

    public static let miniCPMV46 = LocalVLMPreset(
        id: "minicpm-v-4.6",
        displayName: "MiniCPM-V 4.6",
        licenseNote: "Apache-2.0; checked 2026-07-08 at https://huggingface.co/openbmb/MiniCPM-V-4.6.",
        status: .recommended,
        safetyNote: "Use for passive screen VQA only.",
        runtimeNotes: [
            "Config-only preset; no weights bundled.",
            "OpenBMB reports vLLM, SGLang, llama.cpp, and Ollama support; verify selected runtime locally.",
            "Use Fixtures/VLM/benchmark-template.json before recommending."
        ]
    )

    public static let qwen3VL = LocalVLMPreset(
        id: "qwen3-vl",
        displayName: "Qwen3-VL",
        licenseNote: "Apache-2.0; checked 2026-07-08 at https://github.com/QwenLM/Qwen3-VL.",
        status: .recommended,
        safetyNote: "GUI-agent capabilities must stay disabled; passive VQA only.",
        runtimeNotes: [
            "Supported sizes checked: 2B, 4B, 8B, 30B-A3B, 32B, and 235B-A22B.",
            "Upstream documents visual-agent capabilities; Cerberus must wrap prompts as observe-only.",
            "Expect heavier local latency than MiniCPM-V 4.6."
        ]
    )

    public static let qwen25VL = LocalVLMPreset(
        id: "qwen2.5-vl",
        displayName: "Qwen2.5-VL",
        licenseNote: "Apache-2.0 for 7B Instruct; checked 2026-07-08 at https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct.",
        status: .fallback,
        safetyNote: "Use for OCR/document/layout screen questions only.",
        runtimeNotes: [
            "Config-only preset; no weights bundled.",
            "Practical variants checked: 3B edge model and 7B Instruct; verify exact checkpoint before use.",
            "Expected strengths: OCR, documents, charts, layout, and UI screenshots."
        ]
    )

    public static let smolVLM = LocalVLMPreset(
        id: "smolvlm",
        displayName: "SmolVLM",
        licenseNote: "Apache-2.0; checked 2026-07-08 at https://huggingface.co/blog/smolvlm.",
        status: .fallback,
        safetyNote: "Use for low-resource passive screen questions.",
        runtimeNotes: [
            "Config-only preset; no weights bundled.",
            "Low-resource fallback for users who cannot run MiniCPM, Qwen, or InternVL.",
            "Expect weaker OCR/layout/chart quality than larger VLMs."
        ],
        recommendedMaxTokens: 128,
        recommendedTimeoutSeconds: 30
    )

    public static let gemma4 = LocalVLMPreset(
        id: "gemma-4",
        displayName: "Gemma 4",
        licenseNote: "Apache-2.0 for google/gemma-4-E2B-it; checked 2026-07-08 at https://huggingface.co/google/gemma-4-E2B-it and https://ai.google.dev/gemma/docs/core/model_card_4.",
        status: .fallback,
        safetyNote: "Use for passive screen VQA only; verify downstream conversion terms before redistribution.",
        runtimeNotes: [
            "Config-only preset; no weights bundled.",
            "Local runtime checked: MLX-VLM with mlx-community/gemma-4-e2b-it-4bit on Apple Silicon.",
            "Google MLX docs expose a localhost OpenAI-compatible server at http://localhost:8080/v1."
        ]
    )

    public static let internVL35 = LocalVLMPreset(
        id: "internvl3.5",
        displayName: "InternVL3.5",
        licenseNote: "Apache-2.0 for 1B/2B/4B/8B checkpoints; checked 2026-07-08 at https://huggingface.co/OpenGVLab/InternVL3_5-1B.",
        status: .fallback,
        safetyNote: "GUI and embodied-agent capabilities must stay disabled; passive VQA only.",
        runtimeNotes: [
            "Config-only preset; no weights bundled.",
            "Selected variants: OpenGVLab/InternVL3_5-1B, 2B, 4B, and 8B.",
            "[Inference] Start local Mac evaluation with 1B or 2B; treat 4B and 8B as GPU or quantized-runtime targets."
        ]
    )

    public static let fastVLM = LocalVLMPreset(
        id: "fastvlm",
        displayName: "Apple FastVLM",
        licenseNote: "Research/demo path; verify model and code terms before use.",
        status: .experimental,
        safetyNote: "Experimental MLX/Core ML direction only.",
        runtimeNotes: ["Useful Apple Silicon architecture reference.", "Do not default-enable."]
    )

    public static let pixtral12B = LocalVLMPreset(
        id: "pixtral-12b",
        displayName: "Pixtral 12B",
        licenseNote: "Apache-2.0 but deprecated by Mistral.",
        status: .baselineOnly,
        safetyNote: "Do not recommend except as a comparison baseline.",
        runtimeNotes: ["Deprecated baseline only."]
    )

    public static let all: [LocalVLMPreset] = [
        miniCPMV46,
        qwen3VL,
        qwen25VL,
        smolVLM,
        gemma4,
        internVL35,
        fastVLM,
        pixtral12B
    ]

    public static func preset(id: String) -> LocalVLMPreset? {
        all.first { $0.id == id }
    }
}
