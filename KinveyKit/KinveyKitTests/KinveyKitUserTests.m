//
//  KinveyKitUserTests.m
//  KinveyKit
//
//  Created by Brian Wilson on 1/5/12.
//  Copyright (c) 2012-2013 Kinvey. All rights reserved.
//

#import "KinveyKitUserTests.h"
#import "KinveyUser.h"
#import "KCSClient.h"
#import "KCSKeyChain.h"
#import "KCSConnectionPool.h"
#import "KCSMockConnection.h"
#import "KCSConnectionResponse.h"
#import "KinveyHTTPStatusCodes.h"
#import "KCS_SBJson.h"
#import "KinveyPing.h"
#import "KCSLogManager.h"
#import "KCSAuthCredential.h"
#import "KCSRESTRequest.h"
#import "KinveyCollection.h"
#import "NSString+KinveyAdditions.h"

#import "TestUtils.h"

typedef BOOL(^KCSUserSuccessAction)(KCSUser *, KCSUserActionResult);
typedef BOOL(^KCSUserFailureAction)(KCSUser *, NSError *);
typedef BOOL(^KCSEntitySuccessAction)(id, NSObject *);
typedef BOOL(^KCSEntityFailureAction)(id, NSError *);


@interface KinveyKitUserTests ()
@property (nonatomic) BOOL testPassed;
@property (nonatomic, copy) KCSUserSuccessAction onSuccess;
@property (nonatomic, copy) KCSUserFailureAction onFailure;
@property (nonatomic, copy) KCSEntitySuccessAction onEntitySuccess;
@property (nonatomic, copy) KCSEntityFailureAction onEntityFailure;
@property (nonatomic, retain) KCS_SBJsonParser *parser;
@property (nonatomic, retain) KCS_SBJsonWriter *writer;

@end

@implementation KinveyKitUserTests

- (void)setUp
{
    _testPassed = NO;
    _onSuccess = [^(KCSUser *u, KCSUserActionResult result){ return NO; } copy];
    _onFailure = [^(KCSUser *u, NSError *error){ return NO; } copy];
    _onEntitySuccess = [^(id u, NSObject *obj){ return NO; } copy];
    _onEntityFailure = [^(id u, NSError *error){ return NO; } copy];
    STAssertTrue([TestUtils setUpKinveyUnittestBackend],@"");

    _parser = [[KCS_SBJsonParser alloc] init];
    _writer = [[KCS_SBJsonWriter alloc] init];
}


// These tests are ordered and must be run first, hence the AAAXX

- (void)testAAAAAInitializeCurrentUserInitializesCurrentUserNoNetwork{
    [[[KCSClient sharedClient] currentUser] logout];
    
    KCSUser *cUser = [[KCSClient sharedClient] currentUser];
    STAssertNil(cUser.username, @"uname should start nil");
    STAssertNil(cUser.password, @"pw should start nil");

    // initialize the user in the keychain (make a user that's "logged in")
    [KCSKeyChain setString:@"brian" forKey:@"username"];
    [KCSKeyChain setString:@"12345" forKey:@"password"];
    [KCSKeyChain setString:@"That's the combination for my luggage" forKey:@"_id"];
    
    [KCSUser initCurrentUser];

    cUser = [[KCSClient sharedClient] currentUser];
    KCSLogDebug(@"Blah: %@", cUser.password);
    
    STAssertEqualObjects(cUser.username, @"brian", @"uname should match");
    STAssertEqualObjects(cUser.password, @"12345", @"pw should match");
}

- (void)testAAABBLogoutLogsOutCurrentUser{
    [[[KCSClient sharedClient] currentUser] logout];
    
    KCSUser *cUser = [[KCSClient sharedClient] currentUser];
    [cUser logout];
    STAssertNil(cUser.username, @"uname should start nil");
    STAssertNil(cUser.password, @"pw should start nil");
}

