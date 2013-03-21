# KinveyKit Release History

## 1.14
### 1.14.0
** Release Date:** March 21, 2013

* Added `+ [KCSReduceFunction AGGREGATE]` grouping function which returns whole objects for the store type, grouped by the specified field. This is useful for building sectioned tables. 
* Added `+ [KCSQuery queryWithQuery:]` copy factory method.
* Replaced (deprecated) `KCSMetadata` `usersWithReadAccess` and `setUsersWithReadAccess:` with `readers` mutable array; and replaced `usersWithWriteAccess` and `setUsersWithWriteAccess:` with `writers` mutable array. User `_id`'s can now be added directly to these arrays instead of using accessor methods. 
* Added `KCSClient` set-up option `KCS_USER_CAN_CREATE_IMPLICT` to disable creating "implicit users" when set to `NO`. If a request is sent before a login with a username or social identity, it will complete with an authentication error.

        (void)[[KCSClient sharedClient] initializeKinveyServiceForAppKey:@"<#APP KEY#>"
                                                           withAppSecret:@"<#APP SECRET#>"
                                                            usingOptions:@{KCS_USER_CAN_CREATE_IMPLICT : @NO}];

                                                                                                               
* Added `KCSClient` set-up option `KCS_LOG_SINK` to allow you to send KinveyKit logs to a custom logger, such as Testflight. This requires that you create an object that implements the new `KCSLogSink` protocol and configure logging. For example:


        @interface TestFlightLogger : NSObject <KCSLogSink>
        @end
        @implementation TestFlightLogger
        
        - (void)log:(NSString *)message
        {
            TFLog(@"%@", message);
        }
        @end
        
	and, in the app delegate: 
	
    	(void)[[KCSClient sharedClient] initializeKinveyServiceForAppKey:@"<#APP KEY#>"
    	                                                   withAppSecret:@"<#APP SECRET#>"
        	                                                usingOptions:@{KCS_LOG_SINK : [[TestFlightLogger alloc] init]}];
    
        [KCSClient configureLoggingWithNetworkEnabled:NO debugEnabled:NO traceEnabled:NO warningEnabled:YES errorEnabled:YES];

