//
//  ViewController.swift
//  WIWebJSBridge
//
//  Created by zyp on 01/11/2025.
//  Copyright (c) 2025 zyp. All rights reserved.
//

import UIKit
import WIWebJSBridge
import WebKit

class ViewController: UIViewController, WKNavigationDelegate {
    var webView: WKWebView!
    lazy var bridge: WIWebJSBridge = {
        let bridge = WIWebJSBridge(webView: webView)
        bridge.webViewDelegate = self
        return bridge
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        setupWeb()
        bridge.register(handlerName: "xxx") { data, callBack in
            // to do:
        }
        webView.load(URLRequest(url: URL(string: "https://wap.baidu.com")!))
    }

    func setupWeb() {
        let contentController = WKUserContentController();
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.userContentController = contentController
        webView = WKWebView(frame: view.frame, configuration: webConfiguration)
        webView.navigationDelegate = self
        if #available(iOS 11.0, *) {
            webView.scrollView.contentInsetAdjustmentBehavior = .never
        } else {
            automaticallyAdjustsScrollViewInsets = false
        }
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
    }
}

