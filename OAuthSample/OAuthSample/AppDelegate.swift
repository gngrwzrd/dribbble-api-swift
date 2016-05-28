//
//  AppDelegate.swift
//  OAuthSample
//
//  Created by Aaron Smith on 3/23/16.
//  Copyright © 2016 gngrwzrd. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
	var window: UIWindow?
    
	func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
		// Override point for customization after application launch.
		return true
	}
    
    func application(application: UIApplication, handleOpenURL url: NSURL) -> Bool {
        DribbbleAuth.defaultInstance.handleAuthCallbackWithURL(url)
        return true
    }
    
}

