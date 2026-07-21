import Flutter
import Foundation

private let modelDownloadChannelName = "pov_agent/model_downloads"
private let modelDownloadProgressChannelName = "pov_agent/model_download_progress"

/// Process-independent description stored on every background URLSession task.
struct BackgroundModelTransferDescriptor: Codable, Equatable {
  let transferId: String
  let sourceUrl: String
  let destinationPath: String
  let expectedBytes: Int64

  init(arguments: [String: Any]) throws {
    guard
      let transferId = arguments["transferId"] as? String,
      transferId.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
      let sourceUrl = arguments["sourceUrl"] as? String,
      let url = URL(string: sourceUrl),
      let scheme = url.scheme,
      scheme == "https" || scheme == "http",
      let destinationPath = arguments["destinationPath"] as? String,
      destinationPath.hasPrefix("/"),
      let expectedBytes = (arguments["expectedBytes"] as? NSNumber)?.int64Value,
      expectedBytes > 0
    else {
      throw BackgroundModelTransferFailure.invalidArguments(
        "download requires a valid transferId, HTTP URL, absolute destinationPath, and expectedBytes."
      )
    }
    self.transferId = transferId
    self.sourceUrl = sourceUrl
    self.destinationPath = destinationPath
    self.expectedBytes = expectedBytes
  }

  init(
    transferId: String,
    sourceUrl: String,
    destinationPath: String,
    expectedBytes: Int64
  ) {
    self.transferId = transferId
    self.sourceUrl = sourceUrl
    self.destinationPath = destinationPath
    self.expectedBytes = expectedBytes
  }

  func encodedTaskDescription() throws -> String {
    let data = try JSONEncoder().encode(self)
    guard let description = String(data: data, encoding: .utf8) else {
      throw BackgroundModelTransferFailure.invalidArguments(
        "The transfer descriptor could not be encoded."
      )
    }
    return description
  }

  static func decode(taskDescription: String?) -> BackgroundModelTransferDescriptor? {
    guard let taskDescription, let data = taskDescription.data(using: .utf8) else {
      return nil
    }
    return try? JSONDecoder().decode(Self.self, from: data)
  }
}

struct BackgroundModelTransferSnapshot {
  let transferId: String
  let receivedBytes: Int64
  let expectedBytes: Int64

  var platformPayload: [String: Any] {
    [
      "transferId": transferId,
      "receivedBytes": receivedBytes,
      "expectedBytes": expectedBytes,
    ]
  }
}

enum BackgroundModelTransferFailure: Error {
  case invalidArguments(String)
  case descriptorConflict
  case httpStatus(Int)
  case sizeMismatch(expected: Int64, actual: Int64)
  case io(String)
  case network(String)
  case cancelled
  case transport(String)
}

private struct BackgroundModelTransferRecord: Codable {
  enum Phase: String, Codable {
    case running
    case failed
    case completed
  }

  let descriptor: BackgroundModelTransferDescriptor
  var phase: Phase
  var receivedBytes: Int64
  var errorMessage: String?

  var snapshot: BackgroundModelTransferSnapshot {
    BackgroundModelTransferSnapshot(
      transferId: descriptor.transferId,
      receivedBytes: receivedBytes,
      expectedBytes: descriptor.expectedBytes
    )
  }
}

/// Owns persistent URLSession download tasks independently of the Flutter UI.
///
/// The task description is the primary identity across process recreation.
/// Minimal records preserve last-confirmed progress while URLSession is between
/// callbacks. Resume data lives in Application Support with backup exclusion;
/// verified model publication remains the Dart store's responsibility.
final class BackgroundModelDownloadCoordinator: NSObject, @unchecked Sendable {
  typealias TransferCompletion = (
    Result<BackgroundModelTransferSnapshot, BackgroundModelTransferFailure>
  ) -> Void

  static let shared = BackgroundModelDownloadCoordinator()

  static var sessionIdentifier: String {
    let bundleId = Bundle.main.bundleIdentifier ?? "pov-agent"
    return "\(bundleId).background-model-downloads"
  }