- (void)testAAACCInitializeCurrentUserInitializesCurrentUserNetwork
{
    [[[KCSClient sharedClient] currentUser] logout];
    
    KCSUser *cUser = [[KCSClient sharedClient] currentUser];
    STAssertNil(cUser.username, @"uname should start nil");
    STAssertNil(cUser.password, @"pw should start nil");
    
    // Create a Mock Object
    KCSMockConnection *connection = [[KCSMockConnection alloc] init];
    
    connection.connectionShouldReturnNow = YES;
    connection.delayInMSecs = 0.0;
    
    // Success dictionary
    NSDictionary *dictionary = wrapResponseDictionary([NSDictionary dictionaryWithObjectsAndKeys:@"brian", @"username",
                                @"12345", @"password",
                                @"hello", @"_id", nil]);
    
    connection.responseForSuccess = [KCSConnectionResponse connectionResponseWithCode:KCS_HTTP_STATUS_CREATED
                                                                         responseData:[self.writer dataWithObject:dictionary]
                                                                           headerData:nil
                                                                             userData:nil];
    
    [[KCSConnectionPool sharedPool] topPoolsWithConnection:connection];

    [KCSUser initCurrentUser];
    cUser = [[KCSClient sharedClient] currentUser];
    
    STAssertEqualObjects(cUser.username, @"brian", @"uname should match");
    STAssertEqualObjects(cUser.password, @"12345", @"pw should match");

    // Make sure we log-out
    [cUser logout];
    
    [[KCSConnectionPool sharedPool] drainPools];
}

//TODO: remove this test point it's no longer needed since PING does not cause a user create should instead try some other request
- (void)noTestAAADDInitializeCurrentUserWithRequestPerformsRequest
{
    [TestUtils justInitServer];
    // Ensure user is logged out
    [[[KCSClient sharedClient] currentUser] logout];

    // Create a mock object for the real request
    KCSMockConnection *realRequest = [[KCSMockConnection alloc] init];
    realRequest.connectionShouldFail = NO;
    realRequest.connectionShouldReturnNow = YES;
    realRequest.responseForSuccess = [KCSConnectionResponse connectionResponseWithCode:KCS_HTTP_STATUS_OK
                                                                          responseData:[self.writer dataWithObject:@{}]
                                                                            headerData:nil
                                                                              userData:nil];
    
    // Create a Mock Object for the user request
    KCSMockConnection *connection = [[KCSMockConnection alloc] init];
    
    connection.connectionShouldReturnNow = YES;
    connection.connectionShouldFail = NO;
    
    // Success dictionary
    NSDictionary *dictionary = @{KCSUserAttributeUsername : @"brian", @"password" : @"password", KCSEntityKeyId : @"_id"};
    connection.responseForSuccess = [KCSConnectionResponse connectionResponseWithCode:KCS_HTTP_STATUS_CREATED
                                                                         responseData:[self.writer dataWithObject:dictionary]
                                                                           headerData:nil
                                                                             userData:nil];
    
    [[KCSConnectionPool sharedPool] topPoolsWithConnection:realRequest];
    [[KCSConnectionPool sharedPool] topPoolsWithConnection:connection];
    
    __block BOOL pingWorked = NO;
    __block NSString *description = nil;
    
    // Run the request
    self.done = NO;
    [KCSPing pingKinveyWithBlock:^(KCSPingResult *res){
        pingWorked = res.pingWasSuccessful; 
        description = res.description;
        self.done = YES;
    }];
    [self poll];
    
    // This test CANNOT work with the existing KCS REST framework.  There's a built-in 0.05 second delay that we cannot compensate for here...
    // at the moment...
    STAssertTrue(pingWorked, @"Ping should work");
    STAssertFalse([description containsStringCaseInsensitive:@"brian"], @"username should be in the description");
    
    // Check to make sure the auth worked
    KCSUser *cUser = [[KCSClient sharedClient] currentUser];
    STAssertFalse([cUser.username isEqualToString:@"brian"], @"uname should match");
    STAssertFalse([cUser.password isEqualToString:@"12345"], @"pw should match");
    
    // Make sure we log-out
    [cUser logout];
    
    [[KCSConnectionPool sharedPool] drainPools];
}


