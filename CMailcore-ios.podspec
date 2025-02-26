Pod::Spec.new do |spec|
  spec.name         = "CMailcore-ios"
  spec.version      = "0.1.1"
  spec.summary      = "Rebuild Mailcore for iOS with mailcore2-ios"
  spec.description  = "MailCore provide a simple and asynchronous API to work with e-mail protocols IMAP, POP and SMTP. The API has been redesigned from ground up."
  spec.homepage     = "https://github.com/MailCore/mailcore2"
  spec.license      = "MIT"
  spec.author       = "MailCore Authors"
  spec.platform     = :ios, "12.0"
  spec.source       = { :git => "https://github.com/driverZhan/mailcore-ios.git", :tag => spec.version.to_s }
  spec.header_dir   = "MailCore"
  spec.requires_arc = false
  spec.source_files = "MailCore/include/MailCore/*.h"
  #spec.public_header_files = "cocoapods-build/include/MailCore/*.h"
  #spec.preserve_paths = "cocoapods-build/include/MailCore/*.h"
  spec.vendored_libraries = "MailCore/lib/libMailCore-ios.a"
  spec.libraries = ["xml2", "iconv", "z", "c++", "resolv"]
end
