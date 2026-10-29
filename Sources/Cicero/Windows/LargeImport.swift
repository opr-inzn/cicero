import CiceroCore
import SwiftUI

/// What the sheets that copy another app's fonts in show about how long it takes (see `CopyTimeEstimate`): copying into
/// ~/Library/Fonts gets slower with each font, into Cicero's Library it takes minutes. Past `threshold` fonts going into the
/// Fonts folder, Cicero's Library is offered; choosing it turns on the setting, as Settings → General does, and the box
/// then says so and can undo it. Shown only before the copying starts.
struct FontLibraryOffer: View {
    /// Fonts into the Fonts folder past which Cicero's Library is offered.
    static let threshold = 2_000

    /// The fonts the copying would put into the Fonts folder.
    let count: Int
    /// Cicero's Library was chosen in this box, so it can be undone in it.
    @Binding var chose: Bool
    @Environment(AppModel.self) private var model

    /// Whether there's anything to show, so a sheet leaves out the space around it otherwise.
    static func isShown(count: Int, chose: Bool, installsIntoFontLibrary: Bool) -> Bool {
        installsIntoFontLibrary ? chose : count > threshold
    }

    var body: some View {
        if model.data.installsIntoFontLibrary {
            notice(icon: Image(systemName: "checkmark.circle.fill"), tint: .green, title: "Copying into Cicero’s Library") {
                Text("\(Self.about(CopyTimeEstimate.onFastMac(count, intoFontsFolder: false))). Fonts you install later go there too. "
                    + "You can change this in Settings\u{00A0}→\u{00A0}General.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Use the Fonts Folder") {
                    chose = false
                    model.setInstallsIntoFontLibrary(false)
                }
                .padding(.top, 6)
            }
        } else {
            let fontsFolder = CopyTimeEstimate.onFastMac(count, intoFontsFolder: true)
            let busy = fontsFolder >= 600 ? "or hours on a busy Mac" : "or much longer on a busy Mac"
            notice(icon: Image(systemName: "clock"), tint: .secondary, title: "Copying \(count.formatted()) fonts can take a long time") {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 2) {
                    GridRow {
                        Text("Into your Fonts folder").foregroundStyle(.secondary)
                        Text("\(Self.about(fontsFolder)), \(busy)")
                    }
                    GridRow {
                        Text("Into Cicero’s Library").foregroundStyle(.secondary)
                        Text(Self.about(CopyTimeEstimate.onFastMac(count, intoFontsFolder: false)))
                    }
                }
                .monospacedDigit()
                Text("macOS gets slower with each font in your Fonts folder. With Cicero’s Library, fonts you install later go there too, "
                    + "and Microsoft Office can’t use them.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                Button("Use Cicero’s Library") {
                    chose = true
                    model.setInstallsIntoFontLibrary(true)
                }
                .padding(.top, 6)
            }
        }
    }

    /// The icon on the title's line, and everything else lined up under the title.
    private func notice<Content: View>(icon: Image, tint: some ShapeStyle, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon.foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).bold().fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 2) { content() }
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// "Less than a minute", "About 40 minutes".
    private static func about(_ seconds: Double) -> String {
        seconds < 60 ? "Less than a minute" : "About " + CopyTimeEstimate.phrase(seconds)
    }
}

/// "Copying fonts, 6,000 of 31,209" and, once `estimate` can tell, "About 30 minutes left": beside it, or `stacked` under
/// it where the sheet is too narrow for both on one line, with the line there from the start, so the sheet doesn't grow
/// when the estimate comes.
struct CopyingProgressLine: View {
    let done: Int
    let total: Int
    let estimate: CopyTimeEstimate
    var stacked = false

    var body: some View {
        let count = Text("Copying fonts, \(done.formatted()) of \(total.formatted())").fixedSize()
        let left = estimate.remaining(total: total).map { $0 < 60 ? "Less than a minute left" : "About \(CopyTimeEstimate.phrase($0)) left" }
        if stacked {
            VStack(alignment: .leading, spacing: 4) {
                count
                Text(left ?? " ").fixedSize()
            }
        } else {
            HStack(spacing: 12) {
                count
                Spacer(minLength: 0)
                if let left { Text(left).fixedSize() }
            }
        }
    }
}
