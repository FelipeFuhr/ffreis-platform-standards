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
reading-order tooling navigate it — a main region, a navigation region where
navigation exists, and a declared document language — plus a sane heading
hierarchy with no skipped levels.

Applies to: `browser-live`, `document-export`.

Distinguish **presence** from **non-emptiness**: a validator asserting that
the title and first heading are non-empty *when present* does not assert they
exist, so a page with no heading at all passes. This rule is the presence
half, and it is the half usually missing.

### `design-token-only`

Color, shadow, spacing and motion values come from declared design tokens;
raw literals are rejected outside the token-definition file itself.

Applies to: all three classes (anywhere a theme defines visual values).

The enforceable form of "keep the visual language consistent". Taste is not
gateable, but *no ad-hoc literal outside the token file* is — the same trick
as a unit-literal ban, aimed at color, shadow, duration and spacing. The
token-definition file is the one declared exception, and belongs in
`exceptions` rather than in a special case inside the checker.

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
