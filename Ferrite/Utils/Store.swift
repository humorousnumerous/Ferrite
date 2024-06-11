//
//  Store.swift
//  Ferrite
//
//
//  Originally created by William Baker on 09/06/2022.
//  https://github.com/Tiny-Home-Consulting/Dependiject/blob/master/Dependiject/Store.swift
//  Copyright (c) 2022 Tiny Home Consulting LLC. All rights reserved.
//
//  Combined together by Brian Dashore
//
//  TODO: Replace with Observable when minVersion >= iOS 17
//

import Combine
import SwiftUI

class ErasedObservableObject: ObservableObject {
    let objectWillChange: AnyPublisher<Void, Never>

    init(objectWillChange: AnyPublisher<Void, Never>) {
        self.objectWillChange = objectWillChange
    }

    static func empty() -> ErasedObservableObject {
        .init(objectWillChange: Empty().eraseToAnyPublisher())
    }
}

protocol AnyObservableObject: AnyObject {
    var objectWillChange: ObservableObjectPublisher { get }
}

// The generic type names were chosen to match the SwiftUI equivalents:
// - ObjectType from StateObject<ObjectType> and ObservedObject<ObjectType>
// - Subject from ObservedObject.Wrapper.subscript<Subject>(dynamicMember:)
// - S from Publisher.receive<S>(on:options:)

/// A property wrapper used to wrap injected observable objects.
///
/// This is similar to SwiftUI's
/// [`StateObject`](https://developer.apple.com/documentation/swiftui/stateobject), but without
/// compile-time type restrictions. The lack of compile-time restrictions means that `ObjectType`
/// may be a protocol rather than a class.
///
/// - Important: At runtime, the wrapped value must conform to ``AnyObservableObject``.
///
/// To pass properties of the observable object down the view hierarchy as bindings, use the
/// projected value:
/// ```swift
/// struct ExampleView: View {
///     @Store var viewModel = Factory.shared.resolve(ViewModelProtocol.self)
///
///     var body: some View {
///         TextField("username", text: $viewModel.username)
///     }
/// }
/// ```
/// Not all injected objects need this property wrapper. See the example projects for examples each
/// way.
@propertyWrapper
struct Store<ObjectType> {
    /// The underlying object being stored.
    let wrappedValue: ObjectType

    // See https://github.com/Tiny-Home-Consulting/Dependiject/issues/38
    fileprivate var _observableObject: ObservedObject<ErasedObservableObject>

    @MainActor var observableObject: ErasedObservableObject {
        _observableObject.wrappedValue
    }

    /// A projected value which has the same properties as the wrapped value, but presented as
    /// bindings.
    ///
    /// Use this to pass bindings down the view hierarchy:
    /// ```swift
    /// struct ExampleView: View {
    ///     @Store var viewModel = Factory.shared.resolve(ViewModelProtocol.self)
    ///
    ///     var body: some View {
    ///         TextField("username", text: $viewModel.username)
    ///     }
    /// }
    /// ```
    var projectedValue: Wrapper {
        Wrapper(self)
    }

    /// Create a stored value on a custom scheduler.
    ///
    /// Use this init to schedule updates on a specific scheduler other than `DispatchQueue.main`.
    init<S: Scheduler>(wrappedValue: ObjectType,
                              on scheduler: S,
                              schedulerOptions: S.SchedulerOptions? = nil)
    {
        self.wrappedValue = wrappedValue

        if let observable = wrappedValue as? AnyObservableObject {
            let objectWillChange = observable.objectWillChange
                .receive(on: scheduler, options: schedulerOptions)
                .eraseToAnyPublisher()
            _observableObject = .init(initialValue: .init(objectWillChange: objectWillChange))
        } else {
            assertionFailure(
                "Only use the Store property wrapper with objects conforming to AnyObservableObject."
            )
            _observableObject = .init(initialValue: .empty())
        }
    }

    /// Create a stored value which publishes on the main thread.
    ///
    /// To control when updates are published, see ``init(wrappedValue:on:schedulerOptions:)``.
    init(wrappedValue: ObjectType) {
        self.init(wrappedValue: wrappedValue, on: DispatchQueue.main)
    }

    /// An equivalent to SwiftUI's
    /// [`ObservedObject.Wrapper`](https://developer.apple.com/documentation/swiftui/observedobject/wrapper)
    /// type.
    @dynamicMemberLookup
    struct Wrapper {
        private var store: Store

        init(_ store: Store<ObjectType>) {
            self.store = store
        }

        /// Returns a binding to the resulting value of a given key path.
        subscript<Subject>(
            dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>
        ) -> Binding<Subject> {
            Binding {
                self.store.wrappedValue[keyPath: keyPath]
            } set: {
                self.store.wrappedValue[keyPath: keyPath] = $0
            }
        }
    }
}

extension Store: DynamicProperty {
    nonisolated mutating func update() {
        _observableObject.update()
    }
}
