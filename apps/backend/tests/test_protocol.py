import unittest

from meeting_backend.protocol import pong_event


class ProtocolTest(unittest.TestCase):
    def test_pong_event_echoes_client_ping_metadata(self) -> None:
        event = pong_event(
            ping_id="ping-1",
            client_sent_at_ms=123,
            server_sent_at_ms=456,
        )

        self.assertEqual(event["type"], "server.pong")
        self.assertEqual(event["ping_id"], "ping-1")
        self.assertEqual(event["client_sent_at_ms"], 123)
        self.assertEqual(event["server_sent_at_ms"], 456)


if __name__ == "__main__":
    unittest.main()
