import SwiftUI

struct SettingsWindow: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Locations", systemImage: "folder") { FoldersSettings() }
            Tab("Sidebar", systemImage: "sidebar.leading") { SidebarSettings() }
            Tab("Coverage", systemImage: "character.textbox") { CharacterSetsSettings() }
        }
        .frame(width: 560, height: 580)
    }
}
