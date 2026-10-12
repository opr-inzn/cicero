import SwiftUI

/// The "Activate Temporarily" submenu: Until Point Quits / Until You Log Out.
struct TemporaryActivationMenu: View {
    let action: (TemporaryScope) -> Void

    var body: some View {
        Menu("Activate Temporarily") {
            ForEach(TemporaryScope.allCases, id: \.self) { scope in
                Button(scope.menuLabel) { action(scope) }
            }
        }
    }
}
