# ADR-015: The shipped mask's destination coordinate space follows the README for this round

Status: Accepted, locally — does not settle which document governs generally

Context: Two documents in this repository disagree about where a constructed pig mask should
live once the pipeline is done with it.
[`INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md`](../../INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md)
§5.2 requires the mask be mapped back to the original image coordinate system. The round's own
specification, `INSTAHAM_APP_WEIGHT_PIPELINE_SCALING_ROTATION_FIX_README.md` §9 and §12, requires
0.34 cm/px training space and explicitly forbids original full-resolution camera coordinates.
Round 8 is instructed to implement the README as the specification for this round, not to
adjudicate between the two documents.

Note that this is a narrower question than ADR-013's segmentation *order*. The gate branch's
`construct_pig_mask()` still unletterboxes to original capture coordinates (`orig_w x orig_h`) —
this conflict is specifically about the **weight branch's** mask, which composes its own
transform from the decoded 640 mask straight into training pixel space and never takes that step
(see [`pipeline/segmentation-2.md`](../pipeline/segmentation-2.md)).

Decision: For this round, the weight branch's constructed mask stays in the README's normalized
training-pixel coordinate space (0.34 cm/px), not original capture coordinates. No code changes
under this ADR — it records the standing this round already shipped under ADR-013, so the
disagreement with the requirements document is visible as a decision rather than as an
unexplained gap between two docs.

Consequences: `INSTAHAM_APP_REQUIREMENTS_AFTER_TRAINING.md` §5.2 is not satisfied by the weight
branch's shipped mask as of this round. Which document generally governs the mask's destination
coordinate space — whether §5.2 should be revised, whether the README's forbidding of original
coordinates should be narrowed to the weight branch only, or something else — is not decided
here and remains open. A future session choosing between them should write a new ADR that
supersedes this one rather than editing this record in place.
