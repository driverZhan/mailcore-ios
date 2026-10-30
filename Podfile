# Uncomment the next line to define a global platform for your project
 platform :ios, '15.0'

target 'MailCoreDemo' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for MailCoreDemo
  # 本地引用，直接使用仓库内 lib/MailCore.xcframework（由 ./build-xcframework.sh 生成）
  pod 'CMailcore-ios', :path => './'
  # 发布后使用远程版本: pod 'CMailcore-ios', '~> 0.2.0'

end

# xcframework 的拷贝/嵌入脚本与 Xcode 用户脚本沙箱不兼容，必须关闭
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    end
  end
  # 主工程同样关闭（[CP] Embed Pods Frameworks 脚本在主工程执行）
  require 'xcodeproj'
  user_project = Xcodeproj::Project.open('./MailCoreDemo.xcodeproj')
  user_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    end
  end
  user_project.save
end
