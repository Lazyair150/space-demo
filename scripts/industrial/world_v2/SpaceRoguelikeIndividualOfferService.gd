extends RefCounted
class_name SpaceRoguelikeIndividualOfferService
## Builds a player-choice offer from the individual library without mutating ownership.
## Candidates retain their own pool/model identity; scores from different models are never compared.

static func roll_offer(
	library: SpaceRoguelikeIndividualLibrary,
	item_kind: String,
	rng: RandomNumberGenerator,
	offer_count: int,
	offer_id: String,
	allowed_rarities: PackedStringArray = PackedStringArray(),
	required_tags: PackedStringArray = PackedStringArray()
) -> Dictionary:
	if library == null or rng == null or not library.is_valid() or offer_count <= 0 or offer_count > 8 or offer_id.strip_edges().is_empty():
		return {"success": false, "reason": "offer request dependencies/count are invalid"}
	var candidates: Array[Dictionary] = []
	var excluded := PackedStringArray()
	for _index in range(offer_count):
		var candidate := library.roll_candidate(item_kind, rng, allowed_rarities, required_tags, excluded)
		if not bool(candidate.get("success", false)):
			break
		var definition_key := "%s:%s@%d" % [
				item_kind,
				String(candidate.get("definitionId", "")),
				int(candidate.get("definitionVersion", 0))
			]
		if excluded.has(definition_key):
			continue
		excluded.append(definition_key)
		candidates.append({
			"candidate": candidate.duplicate(true),
			"itemKind": item_kind,
			"definitionId": String(candidate.get("definitionId", "")),
			"definitionVersion": int(candidate.get("definitionVersion", 0)),
			"rarity": String(candidate.get("rarity", "")),
			"powerScore": float(candidate.get("powerScore", 0.0)),
			"powerBand": candidate.get("powerBand", {}).duplicate(true),
			"powerModelId": String(candidate.get("powerModelId", "")),
			"powerModelVersion": int(candidate.get("powerModelVersion", 0)),
			"tags": candidate.get("tags", []).duplicate(true)
		})
	if candidates.is_empty():
		return {"success": false, "reason": "no eligible individual candidates are available"}
	return {
		"success": true,
		"libraryId": String(library.library_id),
		"libraryVersion": library.definition_version,
		"offerId": offer_id,
		"itemKind": item_kind,
		"requestedCount": offer_count,
		"offers": candidates
	}

## Selection is the only path in this service that transfers a rolled candidate into ownership.
static func acquire_selected(
	offer: Dictionary,
	selected_index: int,
	state: SpacePlayerProgressionState,
	bundle: SpaceHangarCatalogBundle,
	library: SpaceRoguelikeIndividualLibrary,
	instance_id: String
) -> Dictionary:
	if library == null or String(offer.get("offerId", "")).strip_edges().is_empty() or String(offer.get("libraryId", "")) != String(library.library_id) or int(offer.get("libraryVersion", 0)) != library.definition_version:
		return {"success": false, "reason": "offer belongs to a different individual library version"}
	var offers: Variant = offer.get("offers", null)
	if not (offers is Array) or selected_index < 0 or selected_index >= offers.size():
		return {"success": false, "reason": "selected reward index is outside the offer"}
	var selected: Variant = offers[selected_index]
	if not (selected is Dictionary) or not (selected.get("candidate", null) is Dictionary):
		return {"success": false, "reason": "selected reward payload is malformed"}
	return SpaceRoguelikeIndividualRewardService.acquire_candidate(
		state, bundle, library, selected.candidate.duplicate(true), instance_id, String(offer.offerId)
	)
