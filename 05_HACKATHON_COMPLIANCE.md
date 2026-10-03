# Hackathon requirements and project fit

This document maps the supplied competition PDFs to a proposed implementation. They are reference material for the user's request; they do not authorize coding, publication, registration or submission. None of those actions has been performed.

## 1. Mandatory requirements from the supplied documents

| Requirement | PDF reference | BorrowPhone response / current status |
| --- | --- | --- |
| Target HarmonyOS, OpenHarmony or Oniro | CRITERIA p.2 | First runnable target: native ArkTS/ArkUI on the Oniro OpenHarmony 6.1 emulator; Huawei commercial-device compatibility remains unverified |
| Target API20 or newer; minimum API20 where applicable | CRITERIA p.2 | Compile API23, compatible/minimum API20; exercised on OpenHarmony 6.1.0.31 API23 |
| Compatible SDK and working emulator/device execution | CRITERIA p.2 | OpenHarmony SDK23, minimum API20; signed HAP installed and launched on the Oniro API23 emulator |
| Demonstrate a platform/device/system capability | CRITERIA p.2 | Picker, system authentication, window/lifecycle policies; kiosk only if legitimately available |
| Installable application/component without modifying the system | CRITERIA p.2 | One HAP; no OS patch or privileged system replacement |
| Public source repository | CRITERIA p.3 | To be created/published by the team during implementation |
| Reproducible setup, build, installation and launch | CRITERIA pp.2-3 | Evidence and final instructions planned in the implementation document |
| Working `.hap` | CRITERIA p.3 | Locally built, installed and launched; a clean source-copy sign/build passed, while independent reproduction and the submission artifact remain pending |
| Brief recorded demo | CRITERIA p.3 | Proposed script available; recording pending |
| Concise architecture and implementation description | CRITERIA p.3 | Architecture provided now; actual implementation description must follow |
| AI_WORKFLOW.md when AI tools are used | CRITERIA pp.2-3 | Initial honest planning record included; extend throughout development |
| Additional AI integration documentation if product uses AI | CRITERIA p.3 | No product AI planned; not currently applicable |
| English submissions, presentations, demos and project documentation | RULES p.2, section 4 | This document pack is English; plan English UI/demo |
| Created or substantially developed during the challenge; disclose material pre-existing components and AI use | RULES p.2, section 4 | Maintain commit history, tool record and acknowledgements |

The rules refer to the official HackYeah schedule and submission platform. The supplied PDFs do not provide an exact submission time: confirm it from the organizer's current schedule. Do not substitute a guessed time. Team eligibility, registration and rights to third-party/demo assets remain team responsibilities; this architecture does not certify them.

## 2. Scoring and practical evidence

Weights are the same in RULES p.3, section 5 and CRITERIA pp.3-4.

| Criterion | Weight | What BorrowPhone should demonstrate |
| --- | ---: | --- |
| Originality | 20% | A clear, temporary consent boundary for a common phone-sharing interaction; explain distinctive implementation without claiming the first-ever private photo viewer |
| Demonstrated usefulness | 20% | A person shows selected photos without unintentionally swiping into another one; connect directly to Human-Centric Technology |
| Technical execution | 20% | Correct manifest checks, native authentication, bounded imports, error behavior and real negative-path results |
| Use/enhancement of platform capabilities | 20% | Show native system picker and authentication, privacy/lifecycle behavior, and any honestly validated system containment |
| Demonstration quality | 10% | Running narrow workflow, understandable security scope, visible owner and guest roles |
| Reproducibility and transparent workflow | 10% | Clean-build instructions, exact environment, package, commit history and accurate AI_WORKFLOW |

Platform capabilities are one fifth of the score, not a demand to integrate every available kit. The criteria reward justified components and a working narrow solution. Adding cloud AI, distributed networking or an MDM subsystem purely to increase the API count would make privacy and demonstration harder.

## 3. Positioning

**Primary theme: Human-Centric Technology.** The value is controlled disclosure, privacy and understandable ownership of a device during a social interaction. Large buttons, readable contrast and accessible labels support the theme without requiring an unrelated AI feature.

Proposed statement before containment is verified:

> BorrowPhone creates a temporary, owner-approved photo session. Its guest viewer exposes only the selected images and requires fresh system authentication to return to owner controls. Whole-device containment is a separate, device-dependent integration under evaluation.

If a containment deployment passes the necessary tests, describe that exact deployment and prerequisites. Do not remove relevant process-failure limitations from the pitch. If it does not pass, a narrower viewer demo may still show useful functionality, but it must not be presented as fulfilling the full “borrow an unlocked phone safely” promise.

## 4. Submission checklist

- [ ] Public repository contains the actual source and dependency/third-party acknowledgements.
- [ ] API target and minimum meet the competition requirement.
- [ ] Clean build, install and launch instructions were followed successfully by someone else.
- [ ] Working `.hap` corresponds to the demonstrated source revision.
- [ ] Demo recording shows actual behavior and explains emulator/hardware limitations.
- [ ] All submitted written and spoken material is English.
- [ ] Architecture reflects the code that was actually delivered.
- [ ] Validation evidence supports the stated protection scope.
- [ ] AI_WORKFLOW lists actual tools/models, prompts, reviews, failures and remaining limits.
- [ ] Any later product AI has a separate model/inference/data/privacy/validation description.
- [ ] Secrets, personal media, local machine paths and confidential transcripts are excluded from publication.
- [ ] Official deadline, platform and any organizer updates have been checked by the team.

The PDFs remain the authoritative supplied references; the source register identifies both files and the relevant pages. No judgment about licensing, prize acceptance or other legal matters is made here.
