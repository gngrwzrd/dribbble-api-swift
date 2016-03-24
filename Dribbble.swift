
import UIKit

typealias DribbbleAuthCompletion = (NSError?)->Void
typealias DribbbleApiCompletion = (DribbbleApiResult)->Void

let DribbbleErrorDomain:String = "com.dribbble.Error"
let DribbbleErrorCodeAPIError = 0
let DribbbleErrorCodeOAuthError = 1

enum DribbbleAuthScopes:String {
	case Public
	case Write
	case Comment
	case Upload
}

struct DribbbleApiResult {
	var error:NSError?
	var responseStatusCode:Int?
	var response:NSHTTPURLResponse?
	var responseData:NSData?
	var decodedJSON:AnyObject?
}

class DribbbleAuth : NSObject {
	
	private var clientId:String?
	private var clientSecret:String?
	private var token:String?
	private var authCompletion:DribbbleAuthCompletion!
	
	//default configured instance
	static let _defaultInstance:DribbbleAuth = DribbbleAuth()
	static func defaultInstance() -> DribbbleAuth {
		return _defaultInstance
	}
	
	//call to set clientId/clientSecret, optional token. If a previous token was
	//received from a previous OAuth authentication, that will be restored for you
	func restoreWithClientId(clientId:String, clientSecret:String, token:String? = nil) {
		self.clientId = clientId
		self.clientSecret = clientSecret
		self.token = token
		if token == nil {
			if let savedToken = NSUserDefaults.standardUserDefaults().objectForKey("token_\(clientId)") as? String {
				self.token = savedToken
			}
		}
	}
	
	//call to start authentication process
	func authenticateWithScopes(scopes:Set<DribbbleAuthScopes>, completion:DribbbleAuthCompletion) {
		self.authCompletion = completion
		var authURL = "https://dribbble.com/oauth/authorize?client_id=\(self.clientId!)&scope=";
		for scope in scopes {
			authURL += scope.rawValue.lowercaseString + "+"
		}
		let url = NSURL(string: authURL)
		UIApplication.sharedApplication().openURL(url!)
	}
	
	//call with the callback from dribbble, in application:handleOpenURL:
	func handleAuthCallbackWithURL(url:NSURL) {
		//extract code from url
		let components = NSURLComponents(string: url.absoluteString)
		var code:String?
		for component in (components?.queryItems)! {
			if component.name == "code" {
				code = component.value
			}
		}
		
		//check if we have a code
		if code == nil {
			let userInfo = ["Error":"No code parameter in callback"]
			let error = NSError(domain: DribbbleErrorDomain, code: DribbbleErrorCodeOAuthError, userInfo:userInfo)
			self.authCompletion(error)
			return
		}
		
		//sertup request body
		let params = ["code":code!,"client_id":clientId!,"client_secret":clientSecret!];
		var json:NSData?
		do {
			json = try NSJSONSerialization.dataWithJSONObject(params, options: NSJSONWritingOptions())
		} catch let error as NSError {
			self.authCompletion(error)
			return
		}
		
		//compose request
		let tokenURL = NSURL(string: "https://dribbble.com/oauth/token")
		let request = NSMutableURLRequest(URL: tokenURL!)
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.HTTPBody = json
		request.HTTPMethod = "POST"
		
		//send the request
		let task = NSURLSession.sharedSession().dataTaskWithRequest(request) { (data:NSData?, response:NSURLResponse?, error:NSError?) in
			
			//error
			if error != nil {
				self.authCompletion(error)
				return
			}
			
			//grab results
			var results:[String:AnyObject]?
			if data != nil {
				do {
					try results = NSJSONSerialization.JSONObjectWithData(data!, options: NSJSONReadingOptions()) as? Dictionary<String,AnyObject>
				} catch let error as NSError {
					self.authCompletion(error)
					return
				}
				
				//check for errors from dribbble
				if let errorType = results?["error"], errorDescription = results?["error_description"] {
					var userInfo = [String:AnyObject]()
					userInfo["Error"] = errorType as! String
					userInfo["ErrorDescription"] = errorDescription as! String
					NSUserDefaults.standardUserDefaults().removeObjectForKey("token_\(self.clientId)")
					let error = NSError(domain: DribbbleErrorDomain, code: DribbbleErrorCodeOAuthError, userInfo:userInfo)
					self.authCompletion(error)
					return
				}
				
				//grab access token and save it
				if let access_token = results?["access_token"] as? String {
					self.token = access_token
					NSUserDefaults.standardUserDefaults().setObject(access_token, forKey: "token_\(self.clientId!)")
				}
				
				//callback
				self.authCompletion(error)
			}
		}
		
		task.resume()
	}
	
	//check if a token is available
	func isAuthenticated() -> Bool {
		return self.token != nil
	}
}

