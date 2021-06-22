//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Swift
@_implementationOnly import _SwiftConcurrencyShims

// ==== Task -------------------------------------------------------------------

/// A unit of asynchronous work.
///
/// An instance of `Task` always represents a top-level task. The instance
/// can be used to await its completion, cancel the task, etc., The task will
/// run to completion even if there are no other instances of the `Task`.
///
/// `Task` also provides appropriate context-sensitive static functions which
/// operate on the "current" task, which might either be a detached task or
/// a child task. Because all such functions are `async` they can only
/// be invoked as part of an existing task, and therefore are guaranteed to be
/// effective.
///
/// Only code that's running as part of the task can interact with that task,
/// by invoking the appropriate context-sensitive static functions which operate
/// on the current task.
///
/// A task's execution can be seen as a series of periods where the task ran.
/// Each such period ends at a suspension point or the
/// completion of the task.
///
/// These partial periods towards the task's completion are `PartialAsyncTask`.
/// Unless you're implementing a scheduler,
/// you don't generally interact with partial tasks directly.
///
/// Task Cancellation
/// =================
///
/// Tasks include a shared mechanism for indicating cancellation,
/// but not a shared implementation for how to handle cancellation.
/// Depending on the work you're doing in the task,
/// the correct way to stop that work varies.
/// Likewise,
/// it's the responsibility of the code running as part of the task
/// to check for cancellation whenever stopping is appropriate.
/// In a long-task that includes multiple pieces,
/// you might need to check for cancellation at several points,
/// and handle cancellation differently at each point.
/// If you only need to throw an error to stop the work,
/// call the `Task.checkCancellation()` function to check for cancellation.
/// Other responses to cancellation include
/// returning the work completed so far, returning an empty result, or returning `nil`.
///
/// Cancellation is a purely Boolean state;
/// there's no way to include additional information
/// like the reason for cancellation.
/// This reflects the fact that a task can be canceled for many reasons,
/// and additional reasons can accrue during the cancellation process.
@available(SwiftStdlib 5.5, *)
public struct Task<Success, Failure: Error>: Sendable {
  internal let _task: Builtin.NativeObject

  internal init(_ task: Builtin.NativeObject) {
    self._task = task
  }
}

@available(SwiftStdlib 5.5, *)
extension Task {
  /// Wait for the task to complete, returning (or throwing) its result.
  ///
  /// ### Priority
  /// If the task has not completed yet, its priority will be elevated to the
  /// priority of the current task. Note that this may not be as effective as
  /// creating the task with the "right" priority to in the first place.
  ///
  /// ### Cancellation
  /// If the awaited on task gets cancelled externally the `get()` will throw
  /// a cancellation error.
  ///
  /// If the task gets cancelled internally, e.g. by checking for cancellation
  /// and throwing a specific error or using `checkCancellation` the error
  /// thrown out of the task will be re-thrown here.
  public var value: Success {
    get async throws {
      return try await _taskFutureGetThrowing(_task)
    }
  }

  /// Wait for the task to complete, returning (or throwing) its result.
  ///
  /// ### Priority
  /// If the task has not completed yet, its priority will be elevated to the
  /// priority of the current task. Note that this may not be as effective as
  /// creating the task with the "right" priority to in the first place.
  ///
  /// ### Cancellation
  /// If the awaited on task gets cancelled externally the `get()` will throw
  /// a cancellation error.
  ///
  /// If the task gets cancelled internally, e.g. by checking for cancellation
  /// and throwing a specific error or using `checkCancellation` the error
  /// thrown out of the task will be re-thrown here.

  /// Wait for the task to complete, returning its `Result`.
  ///
  /// ### Priority
  /// If the task has not completed yet, its priority will be elevated to the
  /// priority of the current task. Note that this may not be as effective as
  /// creating the task with the "right" priority to in the first place.
  ///
  /// ### Cancellation
  /// If the awaited on task gets cancelled externally the `get()` will throw
  /// a cancellation error.
  ///
  /// If the task gets cancelled internally, e.g. by checking for cancellation
  /// and throwing a specific error or using `checkCancellation` the error
  /// thrown out of the task will be re-thrown here.
  public var result: Result<Success, Failure> {
    get async {
      do {
        return .success(try await value)
      } catch {
        return .failure(error as! Failure) // as!-safe, guaranteed to be Failure
      }
    }
  }

