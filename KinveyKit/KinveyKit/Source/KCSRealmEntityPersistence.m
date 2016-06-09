//
//  KCSRealmManager.m
//  Kinvey
//
//  Created by Victor Barros on 2015-12-16.
//  Copyright © 2015 Kinvey. All rights reserved.
//

#import "KCSRealmEntityPersistence.h"

@import Realm;
@import Foundation;
@import MapKit;

#import "KCS_CLLocation_Realm.h"

#import "KinveyUser.h"
#import "KCSUserRealm.h"

#import "KCSFile.h"
#import "KCSFileRealm.h"

#import "KCSAclRealm.h"

#import "NSValueTransformer+Kinvey.h"
#import "KCS_CLLocation_Realm_ValueTransformer.h"
#import "KCS_NSArray_CLLocation_NSValueTransformer.h"
#import "KCS_NSArray_KCS_CLLocation_Realm_NSValueTransformer.h"
#import "KCS_NSURL_NSString_NSValueTransformer.h"
#import "KCS_UIImage_NSData_NSValueTransformer.h"
#import "KCS_NSString_NSDate_NSValueTransformer.h"
#import "KinveyPersistable.h"

#import "KCSObjcRuntime.h"
@import ObjectiveC;

#import "KinveyCoreInternal.h"

#import "KCSQueryAdapter.h"
#import "KCSCache.h"
#import "KCSPendingOperationRealm.h"
#import <Kinvey/Kinvey-Swift.h>
#import "KNVKinvey.h"

#define KCSEntityKeyAcl @"_acl"
#define KCSEntityKeyLastRetrievedTime @"lrt"

@protocol PersistableSwift <NSObject>

+(NSString*)kinveyCollectionName;
+(NSDictionary<NSString*, NSString*>*)kinveyPropertyMapping;

-(void)loadFromJson:(NSDictionary<NSString*, NSObject*>*)json;
-(NSDictionary<NSString*, NSObject*>*)toJson;

@end

@interface KCSRealmEntityPersistence () <__KNVCache, __KNVSync>

@property (nonatomic, strong) RLMRealmConfiguration* realmConfiguration;
@property (nonatomic, readonly) RLMRealm* realm;
@property (nonatomic, strong) Class clazz;

@end

@implementation KCSRealmEntityPersistence

@synthesize persistenceId = _persistenceId;
@synthesize collectionName = _collectionName;
@synthesize ttl = _ttl;

static NSMutableDictionary<NSString*, NSString*>* collectionNamesMap = nil;
static NSMutableDictionary<NSString*, NSString*>* classMapOriginalRealm = nil;
static NSMutableDictionary<NSString*, NSMutableSet<NSString*>*>* classMapRealmOriginal = nil;
static NSMutableDictionary<NSString*, NSSet<NSString*>*>* realmClassProperties = nil;
static NSMutableDictionary<NSString*, NSMutableDictionary<NSString*, NSValueTransformer*>*>* valueTransformerMap = nil;

