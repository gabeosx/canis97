import SwiftUI

struct AboutProductView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

    var body: some View {
        VStack(spacing: 18) {
            Image(ProductIdentity.iconBasename)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(ProductIdentity.displayName)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Version \(version) (\(build))")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("\(ProductIdentity.displayName) connects subscribers to SiriusXM using their own subscriber account.")
                Text(ProductIdentity.nonAffiliationStatement)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
        }
        .padding(32)
        .frame(minWidth: 460, minHeight: 360)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("About \(ProductIdentity.displayName)")
    }
}
