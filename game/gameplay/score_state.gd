class_name ScoreState
extends RefCounted
## Score and combo. Deliberately separate from Judge: the Judge
## decides what happened, this decides what it is worth.

const VALUE := {
	Note.Verdict.PERFECT: 100,
	Note.Verdict.GREAT: 75,
	Note.Verdict.GOOD: 50,
	Note.Verdict.MISS: 0,
}

var score: int = 0
var combo: int = 0
var best_combo: int = 0
## Derived from combo so misses and resets cannot leave a stale multiplier.
var multiplier: int:
	get:
		return mini(1 + combo / 10, 5)
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
	# Increment first: the threshold hit earns the new multiplier.
	score += VALUE[n.verdict] * multiplier


## Percentage of the maximum achievable so far.
func accuracy() -> float:
	if judged == 0:
		return 100.0
	var got: int = 0
	for v in counts:
		got += VALUE[v] * counts[v]
	return 100.0 * got / float(judged * VALUE[Note.Verdict.PERFECT])