+(void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        assert([NSThread isMainThread]);
        
        collectionNamesMap = [NSMutableDictionary dictionary];
        classMapOriginalRealm = [NSMutableDictionary dictionary];
        classMapRealmOriginal = [NSMutableDictionary dictionary];
        valueTransformerMap = [NSMutableDictionary dictionary];
        
        //Collections
        
        [self registerOriginalClass:[NSArray class]
                         realmClass:[RLMArray class]];
        
        [self registerOriginalClass:[NSMutableArray class]
                         realmClass:[RLMArray class]];
        
        [self registerOriginalClass:[NSSet class]
                         realmClass:[RLMArray class]];
        
        [self registerOriginalClass:[NSMutableSet class]
                         realmClass:[RLMArray class]];
        
        [self registerOriginalClass:[NSOrderedSet class]
                         realmClass:[RLMArray class]];
        
        [self registerOriginalClass:[NSMutableOrderedSet class]
                         realmClass:[RLMArray class]];
        
        [self registerOriginalClass:[NSDictionary class]
                         realmClass:[NSDictionary class]];
        
        [self registerOriginalClass:[NSMutableDictionary class]
                         realmClass:[NSMutableDictionary class]];
        
        //NSString
        
        [self registerOriginalClass:[NSString class]
                         realmClass:[NSString class]];
        
        [self registerOriginalClass:[NSMutableString class]
                         realmClass:[NSMutableString class]];
        
        [self registerOriginalClass:[NSURL class]
                         realmClass:[NSString class]];
        
        //NSData
        
        [self registerOriginalClass:[NSData class]
                         realmClass:[NSData class]];
        
#if TARGET_OS_IOS
        [self registerOriginalClass:[UIImage class]
                         realmClass:[NSData class]];
#endif
        
        //NSDate
        
        [self registerOriginalClass:[NSDate class]
                         realmClass:[NSDate class]];
        
        //NSNumber
        
        [self registerOriginalClass:[NSNumber class]
                         realmClass:[NSNumber class]];
        
        //CLLocation
        
        [self registerOriginalClass:[CLLocation class]
                         realmClass:[KCS_CLLocation_Realm class]];
        
        //Kinvey Classes
        
        [self registerOriginalClass:[KCSUser class]
                         realmClass:[KCSUserRealm class]];
        
        [self registerOriginalClass:[KCSFile class]
                         realmClass:[KCSFileRealm class]];
        
        [self registerOriginalClass:[KCSMetadata class]
                         realmClass:[KCSMetadataRealm class]];
        
        [self registerOriginalClass:[KNVMetadata class]
                         realmClass:[KCSMetadataRealm class]];
        
        realmClassProperties = [NSMutableDictionary dictionary];
        
        [self registerRealmClassProperties:[KCSUserRealm class]];
        [self registerRealmClassProperties:[KCSFileRealm class]];
        [self registerRealmClassProperties:[KCSMetadataRealm class]];
        [self registerRealmClassProperties:[KCSAclRealm class]];
        [self registerRealmClassProperties:[KCS_CLLocation_Realm class]];
        
        [NSValueTransformer setValueTransformer:[KCS_CLLocation_Realm_ValueTransformer sharedInstance]
                                      fromClass:[CLLocation class]
                                        toClass:[KCS_CLLocation_Realm_ValueTransformer transformedValueClass]];
        
        [NSValueTransformer setValueTransformer:[KCS_NSArray_CLLocation_NSValueTransformer sharedInstance]
                                      fromClass:[NSArray class]
                                        toClass:[KCS_NSArray_CLLocation_NSValueTransformer transformedValueClass]];
        
        [NSValueTransformer setValueTransformer:[KCS_NSArray_KCS_CLLocation_Realm_NSValueTransformer sharedInstance]
                                      fromClass:[NSArray class]
                                        toClass:[KCS_NSArray_KCS_CLLocation_Realm_NSValueTransformer transformedValueClass]];
        
        [NSValueTransformer setValueTransformer:[KCS_NSURL_NSString_NSValueTransformer sharedInstance]
                                      fromClass:[NSURL class]
                                        toClass:[KCS_NSURL_NSString_NSValueTransformer transformedValueClass]];

#if TARGET_OS_IOS
        [NSValueTransformer setValueTransformer:[KCS_UIImage_NSData_NSValueTransformer sharedInstance]
                                      fromClass:[UIImage class]
                                        toClass:[KCS_UIImage_NSData_NSValueTransformer transformedValueClass]];
#endif
        
        [NSValueTransformer setValueTransformer:[KCS_NSString_NSDate_NSValueTransformer sharedInstance]
                                      fromClass:[NSString class]
                                        toClass:[KCS_NSString_NSDate_NSValueTransformer transformedValueClass]];
        
        unsigned int classesCount;
        Class* classes = objc_copyClassList(&classesCount);
        Class class = nil;
        NSSet<NSString*>* ignoreClasses = [NSSet setWithArray:@[@"NSObject", @"KCSFile", @"KCSUser", @"KCSUser2", @"KCSMetadata"]];
        NSString* className = nil;
        for (unsigned int i = 0; i < classesCount; i++) {
            class = classes[i];
            if (!class_conformsToProtocol(class, @protocol(KCSPersistable)) &&
                ![self conformsToPersistableSwiftProtocol:class]) continue;
            className = NSStringFromClass(class);
            if ([ignoreClasses containsObject:className]) continue;
            if (classMapOriginalRealm[className]) continue;
            
            [self createRealmClass:class];
        }
        free(classes);
    });
}

+(BOOL)conformsToPersistableSwiftProtocol:(Class)class
{
    return class_getClassMethod(class, @selector(kinveyCollectionName)) &&
    class_getClassMethod(class, @selector(kinveyPropertyMapping)) &&
    class_getMethodImplementation(class, @selector(loadFromJson:)) &&
    class_getMethodImplementation(class, @selector(toJson));
}

+(void)registerOriginalClass:(Class)originalClass
                  realmClass:(Class)realmClass
{
    [self registerOriginalClassName:NSStringFromClass(originalClass)
                     realmClassName:NSStringFromClass(realmClass)];
}

+(void)registerOriginalClassName:(NSString*)originalClassName
                  realmClassName:(NSString*)realmClassName
{
    classMapOriginalRealm[originalClassName] = realmClassName;
    NSMutableSet<NSString*>* originalClassNames = classMapRealmOriginal[realmClassName];
    if (!originalClassNames) originalClassNames = [NSMutableSet setWithCapacity:1];
    [originalClassNames addObject:originalClassName];
    classMapRealmOriginal[realmClassName] = originalClassNames;
}

