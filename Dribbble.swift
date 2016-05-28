
#if os(iOS)
	import UIKit
#elseif os(OSX)
	import Cocoa
#endif

/// Completion for DribbbleAuth authentication process.
public typealias DribbbleAuthCompletion = (NSError?)->Void

/// Completion for all DribbbleApi service methods.
public typealias DribbbleApiCompletion = (result:DribbbleApiResult)->Void

/// Domain for custom errors from this class.
public let DribbbleErrorDomain:String = "com.dribbble.Error"

/**
Dribbble error codes.

- APIError:	Any API error.
*/
public enum DribbbleErrorCode:Int {
    case APIError
}

/// DribbbleAuthScopes enum for oauth authentication scopes. http://developer.dribbble.com/v1/oauth/#scopes
public enum DribbbleAuthScopes:String {
	
	/// Grants read-only access to public information. This is the default scope if no scope is provided.
	case Public
	
	/// Grants write access to user resources, except comments and shots.
	case Write
	
	/// Grants full access to create, update, and delete comments.
	case Comment
	
	/// Grants full access to create, update, and delete shots and attachments.
	case Upload
}

/**
The *DribbbleApiResult* is a response object that contains all possible objects passed
back to your API call completions as a parameter to *DribbbleApiCompletion*.

Generally you should check the API documentation for any method you're calling as some
API responses use different mechanisms to describe an error. For example some methods
use a responseStatusCode other than 200 to indicate error. Others will use a
responseStatusCode of 200 but have a custom error in JSON.
*/
public class DribbbleApiResult : NSObject {
	
	/// Error
	public var error:NSError?
	
	/// Shortcut for HTTP response status code from the API.
	public var responseStatusCode:Int?
	
	/// Full request response.
	public var response:NSHTTPURLResponse?
	
	/// Raw response data.
	public var responseData:NSData?
	
	/// If response is json, this is the decoded json.
	public var decodedJSON:AnyObject?
	
	/**
	Initialize a DribbbleApiResult.
	
	- parameter error:              NSError.
	- parameter responseStatusCode: HTTP status code from response.
	- parameter response:           NSHTTPURLResponse from the api call.
	- parameter responseData:       Response data.
	- parameter decodedJSON:        Optionally decoded JSON.
	
	- returns: A new instance of DribbbleApiResult.
	*/
	public init(error:NSError?, responseStatusCode:Int?, response:NSHTTPURLResponse?, responseData:NSData?, decodedJSON:AnyObject?) {
		super.init()
		self.error = error
		self.responseStatusCode = responseStatusCode
		self.response = response
		self.responseData = responseData
		self.decodedJSON = decodedJSON
	}
}

/**
The *DribbblAuth* class handles the OAuth authentication process with Dribbble's API.
You pass an instance of this to a *DribbbleApi* instance before you can call API methods.

You need to call *restoreWithClientId(_:clientSecret:token:)* in order to initialize
the default instance properly.

    DribbbleAuth.defaultInstance.restoreWithClientId("myClientId",clientSecret:"myClientSecret")

Or you can initialize a new instance for some other use.

    let auth = DribbbleAuth()
    auth.restoreWithClientId("myClientId",clientSecret:"myClientSecret")

Optionally you can pass an already authenticated OAuth token if you have one available.

    let auth = DribbbleAuth()
    auth.restoreWithClientId("myClientId",clientSecret:"myClientSecret",token:"myToken")

After you've authenticated with OAuth, the token is saved in *NSUserDefaults*. Future calls to
*restoreWithClientId(_:clientSecret:)* will automatically load the saved token using *clientId*
as the key.
*/
public class DribbbleAuth : NSObject {
	
	/// api client id
	private var clientId:String?
	
	/// api client secret
	private var clientSecret:String?
	
	/// api token
	private var token:String?
	
	/// auth process completion
	private var authCompletion:DribbbleAuthCompletion!
	
	/// A default singleton instance
	public static let defaultInstance:DribbbleAuth = {
		let instance = DribbbleAuth()
		return instance
	}()
	
