/// Provenance wording for AI output. The athlete never reads a model or
/// company name outside an AI consent notice (D11); the owner switches
/// providers by budget, so no screen names one. Screens say "AI" and this
/// line, whatever provider id or model id the server stored or sent
/// (old builds of the server still send `provider_label`; it is not shown).
library;

/// The provenance every AI proposal or answer carries: Tracend's rules and
/// validators check the output before the athlete sees it.
const aiProvenanceLine = 'checked by Tracend';
