  //
//  Persistable.swift
//  Kinvey
//
//  Created by Victor Barros on 2015-12-08.
//  Copyright © 2015 Kinvey. All rights reserved.
//

import Foundation
import CoreData
import ObjectMapper
import RealmSwift

public typealias Map = ObjectMapper.Map
infix operator <- : DefaultPrecedence

/// Protocol that turns a NSObject into a persistable class to be used in a `DataStore`.
public protocol Persistable: Mappable {
    
    /// Provides the collection name to be matched with the backend.
    static func collectionName() -> String
    
    /// Default Constructor.
    init()
    
    /// Override this method to tell how to map your own objects.
    mutating func propertyMapping(_ map: Map)
    
}

private func kinveyMappingType(left: String, right: String) {
    let currentThread = Thread.current
    if var kinveyMappingType = currentThread.threadDictionary[KinveyMappingTypeKey] as? [String : [String : String]],
        let className = kinveyMappingType.first?.0,
        var classMapping = kinveyMappingType[className]
    {
        classMapping[left] = right
        kinveyMappingType[className] = classMapping
        currentThread.threadDictionary[KinveyMappingTypeKey] = kinveyMappingType
    }
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- <T>(left: inout T, right: (String, Map)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    left <- right.1
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- <T>(left: inout T?, right: (String, Map)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    left <- right.1
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- <T>(left: inout T!, right: (String, Map)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    left <- right.1
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- <T: Mappable>(left: inout T, right: (String, Map)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    left <- right.1
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- <T: Mappable>(left: inout T?, right: (String, Map)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    left <- right.1
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- <T: Mappable>(left: inout T!, right: (String, Map)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    left <- right.1
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- <Transform: TransformType>(left: inout Transform.Object, right: (String, Map, Transform)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    left <- (right.1, right.2)
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- <Transform: TransformType>(left: inout Transform.Object?, right: (String, Map, Transform)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    left <- (right.1, right.2)
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- <Transform: TransformType>(left: inout Transform.Object!, right: (String, Map, Transform)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    left <- (right.1, right.2)
}

// MARK: String Value Transform

class StringValueTransform: TransformOf<List<StringValue>, [String]> {
    init() {
        super.init(fromJSON: { (array: [String]?) -> List<StringValue>? in
            if let array = array {
                let list = List<StringValue>()
                for item in array {
                    list.append(StringValue(item))
                }
                return list
            }
            return nil
        }, toJSON: { (list: List<StringValue>?) -> [String]? in
            if let list = list {
                return list.map { $0.value }
            }
            return nil
        })
    }
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- (left: List<StringValue>, right: (String, Map)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    var list = left
    switch right.1.mappingType {
    case .toJSON:
        list <- (right.1, StringValueTransform())
    case .fromJSON:
        list <- (right.1, StringValueTransform())
        left.removeAll()
        left.append(objectsIn: list)
    }
}

// MARK: Int Value Transform

class IntValueTransform: TransformOf<List<IntValue>, [Int]> {
    init() {
        super.init(fromJSON: { (array: [Int]?) -> List<IntValue>? in
            if let array = array {
                let list = List<IntValue>()
                for item in array {
                    list.append(IntValue(item))
                }
                return list
            }
            return nil
        }, toJSON: { (list: List<IntValue>?) -> [Int]? in
            if let list = list {
                return list.map { $0.value }
            }
            return nil
        })
    }
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- (left: List<IntValue>, right: (String, Map)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    var list = left
    switch right.1.mappingType {
    case .toJSON:
        list <- (right.1, IntValueTransform())
    case .fromJSON:
        list <- (right.1, IntValueTransform())
        left.removeAll()
        left.append(objectsIn: list)
    }
}

// MARK: Float Value Transform

class FloatValueTransform: TransformOf<List<FloatValue>, [Float]> {
    init() {
        super.init(fromJSON: { (array: [Float]?) -> List<FloatValue>? in
            if let array = array {
                let list = List<FloatValue>()
                for item in array {
                    list.append(FloatValue(item))
                }
                return list
            }
            return nil
        }, toJSON: { (list: List<FloatValue>?) -> [Float]? in
            if let list = list {
                return list.map { $0.value }
            }
            return nil
        })
    }
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- (left: List<FloatValue>, right: (String, Map)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    var list = left
    switch right.1.mappingType {
    case .toJSON:
        list <- (right.1, FloatValueTransform())
    case .fromJSON:
        list <- (right.1, FloatValueTransform())
        left.removeAll()
        left.append(objectsIn: list)
    }
}

// MARK: Double Value Transform

class DoubleValueTransform: TransformOf<List<DoubleValue>, [Double]> {
    init() {
        super.init(fromJSON: { (array: [Double]?) -> List<DoubleValue>? in
            if let array = array {
                let list = List<DoubleValue>()
                for item in array {
                    list.append(DoubleValue(item))
                }
                return list
            }
            return nil
        }, toJSON: { (list: List<DoubleValue>?) -> [Double]? in
            if let list = list {
                return list.map { $0.value }
            }
            return nil
        })
    }
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- (left: List<DoubleValue>, right: (String, Map)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    var list = left
    switch right.1.mappingType {
    case .toJSON:
        list <- (right.1, DoubleValueTransform())
    case .fromJSON:
        list <- (right.1, DoubleValueTransform())
        left.removeAll()
        left.append(objectsIn: list)
    }
}

// MARK: Bool Value Transform

class BoolValueTransform: TransformOf<List<BoolValue>, [Bool]> {
    init() {
        super.init(fromJSON: { (array: [Bool]?) -> List<BoolValue>? in
            if let array = array {
                let list = List<BoolValue>()
                for item in array {
                    list.append(BoolValue(item))
                }
                return list
            }
            return nil
        }, toJSON: { (list: List<BoolValue>?) -> [Bool]? in
            if let list = list {
                return list.map { $0.value }
            }
            return nil
        })
    }
}

/// Override operator used during the `propertyMapping(_:)` method.
public func <- (left: List<BoolValue>, right: (String, Map)) {
    kinveyMappingType(left: right.0, right: right.1.currentKey!)
    var list = left
    switch right.1.mappingType {
    case .toJSON:
        list <- (right.1, BoolValueTransform())
    case .fromJSON:
        list <- (right.1, BoolValueTransform())
        left.removeAll()
        left.append(objectsIn: list)
    }
}

internal let KinveyMappingTypeKey = "Kinvey Mapping Type"

extension Persistable {
    
    static func propertyMappingReverse() -> [String : [String]] {
        var results = [String : [String]]()
        for keyPair in propertyMapping() {
            var properties = results[keyPair.1]
            if properties == nil {
                properties = [String]()
            }
            properties!.append(keyPair.0)
            results[keyPair.1] = properties
        }
        guard
            results[PersistableIdKey] != nil,
            results[PersistableMetadataKey] != nil
        else {
            let isEntity = self is Entity.Type
            let hintMessage = isEntity ? "Please call super.propertyMapping() inside your propertyMapping() method." : "Please add properties in your Persistable model class to map the missing properties."
            precondition(results[PersistableIdKey] != nil, "Property \(PersistableIdKey) (PersistableIdKey) is missing in the propertyMapping() method. \(hintMessage)")
            precondition(results[PersistableMetadataKey] != nil, "Property \(PersistableMetadataKey) (PersistableMetadataKey) is missing in the propertyMapping() method. \(hintMessage)")
            fatalError(hintMessage)
        }
        return results
    }
    
    static func propertyMapping() -> [String : String] {
        let currentThread = Thread.current
        let className = StringFromClass(cls: self as! AnyClass)
        currentThread.threadDictionary[KinveyMappingTypeKey] = [className : [String : String]()]
        let obj = self.init()
        let _ = obj.toJSON()
        if let kinveyMappingType = currentThread.threadDictionary[KinveyMappingTypeKey] as? [String : [String : String]],
            let kinveyMappingClassType = kinveyMappingType[className]
        {
            return kinveyMappingClassType
        }
        return [:]
    }
    
    static func propertyMapping(_ propertyName: String) -> String? {
        return propertyMapping()[propertyName]
    }
    
    internal static func entityIdProperty() -> String {
        return propertyMappingReverse()[PersistableIdKey]!.last!
    }
    
    internal static func aclProperty() -> String? {
        return propertyMappingReverse()[PersistableAclKey]?.last
    }
    
    internal static func metadataProperty() -> String? {
        return propertyMappingReverse()[PersistableMetadataKey]?.last
    }
    
}

extension Persistable where Self: NSObject {
    
    public subscript(key: String) -> Any? {
        get {
            return self.value(forKey: key)
        }
        set {
            self.setValue(newValue, forKey: key)
        }
    }
    
    internal var entityId: String? {
        get {
            return self[type(of: self).entityIdProperty()] as? String
        }
        set {
            self[type(of: self).entityIdProperty()] = newValue
        }
    }
    
    internal var acl: Acl? {
        get {
            if let aclKey = type(of: self).aclProperty() {
                return self[aclKey] as? Acl
            }
            return nil
        }
        set {
            if let aclKey = type(of: self).aclProperty() {
                self[aclKey] = newValue
            }
        }
    }
    
    internal var metadata: Metadata? {
        get {
            if let kmdKey = type(of: self).metadataProperty() {
                return self[kmdKey] as? Metadata
            }
            return nil
        }
        set {
            if let kmdKey = type(of: self).metadataProperty() {
                self[kmdKey] = newValue
            }
        }
    }
    
}
