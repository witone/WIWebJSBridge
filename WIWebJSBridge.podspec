Pod::Spec.new do |s|
  s.name             = 'WIWebJSBridge'
  s.version          = '1.0.0'
  s.summary          = 'IOS H5 Bridge'
  s.description      = <<-DESC
  Translate from ObjC Project WebViewJavascriptBridge(https://github.com/marcuswestin/WebViewJavascriptBridge)
                       DESC

  s.homepage         = 'https://github.com/witone/WIWebJSBridge'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Witone' => 'me_zyp@163.com' }
  s.source           = { :git => 'https://github.com/witone/WIWebJSBridge.git', :tag => s.version.to_s }

  s.ios.deployment_target = '12.0'
  s.source_files = 'WIWebJSBridge/**/*'
  s.swift_version = '5.0'
end