- (void)testCanCreateArbitraryUser
{
    [[[KCSClient sharedClient] currentUser] logout];
    
    NSString *testUsername = @"arbitrary";
    NSString *testPassword = @"54321";
    KCSMockConnection *connection = [[KCSMockConnection alloc] init];
    
    connection.connectionShouldReturnNow = YES;
    connection.connectionShouldFail = NO;
    
    // Success dictionary
    NSDictionary *dictionary = wrapResponseDictionary([NSDictionary dictionaryWithObjectsAndKeys:testUsername, @"username",
                                testPassword, @"password",
                                @"hello", @"_id", nil]);
    
    connection.responseForSuccess = [KCSConnectionResponse connectionResponseWithCode:KCS_HTTP_STATUS_CREATED
                                                                         responseData:[self.writer dataWithObject:dictionary]
                                                                           headerData:nil
                                                                             userData:nil];
    
    [[KCSConnectionPool sharedPool] topPoolsWithConnection:connection];
    
    self.onSuccess = [^(KCSUser *user, KCSUserActionResult result){
        if ([user.username isEqualToString:testUsername] &&
            [user.password isEqualToString:testPassword] &&
            result == KCSUserCreated){
            return YES;
        } else {
            return NO;
        }
    } copy];
    
    [KCSUser userWithUsername:testUsername password:testPassword withDelegate:self];
    STAssertTrue(self.testPassed, @"test should pass");
}

- (void)testCanLoginExistingUser
{
    [[[KCSClient sharedClient] currentUser] logout];
    
    NSString *testUsername = @"existing";
    NSString *testPassword = @"56789";
    KCSMockConnection *connection = [[KCSMockConnection alloc] init];
    
    connection.connectionShouldReturnNow = YES;
    connection.connectionShouldFail = NO;
    
    // Success dictionary
    NSDictionary *dictionary = wrapResponseDictionary([NSDictionary dictionaryWithObjectsAndKeys:
                                testPassword, @"password",
                                testUsername, @"password",
                                @"28hjkshafkh982kjh", @"_id", nil]);

    connection.responseForSuccess = [KCSConnectionResponse connectionResponseWithCode:KCS_HTTP_STATUS_OK
                                                                         responseData:[self.writer dataWithObject:dictionary]
                                                                           headerData:nil
                                                                             userData:nil];
    
    [[KCSConnectionPool sharedPool] topPoolsWithConnection:connection];
    
    self.onSuccess = [^(KCSUser *user, KCSUserActionResult result){
        if ([user.username isEqualToString:testUsername] &&
            [user.password isEqualToString:testPassword] &&
            result == KCSUserFound){
            return YES;
        } else {
            return NO;
        }
    } copy];
    
    [KCSUser loginWithUsername:testUsername password:testPassword withDelegate:self];
    
    STAssertTrue(self.testPassed, @"test should pass");
}

- (void)testCanLogoutUser
{
    [[[KCSClient sharedClient] currentUser] logout];
    
    [KCSKeyChain setString:@"logout" forKey:@"username"];
    [KCSKeyChain setString:@"98765" forKey:@"password"];
    [KCSKeyChain setString:@"That's the combination for my luggage" forKey:@"_id"];
    [KCSUser initCurrentUser];
    [[[KCSClient sharedClient] currentUser] logout];
    
    
    // Check to make sure keychain is clean
    STAssertNil([KCSKeyChain getStringForKey:@"username"], @"username should be clean");
    STAssertNil([KCSKeyChain getStringForKey:@"password"], @"password should be clean");
    STAssertNil([KCSKeyChain getStringForKey:@"_id"], @"_id should be clean");
    
    // Check to make sure we're not authd'
    STAssertFalse([[KCSClient sharedClient] userIsAuthenticated], @"user should be deauthed");
    
    // Check to make sure user is nil
    STAssertNil([[KCSClient sharedClient] currentUser], @"cuser should be nilled");
}