  /// Attempt to cancel the task.
  ///
  /// Whether this function has any effect is task-dependent.
  ///
  /// For a task to respect cancellation it must cooperatively check for it
  /// while running. Many tasks will check for cancellation before beginning
  /// their "actual work", however this is not a requirement nor is it guaranteed
  /// how and when tasks check for cancellation in general.
  public func cancel() {
    Builtin.cancelAsyncTask(_task)
  }
}

@available(SwiftStdlib 5.5, *)
extension Task where Failure == Never {
  /// Wait for the task to complete, returning its result.
  ///
  /// If the task hasn't completed,
  /// its priority increases to that of the current task.
  /// Note that this might not be as effective as
  /// creating the task with the correct priority,
  /// depending on the executor's scheduling details.
  ///
  /// ### Cancellation
  /// The task this refers to may check for cancellation, however
  /// since it is not-throwing it would have to handle it using some other
  /// way than throwing a `CancellationError`, e.g. it could provide a neutral
  /// value of the `Success` type, or encode that cancellation has occurred in
  /// that type itself.
  public var value: Success {
    get async {
      return await _taskFutureGet(_task)
    }
  }
}

@available(SwiftStdlib 5.5, *)
extension Task: Hashable {
  public func hash(into hasher: inout Hasher) {
    UnsafeRawPointer(Builtin.bridgeToRawPointer(_task)).hash(into: &hasher)
  }
}

@available(SwiftStdlib 5.5, *)
extension Task: Equatable {
  public static func ==(lhs: Self, rhs: Self) -> Bool {
    UnsafeRawPointer(Builtin.bridgeToRawPointer(lhs._task)) ==
      UnsafeRawPointer(Builtin.bridgeToRawPointer(rhs._task))
  }
}

// ==== Task Priority ----------------------------------------------------------

/// Task priority may inform decisions an `Executor` makes about how and when
/// to schedule tasks submitted to it.
///
/// ### Priority scheduling
/// An executor MAY utilize priority information to attempt running higher
/// priority tasks first, and then continuing to serve lower priority tasks.
///
/// The exact semantics of how priority is treated are left up to each
/// platform and `Executor` implementation.
///
/// ### Priority inheritance
/// Child tasks automatically inherit their parent task's priority.
///
/// Detached tasks (created by `Task.detached`) DO NOT inherit task priority,
/// as they are "detached" from their parent tasks after all.
///
/// ### Priority elevation
/// In some situations the priority of a task must be elevated (or "escalated", "raised"):
///
/// - if a `Task` running on behalf of an actor, and a new higher-priority
///   task is enqueued to the actor, its current task must be temporarily
///   elevated to the priority of the enqueued task, in order to allow the new
///   task to be processed at--effectively-- the priority it was enqueued with.
///   - this DOES NOT affect `Task.currentPriority()`.
/// - if a task is created with a `Task.Handle`, and a higher-priority task
///   calls the `await handle.get()` function the priority of this task must be
///   permanently increased until the task completes.
///   - this DOES affect `Task.currentPriority()`.
///
/// TODO: Define the details of task priority; It is likely to be a concept
///       similar to Darwin Dispatch's QoS; bearing in mind that priority is not as
///       much of a thing on other platforms (i.e. server side Linux systems).
@available(SwiftStdlib 5.5, *)
public struct TaskPriority: RawRepresentable, Sendable {
  public typealias RawValue = UInt8
  public var rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let high: TaskPriority = .init(rawValue: 0x19)
  public static let userInitiated: TaskPriority = high
  public static let `default`: TaskPriority = .init(rawValue: 0x15)
  public static let low: TaskPriority = .init(rawValue: 0x11)
  public static let utility: TaskPriority = low
  public static let background: TaskPriority = .init(rawValue: 0x09)
}

@available(SwiftStdlib 5.5, *)
extension TaskPriority: Equatable {
  public static func == (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
    lhs.rawValue == rhs.rawValue
  }

  public static func != (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
    lhs.rawValue != rhs.rawValue
  }
}

