//
//  HttpNetworkTransport.swift
//  Kinvey
//
//  Created by Victor Barros on 2015-12-08.
//  Copyright © 2015 Kinvey. All rights reserved.
//

import Foundation

class HttpRequestFactory: RequestFactory {
    
    let client: Client
    
    required init(client: Client) {
        self.client = client
    }
    
    typealias CompletionHandler = (NSData?, NSURLResponse?, NSError?) -> Void
    
    func buildUserSignUp(username username: String? = nil, password: String? = nil) -> HttpRequest {
        let request = HttpRequest(httpMethod: .Post, endpoint: Endpoint.User(client: client), client: client)
        
        request.request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var bodyObject = JsonDictionary()
        if let username = username {
            bodyObject["username"] = username
        }
        if let password = password {
            bodyObject["password"] = password
        }
        request.request.HTTPBody = toJson(bodyObject)
        return request
    }
    
    func buildUserDelete(userId userId: String, hard: Bool) -> HttpRequest {
        let request = HttpRequest(httpMethod: .Delete, endpoint: Endpoint.UserById(client: client, userId: userId), credential: client.activeUser, client: client)
        
        //FIXME: make it configurable
        request.request.setValue("2", forHTTPHeaderField: "X-Kinvey-API-Version")
        
        var bodyObject = JsonDictionary()
        if hard {
            bodyObject["hard"] = true
        }
        request.request.HTTPBody = toJson(bodyObject)
        return request
    }
    
    func buildUserLogin(username username: String, password: String) -> HttpRequest {
        let request = HttpRequest(httpMethod: .Post, endpoint: Endpoint.UserLogin(client: client), client: client)
        request.request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let bodyObject = [
            "username" : username,
            "password" : password
        ]
        request.request.HTTPBody = toJson(bodyObject)
        return request
    }
    
    func buildUserExists(username username: String) -> HttpRequest {
        let request = HttpRequest(httpMethod: .Post, endpoint: Endpoint.UserExistsByUsername(client: client), client: client)
        request.request.HTTPMethod = "POST"
        
        request.request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let bodyObject = ["username" : username]
        request.request.HTTPBody = toJson(bodyObject)
        return request
    }
    
    func buildUserGet(userId userId: String) -> HttpRequest {
        let request = HttpRequest(endpoint: Endpoint.UserById(client: client, userId: userId), credential: client.activeUser, client: client)
        return request
    }
    
    func buildUserSave(user user: User) -> HttpRequest {
        let request = HttpRequest(httpMethod: .Put, endpoint: Endpoint.UserById(client: client, userId: user.userId), credential: client.activeUser, client: client)
        request.request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let bodyObject = user.toJson()
        request.request.HTTPBody = toJson(bodyObject)
        return request
    }
    
    func buildUserResetPassword(usernameOrEmail usernameOrEmail: String) -> HttpRequest {
        let request = HttpRequest(httpMethod: .Post, endpoint: Endpoint.UserResetPassword(usernameOrEmail: usernameOrEmail, client: client), credential: client, client: client)
        return request
    }
    
    func buildUserForgotUsername(email email: String) -> HttpRequest {
        let request = HttpRequest(httpMethod: .Post, endpoint: Endpoint.UserForgotUsername(client: client), credential: client, client: client)
        request.request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let bodyObject = ["email" : email]
        request.request.HTTPBody = toJson(bodyObject)
        return request
    }
    
    func buildAppDataGetById(collectionName collectionName: String, id: String) -> HttpRequest {
        let request = HttpRequest(endpoint: Endpoint.AppDataById(client: client, collectionName: collectionName, id: id), credential: client.activeUser, client: client)
        return request
    }
    
    func buildAppDataFindByQuery(collectionName collectionName: String, query: Query, fields: Set<String>?) -> HttpRequest {
        let request = HttpRequest(endpoint: Endpoint.AppDataByQuery(client: client, collectionName: collectionName, query: query, fields: fields), credential: client.activeUser, client: client)
        return request
    }
    