- (void)testAnonymousUserCreatedIfNoNamedUser
{
    [[[KCSClient sharedClient] currentUser] logout];
    
    NSString *testUsername = @"anon";
    NSString *testPassword = @"72727";
    KCSMockConnection *connection = [[KCSMockConnection alloc] init];
    
    connection.connectionShouldReturnNow = YES;
    connection.connectionShouldFail = NO;
    
    // Success dictionary
    // Success dictionary
    NSDictionary *dictionary = wrapResponseDictionary([NSDictionary dictionaryWithObjectsAndKeys:testUsername, @"username",
                                testPassword, @"password",
                                @"hello", @"_id", nil]);
    
    connection.responseForSuccess = [KCSConnectionResponse connectionResponseWithCode:KCS_HTTP_STATUS_CREATED
                                                                         responseData:[self.writer dataWithObject:dictionary]
                                                                           headerData:nil
                                                                             userData:nil];
    
    [[KCSConnectionPool sharedPool] topPoolsWithConnection:connection];
    
    self.onSuccess = [^(KCSUser *user, KCSUserActionResult result){
        if ([user.username isEqualToString:testUsername] &&
            [user.password isEqualToString:testPassword] &&
            result == KCSUserCreated){
            return YES;
        } else {
            return NO;
        }
    } copy];
    
    KCSAuthCredential *cred = [KCSAuthCredential credentialForURL:[[[KCSClient sharedClient] appdataBaseURL] stringByAppendingString:@"/1234"] usingMethod:kGetRESTMethod];

    KCSUser *preCurrentUser = [[KCSClient sharedClient] currentUser];    
   
    [cred HTTPBasicAuthString];
    
    KCSUser *postCurrentUser = [[KCSClient sharedClient] currentUser];

    STAssertNil(preCurrentUser, @"should be nil pre");
    STAssertNotNil(postCurrentUser, @"should not be nil after");
    STAssertEqualObjects(postCurrentUser.username, testUsername, @"usernames should match");
    STAssertEqualObjects(postCurrentUser.password, testPassword, @"passwords should match");
}

- (void)testCanAddArbitraryDataToUser
{
    [[[KCSClient sharedClient] currentUser] logout];
    
    // Make sure we have a user
    if ([[KCSClient sharedClient] currentUser] == nil){
        [KCSKeyChain setString:@"brian" forKey:@"username"];
        [KCSKeyChain setString:@"12345" forKey:@"password"];
        [KCSKeyChain setString:@"That's the combination for my luggage" forKey:@"_id"];
        
        [KCSUser initCurrentUser];
    }
    
    KCSUser *currentUser = [[KCSClient sharedClient] currentUser];
    
    [currentUser setValue:[NSNumber numberWithInt:32] forAttribute:@"age"];
    [currentUser setValue:@"Brooklyn, NY" forAttribute:@"birthplace"];
    [currentUser setValue:[NSNumber numberWithBool:YES] forAttribute:@"isAlive"];
    
    STAssertEquals((int)[[currentUser getValueForAttribute:@"age"] intValue], (int)32, @"age should match");
    STAssertTrue([[currentUser getValueForAttribute:@"isAlive"] boolValue], @"isAlive should match");
    STAssertEqualObjects([currentUser getValueForAttribute:@"birthplace"], @"Brooklyn, NY", @"birthplace should match");
}