//DribbbleApi to make api calls. Methods are named according to the API here http://developer.dribbble.com/v1/

class DribbbleApi : NSObject {
	
	private var auth:DribbbleAuth;
	
	init?(withDribbbleAuth dribbbleAuth:DribbbleAuth) {
		self.auth = dribbbleAuth
		super.init()
		if !dribbbleAuth.isAuthenticated() {
			return nil
		}
	}
	
	func makeRequest(var forAPIEndpoint endpoint:String, method:String, queryParams:[String:String]? = nil, rawBody:NSData? = nil) -> NSURLRequest {
		endpoint += "?"
		if queryParams != nil {
			for (key,val) in queryParams! {
				endpoint += "&" + key + "=" + val
			}
		}
		endpoint += "&access_token=" + self.auth.token!
		let url = NSURL(string: endpoint)!
		let request = NSMutableURLRequest(URL: url)
		request.HTTPBody = rawBody
		request.HTTPMethod = method
		return request
	}
	
	func makeFormEncodedJSONRequest(var forAPIEndpoint endpoint:String, method:String, body:NSData) -> NSURLRequest {
		endpoint += "?access_token=" + self.auth.token!
		let url = NSURL(string: endpoint)!
		let request = NSMutableURLRequest(URL: url)
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		request.HTTPMethod = method
		request.HTTPBody = body
		return request
	}
	
	func makeMultipartRequest(var forAPIEndpoint endpoint:String, method:String, formParams:[String:AnyObject]) -> NSURLRequest {
		endpoint += "?access_token=" + self.auth.token!
		
		let url = NSURL(string: endpoint)!
		let request = NSMutableURLRequest(URL: url)
		let postData = NSMutableData()
		let boundary = "14737809831466499882746641449"
		
		for (key,value) in formParams {
			if value is NSData {
				let boundaryString = "--\(boundary)\r\n"
				let disposition = "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(key)\"\r\n"
				let contentType = "Content-Type: application/octet-stream\r\n\r\n"
				postData.appendData(boundaryString.dataUsingEncoding(NSUTF8StringEncoding)!)
				postData.appendData(disposition.dataUsingEncoding(NSUTF8StringEncoding)!)
				postData.appendData(contentType.dataUsingEncoding(NSUTF8StringEncoding)!)
				postData.appendData(value as! NSData)
				let newLine = "\r\n"
				postData.appendData(newLine.dataUsingEncoding(NSUTF8StringEncoding)!)
			} else {
				let boundaryString = "--\(boundary)\r\n"
				let disposition = "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n"
				postData.appendData(boundaryString.dataUsingEncoding(NSUTF8StringEncoding)!)
				postData.appendData(disposition.dataUsingEncoding(NSUTF8StringEncoding)!)
			}
			let boundaryString = "--\(boundary)\r\n"
			postData.appendData(boundaryString.dataUsingEncoding(NSUTF8StringEncoding)!)
		}
		
		request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
		request.setValue(postData.length, forKey: "Content-Length")
		request.HTTPMethod = method
		request.HTTPBody = postData
		return request
	}
	
	func sendSimpleRequest(apiPath:String, method:String, queryParams:[String:String]? = nil, rawBody:NSData? = nil, completion:DribbbleApiCompletion) {
		let api = "https://api.dribbble.com/v1/" + apiPath
		let apiRequest = makeRequest(forAPIEndpoint: api, method: method, queryParams: queryParams, rawBody: rawBody)
		let task = NSURLSession.sharedSession().dataTaskWithRequest(apiRequest) { (data:NSData?, response:NSURLResponse?, error:NSError?) in
			self.handleAPIRequestResponse(data, response: response, error: error, completion: completion)
		}
		task.resume()
	}
	
	func sendMultipartRequest(apiPath:String, method:String, formParams:[String:AnyObject], completion:DribbbleApiCompletion) {
		let api = "https://api.dribbble.com/v1/" + apiPath
		let apiRequest = makeMultipartRequest(forAPIEndpoint: api, method: method, formParams: formParams)
		let task = NSURLSession.sharedSession().dataTaskWithRequest(apiRequest) { (data:NSData?, response:NSURLResponse?, error:NSError?) in
			self.handleAPIRequestResponse(data, response: response, error: error, completion: completion)
		}
		task.resume()
	}
	
	func sendFormEncodedJSONRequest(apiPath:String, method:String, parameters:[String:AnyObject]?, completion:DribbbleApiCompletion) throws {
		let encoded = try NSJSONSerialization.dataWithJSONObject(parameters!, options: NSJSONWritingOptions())
		let api = "https://api.dribbble.com/v1/" + apiPath
		let apiRequest = makeFormEncodedJSONRequest(forAPIEndpoint: api, method: method, body: encoded)
		let task = NSURLSession.sharedSession().dataTaskWithRequest(apiRequest) { (data:NSData?, response:NSURLResponse?, error:NSError?) in
			self.handleAPIRequestResponse(data, response: response, error: error, completion: completion)
		}
		task.resume()
	}
	
