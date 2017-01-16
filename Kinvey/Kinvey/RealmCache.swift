//
//  RealmCache.swift
//  Kinvey
//
//  Created by Victor Barros on 2016-06-15.
//  Copyright © 2016 Kinvey. All rights reserved.
//

import Foundation
import Realm
import RealmSwift
import ObjectiveC

let typesNeedsPredicateTranslation = [
    StringValue.self.className(),
    IntValue.self.className(),
    FloatValue.self.className(),
    DoubleValue.self.className(),
    BoolValue.self.className()
]

internal class RealmCache<T: Persistable>: Cache<T> where T: NSObject {
    
    let realm: Realm
    let objectSchema: ObjectSchema
    let propertyNames: [String]
    let propertyTypes: [PropertyType]
    let propertyObjectClassNames: [String?]
    let needsPredicateTranslation: Bool
    let executor: Executor
    
    lazy var entityType = T.self as! Entity.Type
    
    required init(persistenceId: String, fileURL: URL? = nil, encryptionKey: Data? = nil, schemaVersion: UInt64) {
        if !(T.self is Entity.Type) {
            let message = "\(T.self) needs to be a Entity"
            log.severe(message)
            fatalError(message)
        }
        var configuration = Realm.Configuration()
        if let fileURL = fileURL {
            configuration.fileURL = fileURL
        }
        configuration.encryptionKey = encryptionKey
        configuration.schemaVersion = schemaVersion
        
        do {
            realm = try Realm(configuration: configuration)
        } catch {
            configuration.deleteRealmIfMigrationNeeded = true
            realm = try! Realm(configuration: configuration)
        }
        
        let className = NSStringFromClass(T.self).components(separatedBy: ".").last!
        objectSchema = realm.schema[className]!
        
        var propertyNames = [String]()
        var propertyTypes = [PropertyType]()
        var propertyObjectClassNames = [String?]()
        for property in objectSchema.properties {
            propertyNames.append(property.name)
            propertyTypes.append(property.type)
            propertyObjectClassNames.append(property.objectClassName)
        }
        self.propertyNames = propertyNames
        self.propertyTypes = propertyTypes
        self.propertyObjectClassNames = propertyObjectClassNames
        needsPredicateTranslation = !propertyObjectClassNames.filter {
            if let className = $0 {
                return typesNeedsPredicateTranslation.contains(className)
            }
            return false
        }.isEmpty
        
        executor = Executor()
        super.init(persistenceId: persistenceId)
        log.debug("Cache File: \(self.realm.configuration.fileURL!.path)")
    }
    
    func needsTranslation(expression: NSExpression) -> Bool {
        switch expression.expressionType {
        case .keyPath:
            let keyPath = expression.keyPath
            if keyPath.contains(".") {
            } else {
                if let idx = propertyNames.index(of: keyPath),
                    let className = propertyObjectClassNames[idx],
                    typesNeedsPredicateTranslation.contains(className)
                {
                    return true
                }
            }
            return false
        case .function:
            if needsTranslation(expression: expression.operand) {
                return true
            } else if let arguments = expression.arguments {
                for expression in arguments {
                    if needsTranslation(expression: expression) {
                        return true
                    }
                }
            }
            return false
        case .subquery:
            if let expression = expression.collection as? NSExpression {
                return needsTranslation(expression: expression)
            }
            return false
        default:
            return false
        }
    }
    
    func keyPathValuePairExpression(predicate: NSComparisonPredicate) -> (keyPathExpression: NSExpression, valueExpression: NSExpression)? {
        switch predicate.leftExpression.expressionType {
        case .keyPath:
            switch predicate.rightExpression.expressionType {
            case .constantValue:
                return (keyPathExpression: predicate.leftExpression, valueExpression: predicate.rightExpression)
            default:
                return nil
            }
        case .constantValue:
            switch predicate.rightExpression.expressionType {
            case .keyPath:
                return (keyPathExpression: predicate.rightExpression, valueExpression: predicate.leftExpression)
            default:
                return nil
            }
        default:
            return nil
        }
    }
    