- (void)testCanGetCurrentUser
{
    [[[KCSClient sharedClient] currentUser] logout];
    
    
    // Make sure we have a user
    if ([[KCSClient sharedClient] currentUser] == nil){
        [KCSKeyChain setString:@"brian" forKey:@"username"];
        [KCSKeyChain setString:@"12345" forKey:@"password"];
        [KCSKeyChain setString:@"That's the combination for my luggage" forKey:@"_id"];
        
        [KCSUser initCurrentUser];
    }
    
    KCSUser *currentUser = [[KCSClient sharedClient] currentUser];

    NSString *aKey = @"age";
    int age = 32;
    int age_ = 99;
    NSString *bKey = @"birthplace";
    NSString *bPlace = @"Brooklyn, NY";
    NSString *bPlace_ = @"Long Beach, CA";
    NSString *cKey = @"isAlive";
    BOOL alive = YES;
    BOOL alive_ = NO;

    [currentUser setValue:@(age) forAttribute:aKey];
    [currentUser setValue:bPlace forAttribute:bKey];
    [currentUser setValue:@(alive) forAttribute:cKey];

    // Check prior to fetch
    STAssertEquals((int)[[currentUser getValueForAttribute:aKey] intValue], age, @"age should match");
    STAssertEquals((BOOL)[[currentUser getValueForAttribute:cKey] boolValue], alive, @"isAlive should match");
    STAssertEqualObjects([currentUser getValueForAttribute:bKey], bPlace, @"birthplace should match");

    // Prepare request
    NSDictionary *dictionary = wrapResponseDictionary([NSDictionary dictionaryWithObjectsAndKeys:@"brian", @"username",
                                @"12345", @"password",
                                @"That's the combination for my luggage", @"_id",
                                @(age_), aKey,
                                bPlace_, bKey,
                                @(alive_), cKey, nil]);
    
    KCSMockConnection *connection = [[KCSMockConnection alloc] init];
    
    connection.connectionShouldReturnNow = YES;
    connection.connectionShouldFail = NO;

    connection.responseForSuccess = [KCSConnectionResponse connectionResponseWithCode:KCS_HTTP_STATUS_OK
                                                                         responseData:[self.writer dataWithObject:dictionary]
                                                                           headerData:nil
                                                                             userData:nil];
    
    [[KCSConnectionPool sharedPool] topPoolsWithConnection:connection];

    __block NSDictionary *dict;
    
    self.onEntitySuccess = [^(id e, NSObject *obj){
        dict = (NSDictionary *)obj;
        return YES;
    } copy];

    [[[KCSClient sharedClient] currentUser] loadWithDelegate:self];
    
    // Current user is primed
    STAssertEquals((int)[[currentUser getValueForAttribute:aKey] intValue], age_, @"age should match");
    STAssertEquals((BOOL)[[currentUser getValueForAttribute:cKey] boolValue], alive_, @"isAlive should match");
    STAssertEqualObjects([currentUser getValueForAttribute:bKey], bPlace_, @"birthplace should match");
}

- (void)testCanTreatUsersAsCollection
{
    [[[KCSClient sharedClient] currentUser] logout];
    
    // Make sure we have a user
    if ([[KCSClient sharedClient] currentUser] == nil){
        [KCSKeyChain setString:@"brian" forKey:@"username"];
        [KCSKeyChain setString:@"12345" forKey:@"password"];
        [KCSKeyChain setString:@"That's the combination for my luggage" forKey:@"_id"];
        
        [KCSUser initCurrentUser];
    }
    STAssertTrue([[KCSCollection userCollection] isKindOfClass:[KCSCollection class]], @"user collection should be a collection");
}

- (void)user:(KCSUser *)user actionDidCompleteWithResult:(KCSUserActionResult)result
{
    self.testPassed = self.onSuccess(user, result);
}

- (void)user:(KCSUser *)user actionDidFailWithError:(NSError *)error
{
    self.testPassed = self.onFailure(user, error);
}

- (void)entity:(id<KCSPersistable>)entity fetchDidCompleteWithResult:(NSObject *)result
{
    self.testPassed = self.onEntitySuccess(entity, result);
}

- (void)entity:(id<KCSPersistable>)entity fetchDidFailWithError:(NSError *)error
{
    self.testPassed = self.onEntityFailure(entity, error);
}

- (void)entity:(id)entity operationDidCompleteWithResult:(NSObject *)result
{
    self.testPassed = self.onEntitySuccess(entity, result);
    self.done = YES;
}

- (void)entity:(id)entity operationDidFailWithError:(NSError *)error
{
    self.testPassed = self.onEntityFailure(entity, error);
    self.done = YES;
}


static NSString* lastUser;
static NSString* access_token = @"AAAGI68NkOC4BAH51tsJcxZACSdzZAjIUZAjsY5xzVAumCtvIMw3yZBeHgCroDyU7mtNNj9BXhZB05ucgVv6i8ILrkSOuvydPuzMA9lA6R2QlLuQeZArvVp";

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

