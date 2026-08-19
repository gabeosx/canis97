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
          "items": [
            {
              "fixture_marker": "subscription-v1-active-item",
              "state": "active"
            },
            {
              "fixture_marker": "subscription-v1-finished-item",
              "state": "finished"
            }
          ]
        }
        """.utf8
    )

    static let subscriptionV1Inactive = Data(
        """
        {
          "items": [
            {
              "fixture_marker": "subscription-v1-finished-item",
              "state": "finished"
            }
          ]
        }
        """.utf8
    )
}
