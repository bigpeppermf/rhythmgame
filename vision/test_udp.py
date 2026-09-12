"""Wire-format and real localhost socket checks; no camera or Godot required."""

import json
import socket
import unittest
from unittest.mock import patch

from hand_state import HandStateTracker
from udp_protocol import UdpHandSender, build_packet, decode_packet
from udp_receiver import UdpHandReceiver


class UdpTests(unittest.TestCase):
    def test_real_socket_transmits_both_slots_and_state_transitions(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver:
            receiver.bind(("127.0.0.1", 0))
            receiver.settimeout(2)
            sender = UdpHandSender(port=receiver.getsockname()[1])
            self.addCleanup(sender.close)
            tracker = HandStateTracker()
            for seq, (timestamp, position, expected) in enumerate((
                (0.0, (0.3, 0.4), "TRACKED"),
                (0.1, None, "COASTING"),
                (0.2, None, "LOST"),
            )):
                states = tracker.update([position, None], timestamp)
                self.assertTrue(sender.send(states, timestamp, 30.5))
                data, _ = receiver.recvfrom(65535)
                packet = decode_packet(data)
                self.assertEqual(set(packet), {"seq", "t_capture", "fps", "hands"})
                self.assertEqual(packet["seq"], seq)
                self.assertEqual(packet["t_capture"], timestamp)
                self.assertEqual(packet["fps"], 30.5)
                self.assertEqual([hand["slot"] for hand in packet["hands"]], [0, 1])
                left, right = packet["hands"]
                self.assertEqual(set(left), {"slot", "x", "y", "vx", "vy", "conf", "state"})
                self.assertEqual(left["state"], expected)
                self.assertEqual((left["x"], left["y"]), (0.3, 0.4))
                self.assertEqual(right["state"], "LOST")
                self.assertEqual(right["conf"], 0)

    def test_receiver_newest_wins_timeout_and_sequence_restart(self):
        receiver = UdpHandReceiver(port=0)
        self.addCleanup(receiver.close)
        destination = receiver.socket.getsockname()
        states = HandStateTracker().hands
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
            for seq, timestamp in ((4, 1.0), (6, 1.2), (5, 1.1)):
                sender.sendto(json.dumps(build_packet(seq, timestamp, 30, states)).encode(), destination)
            sender.sendto(b"not JSON", destination)
            with patch("udp_receiver.monotonic", return_value=10.0):
                self.assertEqual(receiver.poll()["seq"], 6)
            self.assertEqual(receiver.invalid_packets, 1)
            # Repeated old packets must not keep a disconnected input alive.
            sender.sendto(json.dumps(build_packet(5, 1.1, 30, states)).encode(), destination)
            with patch("udp_receiver.monotonic", return_value=10.5):
                self.assertIsNone(receiver.poll())
            # Python process restart resets seq, but the OS monotonic clock continues.
            sender.sendto(json.dumps(build_packet(0, 2.0, 0, states)).encode(), destination)
            with patch("udp_receiver.monotonic", return_value=11.0):
                self.assertEqual(receiver.poll()["seq"], 0)

    def test_send_failure_drops_without_retry_and_advances_sequence(self):
        with patch("udp_protocol.socket.socket") as socket_factory:
            fake = socket_factory.return_value
            fake.sendto.side_effect = [BlockingIOError("busy"), None]
            sender = UdpHandSender()
            states = HandStateTracker().hands
            self.assertFalse(sender.send(states, 1.0, 0))
            self.assertEqual(sender.dropped, 1)
            self.assertTrue(sender.send(states, 1.1, 30))
            self.assertEqual(fake.sendto.call_count, 2)
            packet = decode_packet(fake.sendto.call_args.args[0])
            self.assertEqual(packet["seq"], 1)
            self.assertEqual(packet["t_capture"], 1.1)
            self.assertIsNone(sender.last_error)
            sender.close()
            fake.close.assert_called_once()

    def test_malformed_packets_are_rejected(self):
        states = HandStateTracker().hands
        for alteration in ("missing_slot", "duplicate_slot", "nan", "bad_state", "lost_conf"):
            with self.subTest(alteration=alteration):
                packet = build_packet(0, 0, 0, states)
                if alteration == "missing_slot":
                    packet["hands"].pop()
                elif alteration == "duplicate_slot":
                    packet["hands"][1]["slot"] = 0
                elif alteration == "nan":
                    packet["hands"][0]["x"] = float("nan")
                elif alteration == "bad_state":
                    packet["hands"][0]["state"] = "HIT"
                else:
                    packet["hands"][0]["conf"] = 1
                with self.assertRaises(ValueError):
                    decode_packet(json.dumps(packet).encode())


if __name__ == "__main__":
    unittest.main()