+(void)registerRealmClassProperties:(Class)realmClass
{
    realmClassProperties[NSStringFromClass(realmClass)] = [KCSObjcRuntime propertyNamesForClass:realmClass];
}

+(void)registerValueTransformer:(NSValueTransformer*)valueTransformer
                       forClass:(Class)class
                   propertyName:(NSString*)propertyName
{
    [self registerValueTransformer:valueTransformer
                      forClassName:NSStringFromClass(class)
                      propertyName:propertyName];
}

+(void)registerValueTransformer:(NSValueTransformer*)valueTransformer
                   forClassName:(NSString*)className
                   propertyName:(NSString*)propertyName
{
    NSMutableDictionary<NSString*, NSValueTransformer*>* propertyMap = valueTransformerMap[className];
    if (!propertyMap) {
        propertyMap = [NSMutableDictionary dictionary];
        valueTransformerMap[className] = propertyMap;
    }
    propertyMap[propertyName] = valueTransformer;
}

+(Class)createRealmClass:(Class)clazz
{
    NSString* className = [NSString stringWithUTF8String:class_getName(clazz)];
    if (![clazz respondsToSelector:@selector(kinveyCollectionName)]) {
        return nil;
    }
    collectionNamesMap[[clazz kinveyCollectionName]] = className;
    
    NSString* realmClassName = [KNVRealmEntitySchema realmClassNameForClass:clazz];
    Class realmClass = objc_allocateClassPair([RLMObject class], realmClassName.UTF8String, 0);
    
    if (classMapOriginalRealm[className]) return NSClassFromString(classMapOriginalRealm[className]);
    
    [self registerOriginalClass:clazz
                     realmClass:realmClass];
    
    [self copyPropertiesFromClass:clazz
                          toClass:realmClass];
    
    [self createKmdToClass:realmClass];
    
    objc_registerClassPair(realmClass);
    
    [self registerRealmClassProperties:realmClass];
    
    [self createPrimaryKeyMethodFromClass:clazz
                                  toClass:realmClass];
    
    return realmClass;
}

+(void)createAclToClass:(Class)toClass
{
    objc_property_attribute_t type = { "T", [NSString stringWithFormat:@"@\"%@\"", NSStringFromClass([KCSAclRealm  class])].UTF8String };
    objc_property_attribute_t ownership = { "C", "" }; // C = copy
    objc_property_attribute_t backingivar = { "V", [NSString stringWithFormat:@"_%@", KCSEntityKeyAcl].UTF8String };
    objc_property_attribute_t attrs[] = { type, ownership, backingivar };
    BOOL added = class_addProperty(toClass, KCSEntityKeyAcl.UTF8String, attrs, 3);
    assert(added);
}

+(void)createKmdToClass:(Class)toClass
{
    NSSet<NSString*> *properties = [KCSObjcRuntime propertyNamesForClass:toClass];
    if (![properties containsObject:KCSEntityKeyMetadata]) {
        objc_property_attribute_t type = { "T", [NSString stringWithFormat:@"@\"%@\"", NSStringFromClass([KCSMetadataRealm class])].UTF8String };
        objc_property_attribute_t backingivar = { "V", [NSString stringWithFormat:@"_%@", KCSEntityKeyMetadata].UTF8String };
        objc_property_attribute_t attrs[] = { type, backingivar };
        BOOL added = class_addProperty(toClass, KCSEntityKeyMetadata.UTF8String, attrs, 2);
        assert(added);
    }
}

