//
//  Entity.swift
//  Kinvey
//
//  Created by Victor Barros on 2016-06-14.
//  Copyright © 2016 Kinvey. All rights reserved.
//

import Foundation
import Realm
import RealmSwift

/// Base class for entity classes that are mapped to a collection in Kinvey.
public class Entity: Object, Persistable, BuilderType {
    
    /// Override this method and return the name of the collection for Kinvey.
    public class func collectionName() -> String {
        preconditionFailure("Method \(#function) must be overridden")
    }
    
    /// The `_id` property mapped in the Kinvey backend.
    public dynamic var entityId: String?
    
    /// The `_kmd` property mapped in the Kinvey backend.
    public dynamic var metadata: Metadata?
    
    /// The `_acl` property mapped in the Kinvey backend.
    public dynamic var acl: Acl?
    
    /// Constructor that validates if the map contains the required fields.
    public required init?(_ map: Map) {
        super.init()
    }
    
    /// Default Constructor.
    public required init() {
        super.init()
    }
    
    /**
     WARNING: This is an internal initializer not intended for public use.
     :nodoc:
     */
    public required init(realm: RLMRealm, schema: RLMObjectSchema) {
        super.init(realm: realm, schema: schema)
    }
    
    /**
     WARNING: This is an internal initializer not intended for public use.
     :nodoc:
     */
    public required init(value: AnyObject, schema: RLMSchema) {
        super.init(value: value, schema: schema)
    }
    
    /// Override this method to tell how to map your own objects.
    public func propertyMapping(map: Map) {
        entityId <- ("entityId", map[PersistableIdKey])
        metadata <- ("metadata", map[PersistableMetadataKey])
        acl <- ("acl", map[PersistableAclKey])
    }
    
    /**
     WARNING: This is an internal initializer not intended for public use.
     :nodoc:
     */
    public override class func primaryKey() -> String? {
        return entityIdProperty()
    }
    
    /**
     WARNING: This is an internal initializer not intended for public use.
     :nodoc:
     */
    public override class func ignoredProperties() -> [String] {
        var properties = [String]()
        for property in ObjCRuntime.properties(self) {
            if !(ObjCRuntime.type(property.1, isSubtypeOf: NSDate.self) ||
                ObjCRuntime.type(property.1, isSubtypeOf: NSData.self) ||
                ObjCRuntime.type(property.1, isSubtypeOf: NSString.self) ||
                ObjCRuntime.type(property.1, isSubtypeOf: RLMObjectBase.self) ||
                ObjCRuntime.type(property.1, isSubtypeOf: RLMOptionalBase.self) ||
                ObjCRuntime.type(property.1, isSubtypeOf: RLMListBase.self) ||
                ObjCRuntime.type(property.1, isSubtypeOf: RLMCollection.self))
            {
                properties.append(property.0)
            }
        }
        return properties
    }
    
}
