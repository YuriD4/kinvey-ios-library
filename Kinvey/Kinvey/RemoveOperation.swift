//
//  RemoveOperation.swift
//  Kinvey
//
//  Created by Victor Barros on 2016-02-15.
//  Copyright © 2016 Kinvey. All rights reserved.
//

import Foundation

class RemoveOperation<T: Persistable where T: NSObject>: WriteOperation<T, UInt> {
    
    let query: Query
    
    init(query: Query, writePolicy: WritePolicy, sync: Sync, cache: Cache, client: Client) {
        self.query = query
        super.init(writePolicy: writePolicy, sync: sync, cache: cache, client: client)
    }
    
    override func executeLocal(completionHandler: CompletionHandler? = nil) -> Request {
        let request = LocalRequest()
        request.execute() { data, response, error in
            self.query.persistableClass = T.self
            let count = self.cache.removeEntitiesByQuery(self.query)
            let request = self.client.networkRequestFactory.buildAppDataRemoveByQuery(collectionName: T.kinveyCollectionName(), query: self.query)
            self.sync.savePendingOperation(self.sync.createPendingOperation(request.request, objectId: nil))
            completionHandler?(count, nil)
        }
        return request
    }
    
    override func executeNetwork(completionHandler: CompletionHandler? = nil) -> Request {
        let request = client.networkRequestFactory.buildAppDataRemoveByQuery(collectionName: T.kinveyCollectionName(), query: query)
        request.execute() { data, response, error in
            if let response = response where response.isResponseOK,
                let results = self.client.responseParser.parse(data, type: [String : AnyObject].self),
                let count = results["count"] as? UInt
            {
                self.cache.removeEntitiesByQuery(self.query)
                completionHandler?(count, nil)
            } else if let error = error {
                completionHandler?(nil, error)
            } else {
                completionHandler?(nil, Error.InvalidResponse)
            }
        }
        return request
    }
    
}
