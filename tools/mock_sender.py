#!/usr/bin/env python3
"""Fake vision module. Emits protocol-correct packets with no camera.

Lets the Godot side exercise the real UDP path — parsing, sequence gaps,
timeouts, LOST handling — before any tracking code exists.

    python3 tools/mock_sender.py                  # both hands circling
    python3 tools/mock_sender.py --pattern sweep  # horizontal sweep
    python3 tools/mock_sender.py --drop 0.1       # drop 10% of packets
    python3 tools/mock_sender.py --lose 3         # a hand vanishes every 3s

See PROTOCOL.md for the packet contract.
"""
import argparse, json, math, socket, time

V = 1


def hand(slot, x, y, vx, vy, conf, state):
    return {"slot": slot, "x": round(x, 4), "y": round(y, 4),
            "vx": round(vx, 3), "vy": round(vy, 3),
            "conf": round(conf, 3), "state": state}


def positions(pattern, t):
    """Return ((x0,y0),(x1,y1)) for the two hands at time t."""
    if pattern == "sweep":
        a = 0.5 + 0.4 * math.sin(t * 1.2)
        return (a, 0.5), (1.0 - a, 0.5)
    if pattern == "static":
        return (0.3, 0.5), (0.7, 0.5)
    # circle: counter-rotating, so they cross - the case that breaks
    # classifier-based handedness and exercises slot continuity.
    return ((0.35 + 0.22 * math.cos(t * 1.6), 0.5 + 0.3 * math.sin(t * 1.6)),
            (0.65 - 0.22 * math.cos(t * 1.6), 0.5 + 0.3 * math.sin(t * 1.6)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=5005)
    ap.add_argument("--fps", type=float, default=60.0)
    ap.add_argument("--pattern", default="circle",
                    choices=["circle", "sweep", "static"])
    ap.add_argument("--drop", type=float, default=0.0,
                    help="fraction of packets to drop (0-1)")
    ap.add_argument("--lose", type=float, default=0.0,
                    help="seconds between simulated tracking losses (0=never)")
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    period = 1.0 / args.fps
    t0 = time.perf_counter()
    prev = positions(args.pattern, 0.0)
    seq = 0
    sent = dropped = 0
    import random

    print(f"-> {args.host}:{args.port}  {args.fps:g}Hz  pattern={args.pattern}")
    print("ctrl-c to stop\n")

    try:
        while True:
            now = time.perf_counter()
            t = now - t0
            cur = positions(args.pattern, t)

            # Hand 1 drops out periodically, if asked.
            lost = args.lose > 0 and (t % args.lose) < 0.4

            hands = []
            for i in (0, 1):
                vx = (cur[i][0] - prev[i][0]) / period
                vy = (cur[i][1] - prev[i][1]) / period
                if lost and i == 1:
                    hands.append(hand(i, cur[i][0], cur[i][1], 0, 0, 0.0, "LOST"))
                else:
                    hands.append(hand(i, cur[i][0], cur[i][1], vx, vy, 0.95, "TRACKED"))
            prev = cur

            seq += 1
            if random.random() >= args.drop:
                sock.sendto(json.dumps({
                    "v": V, "seq": seq, "t_capture": now,
                    "fps": args.fps, "hands": hands,
                }).encode(), (args.host, args.port))
                sent += 1
            else:
                dropped += 1

            if seq % 120 == 0:
                print(f"\rseq {seq}  sent {sent}  dropped {dropped}", end="", flush=True)

            slack = period - (time.perf_counter() - now)
            if slack > 0:
                time.sleep(slack)
    except KeyboardInterrupt:
        print(f"\nstopped. sent {sent}, dropped {dropped}")


if __name__ == "__main__":
    main()