* Added support for log-in with __Salesforce__
    * Added `KCSSocialIDSalesforce` value to `KCSUserSocialIdentifyProvider` enum for use with `+ [KCSUser loginWithSocialIdentity:accessDictionary:withCompletionBlock:]` and `+ [KCSUser registerUserWithSocialIdentity:accessDictionary:withCompletionBlock:]`.    
    * To use with [Salesforce's iOS SDK](https://github.com/forcedotcom/SalesforceMobileSDK-iOS)
	
         
             - (void)oauthCoordinatorDidAuthenticate:(SFOAuthCoordinator *)coordinator authInfo:(SFOAuthInfo *)info
             {
             	NSString* accessToken = coordinator.credentials.accessToken;
             	NSString* instanceURL = [coordinator.credentials.identityUrl absoluteString];
             	NSString* refreshToken = coordinator.credentials.refreshToken;
             	NSString* clientId = coordinator.credentials.clientId;
    
             	NSDictionary* acccessDictionary = @{KCSUserAccessTokenKey : accessToken, KCS_SALESFORCE_IDENTITY_URL : instanceURL, KCS_SALESFORCE_REFRESH_TOKEN : refreshToken, KCS_SALESFORCE_CLIENT_ID : clientId};
    
             	[KCSUser loginWithSocialIdentity:KCSSocialIDSalesforce accessDictionary:acccessDictionary withCompletionBlock:^(KCSUser *user, NSError *errorOrNil, KCSUserActionResult result) {
             		NSLog(@"Logged in user: %@ - error: %@", user, errorOrNil);
             	}];
             }     

* Removed `KCSUniqueNumber` class. 
* Removed deprecated (as of version 1.2) filter API from old Collections interface. 
* Deprecated undocumented `KCSStore` factory methods on `KCSClient`.
* Infrastructure update: entire library now built with ARC.
* Bug fix(es):
    * KCSUserDiscovery returns complete `KCSUser` objects now instead of `NSDictionary`.

## 1.13
### 1.13.2
** Release Date:** January 17, 2013

* Bug fix(es):
    * Fixed issue where airship lib was added twice, causing linker failures.
    
### 1.13.1
** Release Date:** January 7, 2013

* `KCSAppdataStore` and subclasses will now return objects when partial data is loaded from the server in progress blocks with `loadObjectWithID:withCompletionBlock:withProgressBlock:` and `queryWithQuery:withCompletionBlock:withProgressBlock:`
* Bug fix(es):
    * Email verification status property on `KCSUser` is now being properly set once the user has clicked the link in the email and the user is reloaded from the server. 

### 1.13.0 
** Release Date:** December 18, 2012

* Added support for log-in with __LinkedIn__
    * Added `KCSSocialIDLinkedIn` value to `KCSUserSocialIdentifyProvider` enum for use with `+ [KCSUser loginWithSocialIdentity:accessDictionary:withCompletionBlock:]` and `+ [KCSUser registerUserWithSocialIdentity:accessDictionary:withCompletionBlock:]`.
    * Added `+ [KCSUser getAccessDictionaryFromLinkedIn:usingWebView]` to obtain an accessDictionary for use with the register & log-in methods. 
* Added `- [KCSUser updatePassword:completionBlock:]` to change the active user's password. 
* `KCSQuery` geo-queries (`kKCSNearSphere`, `kKCSWithinBox`, `kKCSWithinCenterSphere`, `kKCSWithinPolygon`) on a field other than `KCSEntityKeyGeolocation` will now throw an exception instead of silently fail. 
* Bug fix(es):
    * Fix bug when using Data Integration query and an error is returned in an unexpected format causes a crash. 

## 1.12
### 1.12.1
** Release Date:** December 12, 2012

* Bug Fix(es):
    * Fix crash when using `-[KCSQuery fetchWithQuery:withCompletionBlock:withProgressBlock:]`.

### 1.12.0 [<sub>api diff</sub>](Documents/releasenotes/General/KinveyKit1120APIDiffs/KinveyKit1120APIDiffs.html)
** Release Date:** November 29, 2012 

* Added `KCSRequestId` key to most `NSError` `userInfo` dictionaries. If available, this unique key corresponds to the request to the Kinvey backend. This value is useful for tech support purposes, and should be provided when contacting support@kinvey.com for faster issue resolution. 
* Added `KCSBackendLogicError` constant for `-[NSError code]` value for cases when there is an error running Backend Logic on the Kinvey server (HTTP error code 550).
* `+[KCSQuery queryOnField:withRegex:]` and `+[KCSQuery queryOnField:withRegex:options]` now take either `NSString` or `NSRegularExpression` objects as the regular expression parameter. The `+[KCSQuery queryOnField:withRegex:]` form will use the applicable options from the NSRegularExpression object.
* `CLLocation` objects can now be used as values for a `KCSEntityKeyGeolocation` property. These objects are saved in the form [latitude, longitude]; all other CLLocation properties are discarded. 
* `+[KCSPing pingKinveyWithBlock:]` no longer requires user authentication, and thus will not create or initialize a `KCSUser`. 
* Bug Fix(es):
    * Fix bug when using sort modifiers on queries with old collection API where the sort is not applied correctly

## 1.11
### 1.11.0 [<sub>api diff</sub>](Documents/releasenotes/General/KinveyKit1110APIDiffs/KinveyKit1110APIDiffs.html)
** Release Date:** November 16, 2012

* Replaced `libUAirship-1.3.3` with the smaller `libUAirshipPush-1.3.3` library.
* `- [KCSStore loadObjectWithID:withCompletionBlock:withProgressBlock:]` now accepts `NSSet`s of id's as well as arrays and a single id. 
* Updated `KCSQuery` to throw an exception when trying to negate an exact match query. This is invalid syntax and fails server-side. Use a conditional query with `kKCSNotEqual` to test not equals.  
* Deprecated `+[KCSQuery queryForNilValueInField:]` because it is ambiguous and did not work. It has been modified to work the same as `queryForEmptyValueInField:` and is superceeded by the following behaviors:
    * To find values that have been set to `null` : `+[KCSQuery queryOnField:field withExactMatchForValue:[NSNull null]]`
    * To find values that empty or unset: `+[KCSQuery queryForEmptyValueInField:]`
    * To find either `null` or empty or unset: `+[KCSQuery queryForEmptyOrNullValueInField:]`  
* Usability Enhancements:
    * Created options keys for `KCSAppdataStore` so that a `KCSCollection` object does not have to be explicitly created and managed by the client code.
        * `KCSStoreKeyCollectionName` the collection Name
        * `KCSStoreKeyCollectionTemplateClass` the template class
        * For example, instead of:
            
                KCSCollection* collection = [KCSCollection collectionFromString:@"Events" ofClass:[Event class]];
                _store = [KCSAppdataStore storeWithCollection:collection options:nil];
          You can use the following:
          
                _store = [KCSAppdataStore storeWithOptions:@{ KCSStoreKeyCollectionName : @"Events",
                                                     KCSStoreKeyCollectionTemplateClass : [Event class]}];
                                                    
    * Renamed `KCS_PUSH_MODE` values to match the language used eslewhere
        * `KCS_PUSH_DEBUG` is now `KCS_PUSH_DEVELOPMENT`
        * `KCS_PUSH_RELEASE` is now `KCS_PUSH_PRODUCTION`
    * Exposed `userId` property of `KCSUser` to obtain the `_id` for references.

          


## 1.10
### 1.10.8
** Release Date:** November 13, 2012

* Bug fix(es):
    * Sporadic assertion when initializing user outside of normal flow. 

### 1.10.7
** Release Date:** November 12, 2012

* Bug fix(es):
    * Fixed bug where new user could not be created when using push. 

### 1.10.6
** Release Date:** November 3, 2012

* Bug fix(es):
    * Fixed bug where sign-in with Twitter sporadically crashed or did not complete.

### 1.10.5
** Release Date:** October 30, 2012

* Added `KCSUserAttributeFacebookId` to allow for discovering users through `KCSUserDiscovery` given a Facebook id (from the FB SDK).
* Bug fix(es):
    * Joined `KCSQuery`s using `kKCSAnd` now work correctly. 
    * Fixed error where streaming resource URLs were not fetched properly.

### 1.10.4
** Release Date:** October 23, 2012

* Minor update(s)
    * Additional User information, such as surname and givenname are now persisted in the keychain.

### 1.10.3
** Release Date:** October 18, 2012

* __Change in behavior when saving objects with relationships__.
    * Objects specified as relationships (through `kinveyPropertyToCollectionMapping`) will, by default, __no longer be saved__ to its collection when the owning object is saved. Like before, there will be a reference dictionary saved to the backend in place of the object.
    * If a reference object has not had its `_id` set, either programmatically or by saving that object to the backend, then saving the owning object will fail. The save will not be sent, and the `completionBlock` callback with have an error with an error code: `KCSReferenceNoIdSetError`.
    * To save the reference objects (either to simplify the save or have the backend generate the `_id`'s), have the `KCSPersistable` object implement the `- referenceKinveyPropertiesOfObjectsToSave` method. This will return an array of backend property names for the objects to save. 
        * For example, if you have an `Invitation` object with a reference property `Invitee`, in addition to mentioning the `Invitee` property in `- hostToKinveyPropertyMapping` and `- kinveyPropertyToCollectionMapping`, if you supply `@"Invitee"` in `- referenceKinveyPropertiesOfObjectsToSave`, then any objects in the `Invitee` property will be saved to the backend before saving the `Invitation` object, populating any `_id`'s as necessary.

### 1.10.2
** Release Date:** October 12, 2012

* Improved support for querying relationships through `KCSLinkedAppdataStore` and for using objects in queries
    * Added constants: `KCSMetadataFieldCreator` and `KCSMetadataFieldLastModifiedTime` to `KCSMetadata.h` to allow for querying for entities based on the user that created the object and the last time the entity was updated on the server.
    * Added the ability to use `NSDate` objects in queries, supporting exact matches, greater than (or equal) and less than (or equal) comparisons.
* Added support for establishing references to users:
    * Added constant `KCSUserCollectionName` to allow for adding relationships to user objects from any object's `+kinveyPropertyToCollectionMapping`.
    * Deprecated `- [KCSUser userCollection]` in favor of `+[KCSCollection userCollection]` to create a collection object to the user collection. 
    

### 1.10.1
** Release Date:** October 10, 2012

* Added `+ [KCSUser sendEmailConfirmationForUser:withCompletionBlock:]` in order to send an email confirmation to the user. 

### 1.10.0 [<sub>api diff</sub>](Documents/releasenotes/General/KinveyKit1100APIDiffs/KinveyKit1100APIDiffs.html)

** Release Date: ** October 8, 2012

* Added `+ [KCSUser sendPasswordResetForUser:withCompletionBlock:]` in order to send a password reset email to the user.  
* Bug fix(es):
    * Fixed false error when deleting entities using old `KCSCollection` interface.
    * Fixed error when loading dates that did not specify millisecond information. 

## 1.9
### 1.9.1
** Release Date: ** October 2, 2012

* Bug fix(es):
    * `KCSLinkedAppdataStore` now supports relationships when specifying an optional `cachePolicy` when querying. 

### 1.9.0 [<sub>api diff</sub>](Documents/releasenotes/General/KinveyKit190APIDiffs/KinveyKit190APIDiffs.html)
** Release Date: ** October 1, 2012

* Added support for log-in with twitter
    * Deprecate Facebook-specific methods and replace with generic social identity. See `KCSUser`.
    * Requires linking Twitter.framework and Accounts.framework.
* Added support for `id<KCSPersistable>` objects to be used as match values in `KCSQuery` when using relationships through `KCSLinkedAppdataStore`.
* Deprecated `KCSEntityDict`. You can now just save/load `NSMutableDictionary` objects directly with the backend. Use them like any other `KCSPersistable`.
    * Note: using a non-mutable `NSDictionary` will not have its fields updated when saving the object.
* Upgraded Urban Airship library to 1.3.3.
* Improved usability for Push Notifications
    * Deprecated `- [KCSPush onLoadHelper:]`; use `- [KCSPush onLoadHelper:error:]` instead to capture set-up errors.

## 1.8
### 1.8.3
** Release Date: ** September 25, 2012

* Bug fix(es):
    * Fix issue with production push.
    * Fix issue with analytics on libraries built with Xcode 4.5.

### 1.8.2
** Release Date: ** September 14, 2012

* Bug fix(es): Fix sporadic crash on restore from background.

### 1.8.1 
** Release Date: ** September 13, 2012

* Added `KCSUniqueNumber` entities to provide monotonically increasing numerical sequences across a collection.

### 1.8.0 [<sub>api diff</sub>](Documents/releasenotes/General/KinveyKit180APIDiffs/KinveyKit180APIDiffs.html)
** Release date: ** September 11, 2012

* `KCSLinkedAppdataStore` now supports object relations through saving/loading entities with named fields of other entities.
* Added `kKCSRegex` regular expression querying to `KCSQuery`.
* Added `KCSEntityKeyGeolocation` constant to KinveyPersistable.h as a convience from using the `_geoloc` geo-location field. 
* Added `CLLocation` category methods `- [CLLocation kinveyValue]` and `+ [CLLocation  locationFromKinveyValue:]` to aid in the use of geo data.
* Support for `NSSet`, `NSOrderedSet`, and `NSAttributedString` property types. These are saved as arrays on the backend.  See [Datatypes in KinveyKit](Documents/guides/datatype-guide/Datatypes%20In%20KinveyKit.html) for more information.
* Support for Kinvey backend API version 2. 
* Documentation Updates.
    * Added [Datatypes in KinveyKit](Documents/guides/datatype-guide/Datatypes%20In%20KinveyKit.html) Guide.
    * Added links to the api differences to this document.

## 1.7
### 1.7.0 [<sub>api diff</sub>](Documents/releasenotes/General/KinveyKit170APIDiffs/KinveyKit170APIDiffs.html)
** Release date: ** Aug 17, 2012

* `KCSCachedStore` now provides the ability to persist saves when the application is offline, and then to save them when the application regains connectivity. See also `KCSOfflineSaveStore`.
* Added login with Facebook to `KCSUser`, allowing you to use a Facebook access token to login in to Kinvey.
* Documentation Updates.
    * Added [Threading Guide](Documents/guides/gcd-guide/Using%20KinveyKit%20with%20GCD.html).
    * Added [Core Data Migration Guide](Documents/guides/using-coredata-guide/KinveyKit%20CoreData%20Guide.html)
* Bug Fix(es).
    * Updated our reachability aliases to make the KinveyKit more compatible with other frameworks. 

## 1.6
### 1.6.1 
** Release Date: ** July 31st, 2012

* Bug Fix(es).
    * Fix issue with hang on no results using `KCSAppdataStore`.

### 1.6.0 [<sub>api diff</sub>](Documents/releasenotes/General/KinveyKit160APIDiffs/KinveyKit160APIDiffs.html)
** Release Date: ** July 30th, 2012

* Added `KCSUserDiscovery` to provide a method to lookup other users based upon criteria like name and email address. 
* Upgraded Urban Airship library to 1.2.2.
* Documentation Updates.
    * Added API difference lists for KinveyKit versions 1.4.0, 1.5.0, and 1.6.0
    * Added tutorial for using 3rd Party APIs with OAuth 2.0
* Bug Fix(es).
    * Changed `KCSSortDirection` constants `kKCSAscending` and `kKCSDescending` to sort in the proscribed orders. If you were using the constants as intended, no change is needed. If you swaped them or modified their values to work around the bug, plus update to use the new constants. 

## 1.5

### 1.5.0 [<sub>api diff</sub>](Documents/releasenotes/General/KinveyKit150APIDiffs/KinveyKit150APIDiffs.html)
** Release Date: ** July 10th, 2012

* Added `KCSMetadata` for entities to map by `KCSEntityKeyMetadata` in `hostToKinveyPropertyMapping`. This provides metadata about the entity and allows for fine-grained read/write permissions. 
* Added `KCSLinkedAppdataStore` to allow for the saving/loading of `UIImage` properties automatically from our resource service. 

## 1.4

### 1.4.0 [<sub>api diff</sub>](Documents/releasenotes/General/KinveyKit140APIDiffs/KinveyKit140APIDiffs.html)
** Release Date: ** June 7th, 2012

* Added`KCSCachedStore` for caching queries to collections. 
* Added aggregation support (`groupBy:`) to `KCSStore` for app data collections. 

## 1.3

### 1.3.1
** Release Date: ** May 7th, 2012

* Fixed defect in Resource Service that prevented downloading resources on older iOS versions (< 5.0)

### 1.3.0
** Release Date: ** April 1st, 2012

* Migrate to using SecureUDID
* General memory handling improvements
* Library now checks reachability prior to making a request and calls failure delegate if Kinvey is not reachable.
* Fixed several known bugs

## 1.2

### 1.2.1
** Release Date: ** Februrary 22, 2012

* Update user-agent string to show correct revision

### 1.2.0
** Release Date: ** Februrary 14, 2012

* Updated query interface (See KCSQuery)
* Support for GeoQueries
* Added features to check-reachability
* Stability improvements
* Documentation improvements

## 1.1

### 1.1.1
** Release Date: ** January 24th, 2012

* Fix namespace collision issues.
* Added support for Core Data (using a designated initializer to build objects)

### 1.1.0
** Release Date: ** January 24th, 2012

* Added support for NSDates
* Added full support for Kinvey Users (See KCSUser)
* Stability improvements

## 1.0

### 1.0.0
** Release Date: ** January 20th, 2012

* Initial release of Kinvey Kit
* Basic support for users, appdata and resources
* Limited release