+(void)copyPropertiesFromClass:(Class)fromClass
                       toClass:(Class)toClass
{
    unsigned int propertyCount;
    objc_property_t *properties = class_copyPropertyList(fromClass, &propertyCount);
    NSSet<NSString*>* ignoreClasses = [NSSet setWithArray:@[@"NSDictionary", @"NSMutableDictionary", @"NSAttributedString", @"NSMutableAttributedString"]];
    NSSet<NSString*>* subtypeRequiredClasses = [NSSet setWithArray:@[@"NSArray", @"NSMutableArray", @"NSSet", @"NSMutableSet", @"NSOrderedSet", @"NSMutableOrderedSet", @"NSNumber"]];
    NSRegularExpression* regexClassName = [NSRegularExpression regularExpressionWithPattern:@"@\"(\\w+)(?:<(\\w+)>)?\""
                                                                                    options:0
                                                                                      error:nil];
    NSArray<NSTextCheckingResult*>* matches = nil;
    NSTextCheckingResult* textCheckingResult = nil;
    NSValueTransformer* valueTransformer = nil;
    NSRange range;
    NSString *attributeValue = nil, *propertyName = nil, *className = nil, *subtypeName = nil, *realmClassName = nil;
    objc_property_t property;
    unsigned int attributeCount;
    objc_property_attribute_t *attributes = nil;
    objc_property_attribute_t attribute;
    BOOL ignoreProperty;
    for (int i = 0; i < propertyCount; i++) {
        property = properties[i];
        propertyName = [NSString stringWithUTF8String:property_getName(property)];
        attributeCount = 0;
        attributes = property_copyAttributeList(property, &attributeCount);
        ignoreProperty = NO;
        className = nil;
        for (unsigned int i = 0; i < attributeCount; i++) {
            attribute = attributes[i];
            switch (attribute.name[0]) {
                case 'T':
                    switch (attribute.value[0]) {
                        case 'c':
                            break;
                        case 'i':
                            break;
                        case 's':
                            break;
                        case 'l':
                            break;
                        case 'q':
                            break;
                        case 'C':
                            break;
                        case 'I':
                            break;
                        case 'S':
                            break;
                        case 'L':
                            break;
                        case 'Q': { //unsigned long long
                            ignoreProperty = YES;
                            KCSLogWarn(KCS_LOG_CONTEXT_DATA, @"Data type not supported: [%@ %@]", NSStringFromClass(fromClass), propertyName);
                            break;
                        }
                        case 'f':
                            break;
                        case 'd':
                            break;
                        case 'B':
                            break;
                        case '@':
                            attributeValue = [NSString stringWithUTF8String:attribute.value];
                            matches = [regexClassName matchesInString:attributeValue
                                                              options:0
                                                                range:NSMakeRange(0, attributeValue.length)];
                            if (matches.count > 0 &&
                                matches.firstObject.numberOfRanges > 1 &&
                                [matches.firstObject rangeAtIndex:1].location != NSNotFound)
                            {
                                textCheckingResult = matches.firstObject;
                                className = [attributeValue substringWithRange:[textCheckingResult rangeAtIndex:1]];
                                range = [textCheckingResult rangeAtIndex:2];
                                subtypeName = range.location != NSNotFound ? [attributeValue substringWithRange:range] : nil;
                                if ([ignoreClasses containsObject:className]) {
                                    ignoreProperty = YES;
                                    KCSLogWarn(KCS_LOG_CONTEXT_DATA, @"Data type not supported: [%@ %@] (%@)", NSStringFromClass(fromClass), propertyName, className);
                                } else if ([subtypeRequiredClasses containsObject:className] &&
                                           subtypeName == nil)
                                {
                                    ignoreProperty = YES;
                                    KCSLogWarn(KCS_LOG_CONTEXT_DATA, @"Data type requires a subtype: [%@ %@] (%@)", NSStringFromClass(fromClass), propertyName, className);
                                } else {
                                    realmClassName = classMapOriginalRealm[className];
                                    if ([className isEqualToString:realmClassName]) {
                                        valueTransformer = nil;
                                    } else {
                                        valueTransformer = [NSValueTransformer valueTransformerFromClassName:className
                                                                                                 toClassName:realmClassName];
                                    }
                                    if (valueTransformer) {
                                        [self registerValueTransformer:valueTransformer
                                                              forClass:fromClass
                                                          propertyName:propertyName];
                                    } else if (classMapOriginalRealm[className] == nil) {
                                        realmClassName = NSStringFromClass([self createRealmClass:NSClassFromString(className)]);
                                        if (!realmClassName) {
                                            if (class_conformsToProtocol(NSClassFromString(className), @protocol(KNVJsonObject))) {
                                                realmClassName = @"NSString"; //Json
                                            } else if (class_conformsToProtocol(NSClassFromString(className), @protocol(NSCoding))) {
                                                realmClassName = @"NSString"; //NSData as Base64
                                            }
                                        }
                                    }
                                    if (realmClassName) {
                                        if (subtypeName) {
                                            attribute.value = [NSString stringWithFormat:@"@\"%@<%@>\"", realmClassName, classMapOriginalRealm[subtypeName] ?  classMapOriginalRealm[subtypeName] : subtypeName].UTF8String;
                                        } else {
                                            attribute.value = [NSString stringWithFormat:@"@\"%@\"", realmClassName].UTF8String;
                                        }
                                        attributes[i] = attribute;
                                    } else {
                                        ignoreProperty = YES;
                                    }
                                }
                            }
                            break;
                        default:
                            break;
                    }
                    break;
                case 'R':
                    ignoreProperty = YES;
                    break;
                default:
                    break;
            }
        }
        if (!ignoreProperty) {
            BOOL added = class_addProperty(toClass, propertyName.UTF8String, attributes, attributeCount);
            assert(added);
        }
        free(attributes);
    }
    free(properties);
}