	/**
	Call this to set clientId and clientSecret. Token is an optional argument. Additionally
	this will save any tokens you pass to NSUserDefaults using the clientId as the key. If you
	pass nil for token, it will try and load a token from NSUserDefaults with clientId.
	
	- parameter clientId:         Dribbble API clientId
	- parameter clientSecret:     Dribbble API clientSecret
	- parameter token:            (Optional) API token
	*/
	public func restoreWithClientId(clientId:String, clientSecret:String, token:String? = nil) -> Bool {
		self.clientId = clientId
		self.clientSecret = clientSecret
		self.token = token
		if let token = token {
			NSUserDefaults.standardUserDefaults().setObject(token, forKey: "token_\(self.clientId!)")
			return true
		} else {
			if let savedToken = NSUserDefaults.standardUserDefaults().objectForKey("token_\(clientId)") as? String {
				self.token = savedToken
				return true
			}
		}
		return false
	}
	
	/**
	Call to start authentication process. On iOS Safari will open, on Mac the users' default browser
	will open to Dribbble prompting them to login. Your app needs to be registered for a custom URL
	callback.
	
	For iOS use:
	
	    application:handleOpenURL: in AppDelegate.m.
	
	For Mac use:
	
	    NSApppleEventManager.setEventHandler to register for a URL callback
	
	- parameter scopes:     A Set containing DribbbleAuthScopes enum values
	- parameter completion: A callback of type DribbbleAuthCompletion
	*/
	public func authenticateWithScopes(scopes:Set<DribbbleAuthScopes>, completion:DribbbleAuthCompletion) {
		authCompletion = completion
		var authURL = "https://dribbble.com/oauth/authorize?client_id=\(clientId!)&scope=";
		for scope in scopes {
			authURL += scope.rawValue.lowercaseString + "+"
		}
		let url = NSURL(string: authURL)
		#if os(iOS)
		UIApplication.sharedApplication().openURL(url!)
		#elseif os(OSX)
		NSWorkspace.sharedWorkspace().openURL(url!)
		#endif
	}
	