    func variableValuePairExpression(predicate: NSComparisonPredicate) -> (variableExpression: NSExpression, expression: NSExpression)? {
        switch predicate.leftExpression.expressionType {
        case .variable:
            return (variableExpression: predicate.leftExpression, expression: predicate.rightExpression)
        default:
            switch predicate.rightExpression.expressionType {
            case .variable:
                return (variableExpression: predicate.rightExpression, expression: predicate.leftExpression)
            default:
                return nil
            }
        }
    }
    
    func translate(expression: NSExpression) -> NSExpression {
        switch expression.expressionType {
        case .keyPath:
            var keyPath = expression.keyPath
            if keyPath.contains(".") {
            } else {
                if let idx = propertyNames.index(of: keyPath),
                    let className = propertyObjectClassNames[idx],
                    typesNeedsPredicateTranslation.contains(className)
                {
                    keyPath += ".value"
                }
            }
            return NSExpression(forKeyPath: keyPath)
        case .function:
            if expression.operand.expressionType == .subquery,
                let suffix = expression.arguments?.first?.description
            {
                let subquery = translate(expression: expression.operand)
                return NSExpression(format: "\(subquery).\(suffix)")
            } else {
                switch expression.function {
                case "objectFrom:withIndex:":
                    if let keyPath = expression.arguments?.first?.description,
                        let idx = expression.arguments?.last?.description,
                        idx != "SIZE"
                    {
                        return NSExpression(format: "\(keyPath)[\(idx)].value")
                    }
                    return expression
                default:
                    return expression
                }
            }
        case .subquery:
            if let collectionExpression = expression.collection as? NSExpression,
                let subqueryPredicate = expression.predicate as? NSComparisonPredicate,
                let variableValuePairExpression = variableValuePairExpression(predicate: subqueryPredicate)
            {
                let predicate = NSComparisonPredicate(
                    leftExpression: NSExpression(forVariable: "\(variableValuePairExpression.variableExpression.variable).value"),
                    rightExpression: variableValuePairExpression.expression,
                    modifier: subqueryPredicate.comparisonPredicateModifier,
                    type: subqueryPredicate.predicateOperatorType,
                    options: subqueryPredicate.options
                )
                return NSExpression(
                    forSubquery: collectionExpression,
                    usingIteratorVariable: variableValuePairExpression.variableExpression.variable,
                    predicate: predicate
                )
            }
            return expression
        default:
            return expression
        }
    }
    
    func translate(predicate: NSPredicate) -> NSPredicate {
        if let predicate = predicate as? NSComparisonPredicate {
            let leftExpressionNeedsTranslation = needsTranslation(expression: predicate.leftExpression)
            let rightExpressionNeedsTranslation = needsTranslation(expression: predicate.rightExpression)
            if (leftExpressionNeedsTranslation || rightExpressionNeedsTranslation) {
                if predicate.predicateOperatorType == .contains, let keyPathValuePairExpression = keyPathValuePairExpression(predicate: predicate) {
                    return NSPredicate(format: "SUBQUERY(\(keyPathValuePairExpression.keyPathExpression.keyPath), $item, $item.value == %@).@count > 0", keyPathValuePairExpression.valueExpression.constantValue as! CVarArg)
                } else {
                    return NSComparisonPredicate(
                        leftExpression: translate(expression: predicate.leftExpression),
                        rightExpression: translate(expression: predicate.rightExpression),
                        modifier: predicate.comparisonPredicateModifier,
                        type: predicate.predicateOperatorType,
                        options: predicate.options
                    )
                }
            }
        }
        return predicate
    }
    