- (void) testLoginWithFacebookOld
{
    [TestUtils justInitServer];
    // Ensure user is logged out
    [[[KCSClient sharedClient] currentUser] logout];
    self.done = NO;
    [KCSUser loginWithFacebookAccessToken:access_token withCompletionBlock:^(KCSUser *user, NSError *errorOrNil, KCSUserActionResult result) {
        STAssertNoError;
        STAssertNotNil(user, @"user should not be nil");
        self.done = YES;
    }];
    [self poll];
    
    self.done = NO;
    [KCSPing pingKinveyWithBlock:^(KCSPingResult *result) {
        STAssertTrue(result.pingWasSuccessful, @"should have been a success.");
        self.done = YES;
    }];
    [self poll];
    
    lastUser = [KCSClient sharedClient].currentUser.username;
}

#pragma clang diagnostic pop

- (void) testLoginWithFacebookNew
{
    [TestUtils justInitServer];
    // Ensure user is logged out
    [[[KCSClient sharedClient] currentUser] logout];
    self.done = NO;
    [KCSUser loginWithSocialIdentity:KCSSocialIDFacebook accessDictionary:@{KCSUserAccessTokenKey : access_token} withCompletionBlock:^(KCSUser *user, NSError *errorOrNil, KCSUserActionResult result) {
        STAssertNoError;
        STAssertNotNil(user, @"user should not be nil");
        self.done = YES;
    }];
    [self poll];
    
    self.done = NO;
    [KCSPing pingKinveyWithBlock:^(KCSPingResult *result) {
        STAssertTrue(result.pingWasSuccessful, @"should have been a success.");
        self.done = YES;
    }];
    [self poll];
    
    lastUser = [KCSClient sharedClient].currentUser.username;
}

/* function named this way to follow the login with FB */
//TODO: get this to work in the simulator
#if NEVER
- (void) testLoginWithFacebookPersists
{
    [TestUtils justInitServer];
    
    self.done = NO;
    [KCSPing pingKinveyWithBlock:^(KCSPingResult *result) {
        STAssertTrue(result.pingWasSuccessful, @"should have been a success.");
        STAssertEqualObjects(lastUser, [KCSClient sharedClient].currentUser.username, @"user names should match");
        STAssertNotNil([KCSClient sharedClient].currentUser.sessionAuth, @"should have a valid session token");
        self.done = YES;
    }];
    [self poll];
}
#endif

- (void) testLoginWithTwitter
{
    [TestUtils justInitServer];
    // Ensure user is logged out
    [[[KCSClient sharedClient] currentUser] logout];
    self.done = NO;
    
    [KCSUser loginWithSocialIdentity:KCSSocialIDTwitter accessDictionary:@{@"access_token" : @"823982046-Z0OrwAWQO3Ys2jtGM1k7hDnD6Ty9f54T1JRaDHHi",         @"access_token_secret" : @"3yIDGXVZV67m3G480stFgYk5eHZ7UCOSlOVHxh5RQ3g"}
     withCompletionBlock:^(KCSUser *user, NSError *errorOrNil, KCSUserActionResult result) {
         STAssertNotNil(user, @"user should not be nil");
         self.done = YES;
     }];
    
    [self poll];
    
    self.done = NO;
    [KCSPing pingKinveyWithBlock:^(KCSPingResult *result) {
        STAssertTrue(result.pingWasSuccessful, @"should have been a success.");
        self.done = YES;
    }];
    [self poll];
    
    lastUser = [KCSClient sharedClient].currentUser.username;
}

- (void) testUserCollection
{
    KCSAppdataStore* store = [KCSAppdataStore storeWithCollection:[KCSCollection userCollection] options:nil];
    self.done = NO;
    [store loadObjectWithID:[KCSUser activeUser].kinveyObjectId withCompletionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        if(errorOrNil) {
            NSLog(@"Failed to load users... %@", errorOrNil);
        } else {
            NSLog(@"%@", objectsOrNil);
        }
        self.done = YES;
    } withProgressBlock:nil];
    [self poll];
}