	func handleAPIRequestResponse(data:NSData?, response:NSURLResponse?, error:NSError?, completion:DribbbleApiCompletion) {
		//setup a result struct
		let httpResponse = response as! NSHTTPURLResponse
		let headers = httpResponse.allHeaderFields
		var resultStruct = DribbbleApiResult(error: error, responseStatusCode: httpResponse.statusCode, response: httpResponse, responseData: data, decodedJSON: nil)
		
		//check for error
		if error != nil {
			completion(resultStruct)
			return
		}
		
		//if result is json decode it
		if let contentType = headers["Content-Type"] as? String {
			if contentType == "application/json" {
				//get json results
				var results:AnyObject?
				do {
					try results = NSJSONSerialization.JSONObjectWithData(data!, options: NSJSONReadingOptions.AllowFragments)
					resultStruct.decodedJSON = results
				} catch let error as NSError {
					resultStruct.error = error
					completion(resultStruct)
					return
				}
				
				//check for custom error in json response
				if let errorDescription = results?["error_description"] as? String {
					resultStruct.decodedJSON = results
					let error = NSError(domain: DribbbleErrorDomain, code: DribbbleErrorCodeAPIError, userInfo:["ErrorDescription":errorDescription])
					resultStruct.error = error
					completion(resultStruct)
					return
				}
			}
		}
		
		completion(resultStruct)
	}
	
	//MARK: Buckets - http://developer.dribbble.com/v1/buckets/
	
	func getABucket(bucketId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("buckets/\(bucketId)", method: "GET", completion: completion)
	}
	
	func createABucket(parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("buckets", method: "POST", parameters: parameters, completion: completion)
	}
	
	func updateABucket(parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("buckets", method: "PUT", parameters: parameters, completion: completion)
	}
	
	func deleteABucket(bucketId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("buckets/\(bucketId)", method: "DELETE", completion: completion)
	}
	
	//MARK: Buckets/Shots - http://developer.dribbble.com/v1/buckets/shots/
	
	func listShotsForABucket(bucketId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("buckets/\(bucketId)/shots", method: "GET", completion: completion)
	}
	
	func addAShotToABucket(bucketId:String, parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("buckets/\(bucketId)/shots", method: "PUT", parameters: parameters, completion: completion)
	}
	
	func removeAShotFromABucket(bucketId:String, parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("buckets/\(bucketId)/shots", method: "DELETE", parameters: parameters, completion: completion)
	}
	
	//MARK: Projects - http://developer.dribbble.com/v1/projects/
	
	func getAProject(projectId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("projects/\(projectId)", method: "GET", completion: completion)
	}
	
	//MARK: Projects/Shots - http://developer.dribbble.com/v1/projects/shots/
	
	func listShotsForAProject(projectId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("projects/\(projectId)/shots", method: "GET", completion: completion)
	}
	
	//MARK: Shots - http://developer.dribbble.com/v1/shots/
	
	func listShots(parameters:[String:String]?, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots", method: "GET", queryParams: parameters, completion: completion)
	}
	
