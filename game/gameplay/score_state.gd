class_name ScoreState
extends RefCounted
## Score, combo and accuracy. Deliberately separate from Judge: the Judge
## decides what happened, this decides what it is worth.

const VALUE := {
	Note.Verdict.PERFECT: 100,
	Note.Verdict.GREAT: 70,
	Note.Verdict.GOOD: 40,
	Note.Verdict.MISS: 0,
}

var score: int = 0
var combo: int = 0
var best_combo: int = 0
var counts: Dictionary = {}
var judged: int = 0


func _init() -> void:
	reset()


func reset() -> void:
	score = 0
	combo = 0
	best_combo = 0
	judged = 0
	counts = {
		Note.Verdict.PERFECT: 0, Note.Verdict.GREAT: 0,
		Note.Verdict.GOOD: 0, Note.Verdict.MISS: 0,
	}


func apply(n: Note) -> void:
	judged += 1
	counts[n.verdict] += 1

	if n.verdict == Note.Verdict.MISS:
		combo = 0
		return

	combo += 1
	best_combo = maxi(best_combo, combo)
	# Combo multiplier caps at 4x so a single early miss is survivable.
	var mult: int = clampi(1 + combo / 10, 1, 4)
	score += VALUE[n.verdict] * mult


## Percentage of the maximum achievable so far.
func accuracy() -> float:
	if judged == 0:
		return 100.0
	var got: int = 0
	for v in counts:
		got += VALUE[v] * counts[v]
	return 100.0 * got / float(judged * VALUE[Note.Verdict.PERFECT])