#pragma mark - Password reset

- (void) testPasswordReset
{
    //need to use a premade user
    self.done = NO;
    NSString* testUser = @"testino";
    [KCSUser loginWithUsername:testUser password:@"12345" withCompletionBlock:^(KCSUser *user, NSError *errorOrNil, KCSUserActionResult result) {
        STAssertNoError;
        self.done = YES;
    }];
    [self poll];
        
    self.done = NO;
    [KCSUser sendPasswordResetForUser:testUser withCompletionBlock:^(BOOL emailSent, NSError *errorOrNil) {
        STAssertNoError;
        STAssertTrue(emailSent, @"Should send email");
        self.done = YES;
    }];
    [self poll];
}

- (void) testPasswordResetWithNoEmailDoesNotError
{
    //need to use a premade user
    self.done = NO;
    NSString* testUser = @"testino2";
    [KCSUser loginWithUsername:testUser password:@"12345" withCompletionBlock:^(KCSUser *user, NSError *errorOrNil, KCSUserActionResult result) {
        STAssertNoError;
        self.done = YES;
    }];
    [self poll];
    
    self.done = NO;
    [KCSUser sendPasswordResetForUser:testUser withCompletionBlock:^(BOOL emailSent, NSError *errorOrNil) {
        STAssertNoError;
        STAssertTrue(emailSent, @"Should have send email, anyway");
        self.done = YES;
    }];
    [self poll];
}

- (void) testPasswordResetWithBadUserEmailDoesNotError
{
    NSString* testUser = @"BADUSER";
    self.done = NO;
    [KCSUser sendPasswordResetForUser:testUser withCompletionBlock:^(BOOL emailSent, NSError *errorOrNil) {
        STAssertNoError;
        STAssertTrue(emailSent, @"Should have send email, anyway");
        self.done = YES;
    }];
    [self poll];

}

- (void) testEscapeUser
{
    NSString* testUser = @"abc . foo@foo.com";
    self.done = NO;
    [KCSUser sendPasswordResetForUser:testUser withCompletionBlock:^(BOOL emailSent, NSError *errorOrNil) {
        STAssertNoError;
        STAssertTrue(emailSent, @"Should have send email, anyway");
        self.done = YES;
    }];
    [self poll];
}

- (void) testSendEmailConfirm
{
    self.done = NO;
    NSString* testUser = @"testino";
    [KCSUser loginWithUsername:testUser password:@"12345" withCompletionBlock:^(KCSUser *user, NSError *errorOrNil, KCSUserActionResult result) {
        STAssertNoError;
        self.done = YES;
    }];
    [self poll];
    
    self.done = NO;
    [KCSUser sendEmailConfirmationForUser:testUser withCompletionBlock:^(BOOL emailSent, NSError *errorOrNil) {
        STAssertNoError;
        STAssertTrue(emailSent, @"Should send email");
        self.done = YES;
    }];
    [self poll];

}

- (void) testChangePassword
{
    KCSUser* u = [KCSUser activeUser];
    NSString* currentPassword = u.password;
//    NSString* keychainPassword = [KCSKeyChain getStringForKey:@"password"];
    
    STAssertNotNil(currentPassword, @"current password should not be nil");
//   STAssertNotNil(keychainPassword, @"keychain should not be nil");
    
//    STAssertEqualObjects(currentPassword, keychainPassword, @"passwords should match");
    STAssertFalse([currentPassword isEqualToString:@"foo"], @"should be old password");
    
    
    self.done = NO;
    [u changePassword:@"foo" completionBlock:^(NSArray *objectsOrNil, NSError *errorOrNil) {
        STAssertNoError;
        STAssertEqualObjects(@"foo", [[KCSUser activeUser] password], @"password should be updated");
        NSString* newKeychainPwd = [KCSKeyChain getStringForKey:@"password"];
        STAssertTrue([newKeychainPwd isEqualToString:@"foo"], @"should be old password");
        
        self.done = YES;
    }];
    [self poll];
}
@end
