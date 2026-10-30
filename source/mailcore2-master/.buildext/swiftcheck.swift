import MailCore
import Foundation

let addr = MCOAddress(mailbox: "a@b.com")!
let session = MCOIMAPSession()
print("MailCore imported OK; mailbox=\(addr.mailbox ?? ""), sessionClass=\(type(of: session))")