+(void)createPrimaryKeyMethodFromClass:(Class)fromClass
                               toClass:(Class)toClass
{
    NSString* primaryKey = nil;
    NSDictionary<NSString*, NSString*>* propertyMapping = nil;
    if ([self conformsToPersistableSwiftProtocol:fromClass]) {
        propertyMapping = [fromClass kinveyPropertyMapping];
    } else {
        @try {
            id<KCSPersistable> sampleObj = [[fromClass alloc] init];
            propertyMapping = [sampleObj hostToKinveyPropertyMapping];
        } @catch (NSException *exception) {
            //do nothing!
        }
    }
    if (propertyMapping) {
        NSString* value;
        for (NSString* key in propertyMapping) {
            value = propertyMapping[key];
            if ([value isEqualToString:KCSEntityKeyId]) {
                primaryKey = key;
                break;
            }
        }
    }
    
    if (!primaryKey) {
        primaryKey = KCSEntityKeyId;
        objc_property_attribute_t type = { "T", "@\"NSString\"" };
        objc_property_attribute_t ownership = { "C", "" }; // C = copy
        objc_property_attribute_t backingivar  = { "V", [NSString stringWithFormat:@"_%@", primaryKey].UTF8String };
        objc_property_attribute_t attrs[] = { type, ownership, backingivar };
        BOOL added = class_addProperty(toClass, primaryKey.UTF8String, attrs, 3);
        if (!added) {
            class_replaceProperty(toClass, primaryKey.UTF8String, attrs, 3);
        }
    }
    
    SEL sel = @selector(primaryKey);
    IMP imp = imp_implementationWithBlock(^NSString*(Class class) {
        return primaryKey;
    });
    Method method = class_getClassMethod(toClass, sel);
    const char* className = class_getName(toClass);
    Class metaClass = objc_getMetaClass(className);
    BOOL added = class_addMethod(metaClass, sel, imp, method_getTypeEncoding(method));
    assert(added);
}

+(Class)realmClassForClass:(Class)class
{
    Class clazz = NSClassFromString(classMapOriginalRealm[NSStringFromClass(class)]);
    if (!clazz && [class isSubclassOfClass:[RLMObject class]]) {
        clazz = class;
    }
    return clazz;
}

-(RLMRealm *)realm
{
    NSError* error = nil;
    RLMRealm* realm = [RLMRealm realmWithConfiguration:self.realmConfiguration
                                                 error:&error];
    if (error) {
        @throw error;
    }
    [realm refresh];
    return realm;
}

static inline void saveEntity(NSDictionary<NSString *,id> *entity, RLMRealm* realm, Class realmClass)
{
    RLMObject* obj = [realmClass createOrUpdateInRealm:realm
                                             withValue:entity];
    assert(obj);
}

#pragma mark - Cache

+(RLMRealmConfiguration*)configurationForPersistenceId:(NSString *)persistenceId
{
    return [self configurationForPersistenceId:persistenceId
                                      filePath:nil
                                 encryptionKey:nil];
}

+(RLMRealmConfiguration*)configurationForPersistenceId:(NSString *)persistenceId
                                              filePath:(NSString *)filePath
                                         encryptionKey:(NSData*)encryptionKey
{
    RLMRealmConfiguration* realmConfiguration = [RLMRealmConfiguration defaultConfiguration];
    
    if (filePath) {
        realmConfiguration.fileURL = [NSURL fileURLWithPath:filePath];
    } else {
        NSString* path = [realmConfiguration.fileURL.path.stringByDeletingLastPathComponent stringByAppendingPathComponent:persistenceId];
        NSFileManager* fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:path]) {
            NSError *error = nil;
            BOOL created = [fileManager createDirectoryAtPath:path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
            if (!created && error) {
                NSLog(@"%@", error);
            }
        }
        path = [path stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.realm", [__KNVClient defaultTag]]];
        realmConfiguration.fileURL = [NSURL fileURLWithPath:path];
    }
    
    NSLog(@"Database Path: %@", realmConfiguration.fileURL.path);
    
    if (encryptionKey) {
        realmConfiguration.encryptionKey = encryptionKey;
    }
    
    return realmConfiguration;
}

-(instancetype)initWithPersistenceId:(NSString *)persistenceId
                      collectionName:(NSString *)collectionName
{
    return [self initWithPersistenceId:persistenceId
                        collectionName:collectionName
                              filePath:nil
                         encryptionKey:nil];
}

-(instancetype)initWithPersistenceId:(NSString *)persistenceId
                      collectionName:(NSString *)collectionName
                            filePath:(NSString *)filePath
                       encryptionKey:(NSData*)encryptionKey
{
    self = [super init];
    if (self) {
        self.persistenceId = persistenceId;
        self.collectionName = collectionName;
        self.clazz = collectionName ? NSClassFromString(collectionNamesMap[self.collectionName]) : nil;
        
        self.realmConfiguration = [self.class configurationForPersistenceId:persistenceId
                                                                   filePath:filePath
                                                              encryptionKey:encryptionKey];
        assert(self.realm);
    }
    return self;
}

