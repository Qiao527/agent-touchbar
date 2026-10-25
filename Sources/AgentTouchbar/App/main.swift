import AppKit

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
// 只在菜单栏显示图标，不出现在 Dock
app.setActivationPolicy(.accessory)
app.run()