    fileprivate func results(_ query: Query) -> RealmSwift.Results<Entity> {
        log.verbose("Fetching by query: \(query)")
        var realmResults = self.realm.objects(self.entityType)
        if var predicate = query.predicate {
            if needsPredicateTranslation {
                predicate = translate(predicate: predicate)
            }
            realmResults = realmResults.filter(predicate)
        }
        if let sortDescriptors = query.sortDescriptors {
            for sortDescriptor in sortDescriptors {
                realmResults = realmResults.sorted(byProperty: sortDescriptor.key!, ascending: sortDescriptor.ascending)
            }
        }
        
        if let ttl = ttl, let kmdKey = T.metadataProperty() {
            realmResults = realmResults.filter("\(kmdKey).lrt >= %@", Date().addingTimeInterval(-ttl))
        }
        
        return realmResults
    }
    
    fileprivate func newInstance<P:Persistable>(_ type: P.Type) -> P {
        return type.init()
    }

    fileprivate func detach(_ entity: Object, props: [String]) -> Object {
        log.verbose("Detaching object: \(entity)")
        
        var json: Dictionary<String, Any>
        let obj = type(of:entity).init()
        
        json = entity.dictionaryWithValues(forKeys: props)
        
        for property in json.keys {
            let value = json[property]
                
            if let value = value as? Object {
                
                let nestedClassName = StringFromClass(cls: type(of:value)).components(separatedBy: ".").last!
                let nestedObjectSchema = realm.schema[nestedClassName]
                let nestedProperties = nestedObjectSchema?.properties.map {
                    return $0.name
                }
                    
                json[property] = self.detach(value, props: nestedProperties!)
            }
        }
            
        obj.setValuesForKeys(json)
            
        return obj

    }
    
    override func detach(_ results: [T], query: Query?) -> [T] {
        log.verbose("Detaching \(results.count) object(s)")
        var detachedResults = [T]()
        let skip = query?.skip ?? 0
        let limit = query?.limit ?? results.count
        var arrayEnumerate: [T]
        if skip != 0 || limit != results.count {
            let begin = max(min(skip, results.count), 0)
            let end = max(min(skip + limit, results.count), 0)
            arrayEnumerate = Array<T>(results[begin ..< end])
        } else {
            arrayEnumerate = results
        }
        for entity in arrayEnumerate {
            if let entity = entity as? Object {
                detachedResults.append(detach(entity, props: self.propertyNames) as! T)
            }
        }
        return detachedResults
    }
    
    func detach(_ results: RealmSwift.Results<Entity>, query: Query?) -> [T] {
        return detach(results.map { $0 as! T }, query: query)
    }
    
    override func saveEntity(_ entity: T) {
        log.verbose("Saving object: \(entity)")
        executor.executeAndWait {
            try! self.realm.write {
                self.realm.create((type(of: entity) as! Entity.Type), value: entity, update: true)
            }
        }
    }
    
    override func saveEntities(_ entities: [T]) {
        log.verbose("Saving \(entities.count) object(s)")
        executor.executeAndWait {
            try! self.realm.write {
                for entity in entities {
                    self.realm.create((type(of: entity) as! Entity.Type), value: entity, update: true)
                }
            }
        }
    }
    
    override func findEntity(_ objectId: String) -> T? {
        log.verbose("Finding object by ID: \(objectId)")
        var result: T?
        executor.executeAndWait {
            result = self.realm.object(ofType: self.entityType, forPrimaryKey: objectId) as? T
            if result != nil {
                if let resultObj = result as? Object {
                    result = self.detach(resultObj, props: self.propertyNames) as? T
                }
            }
        }
        return result
    }
    
    override func findEntityByQuery(_ query: Query) -> [T] {
        log.verbose("Finding objects by query: \(query)")
        var results = [T]()
        executor.executeAndWait {
            results = self.detach(self.results(query), query: query)
        }
        return results
    }
    
