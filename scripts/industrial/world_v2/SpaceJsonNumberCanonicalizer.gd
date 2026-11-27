class_name SpaceJsonNumberCanonicalizer
extends RefCounted
## Single owner for the JSON numeric boundary of the battle checkpoint.
##
## JSON has no integer type, so Godot decodes every number in a persisted snapshot as a
## float. The checkpoint schemas use integers for fixed-point volumes, sequence numbers and
## RNG state, and their validators reject floats on purpose: a truncated or fractional value
## must not pass as an integer. Canonicalising once, where the snapshot is decoded, keeps
## those validators strict without every domain re-implementing the same int/float tolerance.
##
## Only integral values inside the exact-integer range are converted. Anything else keeps its
## float type so schema validation still rejects it instead of silently truncating it.

const MAX_EXACT_INTEGER := 9007199254740991.0

## Returns a deep copy with integral floats converted to int; non-numeric values are returned
## unchanged. Never mutates the input.
static func canonicalize(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		if is_finite(number) and absf(number) <= MAX_EXACT_INTEGER and floor(number) == number:
			return int(number)
		return value
	if value is Dictionary:
		var canonical_dictionary := {}
		for key in value:
			canonical_dictionary[key] = canonicalize(value[key])
		return canonical_dictionary
	if value is Array:
		var canonical_array: Array = []
		for element in value:
			canonical_array.append(canonicalize(element))
		return canonical_array
	return value
