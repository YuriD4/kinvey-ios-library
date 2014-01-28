//
//  KinveyUserDiscoveryTests.m
//  KinveyKit
//
//  Created by Michael Katz on 7/14/12.
//  Copyright (c) 2012-2014 Kinvey. All rights reserved.
//
// This software is licensed to you under the Kinvey terms of service located at
// http://www.kinvey.com/terms-of-use. By downloading, accessing and/or using this
// software, you hereby accept such terms of service  (and any agreement referenced
// therein) and agree that you have read, understand and agree to be bound by such
// terms of service and are of legal age to agree to such terms with Kinvey.
//
// This software contains valuable confidential and proprietary information of
// KINVEY, INC and is subject to applicable licensing agreements.
// Unauthorized reproduction, transmission or distribution of this file and its
// contents is a violation of applicable laws.
//


#import "KinveyUserDiscoveryTests.h"
#import "TestUtils.h"
#import "KinveyUser.h"


@implementation KinveyUserDiscoveryTests

- (void) setUp
{
    BOOL setup = [TestUtils setUpKinveyUnittestBackend];
    STAssertTrue(setup, @"need to be set-up");    
}

- (void) createUser:(NSString*)username email:(NSString*)email fname:(NSString*)fname lname:(NSString*)lname
{
    self.done = NO;
    [KCSUser userWithUsername:username password:@"hero" fieldsAndValues:nil withCompletionBlock:^(KCSUser *user, NSError *errorOrNil, KCSUserActionResult result) {
        if (errorOrNil != nil && [[errorOrNil domain] isEqualToString:KCSUserErrorDomain] && [errorOrNil code] == KCSConflictError) {
            [KCSUser loginWithUsername:username password:@"hero" withCompletionBlock:^(KCSUser *user, NSError *errorOrNil, KCSUserActionResult result) {
                STAssertNoError
                self.done = YES;
            }];
        } else {
            STAssertNoError
            user.email = email;
            user.surname = lname;
            user.givenName = fname;
            [user saveWithCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
                STAssertNoError
                self.done = YES;
            }];
        }
    }];
    [self poll];
    STAssertEqualObjects(fname,[[KCSUser activeUser] givenName], @"names should match");

}

- (void) testDiscovery
{
    [self createUser:@"superman" email:@"superman@justiceleague.com" fname:@"Clark" lname:@"Kent"];
    [self createUser:@"batman" email:@"batman@justiceleague.com" fname:@"Bruce" lname:@"Wayne"];
    [self createUser:@"wonderwoman" email:@"wonderwoman@justiceleague.com" fname:@"Diana" lname:@"Prince"];
    [self createUser:@"flash" email:@"flash@justiceleague.com" fname:@"Wally" lname:@"West"];
    [self createUser:@"greenLantern" email:@"greeny@justiceleague.com" fname:@"John" lname:@"Stewart"];
    
    self.done = NO;
    [KCSUserDiscovery lookupUsersForFieldsAndValues:[NSDictionary dictionaryWithObjectsAndKeys:@"batman", @"username", nil] completionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        STAssertNoError
        STAssertObjects(1)
        KCSUser* obj = objectsOrNil[0];
        STAssertEqualObjects(@"Wayne", obj.surname, @"expecting a match");
        self.done = YES;
    } progressBlock:nil];
    [self poll];
}

@end