	/**
	Call this to finish the OAuth authentication process. The callback URL comes from
	Dribbble and should contain a "code" parameter.
	
	http://developer.dribbble.com/v1/oauth/
	
	- parameter url: The callback URL received by your application.
	*/
	public func handleAuthCallbackWithURL(url:NSURL) {
		
		//extract code from url
		let components = NSURLComponents(string: url.absoluteString)
		var code:String?
		for component in (components?.queryItems)! {
			if component.name == "code" {
				code = component.value
			}
		}
		
		//check if we have a code
		guard code != nil else {
			let userInfo = ["Error":"No code parameter in callback"]
			let error = NSError(domain: DribbbleErrorDomain, code: DribbbleErrorCode.APIError.rawValue, userInfo:userInfo)
			authCompletion(error)
			return
		}
		
		//setup request body
		let params = ["code":code!,"client_id":clientId!,"client_secret":clientSecret!];
		var json:NSData?
		do {
			json = try NSJSONSerialization.dataWithJSONObject(params, options: NSJSONWritingOptions())
		} catch let error as NSError {
			authCompletion(error)
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
					let error = NSError(domain: DribbbleErrorDomain, code: DribbbleErrorCode.APIError.rawValue, userInfo: userInfo)
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
	
	/**
	Check if a token is available, meaning you're authenticated.
	
	- returns: Bool if authenticated or not.
	*/
	public func isAuthenticated() -> Bool {
		return self.token != nil
	}
}

/// The DribbbleApi class is for making API calls. You initialize this with an instance of DribbbleAuth.
/// Methods are named according to the API here http://developer.dribbble.com/v1/.
/// For information about what's in the result callback refer to the Dribbble API docs for each specific endpoint.
public class DribbbleApi : NSObject {
	
	/// DribbbleAuth instance.
	var auth:DribbbleAuth;
	
	/**
	Initialize a DribbbleApi. This is a failable initializer - if your instance of dribbbleAuth is not
	authenticated it will fail.
	
	- parameter dribbbleAuth: An authenticated instance of DribbbleAuth
	
	- returns: self or nil
	*/
	public init?(withDribbbleAuth dribbbleAuth:DribbbleAuth) {
		if !dribbbleAuth.isAuthenticated() {
			return nil
		}
		auth = dribbbleAuth
		super.init()
	}
	
	func makeRequest(forAPIEndpoint endpoint:String, method:String, queryParams:[String:String]? = nil, rawBody:NSData? = nil) -> NSURLRequest {
		var newEndpoint = endpoint + "?"
		if queryParams != nil {
			for (key,val) in queryParams! {
				newEndpoint += "&" + key + "=" + val
			}
		}
		newEndpoint += "&access_token=" + auth.token!
		let url = NSURL(string: newEndpoint)!
		let request = NSMutableURLRequest(URL: url)
		request.HTTPBody = rawBody
		request.HTTPMethod = method
		return request
	}
	
	func makeFormEncodedJSONRequest(forAPIEndpoint endpoint:String, method:String, body:NSData) -> NSURLRequest {
		let newEndpoint = endpoint + "?access_token=" + auth.token!
		let url = NSURL(string: newEndpoint)!
		let request = NSMutableURLRequest(URL: url)
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		request.HTTPMethod = method
		request.HTTPBody = body
		return request
	}
	
	func makeMultipartRequest(forAPIEndpoint endpoint:String, method:String, formParams:[String:AnyObject]) -> NSURLRequest {
		let newEndpoint = endpoint + "?access_token=" + auth.token!
		let url = NSURL(string: newEndpoint)!
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
		let httpResponse = response as? NSHTTPURLResponse
		let headers = httpResponse?.allHeaderFields
		let resultStruct = DribbbleApiResult(error: error, responseStatusCode: httpResponse?.statusCode, response: httpResponse, responseData: data, decodedJSON: nil)
		
		//check for error
		guard error == nil else {
			completion(result: resultStruct)
			return
		}
		
		//if result is json decode it
		if let contentType = headers?["Content-Type"] as? String {
			if contentType.containsString("application/json") {
				//get json results
				var results:AnyObject?
				do {
					try results = NSJSONSerialization.JSONObjectWithData(data!, options: NSJSONReadingOptions.AllowFragments)
					resultStruct.decodedJSON = results
				} catch let error as NSError {
					resultStruct.error = error
					completion(result: resultStruct)
					return
				}
                
				//check for custom error in json response
				if let message = results?["message"] as? String {
					var userInfo:[String:AnyObject] = ["message":message]
					if let errors = results?["errors"] {
						userInfo["errors"] = errors
					}
					let error = NSError(domain: DribbbleErrorDomain, code: DribbbleErrorCode.APIError.rawValue , userInfo: userInfo)
					resultStruct.error = error
					completion(result: resultStruct)
					return
				}
			}
		}
		
		completion(result: resultStruct)
	}
	
	//MARK: Buckets - http://developer.dribbble.com/v1/buckets/
	
	public func getABucket(bucketId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("buckets/\(bucketId)", method: "GET", completion: completion)
	}
	
	public func createABucket(parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("buckets", method: "POST", parameters: parameters, completion: completion)
	}
	
	public func updateABucket(parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("buckets", method: "PUT", parameters: parameters, completion: completion)
	}
	
	public func deleteABucket(bucketId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("buckets/\(bucketId)", method: "DELETE", completion: completion)
	}
	
	//MARK: Buckets/Shots - http://developer.dribbble.com/v1/buckets/shots/
	
	public func listShotsForABucket(bucketId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("buckets/\(bucketId)/shots", method: "GET", completion: completion)
	}
	
	public func addAShotToABucket(bucketId:String, parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("buckets/\(bucketId)/shots", method: "PUT", parameters: parameters, completion: completion)
	}
	
	public func removeAShotFromABucket(bucketId:String, parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("buckets/\(bucketId)/shots", method: "DELETE", parameters: parameters, completion: completion)
	}
	
	//MARK: Projects - http://developer.dribbble.com/v1/projects/
	
	public func getAProject(projectId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("projects/\(projectId)", method: "GET", completion: completion)
	}
	
	//MARK: Projects/Shots - http://developer.dribbble.com/v1/projects/shots/
	
	public func listShotsForAProject(projectId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("projects/\(projectId)/shots", method: "GET", completion: completion)
	}
	
	//MARK: Shots - http://developer.dribbble.com/v1/shots/
	
	public func listShots(parameters:[String:String]?, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots", method: "GET", queryParams: parameters, completion: completion)
	}
	
	public func getAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots\(shotId)", method: "GET", completion: completion)
	}
	
	public func createAShot(parameters:[String:AnyObject], completion:DribbbleApiCompletion) {
		sendMultipartRequest("shots", method: "POST", formParams: parameters, completion: completion)
	}
	
	public func updateAShot(shotId:String, parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("shots/\(shotId)", method: "PUT", parameters: parameters, completion: completion)
	}
	
	public func deleteAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)", method: "DELETE", completion: completion)
	}
	
	//MARK: Shots/Attachments - http://developer.dribbble.com/v1/shots/attachments/
	
	public func listAttachmentsForShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/attachments", method: "GET", completion: completion)
	}
	
	public func createAttachment(shotId:String, parameters:[String:AnyObject], completion:DribbbleApiCompletion) {
		sendMultipartRequest("shots/\(shotId)/attachments", method: "POST", formParams: parameters, completion: completion)
	}
	
	public func getASingleAttachment(shotId:String, attachmentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/attachments/\(attachmentId)", method: "GET", completion: completion)
	}
	
	public func deleteAnAttachment(shotId:String, attachmentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/attachments/\(attachmentId)", method: "DELETE", completion: completion)
	}
	
	//MARK: Shots/Buckets - http://developer.dribbble.com/v1/shots/buckets/
	
	public func listBucketsForAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/buckets", method: "GET", completion: completion)
	}
	
	//MARK: Shots/Comments - http://developer.dribbble.com/v1/shots/comments/
	
	public func listCommentsForAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments", method: "GET", completion: completion)
	}
	
	public func listLikesForAComment(shotId:String, commentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments/\(commentId)/likes", method: "GET", completion: completion)
	}
	
	public func createAComment(shotId:String, parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("shots/\(shotId)/comments", method: "POST", parameters: parameters, completion: completion)
	}
	
	public func getASingleComment(shotId:String, commentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments/\(commentId)", method: "GET", completion: completion)
	}
	
	public func updateAComment(shotId:String, commentId:String, parameters:[String:String], completion:DribbbleApiCompletion) throws {
		try sendFormEncodedJSONRequest("shots/\(shotId)/comments/\(commentId)", method: "PUT", parameters: parameters, completion: completion)
	}
	
	public func deleteAComment(shotId:String, commentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments/\(commentId)", method: "DELETE", completion: completion)
	}
	
	public func checkIfYouLikeAComment(shotId:String, commentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments/\(commentId)/like", method: "GET", completion: completion)
	}
	
	public func likeAComment(shotId:String, commentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments/\(commentId)/like", method: "POST", completion: completion)
	}
	
	public func unlikeAComment(shotId:String, commentId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/comments/\(commentId)/unlike", method: "DELETE", completion: completion)
	}
	
	//MARK: Shots/Likes - http://developer.dribbble.com/v1/shots/likes/
	
	public func listLikesForAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/likes", method: "GET", completion: completion)
	}
	
	public func checkIfYouLikeAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/like", method: "GET", completion: completion)
	}
	
	public func likeShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/like", method: "POST", completion: completion)
	}
	
	public func unlikeShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/like", method: "DELETE", completion: completion)
	}
	
	//MARK: Shots/Projects - http://developer.dribbble.com/v1/shots/projects/
	
	public func listProjectsForAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/projects", method: "GET", completion: completion)
	}
	
	//MARK: Shots/Rebounds http://developer.dribbble.com/v1/shots/rebounds/
	
	public func listReboundsForAShot(shotId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("shots/\(shotId)/rebounds", method: "GET", completion: completion)
	}
	
	//MARK: Teams/Members - http://developer.dribbble.com/v1/teams/members/
	
	public func listATeamsMembers(teamId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("teams/\(teamId)/members", method: "GET", completion: completion)
	}
	
	public func listShotsForATeam(teamId:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("teams/\(teamId)/shots", method: "GET", completion: completion)
	}
	
	//MARK: Users - http://developer.dribbble.com/v1/users/
	
	public func getASingleUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)", method: "GET", completion: completion)
	}
	
	public func getTheAuthenticatedUser(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user", method: "GET", completion: completion)
	}
	
	//MARK: Users/Buckets - http://developer.dribbble.com/v1/users/buckets/
	
	public func listAUsersBuckets(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/buckets", method: "GET", completion: completion)
	}
	
	public func listAuthedUsersBuckets(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/buckets", method: "GET", completion: completion)
	}
	
	//MARK: Users/Followers - http://developer.dribbble.com/v1/users/followers/
	
	public func listFollowersOfAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/followers", method: "GET", completion: completion)
	}
	
	public func listAuthedUsersFollowers(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/followers", method: "GET", completion: completion)
	}
	
	public func listUsersFollowedByAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/following", method: "GET", completion: completion)
	}
	
	public func listAuthedUserFollowing(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/following", method: "GET", completion: completion)
	}
	
	public func listShotsForUsersFollowedByAuthedUser(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/following/shots", method: "GET", completion: completion)
	}
	
	public func checkIfYouAreFollowingAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/following/\(username)", method: "GET", completion: completion)
	}
	
	public func checkIfOneUserIsFollowingAnother(username:String, targetUsername:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/\(username)/following\(targetUsername)", method: "GET", completion: completion)
	}
	
	public func followAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/follow", method: "PUT", completion: completion)
	}
	
	public func unfollowAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/follow", method: "DELETE", completion: completion)
	}
	
	//MARK: Users/Likes - http://developer.dribbble.com/v1/users/likes/
	
	public func listShotLikesForAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/likes", method: "GET", completion: completion)
	}
	
	public func listShotLikesForAuthedUser(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/likes", method: "GET", completion: completion)
	}
	
	//MARK: Users/Projects - http://developer.dribbble.com/v1/users/projects/
	
	public func listAUsersProjects(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/projects", method: "GET", completion: completion)
	}
	
	public func listAuthedUsersProjects(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/projects", method: "GET", completion: completion)
	}
	
	//MARK: Users/Shots http://developer.dribbble.com/v1/users/shots/
	
	public func listShotsForAUser(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/shots", method: "GET", completion: completion)
	}
	
	public func listAuthedUsersShots(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/shots", method: "GET", completion: completion)
	}
	
	//MARK: Users/Teams - http://developer.dribbble.com/v1/users/teams/
	
	public func listAUsersTeams(username:String, completion:DribbbleApiCompletion) {
		sendSimpleRequest("users/\(username)/teams", method: "GET", completion: completion)
	}
	
	public func listAuthedUsersTeams(completion:DribbbleApiCompletion) {
		sendSimpleRequest("user/teams", method: "GET", completion: completion)
	}
}

