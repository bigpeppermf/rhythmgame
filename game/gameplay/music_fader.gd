class_name MusicFader
extends RefCounted
## Ducks the music under a miss streak, and lifts it back on a hit.
##
## Deliberately separate from ScoreState: that decides what a judgement is
## worth to the score, this decides what it does to the mix. A miss should be
## heard, not just seen in a combo counter resetting.
##
## Only sets Conductor.volume_db - Conductor itself owns turning that target
## into an actual fade, so this class never touches the player directly.

## Ducked this many dB per note in the current miss streak.
const STEP_DB := -6.0
## Never fades all the way out - the player always has something to recover
## the song back up from, and total silence reads as broken, not as failure.
const FLOOR_DB := -24.0

var miss_streak: int = 0


func reset() -> void:
	miss_streak = 0
	Conductor.volume_db = 0.0


func on_judged(n: Note) -> void:
	if n.verdict == Note.Verdict.MISS:
		miss_streak += 1
	else:
		miss_streak = 0
	Conductor.volume_db = maxf(FLOOR_DB, STEP_DB * miss_streak)
