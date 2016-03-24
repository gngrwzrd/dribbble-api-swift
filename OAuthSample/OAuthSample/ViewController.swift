//
//  ViewController.swift
//  OAuthSample
//
//  Created by Aaron Smith on 3/23/16.
//  Copyright © 2016 gngrwzrd. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}
    
    @IBAction func authorize(sender:AnyObject?) {
        let clientId = "719d0fba9b7a815b3da02caa7cebb929b73b79e25a0f85c1fd0edfc06db6fe05"
        let clientSecret = "331835562693e8c04f2e875f9ea7f5df92bfeb3895f7603af535aacd55642243"
        DribbbleAuth.defaultInstance().restoreWithClientId(clientId, clientSecret: clientSecret)
        let scopes:Set<DribbbleAuthScopes> = [DribbbleAuthScopes.Public]
        
        if !DribbbleAuth.defaultInstance().isAuthenticated() {
            DribbbleAuth.defaultInstance().authenticateWithScopes(scopes) { (error:NSError?) -> Void in
                print(error)
                print("isAuthed:",DribbbleAuth.defaultInstance().isAuthenticated())
            }
        } else {
            print("already authed");
        }
    }
}