    override func findIdsLmtsByQuery(_ query: Query) -> [String : String] {
        log.verbose("Finding ids and lmts by query: \(query)")
        var results = [String : String]()
        executor.executeAndWait {
            for entity in self.results(Query(predicate: query.predicate)) {
                if let entityId = entity.entityId, let lmt = entity.metadata?.lmt {
                    results[entityId] = lmt
                }
            }
        }
        return results
    }
    
    override func findAll() -> [T] {
        log.verbose("Finding All")
        var results = [T]()
        executor.executeAndWait {
            results = self.detach(self.realm.objects(self.entityType), query: nil)
        }
        return results
    }
    
    override func count(_ query: Query? = nil) -> Int {
        log.verbose("Counting by query: \(query)")
        var result = 0
        executor.executeAndWait {
            if let query = query {
                result = self.results(query).count
            } else {
                result = self.realm.objects(self.entityType).count
            }
        }
        return result
    }
    
    override func removeEntity(_ entity: T) -> Bool {
        log.verbose("Removing object: \(entity)")
        var result = false
        if let entityId = entity.entityId {
            executor.executeAndWait {
                var found = false
                try! self.realm.write {
                    if let entity = self.realm.object(ofType: (type(of: entity) as! Entity.Type), forPrimaryKey: entityId) {
                        self.realm.delete(entity)
                        found = true
                    }
                }
                result = found
            }
        }
        return result
    }
    
    override func removeEntities(_ entities: [T]) -> Bool {
        log.verbose("Removing objects: \(entities)")
        var result = false
        executor.executeAndWait {
            try! self.realm.write {
                for entity in entities {
                    let entity = self.realm.object(ofType: type(of: entity) as! Entity.Type, forPrimaryKey: entity.entityId!)
                    if let entity = entity {
                        self.realm.delete(entity)
                        result = true
                    }
                }
            }
        }
        return result
    }
    
    override func removeEntitiesByQuery(_ query: Query) -> Int {
        log.verbose("Removing objects by query: \(query)")
        var result = 0
        executor.executeAndWait {
            try! self.realm.write {
                let results = self.results(query)
                result = results.count
                self.realm.delete(results)
            }
        }
        return result
    }
    
    override func removeAllEntities() {
        log.verbose("Removing all objects")
        executor.executeAndWait {
            try! self.realm.write {
                self.realm.delete(self.realm.objects(self.entityType))
            }
        }
    }
    
}

internal class RealmPendingOperation: Object, PendingOperationType {
    
    dynamic var requestId: String
    dynamic var date: Date
    
    dynamic var collectionName: String
    dynamic var objectId: String?
    
    dynamic var method: String
    dynamic var url: String
    dynamic var headers: Data
    dynamic var body: Data?
    
    init(request: URLRequest, collectionName: String, objectId: String?) {
        date = Date()
        requestId = request.value(forHTTPHeaderField: .requestId)!
        self.collectionName = collectionName
        self.objectId = objectId
        method = request.httpMethod ?? "GET"
        url = request.url!.absoluteString
        headers = try! JSONSerialization.data(withJSONObject: request.allHTTPHeaderFields!, options: [])
        body = request.httpBody
        super.init()
    }
    
    required init() {
        date = Date()
        requestId = ""
        collectionName = ""
        method = ""
        url = ""
        headers = Data()
        super.init()
    }
    
    required init(value: Any, schema: RLMSchema) {
        date = Date()
        requestId = ""
        collectionName = ""
        method = ""
        url = ""
        headers = Data()
        super.init(value: value, schema: schema)
    }
    
    required init(realm: RLMRealm, schema: RLMObjectSchema) {
        date = Date()
        requestId = ""
        collectionName = ""
        method = ""
        url = ""
        headers = Data()
        super.init(realm: realm, schema: schema)
    }
    
    func buildRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.allHTTPHeaderFields = try? JSONSerialization.jsonObject(with: headers, options: []) as! [String : String]
        if let body = body {
            request.httpBody = body
        }
        return request
    }
    
    override class func primaryKey() -> String? {
        return "requestId"
    }
    
}