-(void)saveEntity:(NSDictionary<NSString *,id> *)entity
{
    Class realmClass = [[self class] realmClassForClass:self.clazz];
    RLMRealm* realm = self.realm;
    [realm transactionWithBlock:^{
        saveEntity(entity, realm, realmClass);
    }];
}

-(void)saveEntities:(NSArray<NSDictionary<NSString *,id> *> *)entities
{
    Class realmClass = [[self class] realmClassForClass:self.clazz];
    RLMRealm* realm = self.realm;
    [realm transactionWithBlock:^{
        for (NSDictionary<NSString*, id>* entity in entities) {
            saveEntity(entity, realm, realmClass);
        }
    }];
}

-(BOOL)removeEntity:(NSDictionary<NSString *, id> *)entity
{
    return [self removeEntity:entity
                     forClass:self.clazz];
}

-(BOOL)removeEntity:(NSDictionary<NSString *, id> *)entity
           forClass:(Class)class
{
    NSDictionary<NSString*, NSString*>* propertyMapping = [class kinveyPropertyMapping].invert;
    NSString* keyId = propertyMapping[KCSEntityKeyId];
    KNVQuery* query = [[KNVQuery alloc] initWithPredicate:[NSPredicate predicateWithFormat:[NSString stringWithFormat:@"%@ = %%@", keyId], entity[keyId]]
                                            sortDescriptors:nil];
    NSUInteger count = [self removeEntitiesByQuery:[[KCSQueryAdapter alloc] initWithQuery:query]
                                          forClass:class];
    return count > 0;
}

-(NSUInteger)removeEntitiesByQuery:(id<KCSQuery>)query
{
    return [self removeEntitiesByQuery:query
                              forClass:self.clazz];
}

-(NSUInteger)removeEntitiesByQuery:(id<KCSQuery>)query
                          forClass:(Class)class
{
    NSPredicate* predicate = query.predicate;
    if (!predicate) {
        predicate = [NSPredicate predicateWithValue:YES];
    }
    Class realmClass = [[self class] realmClassForClass:class];
    RLMRealm* realm = self.realm;
    __block NSUInteger count = 0;
    [realm transactionWithBlock:^{
        RLMResults* results = [realmClass objectsInRealm:realm
                                           withPredicate:predicate];
        count = results.count;
        [self cascadeDeleteResults:results
                             realm:realm];
    }];
    return count;
}

-(void)cascadeDeleteResults:(RLMResults*)results
                      realm:(RLMRealm*)realm
{
    for (RLMObject* obj in results) {
        [self cascadeDeleteObject:obj
                            realm:realm];
    }
}

-(void)cascadeDeleteObject:(RLMObject*)obj
                     realm:(RLMRealm*)realm
{
    if (!obj) {
        return;
    }
    for (RLMProperty* property in obj.objectSchema.properties) {
        switch (property.type) {
            case RLMPropertyTypeObject:
                [self cascadeDeleteObject:obj[property.name]
                                    realm:realm];
                break;
            case RLMPropertyTypeArray:
                for (RLMObject* nestedObj in (RLMArray*) obj[property.name]) {
                    [self cascadeDeleteObject:nestedObj
                                        realm:realm];
                }
                break;
            default:
                break;
        }
    }
    [realm deleteObject:obj];
}

-(NSArray<NSString*>*)keysForClass:(Class)class
{
    NSDictionary<NSString*, NSString*>* kinveyPropertyMapping = [class kinveyPropertyMapping];
    NSMutableArray<NSString*>* keys = kinveyPropertyMapping.allKeys.mutableCopy;
    NSArray<NSString*>* values = kinveyPropertyMapping.allValues;
    if (![values containsObject:KCSEntityKeyMetadata]) {
        [keys addObject:KCSEntityKeyMetadata];
    }
    if (![values containsObject:KCSEntityKeyAcl]) {
        [keys addObject:KCSEntityKeyAcl];
    }
    return keys;
}

-(NSDictionary<NSString *,id> *)findEntity:(NSString *)objectId
{
    return [self findEntity:objectId
                   forClass:self.clazz];
}

-(RLMObject*)filterExpiredObject:(RLMObject*)obj
                        forClass:(Class)class
{
    if (self.ttl > 0) {
        NSString* kmdKey = [__KNVPersistable kmdKey:class];
        if (!kmdKey) {
            kmdKey = KNVPersistableMetadataKey;
        }
        KCSMetadataRealm* kmd = obj[kmdKey];
        NSDate* date = kmd.lrt != nil ? [kmd.lrt toDate] : [kmd.ect toDate];
        if (date && [[NSDate date] timeIntervalSinceDate:date] > self.ttl) {
            obj = nil;
        }
    }
    return obj;
}

