//
//  KinveyUserDiscoveryTests.m
//  KinveyKit
//
//  Created by Michael Katz on 7/14/12.
//  Copyright (c) 2012-2013 Kinvey. All rights reserved.
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
            [user saveToCollection:[KCSCollection userCollection] withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
                STAssertNoError
                self.done = YES;
            } withProgressBlock:nil];
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
