import Foundation

enum RegexReplacementExecutionError: LocalizedError, Equatable {
  case workerUnavailable
  case timedOut
  case workerFailed
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .workerUnavailable: "Regular-expression processing is unavailable."
    case .timedOut: "Regular-expression processing exceeded the time limit."
    case .workerFailed: "Regular-expression processing failed."
    case .invalidResponse: "Regular-expression processing returned an invalid result."
    }
  }
}

@MainActor
protocol RegexReplacementApplying: AnyObject {
  func apply(_ rules: RegexReplacementRules, to text: String) async throws -> String
}

struct RegexReplacementWorkerRequest: Codable, Sendable {
  let rules: RegexReplacementRules
  let text: String
}

struct RegexReplacementWorkerResponse: Codable, Sendable {
  let text: String?
  let error: String?
}

enum RegexReplacementWorker {
  static let argument = "--regex-replacement-worker"

  static func run() {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let response: RegexReplacementWorkerResponse
    do {
      let request = try JSONDecoder().decode(RegexReplacementWorkerRequest.self, from: input)
      response = .init(text: try apply(request.rules, to: request.text), error: nil)
    } catch {
      response = .init(text: nil, error: "Regular-expression processing failed.")
    }
    guard let data = try? JSONEncoder().encode(response) else { return }
    try? FileHandle.standardOutput.write(contentsOf: data)
  }

  static func apply(_ rules: RegexReplacementRules, to text: String) throws -> String {
    try rules.rules.reduce(text) { partial, rule in
      let regex = try NSRegularExpression(pattern: rule.pattern)
      return regex.stringByReplacingMatches(
        in: partial,
        range: NSRange(location: 0, length: (partial as NSString).length),
        withTemplate: rule.replacement
      )
    }
  }
}

@MainActor
protocol RegexReplacementWorkerRunning: AnyObject {
  func run(input: Data, timeout: Duration) async throws -> Data
}

@MainActor
final class RegexReplacementService: RegexReplacementApplying {
  static let executionTimeout: Duration = .milliseconds(500)

  private let runner: any RegexReplacementWorkerRunning

  init(runner: (any RegexReplacementWorkerRunning)? = nil) {
    self.runner = runner ?? ProcessRegexReplacementWorkerRunner()
  }

  func apply(_ rules: RegexReplacementRules, to text: String) async throws -> String {
    guard rules.rules.isEmpty == false else { return text }
    let input = try JSONEncoder().encode(RegexReplacementWorkerRequest(rules: rules, text: text))
    let output = try await runner.run(input: input, timeout: Self.executionTimeout)
    let response = try JSONDecoder().decode(RegexReplacementWorkerResponse.self, from: output)
    if response.error != nil { throw RegexReplacementExecutionError.workerFailed }
    guard let text = response.text else { throw RegexReplacementExecutionError.invalidResponse }
    return text
  }
}

@MainActor
final class ProcessRegexReplacementWorkerRunner: RegexReplacementWorkerRunning {
  private let executableURL: URL?
  private let arguments: [String]

  init(
    executableURL: URL? = Bundle.main.executableURL,
    arguments: [String] = [RegexReplacementWorker.argument]
  ) {
    self.executableURL = executableURL
    self.arguments = arguments
  }

  func run(input: Data, timeout: Duration) async throws -> Data {
    guard let executableURL else { throw RegexReplacementExecutionError.workerUnavailable }
    let run = RegexReplacementWorkerProcess(
      executableURL: executableURL,
      arguments: arguments,
      timeout: timeout
    )
    return try await run.run(input: input)
  }
}

@MainActor
private final class RegexReplacementWorkerProcess {
  private let process = Process()
  private let input = Pipe()
  private let output = Pipe()
  private let executableURL: URL
  private let arguments: [String]
  private let timeout: Duration
  private var continuation: CheckedContinuation<Data, Error>?
  private var timeoutTask: Task<Void, Never>?

  init(executableURL: URL, arguments: [String], timeout: Duration) {
    self.executableURL = executableURL
    self.arguments = arguments
    self.timeout = timeout
  }

  func run(input data: Data) async throws -> Data {
    try Task.checkCancellation()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        do {
          try start(input: data)
        } catch {
          finish(throwing: error)
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancel() }
    }
  }

  private func start(input data: Data) throws {
    process.executableURL = executableURL
    process.arguments = arguments
    process.standardInput = input
    process.standardOutput = output
    let outputHandle = output.fileHandleForReading
    process.terminationHandler = { [weak self, outputHandle] process in
      let data = outputHandle.readDataToEndOfFile()
      let status = process.terminationStatus
      Task { @MainActor [weak self] in self?.finished(data: data, status: status) }
    }
    try process.run()
    try input.fileHandleForWriting.write(contentsOf: data)
    try input.fileHandleForWriting.close()
    let timeout = self.timeout
    timeoutTask = Task { [weak self, timeout] in
      do {
        try await Task.sleep(for: timeout)
      } catch {
        return
      }
      self?.timeoutElapsed()
    }
  }

  private func timeoutElapsed() {
    guard continuation != nil else { return }
    if process.isRunning { process.terminate() }
    finish(throwing: RegexReplacementExecutionError.timedOut)
  }

  private func cancel() {
    guard continuation != nil else { return }
    if process.isRunning { process.terminate() }
    finish(throwing: CancellationError())
  }

  private func finished(data: Data, status: Int32) {
    guard continuation != nil else { return }
    guard status == 0 else {
      finish(throwing: RegexReplacementExecutionError.workerFailed)
      return
    }
    timeoutTask?.cancel()
    timeoutTask = nil
    continuation?.resume(returning: data)
    continuation = nil
  }

  private func finish(throwing error: Error) {
    timeoutTask?.cancel()
    timeoutTask = nil
    continuation?.resume(throwing: error)
    continuation = nil
  }
}
