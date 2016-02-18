//
//  RealmLogger.swift
//  RealmResultsController
//
//  Created by Pol Quintana on 6/8/15.
//  Copyright © 2015 Redbooth.
//

import Foundation
import RealmSwift

/**
 Internal RealmResultsController class
 In charge of listen to Realm notifications and notify the RRCs when finished
 A logger is associated with one and only one Realm.
*/
class RealmLogger {
    var realm: Realm
    var temporary: [String : RealmChange] = [:]
    var notificationToken: NotificationToken?
    
    init(realm: Realm) {
        self.realm = realm
        
        if NSThread.isMainThread() {
            registerNotificationBlock()
        }
        else {
            CFRunLoopPerformBlock(CFRunLoopGetCurrent(), kCFRunLoopDefaultMode) {
                self.registerNotificationBlock()
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopRun()
        }
    }
    
    @objc func registerNotificationBlock() {
        self.notificationToken = self.realm.addNotificationBlock { notification, realm in
            if notification == .DidChange {
                self.finishRealmTransaction()
            }
        }
    }
    
    /**
    When a Realm finish a write transaction, notify any active RRC via NSNotificaion
    Then clean the current state.
    */
    func finishRealmTransaction() {
        let name = realm.path.hasSuffix("testingRealm") ? "realmChangesTest" : "realmChanges"
        let values = [RealmChange](temporary.values)
        NSNotificationCenter.defaultCenter().postNotificationName(name, object: [realm.path : values])
        postIndividualNotifications(values)
        cleanAll()
    }
    
    /**
    Posts a notification for every change occurred in Realm
    */
    func postIndividualNotifications(values: [RealmChange]) {
        for change: RealmChange in values {
            guard let object = change.mirror else { continue }
            guard let name = object.objectIdentifier() else { continue }
            NSNotificationCenter.defaultCenter().postNotificationName(name, object: change)
        }
    }
    
    func didAdd<T: Object>(object: T) {
        addObject(object, action: .Add)
    }
    
    func didUpdate<T: Object>(object: T) {
        addObject(object, action: .Update)
    }
    
    func didDelete<T: Object>(object: T) {
        addObject(object, action: .Delete)
    }
    
    /**
    When there is an operation in a Realm, instead of keeping a reference to the original object
    we create a mirror that is thread safe and can be passed to RRC to operate with it safely.
    :warning: the relationships of the Mirror are not thread safe.
    
    - parameter object Object that is involed in the transaction
    - parameter action Action that was performed on that object
    */
    func addObject<T: Object>(object: T, action: RealmAction) {
        let realmChange = RealmChange(type: (object as Object).dynamicType, action: action, mirror: object.getMirror())
        guard let key = realmChange.mirror?.objectIdentifier() else { return }
        if let oldChange = temporary[key] {
            warnDuplicated(T.self, originalChange: oldChange.action, newChange: action)
        }
        temporary[key] = realmChange
    }
    
    
    func warnDuplicated(type: Object.Type, originalChange: RealmAction, newChange: RealmAction) {
        NSLog("[WARNING] Attempt to \(newChange) a \(type) object that had a previous action (\(originalChange)). Last change (\(newChange)) prevails")
        NSLog("Set a symbolic breakpoint on 'RealmLogger.warnDuplicated' to debug this error")
    }
    
    func cleanAll() {
        temporary.removeAll()
    }
}
