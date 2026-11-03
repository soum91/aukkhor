import unittest

from scripts.publish_install_variants import synchronize_latest_version


class FeedLatestVersionTests(unittest.TestCase):
    def test_legacy_metadata_never_points_to_an_old_ipa(self):
        app = {
            "version": "0.2.0.56",
            "buildVersion": "56",
            "downloadURL": "https://example.test/v56.ipa",
            "versions": [
                {
                    "version": "0.2.0.68",
                    "buildVersion": "68",
                    "downloadURL": "https://example.test/v68.ipa",
                    "size": 1234567,
                    "date": "2026-11-02",
                    "minOSVersion": "16.0",
                },
                {"version": "0.2.0.56", "downloadURL": "https://example.test/v56.ipa"},
            ],
        }
        synchronize_latest_version(app, "Verified keyboard with input fixes")
        for field in ("version", "buildVersion", "downloadURL", "size", "minOSVersion"):
            self.assertEqual(app[field], app["versions"][0][field])
        self.assertEqual(app["versionDate"], app["versions"][0]["date"])
        self.assertEqual(app["buildVersion"], "68")
        self.assertEqual(app["versionDescription"], "Verified keyboard with input fixes")


if __name__ == "__main__":
    unittest.main()