@available(SwiftStdlib 5.5, *)
extension TaskPriority: Comparable {
  public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public static func <= (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
    lhs.rawValue <= rhs.rawValue
  }

  public static func > (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
    lhs.rawValue > rhs.rawValue
  }

  public static func >= (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
    lhs.rawValue >= rhs.rawValue
  }
}

@available(SwiftStdlib 5.5, *)
extension TaskPriority: Codable { }

@available(SwiftStdlib 5.5, *)
extension Task where Success == Never, Failure == Never {

  /// Returns the `current` task's priority.
  ///
  /// If no current `Task` is available, queries the system to determine the
  /// priority at which the current function is running. If the system cannot
  /// provide an appropriate priority, returns `Priority.default`.
  ///
  /// - SeeAlso: `TaskPriority`
  public static var currentPriority: TaskPriority {
    withUnsafeCurrentTask { task in
      // If we are running on behalf of a task, use that task's priority.
      if let task = task {
        return task.priority
      }

      // Otherwise, query the system.
      return TaskPriority(rawValue: UInt8(0))
    }
  }
}

@available(SwiftStdlib 5.5, *)
extension TaskPriority {
  /// Downgrade user-interactive to user-initiated.
  var _downgradeUserInteractive: TaskPriority {
    return self
  }
}

// ==== Job Flags --------------------------------------------------------------

/// Flags for schedulable jobs.
///
/// This is a port of the C++ FlagSet.
@available(SwiftStdlib 5.5, *)
struct JobFlags {
  /// Kinds of schedulable jobs.
  enum Kind: Int32 {
    case task = 0
  }

  /// The actual bit representation of these flags.
  var bits: Int32 = 0

  /// The kind of job described by these flags.
  var kind: Kind {
    get {
      Kind(rawValue: bits & 0xFF)!
    }

    set {
      bits = (bits & ~0xFF) | newValue.rawValue
    }
  }

  /// Whether this is an asynchronous task.
  var isAsyncTask: Bool { kind == .task }

  /// The priority given to the job.
  var priority: TaskPriority? {
    get {
      let value = (Int(bits) & 0xFF00) >> 8

      if value == 0 {
        return nil
      }

      return TaskPriority(rawValue: UInt8(value))
    }

    set {
      bits = (bits & ~0xFF00) | Int32((Int(newValue?.rawValue ?? 0) << 8))
    }
  }

  /// Whether this is a child task.
  var isChildTask: Bool {
    get {
      (bits & (1 << 24)) != 0
    }

    set {
      if newValue {
        bits = bits | 1 << 24
      } else {
        bits = (bits & ~(1 << 24))
      }
    }
  }

  /// Whether this is a future.
  var isFuture: Bool {
    get {
      (bits & (1 << 25)) != 0
    }

    set {
      if newValue {
        bits = bits | 1 << 25
      } else {
        bits = (bits & ~(1 << 25))
      }
    }
  }

  /// Whether this is a group child.
  var isGroupChildTask: Bool {
    get {
      (bits & (1 << 26)) != 0
    }

    set {
      if newValue {
        bits = bits | 1 << 26
      } else {
        bits = (bits & ~(1 << 26))
      }
    }
  }

  /// Whether this is a task created by the 'async' operation, which
  /// conceptually continues the work of the synchronous code that invokes
  /// it.
  var isContinuingAsyncTask: Bool {
    get {
      (bits & (1 << 27)) != 0
    }

    set {
      if newValue {
        bits = bits | 1 << 27
      } else {
        bits = (bits & ~(1 << 27))
      }
    }
  }
}

// ==== Task Creation Flags --------------------------------------------------

/// Flags for schedulable jobs.
///
/// This is a port of the C++ FlagSet.
@available(SwiftStdlib 5.5, *)
struct TaskCreateFlags {
  /// The actual bit representation of these flags.
  var bits: Int = 0

  /// The priority given to the job.
  var priority: TaskPriority? {
    get {
      let value = Int(bits) & 0xFF

      if value == 0 {
        return nil
      }

      return TaskPriority(rawValue: UInt8(value))
    }

    set {
      bits = (bits & ~0xFF) | Int(newValue?.rawValue ?? 0)
    }
  }

