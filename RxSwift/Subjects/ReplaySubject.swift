//
//  ReplaySubject.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 4/14/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation

/**
Represents an object that is both an observable sequence as well as an observer.

Each notification is broadcasted to all subscribed and future observers, subject to buffer trimming policies.
*/
public class ReplaySubject<Element>
    : Observable<Element>
    , SubjectType
    , ObserverType
    , Disposable {
    public typealias SubjectObserverType = ReplaySubject<Element>
    
    /**
     Indicates whether the subject has any observers
     */
    public var hasObservers: Bool {
        _lock.lock(); defer { _lock.unlock() }
        return _observers.count > 0
    }
    
    private var _lock = NSRecursiveLock()
    
    // state
    private var _isDisposed = false
    private var _stoppedEvent = nil as Event<Element>?
    private var _observers = Bag<AnyObserver<Element>>()
    
    typealias DisposeKey = Bag<AnyObserver<Element>>.KeyType
    
    func unsubscribe(_ key: DisposeKey) {
        abstractMethod()
    }
    
    /**
    Notifies all subscribed observers about next event.
    
    - parameter event: Event to send to the observers.
    */
    public func on(_ event: Event<E>) {
        abstractMethod()
    }
    
    /**
    Returns observer interface for subject.
    */
    public func asObserver() -> SubjectObserverType {
        return self
    }
    
    /**
    Unsubscribe all observers and release resources.
    */
    public func dispose() {
    }

    /**
    Creates new instance of `ReplaySubject` that replays at most `bufferSize` last elements of sequence.
    
    - parameter bufferSize: Maximal number of elements to replay to observer after subscription.
    - returns: New instance of replay subject.
    */
    public static func create(_ bufferSize: Int) -> ReplaySubject<Element> {
        if bufferSize == 1 {
            return ReplayOne()
        }
        else {
            return ReplayMany(bufferSize: bufferSize)
        }
    }

    /**
    Creates a new instance of `ReplaySubject` that buffers all the elements of a sequence.
    To avoid filling up memory, developer needs to make sure that the use case will only ever store a 'reasonable'
    number of elements.
    */
    public static func createUnbounded() -> ReplaySubject<Element> {
        return ReplayAll()
    }
}

class ReplayBufferBase<Element>
    : ReplaySubject<Element>
    , SynchronizedUnsubscribeType {
    
    func trim() {
        abstractMethod()
    }
    
    func addValueToBuffer(_ value: Element) {
        abstractMethod()
    }
    
    func replayBuffer(_ observer: AnyObserver<Element>) {
        abstractMethod()
    }
    
    override func on(_ event: Event<Element>) {
        _lock.lock(); defer { _lock.unlock() }
        _synchronized_on(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        if _isDisposed {
            return
        }
        
        if _stoppedEvent != nil {
            return
        }
        
        switch event {
        case .next(let value):
            addValueToBuffer(value)
            trim()
            _observers.on(event)
        case .error, .completed:
            _stoppedEvent = event
            trim()
            _observers.on(event)
            _observers.removeAll()
        }
    }
    
    override func subscribe<O : ObserverType where O.E == Element>(_ observer: O) -> Disposable {
        _lock.lock(); defer { _lock.unlock() }
        return _synchronized_subscribe(observer)
    }

    func _synchronized_subscribe<O : ObserverType where O.E == E>(_ observer: O) -> Disposable {
        if _isDisposed {
            observer.on(.error(RxError.disposed(object: self)))
            return Disposables.create()
        }
     
        let AnyObserver = observer.asObserver()
        
        replayBuffer(AnyObserver)
        if let stoppedEvent = _stoppedEvent {
            observer.on(stoppedEvent)
            return Disposables.create()
        }
        else {
            let key = _observers.insert(AnyObserver)
            return SubscriptionDisposable(owner: self, key: key)
        }
    }

    func synchronizedUnsubscribe(_ disposeKey: DisposeKey) {
        _lock.lock(); defer { _lock.unlock() }
        _synchronized_unsubscribe(disposeKey)
    }

    func _synchronized_unsubscribe(_ disposeKey: DisposeKey) {
        if _isDisposed {
            return
        }
        
        _ = _observers.removeKey(disposeKey)
    }
    
    override func dispose() {
        super.dispose()

        synchronizedDispose()
    }

    func synchronizedDispose() {
        _lock.lock(); defer { _lock.unlock() }
        _synchronized_dispose()
    }

    func _synchronized_dispose() {
        _isDisposed = true
        _stoppedEvent = nil
        _observers.removeAll()
    }
}

final class ReplayOne<Element> : ReplayBufferBase<Element> {
    private var _value: Element?
    
    override init() {
        super.init()
    }
    
    override func trim() {
        
    }
    
    override func addValueToBuffer(_ value: Element) {
        _value = value
    }
    
    override func replayBuffer(_ observer: AnyObserver<Element>) {
        if let value = _value {
            observer.on(.next(value))
        }
    }

    override func _synchronized_dispose() {
        super._synchronized_dispose()
        _value = nil
    }
}

class ReplayManyBase<Element> : ReplayBufferBase<Element> {
    private var _queue: Queue<Element>
    
    init(queueSize: Int) {
        _queue = Queue(capacity: queueSize + 1)
    }
    
    override func addValueToBuffer(_ value: Element) {
        _queue.enqueue(value)
    }
    
    override func replayBuffer(_ observer: AnyObserver<E>) {
        for item in _queue {
            observer.on(.next(item))
        }
    }

    override func _synchronized_dispose() {
        super._synchronized_dispose()
        _queue = Queue(capacity: 0)
    }
}

final class ReplayMany<Element> : ReplayManyBase<Element> {
    private let _bufferSize: Int
    
    init(bufferSize: Int) {
        _bufferSize = bufferSize
        
        super.init(queueSize: bufferSize)
    }
    
    override func trim() {
        while _queue.count > _bufferSize {
            _ = _queue.dequeue()
        }
    }
}

final class ReplayAll<Element> : ReplayManyBase<Element> {
    init() {
        super.init(queueSize: 0)
    }
    
    override func trim() {
        
    }
}