	func getAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots\(shotId)", method: "GET", completion: completion)
	}
	
	func createAShot(parameters:[String:AnyObject], completion:DribbbleApiCompletion) {
		sendMultipartRequest("shots", method: "POST", formParams: parameters, completion: completion)
	}
	
	func updateAShot(shotId:String, parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("shots/\(shotId)", method: "PUT", parameters: parameters, completion: completion)
	}
	
	func deleteAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)", method: "DELETE", completion: completion)
	}
	
	//MARK: Shots/Attachments - http://developer.dribbble.com/v1/shots/attachments/
	
	func listAttachmentsForShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/attachments", method: "GET", completion: completion)
	}
	
	func createAttachment(shotId:String, parameters:[String:AnyObject], completion:DribbbleApiCompletion) {
		sendMultipartRequest("shots/\(shotId)/attachments", method: "POST", formParams: parameters, completion: completion)
	}
	
	func getASingleAttachment(shotId:String, attachmentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/attachments/\(attachmentId)", method: "GET", completion: completion)
	}
	
	func deleteAnAttachment(shotId:String, attachmentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/attachments/\(attachmentId)", method: "DELETE", completion: completion)
	}
	
	//MARK: Shots/Buckets - http://developer.dribbble.com/v1/shots/buckets/
	
	func listBucketsForAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/buckets", method: "GET", completion: completion)
	}
	
	//MARK: Shots/Comments - http://developer.dribbble.com/v1/shots/comments/
	
	func listCommentsForAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments", method: "GET", completion: completion)
	}
	
	func listLikesForAComment(shotId:String, commentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments/\(commentId)/likes", method: "GET", completion: completion)
	}
	
	func createAComment(shotId:String, parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("shots/\(shotId)/comments", method: "POST", parameters: parameters, completion: completion)
	}
	
	func getASingleComment(shotId:String, commentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments/\(commentId)", method: "GET", completion: completion)
	}
	
	func updateAComment(shotId:String, commentId:String, parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("shots/\(shotId)/comments/\(commentId)", method: "PUT", parameters: parameters, completion: completion)
	}
	
	func deleteAComment(shotId:String, commentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments/\(commentId)", method: "DELETE", completion: completion)
	}
	
	func checkIfYouLikeAComment(shotId:String, commentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments/\(commentId)/like", method: "GET", completion: completion)
	}
	
	func likeAComment(shotId:String, commentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments/\(commentId)/like", method: "POST", completion: completion)
	}
	
	func unlikeAComment(shotId:String, commentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments/\(commentId)/unlike", method: "DELETE", completion: completion)
	}
	
	//MARK: Shots/Likes - http://developer.dribbble.com/v1/shots/likes/
	
	func listLikesForAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/likes", method: "GET", completion: completion)
	}
	
	func checkIfYouLikeAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/like", method: "GET", completion: completion)
	}
	
	func likeShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/like", method: "POST", completion: completion)
	}
	
	func unlikeShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/like", method: "DELETE", completion: completion)
	}
	
	//MARK: Shots/Projects - http://developer.dribbble.com/v1/shots/projects/
	
	func listProjectsForAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/projects", method: "GET", completion: completion)
	}
	
	//MARK: Shots/Rebounds http://developer.dribbble.com/v1/shots/rebounds/
	
	func listReboundsForAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/rebounds", method: "GET", completion: completion)
	}
	
	//MARK: Teams/Members - http://developer.dribbble.com/v1/teams/members/
	
	func listATeamsMembers(teamId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("teams/\(teamId)/members", method: "GET", completion: completion)
	}
	
	func listShotsForATeam(teamId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("teams/\(teamId)/shots", method: "GET", completion: completion)
	}
	
	//MARK: Users - http://developer.dribbble.com/v1/users/
	
	func getASingleUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)", method: "GET", completion: completion)
	}
	
	func getTheAuthenticatedUser(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user", method: "GET", completion: completion)
	}
	
	//MARK: Users/Buckets - http://developer.dribbble.com/v1/users/buckets/
	
	func listAUsersBuckets(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/buckets", method: "GET", completion: completion)
	}
	
	func listAuthedUsersBuckets(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/buckets", method: "GET", completion: completion)
	}
	
	//MARK: Users/Followers - http://developer.dribbble.com/v1/users/followers/
	
	func listFollowersOfAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/followers", method: "GET", completion: completion)
	}
	
	func listAuthedUsersFollowers(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/followers", method: "GET", completion: completion)
	}
	
	func listUsersFollowedByAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/following", method: "GET", completion: completion)
	}
	
	func listAuthedUserFollowing(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/following", method: "GET", completion: completion)
	}
	
	func listShotsForUsersFollowedByAuthedUser(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/following/shots", method: "GET", completion: completion)
	}
	
	func checkIfYouAreFollowingAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/following/\(username)", method: "GET", completion: completion)
	}
	
	func checkIfOneUserIsFollowingAnother(username:String, targetUsername:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/\(username)/following\(targetUsername)", method: "GET", completion: completion)
	}
	
	func followAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/follow", method: "PUT", completion: completion)
	}
	
	func unfollowAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/follow", method: "DELETE", completion: completion)
	}
	
	//MARK: Users/Likes - http://developer.dribbble.com/v1/users/likes/
	
	func listShotLikesForAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/likes", method: "GET", completion: completion)
	}
	
	func listShotLikesForAuthedUser(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/likes", method: "GET", completion: completion)
	}
	
	//MARK: Users/Projects - http://developer.dribbble.com/v1/users/projects/
	
	func listAUsersProjects(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/projects", method: "GET", completion: completion)
	}
	
	func listAuthedUsersProjects(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/projects", method: "GET", completion: completion)
	}
	
	//MARK: Users/Shots http://developer.dribbble.com/v1/users/shots/
	
	func listShotsForAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/shots", method: "GET", completion: completion)
	}
	
	func listAuthenticatedUsersShots(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/shots", method: "GET", completion: completion)
	}
	
	//MARK: Users/Teams - http://developer.dribbble.com/v1/users/teams/
	
	func listAUsersTeams(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/teams", method: "GET", completion: completion)
	}
	
	func listAuthedUsersTeams(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/teams", method: "GET", completion: completion)
	}
}

class DribbbleShotsCollection : NSObject {
	
}