  private let stateQueue = DispatchQueue(
    label: "pov-agent.background-model-downloads.state"
  )
  private let sessionDelegateQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "pov-agent.background-model-downloads.delegate"
    queue.maxConcurrentOperationCount = 1
    return queue
  }()
  private let fileManager: FileManager

  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.background(
      withIdentifier: Self.sessionIdentifier
    )
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    configuration.waitsForConnectivity = true
    configuration.allowsCellularAccess = true
    configuration.httpMaximumConnectionsPerHost = 2
    return URLSession(
      configuration: configuration,
      delegate: self,
      delegateQueue: sessionDelegateQueue
    )
  }()

  private var records: [String: BackgroundModelTransferRecord]
  private var waiters: [String: [TransferCompletion]] = [:]
  private var cancellationWaiters: [
    String: [(Result<Void, BackgroundModelTransferFailure>) -> Void]
  ] = [:]
  private var cancellationTaskIds: [String: Set<Int>] = [:]
  private var pendingCancellationQueries: Set<String> = []
  private var cancellationRequested: Set<String> = []
  private var pendingStarts: Set<String> = []
  private var explicitlyCancelledTaskIds: Set<Int> = []
  private var terminalTaskIds: Set<Int> = []
  private var progressObserver: ((BackgroundModelTransferSnapshot) -> Void)?
  private var backgroundEventsCompletion: (() -> Void)?
  private var backgroundEventsFinished = false

  init(
    fileManager: FileManager = .default
  ) {
    self.fileManager = fileManager
    records = Self.loadRecords(fileManager: fileManager)
    super.init()
  }

  /// Reconnects the delegate to tasks restored by the operating system.
  func activate() {
    stateQueue.async {
      _ = self.session
      self.session.getAllTasks { tasks in
        self.stateQueue.async {
          self.reconcile(tasks: tasks)
        }
      }
    }
  }

  func handlesBackgroundSession(identifier: String) -> Bool {
    identifier == Self.sessionIdentifier
  }

  func setBackgroundEventsCompletion(_ completion: @escaping () -> Void) {
    stateQueue.async {
      if self.backgroundEventsFinished {
        self.backgroundEventsFinished = false
        self.deliverOnMain(completion)
        return
      }
      self.backgroundEventsCompletion = completion
    }
  }

  func setProgressObserver(
    _ observer: ((BackgroundModelTransferSnapshot) -> Void)?
  ) {
    stateQueue.async {
      self.progressObserver = observer
      guard let observer else { return }
      for record in self.records.values where record.phase == .running {
        self.deliverOnMain {
          observer(record.snapshot)
        }
      }
    }
  }

  /// Starts or reattaches to one task using its stable manifest identity.
  func start(
    descriptor: BackgroundModelTransferDescriptor,
    completion: @escaping TransferCompletion
  ) {
    stateQueue.async {
      self.waiters[descriptor.transferId, default: []].append(completion)
      if self.pendingStarts.contains(descriptor.transferId) { return }
      self.pendingStarts.insert(descriptor.transferId)
      self.session.getAllTasks { tasks in
        self.stateQueue.async {
          self.startOrAttach(descriptor: descriptor, tasks: tasks)
        }
      }
    }
  }

  /// Cancels active work and removes all unverified native transfer state.
  func cancel(
    transferId: String,
    completion: @escaping (Result<Void, BackgroundModelTransferFailure>) -> Void
  ) {
    stateQueue.async {
      self.cancellationWaiters[transferId, default: []].append(completion)
      self.cancellationRequested.insert(transferId)
      if self.pendingCancellationQueries.contains(transferId)
        || self.cancellationTaskIds[transferId] != nil
      {
        return
      }
      self.pendingCancellationQueries.insert(transferId)
      self.session.getAllTasks { tasks in
        self.stateQueue.async {
          self.pendingCancellationQueries.remove(transferId)
          let matchingTasks = tasks.filter {
            BackgroundModelTransferDescriptor.decode(
              taskDescription: $0.taskDescription
            )?.transferId == transferId
          }
          guard !matchingTasks.isEmpty else {
            if self.pendingStarts.contains(transferId) { return }
            self.finishCancellation(transferId: transferId)
            return
          }
          self.cancellationTaskIds[transferId] = Set(
            matchingTasks.map(\.taskIdentifier)
          )
          for task in matchingTasks {
            self.explicitlyCancelledTaskIds.insert(task.taskIdentifier)
            task.cancel()
          }
          self.pendingStarts.remove(transferId)
          self.removePersistentState(transferId: transferId)
        }
      }
    }
  }

  private func startOrAttach(
    descriptor: BackgroundModelTransferDescriptor,
    tasks: [URLSessionTask]
  ) {
    defer { pendingStarts.remove(descriptor.transferId) }

    if cancellationRequested.contains(descriptor.transferId) {
      if cancellationTaskIds[descriptor.transferId] == nil {
        finishCancellation(transferId: descriptor.transferId)
      }
      return
    }

    if let receivedBytes = completeDestinationBytes(for: descriptor) {
      let snapshot = BackgroundModelTransferSnapshot(
        transferId: descriptor.transferId,
        receivedBytes: receivedBytes,
        expectedBytes: descriptor.expectedBytes
      )
      persistCompleted(descriptor: descriptor)
      emit(snapshot)
      finishWaiters(
        transferId: descriptor.transferId,
        result: .success(snapshot)
      )
      return
    }

    let taskWithIdentity = tasks.first {
      BackgroundModelTransferDescriptor.decode(
        taskDescription: $0.taskDescription
      )?.transferId == descriptor.transferId
    }
    if let taskWithIdentity {
      guard
        let restored = BackgroundModelTransferDescriptor.decode(
          taskDescription: taskWithIdentity.taskDescription
        ),
        restored == descriptor
      else {
        finishWaiters(
          transferId: descriptor.transferId,
          result: .failure(.descriptorConflict)
        )
        return
      }
      if
        taskWithIdentity.state != .completed,
        taskWithIdentity.state != .canceling
      {
        let received = max(0, taskWithIdentity.countOfBytesReceived)
        persistRunning(descriptor: descriptor, receivedBytes: received)
        emit(
          BackgroundModelTransferSnapshot(
            transferId: descriptor.transferId,
            receivedBytes: received,
            expectedBytes: descriptor.expectedBytes
          )
        )
        taskWithIdentity.resume()
        return
      }
    }

    do {
      let task: URLSessionDownloadTask
      if let resumeData = try loadResumeData(transferId: descriptor.transferId) {
        task = session.downloadTask(withResumeData: resumeData)
        try? deleteResumeData(transferId: descriptor.transferId)
      } else {
        guard let source = URL(string: descriptor.sourceUrl) else {
          throw BackgroundModelTransferFailure.invalidArguments(
            "The model source URL is invalid."
          )
        }
        var request = URLRequest(url: source)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("pov-agent-model-store/1", forHTTPHeaderField: "User-Agent")
        task = session.downloadTask(with: request)
      }
      task.taskDescription = try descriptor.encodedTaskDescription()
      persistRunning(descriptor: descriptor, receivedBytes: 0)
      emit(
        BackgroundModelTransferSnapshot(
          transferId: descriptor.transferId,
          receivedBytes: 0,
          expectedBytes: descriptor.expectedBytes
        )
      )
      task.resume()
    } catch let failure as BackgroundModelTransferFailure {
      finishWaiters(
        transferId: descriptor.transferId,
        result: .failure(failure)
      )
    } catch {
      finishWaiters(
        transferId: descriptor.transferId,
        result: .failure(.io(error.localizedDescription))
      )
    }
  }

  private func reconcile(tasks: [URLSessionTask]) {
    for task in tasks {
      guard
        task.state != .completed,
        task.state != .canceling,
        let descriptor = BackgroundModelTransferDescriptor.decode(
          taskDescription: task.taskDescription
        )
      else { continue }
      let received = max(0, task.countOfBytesReceived)
      persistRunning(descriptor: descriptor, receivedBytes: received)
      emit(
        BackgroundModelTransferSnapshot(
          transferId: descriptor.transferId,
          receivedBytes: received,
          expectedBytes: descriptor.expectedBytes
        )
      )
      task.resume()
    }
  }

  private func publishDownloadedFile(
    task: URLSessionDownloadTask,
    location: URL,
    descriptor: BackgroundModelTransferDescriptor
  ) {
    if
      let response = task.response as? HTTPURLResponse,
      !(200...299).contains(response.statusCode)
    {
      terminalTaskIds.insert(task.taskIdentifier)
      removePersistentState(transferId: descriptor.transferId)
      finishWaiters(
        transferId: descriptor.transferId,
        result: .failure(.httpStatus(response.statusCode))
      )
      return
    }

    do {
      let attributes = try fileManager.attributesOfItem(atPath: location.path)
      let actualBytes = (attributes[.size] as? NSNumber)?.int64Value ?? -1
      guard actualBytes == descriptor.expectedBytes else {
        terminalTaskIds.insert(task.taskIdentifier)
        removePersistentState(transferId: descriptor.transferId)
        finishWaiters(
          transferId: descriptor.transferId,
          result: .failure(
            .sizeMismatch(
              expected: descriptor.expectedBytes,
              actual: actualBytes
            )
          )
        )
        return
      }

      let destination = URL(fileURLWithPath: descriptor.destinationPath)
      try fileManager.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.moveItem(at: location, to: destination)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var mutableDestination = destination
      try mutableDestination.setResourceValues(values)

      terminalTaskIds.insert(task.taskIdentifier)
      try? deleteResumeData(transferId: descriptor.transferId)
      persistCompleted(descriptor: descriptor)
      let snapshot = BackgroundModelTransferSnapshot(
        transferId: descriptor.transferId,
        receivedBytes: actualBytes,
        expectedBytes: descriptor.expectedBytes
      )
      emit(snapshot)
      finishWaiters(
        transferId: descriptor.transferId,
        result: .success(snapshot)
      )
    } catch {
      terminalTaskIds.insert(task.taskIdentifier)
      removePersistentState(transferId: descriptor.transferId)
      finishWaiters(
        transferId: descriptor.transferId,
        result: .failure(.io(error.localizedDescription))
      )
    }
  }

  private func handleCompletion(
    task: URLSessionTask,
    error: Error?,
    descriptor: BackgroundModelTransferDescriptor?
  ) {
    if explicitlyCancelledTaskIds.remove(task.taskIdentifier) != nil {
      let transferId = descriptor?.transferId ?? cancellationTaskIds.first {
        $0.value.contains(task.taskIdentifier)
      }?.key
      if let transferId {
        removePersistentState(transferId: transferId)
        if var taskIds = cancellationTaskIds[transferId] {
          taskIds.remove(task.taskIdentifier)
          if taskIds.isEmpty {
            cancellationTaskIds.removeValue(forKey: transferId)
            finishCancellation(transferId: transferId)
          } else {
            cancellationTaskIds[transferId] = taskIds
          }
        }
      }
      return
    }
    if terminalTaskIds.remove(task.taskIdentifier) != nil { return }
    guard let error, let descriptor else { return }

    let nativeError = error as NSError
    if let resumeData = nativeError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
      try? saveResumeData(
        resumeData,
        transferId: descriptor.transferId
      )
    }
    let record = BackgroundModelTransferRecord(
      descriptor: descriptor,
      phase: .failed,
      receivedBytes: max(0, task.countOfBytesReceived),
      errorMessage: error.localizedDescription
    )
    records[descriptor.transferId] = record
    persistRecords()
    let failure: BackgroundModelTransferFailure = nativeError.domain == NSURLErrorDomain
      ? .network(error.localizedDescription)
      : .transport(error.localizedDescription)
    finishWaiters(
      transferId: descriptor.transferId,
      result: .failure(failure)
    )
  }

  private func persistRunning(
    descriptor: BackgroundModelTransferDescriptor,
    receivedBytes: Int64
  ) {
    records[descriptor.transferId] = BackgroundModelTransferRecord(
      descriptor: descriptor,
      phase: .running,
      receivedBytes: receivedBytes,
      errorMessage: nil
    )
    persistRecords()
  }

  private func persistCompleted(descriptor: BackgroundModelTransferDescriptor) {
    records[descriptor.transferId] = BackgroundModelTransferRecord(
      descriptor: descriptor,
      phase: .completed,
      receivedBytes: descriptor.expectedBytes,
      errorMessage: nil
    )
    persistRecords()
  }

  private func persistRecords() {
    guard let data = try? JSONEncoder().encode(records) else { return }
    guard let url = try? transferStateDirectory().appendingPathComponent(
      "state.json",
      isDirectory: false
    ) else { return }
    try? data.write(to: url, options: .atomic)
  }

  private func removePersistentState(transferId: String) {
    let descriptor = records[transferId]?.descriptor
    records.removeValue(forKey: transferId)
    persistRecords()
    try? deleteResumeData(transferId: transferId)
    if let descriptor {
      try? fileManager.removeItem(
        atPath: descriptor.destinationPath
      )
    }
  }

  private func completeDestinationBytes(
    for descriptor: BackgroundModelTransferDescriptor
  ) -> Int64? {
    guard
      let attributes = try? fileManager.attributesOfItem(
        atPath: descriptor.destinationPath
      ),
      let size = attributes[.size] as? NSNumber,
      size.int64Value == descriptor.expectedBytes
    else { return nil }
    return size.int64Value
  }

  private func transferStateDirectory() throws -> URL {
    try Self.transferStateDirectory(fileManager: fileManager)
  }

  private static func transferStateDirectory(
    fileManager: FileManager
  ) throws -> URL {
    let support = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    var directory = support.appendingPathComponent(
      "model-transfers",
      isDirectory: true
    )
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
    return directory
  }

  private static func loadRecords(
    fileManager: FileManager
  ) -> [String: BackgroundModelTransferRecord] {
    guard
      let directory = try? transferStateDirectory(fileManager: fileManager),
      let data = try? Data(
        contentsOf: directory.appendingPathComponent(
          "state.json",
          isDirectory: false
        )
      ),
      let records = try? JSONDecoder().decode(
        [String: BackgroundModelTransferRecord].self,
        from: data
      )
    else { return [:] }
    return records
  }

  private func resumeDataUrl(transferId: String) throws -> URL {
    try transferStateDirectory().appendingPathComponent(
      "\(transferId).resume",
      isDirectory: false
    )
  }

  private func loadResumeData(transferId: String) throws -> Data? {
    let url = try resumeDataUrl(transferId: transferId)
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    return try Data(contentsOf: url)
  }

  private func saveResumeData(_ data: Data, transferId: String) throws {
    try data.write(
      to: resumeDataUrl(transferId: transferId),
      options: .atomic
    )
  }

  private func deleteResumeData(transferId: String) throws {
    let url = try resumeDataUrl(transferId: transferId)
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  private func emit(_ snapshot: BackgroundModelTransferSnapshot) {
    guard let progressObserver else { return }
    deliverOnMain {
      progressObserver(snapshot)
    }
  }

  private func finishWaiters(
    transferId: String,
    result: Result<BackgroundModelTransferSnapshot, BackgroundModelTransferFailure>
  ) {
    let callbacks = waiters.removeValue(forKey: transferId) ?? []
    for callback in callbacks {
      deliverOnMain {
        callback(result)
      }
    }
  }

  private func finishCancellation(transferId: String) {
    cancellationRequested.remove(transferId)
    pendingCancellationQueries.remove(transferId)
    cancellationTaskIds.removeValue(forKey: transferId)
    removePersistentState(transferId: transferId)
    finishWaiters(
      transferId: transferId,
      result: .failure(.cancelled)
    )
    let callbacks = cancellationWaiters.removeValue(forKey: transferId) ?? []
    for callback in callbacks {
      deliverOnMain {
        callback(.success(()))
      }
    }
  }

  private func deliverOnMain(_ operation: @escaping () -> Void) {
    DispatchQueue.main.async(execute: operation)
  }
}