  /// Whether this is a child task.
  var isChildTask: Bool {
    get {
      (bits & (1 << 8)) != 0
    }

    set {
      if newValue {
        bits = bits | 1 << 8
      } else {
        bits = (bits & ~(1 << 8))
      }
    }
  }

  /// Whether to copy thread locals from the currently-executing task into the
  /// newly-created task.
  var copyThreadLocals: Bool {
    get {
      (bits & (1 << 10)) != 0
    }

    set {
      if newValue {
        bits = bits | 1 << 10
      } else {
        bits = (bits & ~(1 << 10))
      }
    }
  }

  /// Whether this task should inherit as much context from the
  /// currently-executing task as it can.
  var inheritContext: Bool {
    get {
      (bits & (1 << 11)) != 0
    }

    set {
      if newValue {
        bits = bits | 1 << 11
      } else {
        bits = (bits & ~(1 << 11))
      }
    }
  }

  /// Whether to enqueue the newly-created task on the given executor (if
  /// specified) or the global executor.
  var enqueueJob: Bool {
    get {
      (bits & (1 << 12)) != 0
    }

    set {
      if newValue {
        bits = bits | 1 << 12
      } else {
        bits = (bits & ~(1 << 12))
      }
    }
  }

  /// Whether to add a pending group task unconditionally as part of creating
  /// the task.
  var addPendingGroupTaskUnconditionally: Bool {
    get {
      (bits & (1 << 13)) != 0
    }

    set {
      if newValue {
        bits = bits | 1 << 13
      } else {
        bits = (bits & ~(1 << 13))
      }
    }
  }
}

// ==== Task Creation ----------------------------------------------------------
@available(SwiftStdlib 5.5, *)
extension Task where Failure == Never {
  /// Run given `operation` as asynchronously in its own top-level task.
  ///
  /// The `async` function should be used when creating asynchronous work
  /// that operates on behalf of the synchronous function that calls it.
  /// Like `Task.detached`, the async function creates a separate, top-level
  /// task.
  ///
  /// Unlike `Task.detached`, the task creating by the `Task` initializer
  /// inherits the priority and actor context of the caller, so the `operation`
  /// is treated more like an asynchronous extension to the synchronous
  /// operation.
  ///
  /// - Parameters:
  ///   - priority: priority of the task. If nil, the priority will come from
  ///     Task.currentPriority.
  ///   - operation: the operation to execute
  @discardableResult
  public init(
    priority: TaskPriority? = nil,
    @_inheritActorContext @_implicitSelfCapture operation: __owned @Sendable @escaping () async -> Success
  ) {
    // Set up the job flags for a new task.
    var flags = TaskCreateFlags()
    flags.priority = priority ?? Task<Never, Never>.currentPriority._downgradeUserInteractive
    flags.inheritContext = true
    flags.copyThreadLocals = true
    flags.enqueueJob = true

    // Create the asynchronous task.
    let (task, _) = Builtin.createAsyncTask(
      Int(flags.bits), /*options*/nil, operation)

    self._task = task
  }
}

@available(SwiftStdlib 5.5, *)
extension Task where Failure == Error {
  /// Run given `operation` as asynchronously in its own top-level task.
  ///
  /// This initializer creates asynchronous work on behalf of the synchronous function that calls it.
  /// Like `Task.detached`, this initializer creates a separate, top-level task.
  /// Unlike `Task.detached`, the task created inherits the priority and
  /// actor context of the caller, so the `operation` is treated more like an
  /// asynchronous extension to the synchronous operation.
  ///
  /// - Parameters:
  ///   - priority: priority of the task. If nil, the priority will come from
  ///     Task.currentPriority.
  ///   - operation: the operation to execute
  @discardableResult
  public init(
    priority: TaskPriority? = nil,
    @_inheritActorContext @_implicitSelfCapture operation: __owned @Sendable @escaping () async throws -> Success
  ) {
    // Set up the job flags for a new task.
    var flags = TaskCreateFlags()
    flags.priority = priority ?? Task<Never, Never>.currentPriority._downgradeUserInteractive
    flags.inheritContext = true
    flags.copyThreadLocals = true
    flags.enqueueJob = true

    // Create the asynchronous task future.
    let (task, _) = Builtin.createAsyncTask(
        Int(flags.bits), /*options*/nil, operation)

    self._task = task
  }
}

