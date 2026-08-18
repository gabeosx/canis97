import Foundation

enum SanitizedNativeResponseFixtures {
    static let profileV4Authenticated = Data(
        """
        {
          "fixture_context": {
            "fixture_marker": "profile-v4-context"
          },
          "fixture_marker": "profile-v4-body",
          "fixture_note": "fixture-only"
        }
        """.utf8
    )

    static let subscriptionV1Active = Data(
        """
        {
          "fixture_context": {
            "fixture_marker": "subscription-v1-active-context"
          },
          "fixture_marker": "subscription-v1-active-body",
          "subscription": {
            "fixture_marker": "subscription-v1-active-inner",
            "status": "active"
          }
        }
        """.utf8
    )

    static let subscriptionV1Inactive = Data(
        """
        {
          "fixture_context": {
            "fixture_marker": "subscription-v1-inactive-context"
          },
          "fixture_marker": "subscription-v1-inactive-body",
          "subscription": {
            "fixture_marker": "subscription-v1-inactive-inner",
            "status": "inactive"
          }
        }
        """.utf8
    )
}
