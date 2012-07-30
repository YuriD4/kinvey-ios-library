//
//  KCSGroup.m
//  KinveyKit
//
//  Created by Michael Katz on 5/21/12.
//  Copyright (c) 2012 Kinvey. All rights reserved.
//

#import "KCSGroup.h"

@implementation KCSGroup

- (id) initWithJsonArray:(NSArray*)jsonData valueKey:(NSString*)key queriedFields:(NSArray*)fields;
{
    self = [super init];
    if (self) {
        _array = [jsonData retain];
        _queriedFields = [[NSArray arrayWithArray:fields] retain];
        _key = [key retain];
    }
    return self;
}

- (void) dealloc
{
    [_array release];
    [_key release];
    [_queriedFields release];

    [super dealloc];
}

- (NSArray*) fieldsAndValues
{
    return _array;
}

- (NSString*) returnValueKey 
{
    return _key;
}

- (id) reducedValueForFields:(NSDictionary*)fields
{
    __block NSNumber* number = [NSNumber numberWithInt:NSNotFound];
    [self enumerateWithBlock:^(NSArray *fieldValues, id value, NSUInteger idx, BOOL *stop) {
        BOOL found = NO;
        for (NSString* field in [fields allKeys]) {
            if ([_queriedFields containsObject:field] && [[fieldValues objectAtIndex:[_queriedFields indexOfObject:field]] isEqual:[fields objectForKey:field]]) {
                found = YES;
            } else {
                found = NO;
                break;
            }
        }
        if (found) {
            *stop = YES;
            number = value;
        }
    }];
    return number;
}

- (void) enumerateWithBlock:(void (^)(NSArray* fieldValues, id value, NSUInteger idx, BOOL *stop))block
{
    [_array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSDictionary* result = obj;
        NSMutableArray* fieldValues = [NSMutableArray arrayWithCapacity:result.count - 1];
        for (NSString* field in _queriedFields) {
            [fieldValues addObject:[result objectForKey:field]];
        }
        block([NSArray arrayWithArray:fieldValues], [result objectForKey:_key], idx, stop);
    }];
}

@end