extension BackgroundModelDownloadCoordinator: URLSessionDownloadDelegate {
  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard
      let descriptor = BackgroundModelTransferDescriptor.decode(
        taskDescription: downloadTask.taskDescription
      )
    else { return }
    stateQueue.async {
      let received = max(0, totalBytesWritten)
      self.persistRunning(descriptor: descriptor, receivedBytes: received)
      self.emit(
        BackgroundModelTransferSnapshot(
          transferId: descriptor.transferId,
          receivedBytes: received,
          expectedBytes: descriptor.expectedBytes
        )
      )
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard
      let descriptor = BackgroundModelTransferDescriptor.decode(
        taskDescription: downloadTask.taskDescription
      )
    else { return }
    // URLSession deletes `location` when this delegate method returns, so the
    // move must finish synchronously on the coordinator's non-UI state queue.
    stateQueue.sync {
      publishDownloadedFile(
        task: downloadTask,
        location: location,
        descriptor: descriptor
      )
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    let descriptor = BackgroundModelTransferDescriptor.decode(
      taskDescription: task.taskDescription
    )
    stateQueue.async {
      self.handleCompletion(
        task: task,
        error: error,
        descriptor: descriptor
      )
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    stateQueue.async {
      let completion = self.backgroundEventsCompletion
      self.backgroundEventsCompletion = nil
      guard let completion else {
        self.backgroundEventsFinished = true
        return
      }
      self.deliverOnMain(completion)
    }
  }
}

/// Exposes the native background-transfer owner to the injectable Dart store.
final class BackgroundModelDownloadChannel: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let coordinator: BackgroundModelDownloadCoordinator
  private var eventSink: FlutterEventSink?

  init(
    messenger: FlutterBinaryMessenger,
    coordinator: BackgroundModelDownloadCoordinator
  ) {
    methodChannel = FlutterMethodChannel(
      name: modelDownloadChannelName,
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: modelDownloadProgressChannelName,
      binaryMessenger: messenger
    )
    self.coordinator = coordinator
    super.init()
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    eventChannel.setStreamHandler(self)
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "download":
      do {
        guard let arguments = call.arguments as? [String: Any] else {
          throw BackgroundModelTransferFailure.invalidArguments(
            "download requires a map of arguments."
          )
        }
        let descriptor = try BackgroundModelTransferDescriptor(
          arguments: arguments
        )
        coordinator.start(descriptor: descriptor) { outcome in
          switch outcome {
          case .success(let snapshot):
            result(snapshot.platformPayload)
          case .failure(let failure):
            result(Self.flutterError(for: failure))
          }
        }
      } catch let failure as BackgroundModelTransferFailure {
        result(Self.flutterError(for: failure))
      } catch {
        result(Self.flutterError(for: .transport(error.localizedDescription)))
      }
    case "cancel":
      guard
        let arguments = call.arguments as? [String: Any],
        let transferId = arguments["transferId"] as? String,
        !transferId.isEmpty
      else {
        result(
          Self.flutterError(
            for: .invalidArguments("cancel requires transferId.")
          )
        )
        return
      }
      coordinator.cancel(transferId: transferId) { outcome in
        switch outcome {
        case .success:
          result(nil)
        case .failure(let failure):
          result(Self.flutterError(for: failure))
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    coordinator.setProgressObserver { [weak self] snapshot in
      self?.eventSink?(snapshot.platformPayload)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    coordinator.setProgressObserver(nil)
    return nil
  }

  private static func flutterError(
    for failure: BackgroundModelTransferFailure
  ) -> FlutterError {
    switch failure {
    case .invalidArguments(let message):
      return FlutterError(
        code: "MODEL_DOWNLOAD_INVALID_ARGUMENTS",
        message: message,
        details: nil
      )
    case .descriptorConflict:
      return FlutterError(
        code: "MODEL_DOWNLOAD_INVALID_ARGUMENTS",
        message: "A task with this identity has different pinned metadata.",
        details: nil
      )
    case .httpStatus(let statusCode):
      return FlutterError(
        code: "MODEL_DOWNLOAD_HTTP_STATUS",
        message: "The model host returned HTTP \(statusCode).",
        details: ["statusCode": statusCode]
      )
    case .sizeMismatch(let expected, let actual):
      return FlutterError(
        code: "MODEL_DOWNLOAD_SIZE_MISMATCH",
        message: "The downloaded byte count differs from the manifest.",
        details: ["expectedBytes": expected, "actualBytes": actual]
      )
    case .io(let message):
      return FlutterError(
        code: "MODEL_DOWNLOAD_IO",
        message: message,
        details: nil
      )
    case .network(let message):
      return FlutterError(
        code: "MODEL_DOWNLOAD_NETWORK",
        message: message,
        details: nil
      )
    case .cancelled:
      return FlutterError(
        code: "MODEL_DOWNLOAD_CANCELLED",
        message: "The model download was cancelled.",
        details: nil
      )
    case .transport(let message):
      return FlutterError(
        code: "MODEL_DOWNLOAD_FAILED",
        message: message,
        details: nil
      )
    }
  }

  deinit {
    coordinator.setProgressObserver(nil)
    eventChannel.setStreamHandler(nil)
    methodChannel.setMethodCallHandler(nil)
  }
}
