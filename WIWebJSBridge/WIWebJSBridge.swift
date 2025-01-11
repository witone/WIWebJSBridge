//
//  WIWebJSBridge.swift
//  WIWebJSBridge
//
//  Translate from ObjC Project WebViewJavascriptBridge(https://github.com/marcuswestin/WebViewJavascriptBridge)
//
//  Created by Witone on 2025/1/6.
//

import WebKit

public typealias WIWJBCallback = (_ responseData: Any?) -> Void
public typealias WIWJBHandler = (_ parameters: [String: Any]?, _ callback: WIWJBCallback?) -> Void
public typealias WIWJBMessage = [String: Any]

protocol WebJSBridgeBaseDelegate: NSObjectProtocol {
    func evaluateJavascript(_ jsCommand: String, completionHandler:((Any?, Error?) -> Void)?)
}

class WIWebJSBridgeBase {
    var isLogEnable = false
    
    weak var delegate: WebJSBridgeBaseDelegate?
    
    var messageHandlers: [String: WIWJBHandler]?
    var responseCallbacks: [String: WIWJBCallback]?
    var startupMessageQueue: [WIWJBMessage]?
    
    private var uniqueId: UInt64
    
    init() {
        messageHandlers = [:]
        startupMessageQueue = []
        responseCallbacks = [:]
        uniqueId = 0
    }

    func reset() {
        startupMessageQueue = []
        responseCallbacks = [:]
        uniqueId = 0
    }

    func send(_ handlerName: String?, data: Any?, callback: WIWJBCallback?) {
        var message: [String: Any] = [:]
        message["handlerName"] = handlerName
        if let data {
            message["data"] = data
        }
        if let callback {
            uniqueId += 1
            let callbackId = "swift_cb_\(uniqueId)"
            responseCallbacks?[callbackId] = callback
            message["callbackId"] = callbackId
        }
    }

    func flush(messageQueueString: String) {
        guard let messages = _deserialize(messageJSON: messageQueueString) else {
            _log(messageQueueString)
            return
        }

        for message in messages {
            _log(message)

            if let responseId = message["responseId"] as? String {
                guard let callback = responseCallbacks?[responseId] else { continue }
                callback(message["responseData"])
                responseCallbacks?.removeValue(forKey: responseId)
            } else {
                var callback: WIWJBCallback?
                if let callbackID = message["callbackId"] {
                    callback = { (_ responseData: Any?) -> Void in
                        let msg = ["responseId": callbackID, "responseData": responseData ?? NSNull()] as WIWJBMessage
                        self._queue(message: msg)
                    }
                } else {
                    callback = { (_ responseData: Any?) -> Void in
                        // no logic
                    }
                }

                guard let handlerName = message["handlerName"] as? String else { continue }
                guard let handler = messageHandlers?[handlerName] else {
                    _log("NoHandlerException, No handler for message from JS: \(message)")
                    continue
                }
                handler(message["data"] as? [String : Any], callback)
            }
        }
    }

    func injectJavascriptFile() {
        let js = WIWebJSBridgeJSCode
        delegate?.evaluateJavascript(js) { [weak self] (_, error) in
            guard let self = self else { return }
            if let error = error {
                self._log(error)
                return
            }
            if self.startupMessageQueue != nil {
                self.startupMessageQueue?.forEach { [weak self] message in
                    self?._dispatch(message: message)
                }
                self.startupMessageQueue = nil
            }
        }
    }

    func isWebViewJsBridge(url: URL) -> Bool {
        guard isSchemeMatch(url: url) else { return false }
        return isBridgeLoaded(url: url) || isQueueMessage(url: url)
    }

    func isSchemeMatch(url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "https" || scheme == "wvjbscheme"
    }

    func isQueueMessage(url: URL) -> Bool {
        let host = url.host?.lowercased()
        return isSchemeMatch(url: url) && host == "__wvjb_queue_message__"
    }