    func buildAppDataSave<T: Persistable>(persistable: T) -> HttpRequest {
        let collectionName = T.kinveyCollectionName()
        let bodyObject = T.toJson(persistable: persistable)
        let objId = bodyObject[Kinvey.PersistableIdKey] as? String
        let isNewObj = objId == nil
        let request = HttpRequest(
            httpMethod: isNewObj ? .Post : .Put,
            endpoint: isNewObj ? Endpoint.AppData(client: client, collectionName: collectionName) : Endpoint.AppDataById(client: client, collectionName: collectionName, id: objId!),
            credential: client.activeUser,
            client: client
        )
        
        request.request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.request.HTTPBody = toJson(bodyObject)
        return request
    }
    
    func buildAppDataRemoveByQuery(collectionName collectionName: String, query: Query) -> HttpRequest {
        let request = HttpRequest(
            httpMethod: .Delete,
            endpoint: Endpoint.AppDataByQuery(client: client, collectionName: collectionName, query: query, fields: nil),
            credential: client.activeUser,
            client: client
        )
        return request
    }
    
    func buildAppDataRemoveById(collectionName collectionName: String, objectId: String) -> HttpRequest {
        let request = HttpRequest(
            httpMethod: .Delete,
            endpoint: Endpoint.AppDataById(client: client, collectionName: collectionName, id: objectId),
            credential: client.activeUser,
            client: client
        )
        return request
    }
    
    func buildPushRegisterDevice(deviceToken: NSData) -> HttpRequest {
        let request = HttpRequest(
            httpMethod: .Post,
            endpoint: Endpoint.PushRegisterDevice(client: client),
            credential: client.activeUser,
            client: client
        )
        
        let bodyObject = [
            "platform" : "ios",
            "deviceId" : deviceToken.hexString()
        ]
        request.request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.request.HTTPBody = toJson(bodyObject)
        return request
    }
    
    func buildPushUnRegisterDevice(deviceToken: NSData) -> HttpRequest {
        let request = HttpRequest(
            httpMethod: .Post,
            endpoint: Endpoint.PushUnRegisterDevice(client: client),
            credential: client.activeUser,
            client: client
        )
        
        let bodyObject = [
            "platform" : "ios",
            "deviceId" : deviceToken.hexString()
        ]
        request.request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.request.HTTPBody = toJson(bodyObject)
        return request
    }
    
    func buildBlobUploadFile(file: File) -> HttpRequest {
        let request = HttpRequest(
            httpMethod: file.fileId == nil ? .Post : .Put,
            endpoint: Endpoint.BlobUpload(client: client, fileId: file.fileId, tls: true),
            credential: client.activeUser,
            client: client
        )
        
        var bodyObject: [String : AnyObject] = [
            "_public" : file.publicAccessible
        ]
        
        if let fileId = file.fileId {
            bodyObject["_id"] = fileId
        }
        
        if let fileName = file.fileName {
            bodyObject["_filename"] = fileName
        }
        
        if let size = file.size {
            bodyObject["size"] = String(size)
        }
        
        if let mimeType = file.mimeType {
            bodyObject["mimeType"] = mimeType
        }
        
        request.request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.request.setValue(file.mimeType ?? "application/octet-stream", forHTTPHeaderField: "X-Kinvey-Content-Type")
        request.request.HTTPBody = toJson(bodyObject)
        return request
    }
    
    func buildBlobDownloadFile(file: File, ttl: TTL?) -> HttpRequest {
        let request = HttpRequest(
            httpMethod: .Get,
            endpoint: Endpoint.BlobDownload(client: client, fileId: file.fileId!, query: nil, tls: true, ttlInSeconds: nil),
            credential: client.activeUser,
            client: client
        )
        return request
    }
    
    func buildBlobDeleteFile(file: File) -> HttpRequest {
        let request = HttpRequest(
            httpMethod: .Delete,
            endpoint: Endpoint.BlobById(client: client, fileId: file.fileId!),
            credential: client.activeUser,
            client: client
        )
        return request
    }
    
    func buildBlobQueryFile(query: Query, ttl: TTL?) -> HttpRequest {
        let request = HttpRequest(
            httpMethod: .Get,
            endpoint: Endpoint.BlobDownload(client: client, fileId: nil, query: query, tls: true, ttlInSeconds: nil),
            credential: client.activeUser,
            client: client
        )
        return request
    }
    
    func buildCustomEndpoint(name: String) -> HttpRequest {
        let request = HttpRequest(
            httpMethod: .Post,
            endpoint: Endpoint.CustomEndpooint(client: client, name: name),
            credential: client.activeUser,
            client: client
        )
        return request
    }

}