// ==== Detached Tasks ---------------------------------------------------------
@available(SwiftStdlib 5.5, *)
extension Task where Failure == Never {
  /// Run given throwing `operation` as part of a new top-level task.
  ///
  /// Creating detached tasks should, generally, be avoided in favor of using
  /// `async` functions, `async let` declarations and `await` expressions - as
  /// those benefit from structured, bounded concurrency which is easier to reason
  /// about, as well as automatically inheriting the parent tasks priority,
  /// task-local storage, deadlines, as well as being cancelled automatically
  /// when their parent task is cancelled. Detached tasks do not get any of those
  /// benefits, and thus should only be used when an operation is impossible to
  /// be modelled with child tasks.
  ///
  /// ### Cancellation
  /// A detached task always runs to completion unless it is explicitly cancelled.
  /// Specifically, dropping a detached tasks `Task` does _not_ automatically
  /// cancel given task.
  ///
  /// Cancelling a task must be performed explicitly via `cancel()`.
  ///
  /// - Note: it is generally preferable to use child tasks rather than detached
  ///   tasks. Child tasks automatically carry priorities, task-local state,
  ///   deadlines and have other benefits resulting from the structured
  ///   concurrency concepts that they model. Consider using detached tasks only
  ///   when strictly necessary and impossible to model operations otherwise.
  ///
  /// - Parameters:
  ///   - priority: priority of the task
  ///   - operation: the operation to execute
  /// - Returns: handle to the task, allowing to `await get()` on the
  ///     tasks result or `cancel` it. If the operation fails the handle will
  ///     throw the error the operation has thrown when awaited on.
  @discardableResult
  public static func detached(
    priority: TaskPriority? = nil,
    operation: __owned @Sendable @escaping () async -> Success
  ) -> Task<Success, Failure> {
    // Set up the job flags for a new task.
    var flags = TaskCreateFlags()
    flags.priority = priority ?? .unspecified
    flags.enqueueJob = true

    // Create the asynchronous task future.
    let (task, _) = Builtin.createAsyncTask(
        Int(flags.bits), /*options*/nil, operation)

    return Task(task)
  }
}

@available(SwiftStdlib 5.5, *)
extension Task where Failure == Error {
  /// Run given throwing `operation` as part of a new top-level task.
  ///
  /// Creating detached tasks should, generally, be avoided in favor of using
  /// `async` functions, `async let` declarations and `await` expressions - as
  /// those benefit from structured, bounded concurrency which is easier to reason
  /// about, as well as automatically inheriting the parent tasks priority,
  /// task-local storage, deadlines, as well as being cancelled automatically
  /// when their parent task is cancelled. Detached tasks do not get any of those
  /// benefits, and thus should only be used when an operation is impossible to
  /// be modelled with child tasks.
  ///
  /// ### Cancellation
  /// A detached task always runs to completion unless it is explicitly cancelled.
  /// Specifically, dropping a detached tasks `Task.Handle` does _not_ automatically
  /// cancel given task.
  ///
  /// Cancelling a task must be performed explicitly via `handle.cancel()`.
  ///
  /// - Note: it is generally preferable to use child tasks rather than detached
  ///   tasks. Child tasks automatically carry priorities, task-local state,
  ///   deadlines and have other benefits resulting from the structured
  ///   concurrency concepts that they model. Consider using detached tasks only
  ///   when strictly necessary and impossible to model operations otherwise.
  ///
  /// - Parameters:
  ///   - priority: priority of the task
  ///   - executor: the executor on which the detached closure should start
  ///               executing on.
  ///   - operation: the operation to execute
  /// - Returns: handle to the task, allowing to `await handle.get()` on the
  ///     tasks result or `cancel` it. If the operation fails the handle will
  ///     throw the error the operation has thrown when awaited on.
  @discardableResult
  public static func detached(
    priority: TaskPriority? = nil,
    operation: __owned @Sendable @escaping () async throws -> Success
  ) -> Task<Success, Failure> {
    // Set up the job flags for a new task.
    var flags = TaskCreateFlags()
    flags.priority = priority ?? .unspecified
    flags.enqueueJob = true

    // Create the asynchronous task future.
    let (task, _) = Builtin.createAsyncTask(
        Int(flags.bits), /*options*/nil, operation)

    return Task(task)
  }
}