/**
The DribbbleShotsCollection protocol defines a guideline
to load and collect pages of data from the Dribbble API.
*/
public protocol DribbbleShotsCollectable {
	/**
	Initialize a shots collection.
	
	- parameter dribbble: An instance of a DribbbleApi.
	
	- returns: self
	*/
	init(dribbble:DribbbleApi)
	
	/**
	Load more content from the dribbbleApi.
	
	- parameter completion: A DribbbleApiCompletion callback.
	*/
	func loadContentWithCompletion(completion:DribbbleApiCompletion)
	
	/// Increment the page number in the API call.
	func incrementPage()
	
	/**
	Add data to the collection.
	
	- parameter data: Array? of AnyObject?
	*/
	func addData(data:[AnyObject?]?)
}

/**
The DribbbleShotsCollection class is a default implementation of DribbbleShotsCollectable,
you can override loadContentWithCompletion to customize what API calls you're making to
load more content pages.
*/
public class DribbbleShotsCollection:DribbbleShotsCollectable {
	
	var api:DribbbleApi
	var page:Int = 1
	var parameters: [String : String] {
		return ["page":String(self.page)]
	}
	
	/// Loaded collection data available to use.
	public var data: [AnyObject?]? = nil
	
	/**
	Initialize a collection.
	
	- parameter dribbble: An instance of a DribbbleApi.
	
	- returns: self
	*/
	public required init(dribbble:DribbbleApi) {
		self.api = dribbble
	}
	
	/**
	Load more content from the dribbbleApi.
	
	- parameter completion: A DribbbleApiCompletion callback.
	*/
	public func loadContentWithCompletion(completion: DribbbleApiCompletion) {
		print("Override loadContentWithCompletion and make your API call with self.api")
	}
	
	/**
	Add data to the collection.
	
	- parameter data: Array? of AnyObject?
	*/
	public func addData(data: [AnyObject?]?) {
		guard self.data != nil else { return }
		if let data = data {
			self.data! = self.data! + data
		}
	}
	
	/// Increment the page number in the API call.
	public func incrementPage() {
		page += 1
	}
}
