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
## The same findings as Note pairs, [prev, next], so a tool can draw them in
## place rather than only print them. Placement warnings use [note, note].
var flagged: Array = []


static func load_from(path: String) -> Chart:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Chart: could not read %s" % path)
		return null

	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		push_error("Chart: %s is not a JSON object" % path)
		return null
	var c := from_dict(data)
	if c.title.is_empty():
		c.title = path.get_file()
	return c


static func from_dict(data: Dictionary) -> Chart:
	var c := Chart.new()
	c.title = str(data.get("title", ""))
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
		n.gesture = Note.gesture_from_string(str(raw.get("gesture", "")))
		c.notes.append(n)
	c.sort_notes()
	return c


## Sort on (time, slot), not time alone. Simultaneous notes are common - both
## hands land on the same beat all through the chart - and comparing only time
## leaves their relative order to an unstable sort, so the same file can load
## in a different order twice. Nothing downstream reads tie order, but a chart
## that is not deterministic is one the editor cannot round-trip.
func sort_notes() -> void:
	notes.sort_custom(func(a: Note, b: Note) -> bool:
		return a.slot < b.slot if is_equal_approx(a.time, b.time) else a.time < b.time)


## Replace every note from a dictionary, keeping this Chart object. The editor's
## undo restores snapshots this way so nothing holding the Chart goes stale.
func replace_notes_from(data: Dictionary) -> void:
	notes = from_dict(data).notes


func sec_per_beat() -> float:
	return 60.0 / maxf(bpm, 0.0001)


func beat_of(n: Note) -> float:
	return beat_of_time(n.time)


func beat_of_time(seconds: float) -> float:
	return (seconds - offset) / sec_per_beat()


func set_beat(n: Note, beat: float) -> void:
	n.time = beat * sec_per_beat() + offset


func length_beats(n: Note) -> float:
	return n.length / sec_per_beat()


func set_length_beats(n: Note, beats: float) -> void:
	n.length = maxf(beats, 0.0) * sec_per_beat()
	n.kind = Note.Kind.HOLD if beats > 0.0 else Note.Kind.TAP


func remove_note(n: Note) -> void:
	notes.erase(n)


## Back to the JSON the game loads. Round-tripping is the requirement: loading
## and saving with no edits in between must reproduce the same chart, or the
## editor silently rewrites every file it opens.
##
## Beats are recovered from seconds rather than remembered, so a chart whose
## BPM was corrected keeps its notes on the beat rather than at their old
## wall-clock positions.
func to_dict() -> Dictionary:
	var spb: float = 60.0 / maxf(bpm, 0.0001)
	var out: Array = []
	for n in notes:
		var entry := {
			"beat": snappedf((n.time - offset) / spb, 0.0001),
			"slot": n.slot,
			"x": snappedf(n.pos.x, 0.0001),
			"y": snappedf(n.pos.y, 0.0001),
			"type": "hold" if n.kind == Note.Kind.HOLD else "tap",
		}
		if n.kind == Note.Kind.HOLD:
			entry["length"] = snappedf(n.length / spb, 0.0001)
		if n.needs_gesture():
			entry["gesture"] = String(n.gesture)
		out.append(entry)
	return {
		"title": title,
		"bpm": bpm,
		"audio": audio_path,
		"offset": offset,
		"notes": out,
	}


func save_to(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Chart: cannot write %s (%d)" % [path, FileAccess.get_open_error()])
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), " "))
	f.close()
	return OK


func duration() -> float:
	var end := 0.0
	for n in notes:
		end = maxf(end, n.end_time())
	return end


func rewind() -> void:
	for n in notes:
		n.reset()


## Flag note pairs the same hand cannot physically travel between in time.
##
## With no discrete trigger, difficulty comes from hand travel distance rather
## than note density: two notes 80ms apart in the same place are trivial, two
## notes 400ms apart at opposite corners may be impossible. Density is visible
## when charting; reachability is not, which is why it needs a linter.
func lint(max_speed: float = 2.0,
		track_bounds: Callable = Callable()) -> PackedStringArray:
	warnings = PackedStringArray()
	flagged = []
	var last: Array[Note] = [null, null]

	for n in notes:
		# Placement. Anything off its own track floats over empty space and is
		# unreachable by the hand that owns it.
		if track_bounds.is_valid():
			var t: Vector2 = track_bounds.call(n.slot)
			if n.pos.x < t.x - 0.001 or n.pos.x > t.y + 0.001:
				warnings.append("slot %d: note at %.2fs is off its track (x %.2f)" %
					[n.slot, n.time, n.pos.x])
				flagged.append([n, n])

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
				flagged.append([prev, n])
			elif travel <= 0.0001 and dist > 0.01:
				warnings.append(
					"slot %d: two notes at %.2fs in different places (dist %.2f)" %
					[n.slot, n.time, dist])
				flagged.append([prev, n])
		last[n.slot] = n

	return warnings