// ==== Async Handler ----------------------------------------------------------

// TODO: remove this?
@available(SwiftStdlib 5.5, *)
func _runAsyncHandler(operation: @escaping () async -> ()) {
  typealias ConcurrentFunctionType = @Sendable () async -> ()
  detach(
    operation: unsafeBitCast(operation, to: ConcurrentFunctionType.self)
  )
}

// ==== Async Sleep ------------------------------------------------------------

@available(SwiftStdlib 5.5, *)
extension Task where Success == Never, Failure == Never {
  /// Suspends the current task for _at least_ the given duration
  /// in nanoseconds.
  ///
  /// Calling this method doesn't block the underlying thread.
  ///
  /// - Parameters:
  ///   - duration: The time to sleep, in nanoseconds.
  public static func sleep(_ duration: UInt64) async {
    let currentTask = Builtin.getCurrentAsyncTask()
    let priority = getJobFlags(currentTask).priority ?? Task.currentPriority._downgradeUserInteractive

    return await Builtin.withUnsafeContinuation { (continuation: Builtin.RawUnsafeContinuation) -> Void in
      let job = _taskCreateNullaryContinuationJob(priority: Int(priority.rawValue), continuation: continuation)
      _enqueueJobGlobalWithDelay(duration, job)
    }
  }
}

// ==== Voluntary Suspension -----------------------------------------------------

@available(SwiftStdlib 5.5, *)
extension Task where Success == Never, Failure == Never {

  /// Suspends the current task and allows other tasks to execute.
  ///
  /// A task can voluntarily suspend itself
  /// in the middle of a long-running operation
  /// that doesn't contain any suspension points,
  /// to let other tasks run for a while
  /// before execution returns back to this task.
  ///
  /// If this task is the highest-priority task in the system,
  /// the executor immediately resumes execution of the same task.
  /// As such,
  /// this method isn't necessarily a way to avoid resource starvation.
  public static func yield() async {
    let currentTask = Builtin.getCurrentAsyncTask()
    let priority = getJobFlags(currentTask).priority ?? Task.currentPriority._downgradeUserInteractive

    return await Builtin.withUnsafeContinuation { (continuation: Builtin.RawUnsafeContinuation) -> Void in
      let job = _taskCreateNullaryContinuationJob(priority: Int(priority.rawValue), continuation: continuation)
      _enqueueJobGlobal(job)
    }
  }
}

// ==== UnsafeCurrentTask ------------------------------------------------------

/// Calls the given closure with the with the "current" task in which this
/// function was invoked.
///
/// If you call this function from the body of an asynchronous function,
/// the unsafe task handle passed to the closure is always non-nil
/// because an asynchronous function always runs in the context of a task.
/// However if you call this function from the body of a synchronous function,
/// and that function isn't executing in the context of any task,
/// the unsafe task handle is `nil`.
///
/// Don't store an unsafe task handle
/// for use outside this method's closure.
/// Storing an unsafe task handle doesn't have an impact on the task's actual life cycle,
/// and the behavior of accessing an unsafe task handle
/// outside of the `withUnsafeCurrentTask(body:)` method's closure isn't defined.
/// Instead, use the `task` property of `UnsafeCurrentTask`
/// to access an instance of `Task` that you can store long-term
/// and interact with outside of the closure body.
///
/// - Parameters:
///   - body: A closure that takes an `UnsafeCurrentTask` parameter.
///     If `body` has a return value,
///     that value is also used as the return value
///     for the `withUnsafeCurrentTask(body:)` function.
///
/// - Returns: The return value, if any, of the `body` closure.
@available(SwiftStdlib 5.5, *)
public func withUnsafeCurrentTask<T>(body: (UnsafeCurrentTask?) throws -> T) rethrows -> T {
  guard let _task = _getCurrentAsyncTask() else {
    return try body(nil)
  }

  // FIXME: This retain seems pretty wrong, however if we don't we WILL crash
  //        with "destroying a task that never completed" in the task's destroy.
  //        How do we solve this properly?
  Builtin.retain(_task)

  return try body(UnsafeCurrentTask(_task))
}

