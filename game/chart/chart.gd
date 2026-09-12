class_name Chart
extends RefCounted
## A song's notes, loaded from JSON.
##
## Authoring is in beats because that is how music is written; everything is
## resolved to seconds once at load so nothing does BPM maths at runtime.

var title: String = ""
var bpm: float = 120.0
var audio_path: String = ""
## Shifts the whole chart. Use for songs whose first beat is not at t=0.
var offset: float = 0.0
## Sorted ascending by time. The spawner walks this with an index rather than
## searching, so the ordering is load-bearing.
var notes: Array[Note] = []

## Populated by lint(). Each entry describes a pair the player probably cannot
## physically connect.
var warnings: PackedStringArray = PackedStringArray()


static func load_from(path: String) -> Chart:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Chart: could not read %s" % path)
		return null

	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		push_error("Chart: %s is not a JSON object" % path)
		return null

	var c := Chart.new()
	c.title = str(data.get("title", path.get_file()))
	c.bpm = float(data.get("bpm", 120.0))
	c.audio_path = str(data.get("audio", ""))
	c.offset = float(data.get("offset", 0.0))

	var spb: float = 60.0 / c.bpm
	for raw in data.get("notes", []):
		if not (raw is Dictionary):
			continue
		var n := Note.new()
		n.time = float(raw.get("beat", 0.0)) * spb + c.offset
		n.pos = Vector2(float(raw.get("x", 0.5)), float(raw.get("y", 0.5)))
		n.slot = clampi(int(raw.get("slot", 0)), 0, 1)
		n.kind = Note.kind_from_string(str(raw.get("type", "tap")))
		n.length = float(raw.get("length", 0.0)) * spb
		c.notes.append(n)

	c.notes.sort_custom(func(a: Note, b: Note) -> bool: return a.time < b.time)
	return c


func duration() -> float:
	return notes[-1].end_time() if not notes.is_empty() else 0.0


func rewind() -> void:
	for n in notes:
		n.reset()


## Flag note pairs the same hand cannot physically travel between in time.
##
## With no discrete trigger, difficulty comes from hand travel distance rather
## than note density: two notes 80ms apart in the same place are trivial, two
## notes 400ms apart at opposite corners may be impossible. Density is visible
## when charting; reachability is not, which is why it needs a linter.
func lint(max_speed: float = 2.0, gap: float = 0.0,
		track_bounds: Callable = Callable()) -> PackedStringArray:
	warnings = PackedStringArray()
	var last: Array[Note] = [null, null]

	for n in notes:
		# Placement. The centre band has no track drawn under it, so a note
		# there would float over empty space; a note on the other hand's track
		# is unreachable by the hand that owns it.
		if gap > 0.0 and absf(n.pos.x - 0.5) < gap:
			warnings.append("slot %d: note at %.2fs sits in the centre gap (x %.2f)" %
				[n.slot, n.time, n.pos.x])
		elif track_bounds.is_valid():
			var t: Vector2 = track_bounds.call(n.slot)
			if n.pos.x < t.x - 0.001 or n.pos.x > t.y + 0.001:
				warnings.append("slot %d: note at %.2fs is on the other track (x %.2f)" %
					[n.slot, n.time, n.pos.x])

		var prev: Note = last[n.slot]
		if prev != null:
			# A hold occupies the hand until it ends, so travel time is
			# measured from when the previous note releases it.
			var travel: float = n.time - prev.end_time()
			var dist: float = prev.pos.distance_to(n.pos)
			if travel > 0.0001 and dist / travel > max_speed:
				warnings.append(
					"slot %d: %.2fs -> %.2fs needs %.1f u/s (max %.1f), dist %.2f" %
					[n.slot, prev.end_time(), n.time, dist / travel, max_speed, dist])
			elif travel <= 0.0001 and dist > 0.01:
				warnings.append(
					"slot %d: two notes at %.2fs in different places (dist %.2f)" %
					[n.slot, n.time, dist])
		last[n.slot] = n

	return warnings
