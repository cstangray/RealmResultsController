//
//  RealmThreadHelper.swift
//  RealmResultsController
//
//  Created by Isaac Roldan on 7/10/15.
//  Copyright © 2015 Redbooth. All rights reserved.
//

import Foundation


struct Threading {
    /**
     Execute a block in the main thread.
     If we are already in it, just execute. If not, do a dispatch to execute it.
     
     You can select if the execution should be sync or async (careful with deadlocks!!)
     
     - parameter sync:  Bool, true if the execution should be dispatch_sync, false for dispatch_async
     - parameter block: Block to execute
     */
    static func executeOnMainThread(sync: Bool = false, block: ()->()) {
        if NSThread.currentThread().isMainThread {
            block()
        }
        executeOnQueue(dispatch_get_main_queue(), sync: sync, block: block)
    }
    
    /**
     Execute a block in the passed queue.
     
     You can select if the execution should be sync or async (careful with deadlocks!!)
     
     - parameter sync:  Bool, true if the execution should be dispatch_sync, false for dispatch_async
     - parameter block: Block to execute
     */
    static func executeOnQueue(queue: dispatch_queue_t, sync: Bool = false, block: ()->()) {
        sync ? dispatch_sync(queue, block) : dispatch_async(queue, block)
    }
}