/// An unsafe task handle for the current task.
///
/// To get an instance of `UnsafeCurrentTask` for the current task,
/// call the `withUnsafeCurrentTask(body:)` method.
/// Don't try to store an unsafe task handle
/// for use outside that method's closure.
/// Storing an unsafe task handle doesn't have an impact on the task's actual life cycle,
/// and the behavior of accessing an unsafe task handle
/// outside of the `withUnsafeCurrentTask(body:)` method's closure isn't defined.
/// Instead, use the `task` property of `UnsafeCurrentTask`
/// to access an instance of `Task` that you can store long-term
/// and interact with outside of the closure body.
///
/// Only APIs on `UnsafeCurrentTask` that are also part of `Task`
/// are safe to invoke from another task
/// besides the one that this task handle represents.
/// Calling other APIs from another task is undefined behavior,
/// breaks invariants in other parts of the program running on this task,
/// and may lead to crashes or data loss.
@available(SwiftStdlib 5.5, *)
public struct UnsafeCurrentTask {
  internal let _task: Builtin.NativeObject

  // May only be created by the standard library.
  internal init(_ task: Builtin.NativeObject) {
    self._task = task
  }

  /// Returns `true` if the task is cancelled, and should stop executing.
  ///
  /// - SeeAlso: `checkCancellation()`
  public var isCancelled: Bool {
    _taskIsCancelled(_task)
  }

  /// The current task's priority.
  ///
  /// - SeeAlso: `TaskPriority`
  /// - SeeAlso: `Task.currentPriority`
  public var priority: TaskPriority {
    getJobFlags(_task).priority ?? .unspecified
  }
}

@available(SwiftStdlib 5.5, *)
extension UnsafeCurrentTask: Hashable {
  public func hash(into hasher: inout Hasher) {
    UnsafeRawPointer(Builtin.bridgeToRawPointer(_task)).hash(into: &hasher)
  }
}

@available(SwiftStdlib 5.5, *)
extension UnsafeCurrentTask: Equatable {
  public static func ==(lhs: Self, rhs: Self) -> Bool {
    UnsafeRawPointer(Builtin.bridgeToRawPointer(lhs._task)) ==
      UnsafeRawPointer(Builtin.bridgeToRawPointer(rhs._task))
  }
}

// ==== Internal ---------------------------------------------------------------

@available(SwiftStdlib 5.5, *)
struct TaskOptionRecord {
  // The kind of option record.
  enum Kind: UInt8 {
    case executor = 0
    case taskGroup = 1
  }

  // Flags stored within an option record.
  struct Flags {
    var bits: Int = 0

    init(kind: Kind) {
      self.bits = 0
      self.kind = kind
    }

    /// The kind of option record described by these flags.
    var kind: Kind {
      get {
        Kind(rawValue: UInt8(bits & 0xFF))!
      }

      set {
        bits = (bits & ~0xFF) | Int(newValue.rawValue)
      }
    }
  }

  var flags: Flags
  var parent: UnsafeMutablePointer<TaskOptionRecord>? = nil

  init(kind: Kind, parent: UnsafeMutablePointer<TaskOptionRecord>? = nil) {
    self.flags = Flags(kind: kind)
    self.parent = parent
  }
}

@available(SwiftStdlib 5.5, *)
extension TaskOptionRecord {
  struct TaskGroup {
    var base: TaskOptionRecord
    var group: Builtin.RawPointer

    init(
      parent: UnsafeMutablePointer<TaskOptionRecord>? = nil,
      group: Builtin.RawPointer
    ) {
      self.base = .init(kind: .taskGroup, parent: parent)
      self.group = group
    }
  }
}

@available(SwiftStdlib 5.5, *)
@_silgen_name("swift_task_getCurrent")
func _getCurrentAsyncTask() -> Builtin.NativeObject?

@available(SwiftStdlib 5.5, *)
@_silgen_name("swift_task_getJobFlags")
func getJobFlags(_ task: Builtin.NativeObject) -> JobFlags

@available(SwiftStdlib 5.5, *)
@_silgen_name("swift_task_enqueueGlobal")
@usableFromInline
func _enqueueJobGlobal(_ task: Builtin.Job)

