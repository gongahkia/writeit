import Foundation

public enum LocalVLMPromptPolicy {
    public static let passiveScreenDescription = "passive-screen-description"

    public static func passivePrompt(for prompt: String) -> String {
        """
        Passive screen description only.
        Observe the supplied screenshot and answer the user's visual question.
        Do not click, type, navigate, operate apps, invoke tools, plan GUI actions, or provide step-by-step computer-control instructions.
        If the user asks for GUI-agent behavior, refuse that action briefly and provide only an observe-only description of relevant visible UI.

        User question:
        \(prompt)
        """
    }
}