    func isBridgeLoaded(url: URL) -> Bool {
        let host = url.host?.lowercased()
        return isSchemeMatch(url: url) && host == "__bridge_loaded__"
    }

    func logUnkownMessage(url: URL) {
        print("WebViewJavascriptBridge: WARNING: Received unknown WebViewJavascriptBridge command \(url.absoluteString)")
    }

    func webViewJavascriptCheckCommand() -> String {
        "typeof WebViewJavascriptBridge == \'object\';"
    }

    func webViewJavascriptFetchQueyCommand() -> String {
        "WebViewJavascriptBridge._fetchQueue();"
    }

    func disableJavscriptAlertBoxSafetyTimeout() {
        send("_disableJavascriptAlertBoxSafetyTimeout", data: nil, callback: nil)
    }
}

extension WIWebJSBridgeBase {
    private func _queue(message: WIWJBMessage) {
        if startupMessageQueue == nil {
            _dispatch(message: message)
        } else {
            startupMessageQueue?.append(message)
        }
    }

    private func _dispatch(message: WIWJBMessage) {
        guard var messageJSON = _serialize(message, pretty: false) else { return }
        _log("SEND: \(messageJSON)")
        messageJSON = messageJSON.replacingOccurrences(of: "\\", with: "\\\\")
        messageJSON = messageJSON.replacingOccurrences(of: "\"", with: "\\\"")
        messageJSON = messageJSON.replacingOccurrences(of: "\'", with: "\\\'")
        messageJSON = messageJSON.replacingOccurrences(of: "\n", with: "\\n")
        messageJSON = messageJSON.replacingOccurrences(of: "\r", with: "\\r")
        messageJSON = messageJSON.replacingOccurrences(of: "\u{000C}", with: "\\f")
        messageJSON = messageJSON.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        messageJSON = messageJSON.replacingOccurrences(of: "\u{2029}", with: "\\u2029")

        let jsCommand = "WebViewJavascriptBridge._handleMessageFromIOS('\(messageJSON)');"
        if Thread.current.isMainThread {
            delegate?.evaluateJavascript(jsCommand, completionHandler: nil)
        } else {
            DispatchQueue.main.async {
                self.delegate?.evaluateJavascript(jsCommand, completionHandler: nil)
            }
        }
    }

    private func _serialize(_ message: WIWJBMessage, pretty: Bool) -> String? {
        var result: String?
        do {
            let data = try JSONSerialization.data(withJSONObject: message, options: pretty ? .prettyPrinted : JSONSerialization.WritingOptions(rawValue: 0))
            result = String(data: data, encoding: .utf8)
        } catch let error {
            _log(error)
        }
        return result
    }

    private func _deserialize(messageJSON: String) -> [WIWJBMessage]? {
        var result: [WIWJBMessage] = []
        guard let data = messageJSON.data(using: .utf8) else { return nil }
        do {
            result = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [WIWJBMessage]
        } catch let error {
            _log(error)
        }
        return result
    }

    private func _log<T>(_ message: T, file: String = #file, function: String = #function, line: Int = #line) {
#if DEBUG
        guard isLogEnable else { return }

        let fileName = (file as NSString).lastPathComponent
        print("\(fileName):\(line) \(function) | \(message)")
#endif
    }
}

public class WIWebJSBridge: NSObject {

    private weak var _webView: WKWebView?
    public weak var webViewDelegate: WKNavigationDelegate?
    private var _base: WIWebJSBridgeBase!

    public init(webView: WKWebView) {
        super.init()
        _webView = webView
        _webView?.navigationDelegate = self
        _base = WIWebJSBridgeBase()
        _base.delegate = self
    }

    public func send(data: Any? = nil, callback: WIWJBCallback? = nil) {
        _base.send(nil, data: data, callback: callback)
    }

    public func call(handlerName: String, data: Any? = nil, callback: WIWJBCallback? = nil) {
        _base.send(handlerName, data: data, callback: callback)
    }