@available(SwiftStdlib 5.5, *)
@_silgen_name("swift_task_enqueueGlobalWithDelay")
@usableFromInline
func _enqueueJobGlobalWithDelay(_ delay: UInt64, _ task: Builtin.Job)

@available(SwiftStdlib 5.5, *)
@_silgen_name("swift_task_asyncMainDrainQueue")
public func _asyncMainDrainQueue() -> Never

@available(SwiftStdlib 5.5, *)
public func _runAsyncMain(_ asyncFun: @escaping () async throws -> ()) {
#if os(Windows)
  Task.detached {
    do {
      try await asyncFun()
      exit(0)
    } catch {
      _errorInMain(error)
    }
  }
#else
  @MainActor @Sendable
  func _doMain(_ asyncFun: @escaping () async throws -> ()) async {
    do {
      try await asyncFun()
    } catch {
      _errorInMain(error)
    }
  }

  Task.detached {
    await _doMain(asyncFun)
    exit(0)
  }
#endif
  _asyncMainDrainQueue()
}

// FIXME: both of these ought to take their arguments _owned so that
// we can do a move out of the future in the common case where it's
// unreferenced
@available(SwiftStdlib 5.5, *)
@_silgen_name("swift_task_future_wait")
public func _taskFutureGet<T>(_ task: Builtin.NativeObject) async -> T

@available(SwiftStdlib 5.5, *)
@_silgen_name("swift_task_future_wait_throwing")
public func _taskFutureGetThrowing<T>(_ task: Builtin.NativeObject) async throws -> T

@available(SwiftStdlib 5.5, *)
public func _runChildTask<T>(
  operation: @Sendable @escaping () async throws -> T
) async -> Builtin.NativeObject {
  let currentTask = Builtin.getCurrentAsyncTask()

  // Set up the job flags for a new task.
  var flags = JobFlags()
  flags.kind = .task
  flags.priority = getJobFlags(currentTask).priority ?? .unspecified
  flags.isFuture = true
  flags.isChildTask = true

  // Create the asynchronous task future.
  let (task, _) = Builtin.createAsyncTaskFuture(
      Int(flags.bits), operation)

  // Enqueue the resulting job.
  _enqueueJobGlobal(Builtin.convertTaskToJob(task))

  return task
}

@available(SwiftStdlib 5.5, *)
@_silgen_name("swift_task_cancel")
func _taskCancel(_ task: Builtin.NativeObject)

@available(SwiftStdlib 5.5, *)
@_silgen_name("swift_task_isCancelled")
func _taskIsCancelled(_ task: Builtin.NativeObject) -> Bool

@available(SwiftStdlib 5.5, *)
@_silgen_name("swift_task_createNullaryContinuationJob")
func _taskCreateNullaryContinuationJob(priority: Int, continuation: Builtin.RawUnsafeContinuation) -> Builtin.Job

@available(SwiftStdlib 5.5, *)
@usableFromInline
@_silgen_name("swift_task_isCurrentExecutor")
func _taskIsCurrentExecutor(_ executor: Builtin.Executor) -> Bool

@available(SwiftStdlib 5.5, *)
@usableFromInline
@_silgen_name("swift_task_reportUnexpectedExecutor")
func _reportUnexpectedExecutor(_ _filenameStart: Builtin.RawPointer,
                               _ _filenameLength: Builtin.Word,
                               _ _filenameIsASCII: Builtin.Int1,
                               _ _line: Builtin.Word,
                               _ _executor: Builtin.Executor)

@available(SwiftStdlib 5.5, *)
@_silgen_name("swift_task_getCurrentThreadPriority")
func _getCurrentThreadPriority() -> Int

#if _runtime(_ObjC)

/// Intrinsic used by SILGen to launch a task for bridging a Swift async method
/// which was called through its ObjC-exported completion-handler-based API.
@available(SwiftStdlib 5.5, *)
@_alwaysEmitIntoClient
@usableFromInline
internal func _runTaskForBridgedAsyncMethod(@_inheritActorContext _ body: __owned @Sendable @escaping () async -> Void) {
  Task(operation: body)
}

#endif
