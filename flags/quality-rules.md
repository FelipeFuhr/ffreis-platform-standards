# Quality-rule vocabulary (`category: quality`)

The controlled vocabulary for a flag registry's `rule` field. This file is the
**single source of truth** for valid rule ids —
`scripts/validate-flag-registry.py` extracts them from the `###` headings below
rather than carrying its own copy, so a rule cannot exist in the validator and
not in this document, or vice-versa.

## Why quality rules live in the flag registry at all

The fleet's standing philosophy is that *every point of deliberate variation is
a declared entry, never a silent gap* (`.claude/workspace/AGENTS.md` § "Every
point of variation is a declared flag"). Component and media quality rules are
the same shape of problem wearing different clothes: "this image is not lazy
loaded", "this deck renders in whatever font the build machine happened to
have", "this output target has no verification gate" are all **deliberate
variations in rigor** that were previously invisible. Declaring them makes the
difference between a considered trade-off and an accident machine-checkable.

Two properties carry the whole idea:

1. **Maximum rigor is the default.** A rule is enforced unless something says
   otherwise. Declaring a rule you do not enforce requires saying why.
2. **Every opt-out is declared and reasoned.** An `exceptions` entry is a
   first-class, reviewable allow-list row with a `scope` and a real `reason` —
   never a silent omission, never a bare suppression comment.

## The conformance rule that keeps this honest

A registry entry claiming enforcement must name the thing that enforces it;
one that does not enforce must justify itself. Concretely, for every
`category: quality` entry, `validate-flag-registry.py` requires:

| If the entry… | Then it must… |
|---|---|
| is **enforcing** (`default` is `true`, `"error"`, or `"warn"`) | name the gate in `seam` — a test, check rule, or CI step that actually exists |
| is **not enforcing** (`default` is `false` or `"off"`) | carry ≥1 `exceptions` entry with a real `reason` |
| carries any `exceptions` | give each a non-placeholder `reason` (`TODO`/`N/A`/`later` are rejected) |

This is the fleet's "don't formalize before you enforce — every spec field
needs its CI gate" constraint expressed as a validator. It is deliberately
two-directional: it blocks both the vacuous declaration (a rule nothing
checks) and the silent gap (rigor quietly switched off with no stated reason).

## Output-target classes

A quality rule is only meaningful for some kinds of output. The
`output_target` field names which, using three classes:

| Class | Means | Has a concept of… |
|---|---|---|
| `browser-live` | a page a user interacts with in a browser | viewport, fold position, deferred loading, interaction latency |
| `document-export` | a batch artifact with no runtime (PDF, Markdown, an exported HTML file not served as a page) | pages, text extraction, embedded resources |
| `raster-export` | a batch image | pixel dimensions, encoding, visual determinism |

**Getting this axis right is the point.** "Lazy-load below the fold" is not a
rule a batch-exported PNG is failing — there is no "later" to defer to, and no
fold. Declaring the class prevents a rule being audited against output it
cannot apply to, which is how a quality standard turns into noise and gets
ignored. Across this fleet's compiler family, exactly one compiler
(`ffreis-website-compiler`) produces `browser-live` output; the deck, document
and icon compilers are all batch, and a private CV/document builder produces
only exported artifacts. Treat `browser-live` as the narrow case, not the
default.

---

## Rules

Each rule below states what it asserts, the classes it applies to, and — where
it matters — what it deliberately does **not** claim. "Known enforcement"
records whether any repo in the fleet gates this today; a rule with none is
still a valid vocabulary entry, but declaring it as enforcing requires naming
a real `seam` (see the conformance table above).

### `font-integrity`

Every text node renders in a **declared** font, and the build **verifies the
declaration actually took effect** — resolved in the renderer, and embedded in
the artifact where the format embeds fonts.

Applies to: all three classes (any output with text).

The failure this exists for is silent, and is confirmed to have shipped in
this fleet more than once: a document pipeline that declares one family,
fetches it from a CDN at render time, and embeds a metric-compatible fallback
instead when that fetch does not land — passing every existing gate, because
the gates assert *a font is embedded* and *the text is legible*, never *which
family*. The matching raster case is a renderer with no declared font at all,
where output depends on whichever families the build machine has installed, so
the same commit produces different pixels on different machines.

Enforcing this rule means asserting **identity**, not presence:
`emb=yes`/"text is readable"/OCR recall are legibility proxies and do not
satisfy it. For a renderer, await font readiness before capture and fail when
a declared family did not resolve.

**Identity is necessary but not sufficient — the text must also survive as
text.** PDF/UA treats character encodings, Unicode character maps and use of
the `.notdef` glyph as separate checkpoints from embedding, and for good
reason: a font can be embedded and visually perfect while its glyphs map to no
Unicode, so every downstream consumer (copy-paste, search indexing, a screen
reader, an ATS parser) sees nothing. This has shipped in this fleet — a
renderer rasterised a *variable* font into Type 3 glyph procedures, which both
hid the family name from `pdffonts` and stripped `ToUnicode` from some objects,
degrading extraction with every existing gate still green. Where the format has
the concept, assert Unicode-mappability alongside identity; static per-weight
faces avoid the variable-instance trap entirely.

A theme that deliberately declares only a system stack is a legitimate
`exceptions` entry — a family with no webfont behind it was chosen on purpose,
and the rule's real target is a declared font that silently did not load.

### `image-alt-meaningful`

Every content image carries a non-empty `alt`, or is explicitly declared
decorative (`alt=""`). Presence of the *attribute* is not the assertion —
an empty value must be a deliberate decorative declaration rather than the
default outcome of a missing data key.

Applies to: `browser-live`, `document-export`.

Two half-built shapes are common and both fail this rule: a check that warns
instead of failing (so the warning accumulates and is never read), and a
schema that requires the `alt` *key* but accepts an empty string (so
`alt: ""` satisfies the contract while telling a screen reader nothing). Watch
for scope gaps too — a check wired into one page-rendering path while other
page types bypass it entirely enforces much less than it appears to.

### `output-gate-exists`

Every output target the project ships has **at least one
extraction-grounded verification gate** — a check that inspects the artifact's
*content*, not merely that a file appeared at the expected path.

Applies to: all three classes.

"The file exists with the expected name" is not a gate: it passes for an empty
PDF, a blank PNG, and a page whose body failed to render. Extraction-grounded
means text extracted from the artifact, pixels compared against a baseline, a
structural parse, or a round-trip through a real consumer application.

This is the meta-rule of the set. A compiler can satisfy every other rule in
this file for the target it verifies and ship a completely unverified second
target beside it; declaring this rule per `output_target` is what makes that
asymmetry visible.

### `contrast-aa`

Text meets WCAG 2.2 AA contrast against its actual background: ≥4.5:1, or
≥3:1 for large text (≥24px, or ≥18.66px at weight ≥700).

Applies to: all three classes.

Compute the real ratio from rendered colors. Hand-asserting a ratio in a CSS
comment is documentation, not a gate. This rule is most valuable where a color
arrives from **outside** the repo — a brand registry, a theme overlay, a
per-site inventory — because nothing in the authoring loop will catch an
externally-supplied accent that lands illegibly on its own background.

### `language-declared`

The output declares its natural language, and declares a different one for any
span that changes language.

Applies to: all three classes.

Cheap, mechanical, and easy to leave out of every gate because nothing looks
broken without it: a screen reader simply pronounces the text with the wrong
phonetics. HTML expresses it as `lang`/`hreflang`, PDF as the document and
span `Lang` entries (PDF/UA and PDF/A both make it a checkpoint), a deck or
document theme as a front-matter field.

A tool can decide that a language **is declared and well-formed**; it cannot
decide that the declared language is the **correct** one for the content —
that part needs a human or a language-detection pass, and a rule claiming
otherwise is overclaiming.

Watch the inverse failure, which has shipped here: a build flag that *defaults*
to one language and silently overrides the document's own declaration. The
content was labelled correctly and the pipeline relabelled it.

### `document-tagged-structure`

An exported document carries a real logical structure tree, not just marks on
a page: content is tagged, non-content (rules, decoration, running heads) is
marked as an artifact, headings/tables/lists/links use their proper structure
types, and the structure order reflects the intended reading order.

Applies to: `document-export`.

This is the document-format analogue of `landmark-structure` plus
`table-semantics` plus `heading-hierarchy` at once, and it is standardised:
**PDF/UA (ISO 14289)** defines it, and veraPDF validates it as a few hundred
discrete checkpoints across PDF/UA-1 and PDF/UA-2. A generator that paints
visually-correct pages with no tagging produces a document that is unreadable
to assistive technology while looking perfect to its author — which is exactly
why nothing catches it without a gate.

Machine-decidable: whether a structure tree exists, whether content is tagged,
whether artifacts are marked, whether table header relationships are
well-formed. **Not** machine-decidable: whether the reading order matches human
intent, or whether something tagged as a heading really is one. Split the rule
accordingly rather than claiming the whole of PDF/UA is automatable — the
standard itself distinguishes machine-checkable conditions from ones requiring
human review.

### `conformance-claim-validated`

If an artifact *claims* conformance to a standard, the build **validates** that
claim rather than trusting the metadata that asserts it.

Applies to: `document-export`, `raster-export`.

A conformance claim is a string an encoder writes. Checking that the string is
present proves the encoder wrote it, nothing more — a document can carry a
PDF/A identifier in its XMP and fail actual PDF/A validation. This rule exists
because that specific shortcut is common: a hand-rolled "smoke check" greps for
the claim, the real validator is never run, and the build reports conformance
it has not established.

Mechanical, with a real tool — veraPDF for PDF/A and PDF/UA. It also publishes
a machine-checkable WCAG 2.2 profile distinct from its complete one, which is a
vendor-maintained answer to "which criteria can a gate decide without a human"
and is worth preferring over a hand-drawn subset.

### `output-dimensions`

A raster artifact's pixel dimensions match what its configuration declared.

Applies to: `raster-export`.

Deliberately narrow and purely mechanical. It exists because a fractional
device-scale factor, a sub-pixel element box, or a capture-clip rounding
change can silently shift output by a pixel, and a downstream consumer with a
fixed-geometry slot will be subtly wrong with nothing failing. Cheap to
enforce; catches a class of drift no visual review reliably notices.

### `image-loading-strategy`

Each image declares exactly one loading posture appropriate to its position:
a high-priority hint for a candidate largest-contentful element above the
fold, deferred loading below it, and **never both on the same element** (they
contradict: one says fetch immediately, the other says wait until near the
viewport).

Applies to: `browser-live` **only** — this rule is meaningless for every batch
target, and declaring it against one is a category error.

The specific defect worth gating is an above-the-fold image still marked for
deferred loading: the single most damaging anti-pattern for perceived load
time, and the most mechanically detectable (static analysis of document
position plus attribute, no rendering required). Note that a blanket
"defer everything" default inverts the rule for exactly the image that matters
most, and a template-authored opt-out is the mechanism to declare per image.

### `responsive-image-variants`

A content image offers multiple width variants with an explicit `sizes`
declaration and a modern-format fallback chain, plus intrinsic `width`/
`height` so layout does not shift as it loads.

Applies to: `browser-live` only.

### `form-a11y`

Every form control has a persistent programmatic label, required fields are
marked both visually and programmatically, personal-data fields carry correct
`autocomplete` values, and error messages are wired to their field.

Applies to: `browser-live` only.

A placeholder is not a label — it disappears on first keystroke. An asterisk
alone is not a required-marking. All four parts are statically checkable
against compiled markup; none of them need a browser.

### `landmark-structure`

Every page provides the semantic landmarks that let assistive technology and
reading-order tooling navigate it: exactly one main region, a navigation
region where navigation exists, banner and contentinfo at top level, landmarks
distinguishable from one another, and no content stranded outside them.

Applies to: `browser-live`, `document-export`.

Distinguish **presence** from **non-emptiness**: a validator asserting that
the title and first heading are non-empty *when present* does not assert they
exist, so a page with no heading at all passes. This rule is the presence
half, and it is the half usually missing.

Scoped to landmarks only. Heading levels belong to `heading-hierarchy` and the
document language to `language-declared` — both were folded in here
originally, which made a single registry entry cover three independent gates
and left no way to declare one of them enforced and another not.

### `design-token-only`

Color, shadow, spacing and motion values come from declared design tokens;
raw literals are rejected outside the token-definition file itself.

Applies to: all three classes (anywhere a theme defines visual values).

The enforceable form of "keep the visual language consistent". Taste is not
gateable, but *no ad-hoc literal outside the token file* is — the same trick
as a unit-literal ban, aimed at color, shadow, duration and spacing. The
token-definition file is the one declared exception, and belongs in
`exceptions` rather than in a special case inside the checker.

### `heading-hierarchy`

Headings have discernible text, descend without skipping levels, and the
document has exactly one top-level heading.

Applies to: `browser-live`, `document-export`.

Split out of `landmark-structure`. Statically decidable from the heading
sequence alone — no rendering needed — and it is the structure most readers
actually navigate by.

### `table-semantics`

A data table is built as a data table: a real `<caption>` (not a paragraph
above it styled to look like one), header cells as `<th>` with a correct
`scope`, `<thead>`/`<tbody>` grouping, and — where headers are multi-level and
cannot be expressed by position — explicit `id`/`headers` association. A table
used purely for visual layout is not a data table and must not carry data-table
semantics.

Applies to: `browser-live`, `document-export`.

Fully decidable from static markup, and unusually high-value because the wrong
form is invisible to a sighted reviewer: a fake caption and a `<td>` row of
bold text look identical to a real caption and `<th>` row, while conveying no
relationships at all to anything parsing the structure.

### `link-quality`

A link's own text names its destination well enough to make sense out of
context, links that open a new context say so, and two links with the same
accessible name go to the same place.

Applies to: `browser-live`, `document-export`.

The canonical wrong form is "click here" / "read more", which is useless to
anyone scanning a list of links out of context. Link text and duplicate-name
checks are static; whether a link is distinguishable from surrounding text
*without relying on colour* needs rendered styles.

Note one sub-rule has aged: pairing `target="_blank"` with `rel="noopener"` is
still good hygiene for old browsers, but modern engines apply `noopener`
implicitly, so gate it as a recommendation rather than a security finding.

### `list-semantics`

Lists are real lists: `<li>` only inside `<ul>`/`<ol>`, `<dt>`/`<dd>` only
inside `<dl>`, and no list-shaped pile of `<div>`s with bullet glyphs.

Applies to: `browser-live`, `document-export`.

Pure parent/child structure, entirely static, and cheap. Assistive technology
announces list length and position from it, which a styled `<div>` stack
cannot provide.

### `media-text-alternatives`

Time-based media carries the text alternatives its kind requires: one `<track>`
per purpose, with `captions` (dialogue **plus** sound effects and musical cues)
distinguished from `subtitles` (dialogue transcription or translation only) and
`descriptions`; `srclang` present where the kind requires it; no two tracks
sharing kind, language and label; and no audio that autoplays without a control
to stop it.

Applies to: `browser-live`.

Track presence and attribute correctness are static. Whether autoplaying audio
exceeds the tolerated duration needs a rendered browser. The common wrong form
is a single undifferentiated subtitle file doing duty as captions, which omits
exactly the non-dialogue information a deaf viewer needs.

### `iframe-identified`

Every embedded frame carries a `title` describing what it contains, untrusted
or third-party content is `sandbox`ed, and offscreen frames defer loading.

Applies to: `browser-live`.

Static. Without a title, a screen-reader user must enter the frame to discover
what it is; `sandbox` is the difference between embedding content and granting
it your origin's capabilities.

### `control-semantics`

Interactive controls are the native element for the job, carry discernible
text, and are never nested inside one another.

Applies to: `browser-live`.

Covers the whole family of retrofits: a `<div onclick>` where a `<button>`
belongs, an implicit `<button>` type that submits a form by accident, an icon
button with no accessible name, a link wrapping a button. Static, and the
fix is almost always "use the native element", which is also less code.

### `icon-accessible-name`

An icon that conveys meaning has an accessible name; an icon that is pure
decoration is hidden from assistive technology and carries no ARIA or
`tabindex`.

Applies to: `browser-live`.

Static. The two halves matter equally — an unnamed meaningful icon is silent,
and a decorative icon left exposed adds noise to every screen-reader pass.
Note this interacts with inlining: a build step that converts `<img>` icons to
inline `<svg>` must carry the alternative text across, or it silently destroys
it.

### `unique-ids`

Element ids are unique within a document and every id reference resolves.

Applies to: `browser-live`, `document-export`.

Foundational rather than interesting on its own: `label`/`for`,
`aria-describedby`, `aria-labelledby`, `headers`/`id` and in-page links all
resolve through ids, so a duplicate or dangling id silently breaks whichever
of those depends on it. Cheap, static, and worth gating before the rules that
build on it.

### `element-nesting-valid`

Markup is assembled legally: elements appear only where their content model
permits, required parents and ancestors are present, and elements that may
appear once do.

Applies to: `browser-live`.

The most literal "is this chunk built correctly" rule in the vocabulary, and
the one that catches structural nonsense before any accessibility rule has to
reason about it. Static, and well covered by existing HTML validators rather
than needing bespoke checks.

### `reduced-motion`

Motion respects the viewer's OS-level reduced-motion preference: every
animation or transition is either guarded by the preference query or is not
motion at all.

Applies to: `browser-live` only (a batch artifact does not animate).

---

## Worked examples

An enforcing rule names its gate:

```json
{
  "name": "font_integrity",
  "kind": "gate",
  "category": "quality",
  "binding": "compile",
  "effect": "toggle",
  "default": true,
  "rule": "font-integrity",
  "output_target": "document-export",
  "seam": "tests/pdf_fonts_test.go TestEmbeddedFontIsTheDeclaredFamily",
  "description": "The exported PDF must embed the declared family, not a metric-compatible fallback."
}
```

A deliberate carve-out inside an otherwise-enforced rule:

```json
{
  "name": "font_integrity",
  "kind": "gate",
  "category": "quality",
  "binding": "compile",
  "effect": "toggle",
  "default": true,
  "rule": "font-integrity",
  "seam": "internal/check/probe.js checkFonts",
  "exceptions": [
    {
      "scope": "themes declaring only a system font stack",
      "reason": "a family with no webfont behind it was chosen deliberately; the rule targets a declared webfont that silently failed to load, which is the case that actually breaks output",
      "added": "2026-10-16"
    }
  ]
}
```

A rule the project has decided **not** to enforce yet — honest, visible debt
rather than an absent entry. Note `default: "off"` with a reasoned exception,
**not** a placeholder `seam`: the seam field names a real code location or it
stays absent:

```json
{
  "name": "output_gate_pdf",
  "kind": "value",
  "category": "quality",
  "binding": "compile",
  "effect": "route",
  "options": ["error", "warn", "off"],
  "value_type": "enum",
  "default": "off",
  "rule": "output-gate-exists",
  "output_target": "document-export",
  "exceptions": [
    {
      "scope": "the PDF target",
      "reason": "no text-extraction gate exists for this target yet; the only current check is that the file was written at the expected path, which passes for an empty document. Tracked debt, promote to error when the extraction gate lands.",
      "added": "2026-10-16"
    }
  ]
}
```

## Adding a rule

1. Add a `### \`rule-id\`` section here saying what it asserts, which
   `output_target` classes it applies to, and what it deliberately does not
   claim. The validator picks the id up automatically.
2. Prefer a rule that is mechanically checkable from an artifact. If the only
   way to state it is a matter of taste, it is not a rule — find the
   enforceable invariant underneath it (as `design-token-only` does for
   "consistent visuals").
3. Do not add a rule speculatively for a consumer that does not exist. An id
   here is cheap, but a rule with no real need is how a standard accumulates
   ceremony nobody applies.