    public func register(handlerName: String, handler: @escaping WIWJBHandler) {
        _base.messageHandlers?[handlerName] = handler
    }

    public func remove(handlerName: String) {
        _base.messageHandlers?.removeValue(forKey: handlerName)
    }

    public func reset() {
        _base.reset()
    }

    public func disableJavscriptAlertBoxSafetyTimeout() {
        _base.disableJavscriptAlertBoxSafetyTimeout()
    }
}
extension WIWebJSBridge {
    private func _flushMessageQueue() {
        _webView?.evaluateJavaScript(_base.webViewJavascriptFetchQueyCommand()) { [weak self] (result, error) in
            if error != nil {
                print("WKWebViewJavascriptBridge: WARNING: Error when trying to fetch data from WKWebView: \(String(describing: error))")
            }
            guard let resultStr = result as? String else { return }
            self?._base.flush(messageQueueString: resultStr)
        }
    }
}

extension WIWebJSBridge: WebJSBridgeBaseDelegate {
    func evaluateJavascript(_ jsCommand: String, completionHandler: ((Any?, (any Error)?) -> Void)?) {
        _webView?.evaluateJavaScript(jsCommand, completionHandler: completionHandler)
    }
}

extension WIWebJSBridge: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView == _webView else { return }
        if let webViewDelegate, webViewDelegate.responds(to: #selector(WKNavigationDelegate.webView(_:didFinish:))) {
            webViewDelegate.webView?(webView, didFinish: navigation)
        }
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard webView == _webView else {
            decisionHandler(.allow)
            return
        }
        if let webViewDelegate, webViewDelegate.responds(to: Selector("webView:decidePolicyForNavigationResponse:decisionHandler:")) {
            webViewDelegate.webView?(webView, decidePolicyFor: navigationResponse, decisionHandler: decisionHandler)
        } else {
            decisionHandler(.allow)
        }
    }

    public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard webView == _webView else { return }
        if let webViewDelegate, webViewDelegate.responds(to: #selector(WKNavigationDelegate.webView(_:didReceive:completionHandler:))) {
            webViewDelegate.webView?(webView, didReceive: challenge, completionHandler: completionHandler)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard webView == _webView else {
            decisionHandler(.cancel)
            return
        }
        let url = navigationAction.request.url!
        if _base.isWebViewJsBridge(url: url) {
            if _base.isBridgeLoaded(url: url) {
                _base.injectJavascriptFile()
            } else if _base.isQueueMessage(url: url) {
                _flushMessageQueue()
            } else {
                _base.logUnkownMessage(url: url)
            }
            decisionHandler(.cancel)
            return
        }
        if let webViewDelegate, webViewDelegate.responds(to: Selector("webView:decidePolicyForNavigationAction:decisionHandler:")) {
            webViewDelegate.webView?(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
        } else {
            decisionHandler(.allow)
        }
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView == _webView else { return }
        if let webViewDelegate, webViewDelegate.responds(to: #selector(WKNavigationDelegate.webView(_:didStartProvisionalNavigation:))) {
            webViewDelegate.webView?(webView, didStartProvisionalNavigation: navigation)
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        guard webView == _webView else { return }
        if let webViewDelegate, webViewDelegate.responds(to: #selector(WKNavigationDelegate.webView(_:didFail:withError:))) {
            webViewDelegate.webView?(webView, didFail: navigation, withError: error)
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        guard webView == _webView else { return }
        if let webViewDelegate, webViewDelegate.responds(to: #selector(WKNavigationDelegate.webView(_:didFailProvisionalNavigation:withError:))) {
            webViewDelegate.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
        }
    }
}

let WIWebJSBridgeJSCode = """
;(function() {
    if (window.WebViewJavascriptBridge) {
        return;
    }

    if (!window.onerror) {
        window.onerror = function(msg, url, line) {
            console.log("WebViewJavascriptBridge: ERROR:" + msg + "@" + url + ":" + line);
        }
    }
    window.WebViewJavascriptBridge = {
        registerHandler: registerHandler,
        callHandler: callHandler,
        disableJavscriptAlertBoxSafetyTimeout: disableJavscriptAlertBoxSafetyTimeout,
        _fetchQueue: _fetchQueue,
        _handleMessageFromIOS: _handleMessageFromIOS
    };

    var messagingIframe;
    var sendMessageQueue = [];
    var messageHandlers = {};
    
    var CUSTOM_PROTOCOL_SCHEME = 'https';
    var QUEUE_HAS_MESSAGE = '__wvjb_queue_message__';
    
    var responseCallbacks = {};
    var uniqueId = 1;
    var dispatchMessagesWithTimeoutSafety = true;

    function registerHandler(handlerName, handler) {
        messageHandlers[handlerName] = handler;
    }
    
    function callHandler(handlerName, data, responseCallback) {
        if (arguments.length == 2 && typeof data == 'function') {
            responseCallback = data;
            data = null;
        }
        _doSend({ handlerName:handlerName, data:data }, responseCallback);
    }
    function disableJavscriptAlertBoxSafetyTimeout() {
        dispatchMessagesWithTimeoutSafety = false;
    }
    
    function _doSend(message, responseCallback) {
        if (responseCallback) {
            var callbackId = 'cb_'+(uniqueId++)+'_'+new Date().getTime();
            responseCallbacks[callbackId] = responseCallback;
            message['callbackId'] = callbackId;
        }
        sendMessageQueue.push(message);
        messagingIframe.src = CUSTOM_PROTOCOL_SCHEME + '://' + QUEUE_HAS_MESSAGE;
    }

    function _fetchQueue() {
        var messageQueueString = JSON.stringify(sendMessageQueue);
        sendMessageQueue = [];
        return messageQueueString;
    }

    function _dispatchMessageFromIOS(messageJSON) {
        if (dispatchMessagesWithTimeoutSafety) {
            setTimeout(_doDispatchMessageFromIOS);
        } else {
             _doDispatchMessageFromIOS();
        }
        
        function _doDispatchMessageFromIOS() {
            var message = JSON.parse(messageJSON);
            var messageHandler;
            var responseCallback;

            if (message.responseId) {
                responseCallback = responseCallbacks[message.responseId];
                if (!responseCallback) {
                    return;
                }
                responseCallback(message.responseData);
                delete responseCallbacks[message.responseId];
            } else {
                if (message.callbackId) {
                    var callbackResponseId = message.callbackId;
                    responseCallback = function(responseData) {
                        _doSend({ handlerName:message.handlerName, responseId:callbackResponseId, responseData:responseData });
                    };
                }
                
                var handler = messageHandlers[message.handlerName];
                if (!handler) {
                    console.log("WebViewJavascriptBridge: WARNING: no handler for message from IOS:", message);
                } else {
                    handler(message.data, responseCallback);
                }
            }
        }
    }
    
    function _handleMessageFromIOS(messageJSON) {
        _dispatchMessageFromIOS(messageJSON);
    }

    messagingIframe = document.createElement('iframe');
    messagingIframe.style.display = 'none';
    messagingIframe.src = CUSTOM_PROTOCOL_SCHEME + '://' + QUEUE_HAS_MESSAGE;
    document.documentElement.appendChild(messagingIframe);

    registerHandler("_disableJavascriptAlertBoxSafetyTimeout", disableJavscriptAlertBoxSafetyTimeout);
    
    setTimeout(_callWVJBCallbacks, 0);
    function _callWVJBCallbacks() {
        var callbacks = window.WVJBCallbacks;
        delete window.WVJBCallbacks;
        for (var i=0; i<callbacks.length; i++) {
            callbacks[i](WebViewJavascriptBridge);
        }
    }
})();
"""
