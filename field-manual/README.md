# Field Manual — Maintainer Guide

## 1. Purpose

`field-manual/` is an in-repo committed public-domain (PD) corpus, parallel to
`doom/` in status: content is tracked directly in git and is NOT fetched at
build time. Build scripts copy the directory as-is to the USB at
`field-manual/` — what you see in the repo is exactly what ships.

The corpus covers survival skills, emergency first aid, edible plant
identification, amateur radio operation, private well water management, and
rope knots. All content is browseable via `field-manual/index.html` using a
`file://` URL — no server required, mobile-friendly.

**Why PD-only matters:** Every USB built from this kit redistributes this
content. Including copyrighted material — even one paragraph — would make
every user who builds the kit an infringer. There is no "educational use"
exception for redistribution at scale. PD-only is not a preference; it is
the only legally safe posture for a kit that ships to unknown third parties.

---

## 2. Authoritative PD Sources

### US Government works (safest — use these first)

Works produced by officers or employees of the US Federal Government as part
of their official duties are public domain under 17 U.S.C. § 105. No
publication date or registration check required.

Authoritative agencies for this corpus:

- **FEMA** — emergency preparedness, disaster survival guides
- **FCC** — amateur radio regulations (Part 97, licensing guides)
- **USDA** — edible plants, food safety, field guides
- **EPA** — water quality, private well management
- **DOD / US Army** — field manuals (FM series), survival training publications
- **DOE** — off-grid energy reference materials
- **NOAA** — weather, environmental hazard guidance
- **NIST** — measurement, safety standards

Source URL must be on a `.gov` domain. If a third party re-hosts a government
publication, use the `.gov` original — the re-hosted copy may include
copyrighted editorial additions.

### Pre-1928 published works

Works published before January 1, 1928 are in the public domain in the US
under the pre-1976 Copyright Act. No registration check required; publication
date alone is sufficient.

### US state government works

Most US state government works are public domain, but this varies by state —
some states (California, for example) assert copyright in certain statutory
compilations. Check the specific state's copyright policy before including
state-level content.

### International government works

NOT automatically public domain in the US. A Canadian government publication,
a UK Crown Copyright work, or a WHO document may be copyrighted in the US
even if freely available. Verify case by case before including.

---

## 3. Sources to AVOID

Do not add content from any of the following. The list is explicit because
all of these have been proposed or searched in the past.

**American Red Cross** — The Red Cross is a private nonprofit organization,
NOT a US Government agency. Red Cross first aid manuals, CPR guides, and
training materials are copyrighted by the American Red Cross. Despite the
humanitarian mission, copyright protection is standard and enforced. Do not
include any Red Cross text, diagrams, or checklists.

**The Ashley Book of Knots (Clifford W. Ashley, 1944)** — Published in 1944,
copyright held by Ashley's estate/descendants. Will not enter the public
domain until January 1, 2040 at the earliest. The knots content in this
corpus (`knots.md`) uses Army FM sources only.

**Boy Scouts of America (BSA) handbooks and merit badge pamphlets** — BSA is
a private organization. All BSA publications, including the Fieldbook and
merit badge series, are copyrighted. BSA content is not public domain and
cannot be included.

**Post-1927 commercial wilderness survival books** — Works by authors such as
Tom Brown Jr., Les Stroud, or Mors Kochanski are under copyright. Availability
on Archive.org does NOT imply public domain status. Archive.org hosts
copyrighted works under fair use and lending agreements that do not extend to
redistribution.

**Wikipedia text** — Wikipedia content is licensed CC BY-SA 4.0, not public
domain. Including it would require attribution in every copy AND would force
all derivative works into CC BY-SA (ShareAlike). This is incompatible with
the Apache-2.0 kit license. Do not include Wikipedia text.

---

## 4. Adding a New Topic File

Follow this checklist in order. Do not skip steps.

1. **Identify a PD source.** US Government works (section 2) are the
   preferred starting point. Search `.gov` domains directly rather than
   relying on third-party aggregators.

2. **Confirm PD status.** Ask:
   - Is the publisher a US Federal Government agency? (If yes, PD per
     17 U.S.C. § 105.)
   - Was it published before January 1, 1928? (If yes, PD by date.)
   - If neither applies, do not proceed. See section 6.

3. **Create `field-manual/<topic>.md`.** Filename convention: lowercase,
   hyphen-separated words, `.md` extension. Examples:
   `water-purification.md`, `fire-starting.md`, `navigation-land.md`.

4. **Add an attribution header at the top of the file.** Required format:

   ```
   <!-- SOURCE: <Full publication name>
        PUBLISHER: <Agency or author>
        DATE: <Publication date or edition year>
        PD BASIS: <17 U.S.C. § 105 | Pre-1928 publication | Explicit PD release>
        URL: <Canonical .gov URL or archive link>
   -->
   ```

   Do not omit the URL — it is the paper trail for future vetting.

5. **Extract and summarize the content.** Do not paste the full source
   verbatim if the source document is long — paraphrase and attribute.
   Verbatim short excerpts (checklists, specific procedures) are acceptable
   when accuracy matters (e.g., radio frequency regulations, medical dosing).

6. **Update `field-manual/index.html`.** Add a new entry to the sidebar TOC:

   ```html
   <li><a href="<topic>.md"><Topic Title></a></li>
   ```

   And add a corresponding `<section id="<topic>">` block in the main
   content area following the existing pattern.

7. **Update `field-manual/NOTICE.md`.** Add the new source to the
   "Sources Used" table: title, publisher, date, PD basis, URL.

8. **Commit.** Include the canonical source URL in the commit message body
   for traceability. Example commit message body:

   ```
   Source: https://www.epa.gov/privatewells/private-drinking-water-wells
   PD basis: 17 U.S.C. § 105 (EPA federal government work)
   ```

---

## 5. Updating Existing Files

- **Preserve the attribution header.** Every existing file in the corpus
  has a `<!-- SOURCE: ... -->` header. Do not remove it or rewrite it
  unless you are updating the source reference.

- **Note the edition or version you referenced.** Government publications
  are revised periodically. Record the specific edition in the header, e.g.,
  `FM 21-76, 1992 edition`. If a newer edition exists and you update the
  content, update the DATE field and URL to match the new edition.

- **Treat upstream revisions as new sources.** If the EPA publishes a
  revised well water guide, re-verify PD status of the new edition before
  incorporating it. A revised publication is a new copyright event — the
  original PD basis applies to the original edition only.

- **Do not remove attribution headers when editing.** Prose changes,
  formatting fixes, and content additions are all fine. The header is the
  audit trail for every maintainer who comes after you — stripping it is not
  acceptable regardless of the edit scope.

---

## 6. License Verification Quick-Check

Before adding any source, ask these three questions in order:

**Q1. Is the publisher a US Federal Government agency?**
If yes: PD per 17 U.S.C. § 105. No further check needed. Proceed.

**Q2. Was it published before January 1, 1928?**
If yes: PD in the US under pre-1976 Copyright Act rules. Proceed.

**Q3. Does the copyright holder explicitly state public domain release?**
If yes: PD by declaration. Verify the statement is from the rights holder
(not a third party), then proceed.

**If none of the above apply: DO NOT ADD.**
Do not make assumptions about fair use, educational use, "freely available,"
or Creative Commons licenses — none of these permit redistribution at scale
under Apache-2.0. If you believe a source should qualify and none of the
three questions apply, flag it for explicit legal review rather than adding
it and hoping for the best.