-(NSDictionary<NSString *,id> *)findEntity:(NSString *)objectId
                                  forClass:(Class)class
{
    Class realmClass = [[self class] realmClassForClass:class];
    RLMRealm* realm = self.realm;
    RLMObject* obj = [realmClass objectInRealm:realm
                                 forPrimaryKey:objectId];
    
    if (self.ttl > 0) {
        obj = [self filterExpiredObject:obj
                               forClass:class];
    }
    
    return [obj dictionaryWithValuesForKeys:[self keysForClass:class]];
}

-(NSArray<NSDictionary<NSString*, id>*>*)findEntityByQuery:(id<KCSQuery>)query
{
    return [self findEntityByQuery:query
                          forClass:self.clazz];
}

-(NSArray<NSDictionary<NSString*, id>*>*)findEntityByQuery:(id<KCSQuery>)query
                                                  forClass:(Class)class
{
    Class realmClass = [[self class] realmClassForClass:class];
    RLMRealm* realm = self.realm;
    
    RLMResults* results = [realmClass objectsInRealm:realm
                                       withPredicate:query.predicate];
    
    if (query.sortDescriptors.count > 0) {
        NSMutableArray<RLMSortDescriptor*>* realmSortDescriptor = [NSMutableArray arrayWithCapacity:query.sortDescriptors.count];
        for (NSSortDescriptor* sortDescriptor in query.sortDescriptors) {
            [realmSortDescriptor addObject:[RLMSortDescriptor sortDescriptorWithProperty:sortDescriptor.key
                                                                               ascending:sortDescriptor.ascending]];
        }
        results = [results sortedResultsUsingDescriptors:realmSortDescriptor];
    }
    
    NSArray<NSString*>* keys = [self keysForClass:class];
    
    NSMutableArray<NSDictionary<NSString*, NSObject*>*>* array = [NSMutableArray arrayWithCapacity:results.count];
    NSDictionary<NSString*, NSObject*>* json;
    RLMObject* obj;
    for (NSUInteger i = 0; i < results.count; i++) {
        obj = results[i];
        if (self.ttl > 0) {
            obj = [self filterExpiredObject:obj
                                   forClass:class];
            if (!obj) continue;
        }
        json = [obj dictionaryWithValuesForKeys:keys];
        [array addObject:json];
    }
    return array;
}

-(NSDictionary<NSString*, NSString*>*)findIdsLmtsByQuery:(id<KCSQuery>)query
{
    Class realmClass = [[self class] realmClassForClass:self.clazz];
    RLMRealm* realm = self.realm;
    
    RLMResults* results = [realmClass objectsInRealm:realm
                                       withPredicate:query.predicate];
    
    if (query.sortDescriptors.count > 0) {
        NSMutableArray<RLMSortDescriptor*>* realmSortDescriptor = [NSMutableArray arrayWithCapacity:query.sortDescriptors.count];
        for (NSSortDescriptor* sortDescriptor in query.sortDescriptors) {
            [realmSortDescriptor addObject:[RLMSortDescriptor sortDescriptorWithProperty:sortDescriptor.key
                                                                               ascending:sortDescriptor.ascending]];
        }
        results = [results sortedResultsUsingDescriptors:realmSortDescriptor];
    }
    
    NSString* idKey = [__KNVPersistable idKey:self.clazz];
    NSString* kmdKey = [__KNVPersistable kmdKey:self.clazz];
    if (!kmdKey) {
        kmdKey = KNVPersistableMetadataKey;
    }
    NSString* lmtKey = [KNVMetadata LmtKey];
    
    NSMutableDictionary<NSString*, NSString*>* json = [NSMutableDictionary dictionaryWithCapacity:results.count];
    RLMObject* obj;
    for (NSUInteger i = 0; i < results.count; i++) {
        obj = results[i];
        if (self.ttl > 0) {
            obj = [self filterExpiredObject:obj
                                   forClass:self.clazz];
            if (!obj) continue;
        }
        json[[obj valueForKey:idKey]] = [[obj valueForKey:kmdKey] valueForKey:lmtKey];
    }
    return json;
}

-(NSArray<NSDictionary<NSString *,id> *> *)findAll
{
    return [self findAllForClass:self.clazz];
}

-(NSArray<NSDictionary<NSString *,id> *> *)findAllForClass:(Class)class
{
    Class realmClass = [[self class] realmClassForClass:class];
    RLMRealm* realm = self.realm;
    
    NSDictionary<NSString*, NSString*>* kinveyPropertyMapping = [class kinveyPropertyMapping];
    NSArray<NSString*>* keys = kinveyPropertyMapping.allKeys;
    
    RLMResults* results = [realmClass allObjectsInRealm:realm];
    
    NSMutableArray<NSDictionary<NSString*, NSObject*>*>* array = [NSMutableArray arrayWithCapacity:results.count];
    NSDictionary<NSString*, NSObject*>* json;
    for (RLMObject* obj in results) {
        json = [obj dictionaryWithValuesForKeys:keys];
        [array addObject:json];
    }
    return array;
}

