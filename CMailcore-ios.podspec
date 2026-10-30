Pod::Spec.new do |spec|
  spec.name         = "CMailcore-ios"
  spec.version      = "0.3.0"
  spec.summary      = "Rebuild Mailcore for iOS with mailcore2-ios"
  spec.description  = "MailCore provide a simple and asynchronous API to work with e-mail protocols IMAP, POP and SMTP. The API has been redesigned from ground up."
  spec.homepage     = "https://github.com/MailCore/mailcore2"
  spec.license      = "MIT"
  spec.author       = "MailCore Authors"
  spec.platform     = :ios, "15.0"
  spec.source       = { :git => "https://github.com/driverZhan/mailcore-ios.git", :tag => spec.version.to_s }
  spec.header_dir   = "MailCore"
  spec.requires_arc = false
  spec.vendored_frameworks = "lib/MailCore.xcframework"
  spec.libraries = ["xml2", "iconv", "z", "c++", "resolv"]
end
