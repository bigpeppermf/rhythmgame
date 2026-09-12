class_name HandSource
extends Node
## Anything that can produce hand observations.
##
## The whole point of this class existing is that gameplay never knows which
## subclass it is talking to. `MockHandSource` (mouse) and `UdpHandSource`
## (real camera) are interchangeable, so the game can be built and tested
## end-to-end before the vision module exists.

## Write the latest observations into `hands` (always 2 entries, slot-indexed).
## Called once per frame. Implementations must not block.
func poll(_hands: Array) -> void:
	push_error("HandSource.poll() is abstract - use a subclass")


## Shown in the debug overlay so it is always obvious which input is live.
func source_name() -> String:
	return "abstract"