-(NSUInteger)count
{
    return [self countForClass:self.clazz];
}

-(NSUInteger)countForClass:(Class)class
{
    Class realmClass = [[self class] realmClassForClass:class];
    RLMRealm* realm = self.realm;
    
    RLMResults* results = [realmClass allObjectsInRealm:realm];
    return results.count;
}

-(void)removeAllEntities
{
    Class realmClass = [[self class] realmClassForClass:self.clazz];
    RLMRealm* realm = self.realm;
    [realm transactionWithBlock:^{
        if (realmClass) {
            RLMResults* results = [realmClass allObjectsInRealm:realm];
            if (results) {
                [self cascadeDeleteResults:results
                                     realm:realm];
            }
        } else {
            [realm deleteAllObjects];
        }
    }];
}

-(void)removeAllEntitiesForClass:(Class)class
{
    Class realmClass = [[self class] realmClassForClass:class];
    RLMRealm* realm = self.realm;
    [realm transactionWithBlock:^{
        RLMResults* results = [realmClass allObjectsInRealm:realm];
        if (results) {
            [self cascadeDeleteResults:results
                                 realm:realm];
        }
    }];
}

#pragma mark - Sync Table

-(KNVQuery*)pendingQuery:(NSString*)objectId
{
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"method IN %@", @[@"POST", @"PUT", @"DELETE"]];
    if (self.collectionName) {
        NSPredicate* predicateCollectionName = [NSPredicate predicateWithFormat:@"collectionName == %@", self.collectionName];
        predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[predicateCollectionName, predicate]];
    }
    if (objectId) {
        NSPredicate *predicateObjecId = [NSPredicate predicateWithFormat:@"objectId == %@", objectId];
        predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[predicate, predicateObjecId]];
    }
    NSSortDescriptor* sortDescriptorDate = [NSSortDescriptor sortDescriptorWithKey:@"date" ascending:YES];
    return [[KNVQuery alloc] initWithPredicate:predicate
                               sortDescriptors:@[sortDescriptorDate]];
}

-(KCSPendingOperationRealm*)pendingOperation:(id<KNVPendingOperation>)pendingOperation
{
    return (KCSPendingOperationRealm*) pendingOperation;
}

-(id<KNVPendingOperation>)createPendingOperation:(NSURLRequest *)request
                                        objectId:(NSString*)objectId
{
    return [[KCSPendingOperationRealm alloc] initWithURLRequest:request
                                                 collectionName:self.collectionName
                                                       objectId:objectId];
}

-(void)savePendingOperation:(id<KNVPendingOperation>)pendingOperation
{
    NSDictionary<NSString *,id> *entity = [[self pendingOperation:pendingOperation] toJson];
    RLMRealm* realm = self.realm;
    [realm transactionWithBlock:^{
        saveEntity(entity, realm, [KCSPendingOperationRealm class]);
    }];
}

-(NSArray<id<KNVPendingOperation>> *)pendingOperations
{
    return [self pendingOperations:nil];
}

-(NSArray<id<KNVPendingOperation>> *)pendingOperations:(NSString*)objectId
{
    NSArray<NSDictionary<NSString*, id>*> *entitiesPendingOperations = [self findEntityByQuery:[[KCSQueryAdapter alloc] initWithQuery:[self pendingQuery:objectId]]
                                                                                      forClass:[KCSPendingOperationRealm class]];
    NSMutableArray<id<KNVPendingOperation>> *pendingOperations = [NSMutableArray arrayWithCapacity:entitiesPendingOperations.count];
    for (NSDictionary<NSString*, id>* entityPendingOperations in entitiesPendingOperations) {
        [pendingOperations addObject:[[KCSPendingOperationRealm alloc] initWithValue:entityPendingOperations]];
    }
    return pendingOperations;
}

-(void)removePendingOperation:(id<KNVPendingOperation>)pendingOperation
{
    NSDictionary<NSString *,id> *entity = [[self pendingOperation:pendingOperation] toJson];
    [self removeEntity:entity
              forClass:[KCSPendingOperationRealm class]];
}

-(void)removeAllPendingOperations
{
    [self removeAllPendingOperations:nil];
}

-(void)removeAllPendingOperations:(NSString*)objectId
{
    [self removeEntitiesByQuery:[[KCSQueryAdapter alloc] initWithQuery:[self pendingQuery:objectId]]
                       forClass:[KCSPendingOperationRealm class]];
}

@end
