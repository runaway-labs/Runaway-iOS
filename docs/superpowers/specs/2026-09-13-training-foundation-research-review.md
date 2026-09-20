# Runaway Training Foundation Review

## Decision

The initial foundation should not become the production training system unchanged.
Its useful elements are explicit measurements, equal-priority goals, date-only race
deadlines, validation and account ownership checks. Its weaknesses are more
fundamental than missing interface polish: it stores a snapshot rather than a
training history, uses preference storage for sensitive information, lacks automatic
account-lifecycle invalidation, and does not yet connect goals to prescriptions.

The recommended architecture is an evidence-aware training decision system:

`goals + observations + constraints -> feasible sessions -> prescription -> actual results -> revised decisions`

The language model belongs at the interpretation and explanation boundaries. It
must not become the hidden authority for physiological calculations. Equally,
deterministic mathematics is not automatically scientifically valid: coefficients,
thresholds and progression policies need evidence, transparent assumptions and
evaluation against real training outcomes.

This review covers the current foundation, selected existing integration points,
original training studies, research syntheses and official Apple documentation.
It is not a full application/security audit or a clinical validation of the coach.
Evidence considered is available through September 13, 2026. Some studies were
accessible only as abstracts; those limits are identified below.

## Priority findings

### 1. Account ownership checks are not account lifecycle isolation

**Confirmed by an isolated executable probe.** After saving athlete A's profile,
changing the injected active account to B leaves A's profile exposed through the
store's published `profile` property. A later load/save operation clears it, and
cross-account writes are rejected. The gap is immediate invalidation of memory,
not a demonstrated server authorization bypass.

Relevant code: `Runaway iOS/Services/AthleteTrainingProfileStore.swift`, especially
`profile`, `requireOwner` and `clearSession`. The new store is not yet wired into
the live profile UI, so this is a release blocker for integration rather than a
claim that the current TestFlight build exposes this new data.

**Required change:** own the repository in a session-scoped coordinator. Sign-out
and account replacement must clear profile, observations, decision state and widget
projection together. Associate asynchronous work with an account generation token;
reject late publications from previous generations. Observe authentication changes
rather than hoping the next repository access will clean up.

### 2. UserDefaults is the wrong durable home for this profile

The new store writes the entire encoded aggregate to UserDefaults. That aggregate
includes body measurements and reported limitations. Apple documents UserDefaults
as preference storage and directs sensitive information elsewhere; its privacy
guidance recommends an appropriate strong file-protection level for stored files.
Account-specific key names are useful namespacing, not encryption or an access
control boundary. [Apple UserDefaults](https://developer.apple.com/documentation/Foundation/UserDefaults?changes=_3&language=objc),
[Apple privacy guidance](https://developer.apple.com/documentation/uikit/protecting-the-user-s-privacy).[^1]

**Required change:** use a transactional local repository with explicitly selected
iOS data protection, account ownership, migration and deletion behavior. Keep
credentials or application encryption keys in Keychain. Choose protection policy
alongside locked-device requirements: unavailable protected data is an explicit
state, not a reason to weaken protection silently. Do not put the whole training
database into Keychain. UserDefaults can retain non-sensitive presentation choices.

Cloud synchronization is a separate requirement. Local-only inference does not
imply local-only storage, but health-derived information should not be uploaded by
default just because backend delivery exists. Define consent, retention and a
minimal notification projection before introducing cloud profile sync.

### 3. One baseline cannot support meaningful progression

`AthleteTrainingGoal` has a single optional baseline embedded in the goal. Updating
it would erase the distinction between starting ability and later observations.
`TrainingBodyMeasurements` similarly represents one height and one weight, not a
time series. These can work as display projections, but not as the source of truth.

**Required change:** separate goals from appendable, correctable observations.
Record source, source record ID, measured time, received time, exercise variant,
equipment identity, load convention, effort scale and quality flags. Corrections
supersede earlier observations without silently rewriting history. Goal progress
is a derived view of eligible observations, with its method/version recorded.

### 4. Equal labels do not guarantee equal training priority

The new aggregate allows two equally primary goals. The existing
`TrainingProfile.validated` still requires one primary activity and reduces
supporting sessions first when capacity is exceeded. The new labels alone cannot
change that behavior. The daily selector also has no direct goal portfolio input.

**Required change:** define anti-starvation constraints over an agreed training
window, not just equal coefficients in a score. Track separate running and strength
commitments. If available time cannot satisfy them, expose the conflict and ask
which constraint to change. Do not invent extra time, assume doubles or demote
strength. Deadlines can influence temporary emphasis only with an explicit plan
and visible tradeoff.

### 5. The prescription/result boundary is still too weak

The existing `DailyWorkout` uses a string pace and `Exercise` uses string reps and
weight. Such strings can display a workout, but cannot reliably compare prescribed
versus completed work or drive progression. A single completion Boolean also loses
partial-session and set-level outcomes.

**Required change:** keep typed prescription blocks separate from actual results.
Support timed sets, repetition ranges, external load, assisted load, bodyweight,
rest, unilateral work and equipment increments. The initial schema's loaded-versus-
bodyweight categories cannot fully represent assisted pull-ups or distinguish two
machines with different resistance characteristics. Never infer that matching
display names make observations interchangeable.

## What training evidence supports

### Concurrent training is defensible; universal interference rules are not

Schumann and colleagues' synthesis included 43 studies of concurrent aerobic and
strength training. It did not find a significant pooled disadvantage for maximal
strength or hypertrophy compared with strength training alone, but explosive
strength gains were attenuated, particularly in same-session comparisons. The
review does not establish one ideal schedule for every recreational athlete or
prove that separation by a fixed number of hours guarantees recovery.
[Schumann et al., 2022](https://pubmed.ncbi.nlm.nih.gov/34757594/).[^2]

**Design consequence:** classify demands and outcomes. A heavy lower-body session,
an upper-body session and power work should not all trigger the same generic
strength conflict. Session timing and actual work matter. Equal-priority running
and strength is a reasonable product goal; equal minutes is not its definition.

### Progressive resistance training matters more than algorithmic ornament

The 2026 ACSM position stand updates the 2009 guidance and synthesizes 137 reviews
covering more than 30,000 participants. It distinguishes strength, hypertrophy and
power outcomes and reports that many programming variations do not consistently
change outcomes. It is guidance for healthy adults, not a justification for applying
heavy-load prescriptions to an unassessed person or a special clinical population.
[Currier et al., 2026](https://pubmed.ncbi.nlm.nih.gov/41843416/).[^3]

**Design consequence:** ask what strength means: a specific performance target,
muscle development, general strength or another outcome. Begin with a small,
well-reviewed prescription library and explain the progression rule. Do not sell
complexity as superiority. Avoid defaulting to a maximal test to obtain a baseline.

### Autoregulation needs observations and honest uncertainty

Graham and Cleather studied 31 resistance-trained men in a 12-week squat program.
Both groups improved, with greater improvements in the repetitions-in-reserve
group than fixed loading. This supports feedback-informed adjustment in that
setting, not a promise that a phone can infer every user's appropriate weight.
The paper also discusses limitations of effort estimation and mixed findings
from earlier studies. [Original study](https://research.stmarys.ac.uk/3067/3/Graham-Cleather-Autoregulation-Repetitions-in-Reserve.pdf).[^4]

**Design consequence:** distinguish session RPE, set RPE and repetitions in reserve;
the current unqualified `reportedEffort` number is ambiguous. Gather actual reps,
load and perceived effort, then recommend hold/increase/decrease with an explanation.
Missing evidence produces a calibration or effort-based session, not invented
kilograms. Equipment-specific rounding is part of the prescription.

### HRV research does not validate the current readiness cutoffs

Vesterinen et al. studied 40 recreational endurance runners using individual HRV
criteria to time harder sessions. The HRV group performed fewer moderate/hard
sessions; both groups improved maximal oxygen uptake. The abstract describes
individualized morning measurements, not a universal readiness score with thresholds
at 50 and 70. The small between-group performance difference should not be turned
into a broad claim of algorithmic superiority.
[Vesterinen et al., 2016](https://pubmed.ncbi.nlm.nih.gov/26909534/).[^5]

The app's HealthKit reader requests `heartRateVariabilitySDNN`. Store that metric
identity and acquisition context. Do not substitute an Apple Health sample for a
different HRV measurement protocol without validation. Preserve missingness,
recency, collection source and an individual reference range as separate inputs.

**Design consequence:** recovery decisions should identify which evidence changed
the plan. Missing readings cannot be relabelled poor readiness. A score alone must
not explain away two inactive days and saved goals with a bare Walking title.

### Running progression requires more than a universal weekly percentage

Buist et al.'s randomized trial of 532 novice runners found no reduction in
running-related injuries from the tested graded program based on the 10% rule
relative to its comparison program. That does not show all gradual progression
is ineffective. [Buist et al., 2008](https://pubmed.ncbi.nlm.nih.gov/17940147/).[^6]

A more recent observational cohort of 5,205 runners associated single-session
distance spikes with higher overuse-injury rates. Association is not causation,
and this study cannot supply a guaranteed safe threshold for an individual.
[2025 cohort](https://pubmed.ncbi.nlm.nih.gov/40623829/).[^7]

**Design consequence:** retain session-level exposure as well as weekly totals.
Consider recent longest sessions, training continuity, current tolerance and stated
limitations. Do not label any percentage rule an injury-prevention guarantee, and
do not accumulate missed sessions into automatic catch-up workload.

## Recommended data architecture

Use a small number of explicit domain records rather than one growing Codable blob.

| Record | Responsibility | Important invariants |
|---|---|---|
| Goal | Desired outcome and priority | Stable ID, typed outcome, calendar semantics, lifecycle |
| Observation | What was measured | Source ID, metric, timestamp, quality, correction linkage |
| Session result | What was actually done | Planned linkage optional; partial work and set results preserved |
| Availability | What can be scheduled | Time zone, windows, minutes, travel and doubles consent |
| Equipment | What can be prescribed | Variant, machine identity, available loads and increments |
| Decision | Why this session was selected | Input revision, policy version, reasons, validity and goals |
| Prescription | Exact intended work | Typed blocks, duration/distance/effort/load without ambiguous strings |
| Delivery projection | What a notification may reveal | Minimal content, source revision, privacy choice, expiry |

Use a closed set of typed measurement variants rather than a struct in which every
field is optional. The latter makes many impossible combinations constructible and
shifts correctness entirely onto call-site validation. Maintain explicit migration
decoders for old versions rather than treating any noncurrent schema as corrupt.

Goal feasibility needs a separate result: supported, insufficient evidence or
conflicting constraints. It must not claim a probability of achieving a race time
without an independently validated forecasting model. Height and weight can support
appropriate context but are neither mandatory inputs nor shortcuts to race pace,
lifting loads or readiness.

Prefer a transactional local repository and lightweight observation correction
history over a full distributed event-sourcing platform. This preserves useful
history without needless operational complexity. If cloud sync is added, define
optimistic revisions, conflict resolution and deletion before deployment. Keep
notification snapshots separate from the authoritative training record.

## Engine architecture and mathematical accountability

Do not deploy the earlier additive score as though it were validated training
science. Normalization and weights can make an apparently precise formula favor
one discipline without obvious failures. Start with explicit constraints and
auditable tie-breaking:

1. Establish the known context, missing evidence and supported training population.
2. Remove candidates incompatible with reported limitations, equipment and time.
3. Protect actual completed sessions and explicit user choices.
4. Evaluate running and strength commitments separately over the planning window.
5. Choose among feasible sessions using documented priorities and deterministic ties.
6. Build a typed prescription from reviewed policies and observed performance.
7. Attach reasons, alternatives, confidence limits and expected remaining-week changes.

If no feasible plan exists, return a conflict rather than lowering one goal secretly.
For example, needing more session time than is available cannot be solved by giving
the language model a better prompt. Offer fewer commitments, more available time or
an explicitly revised goal timeline.

Each policy should have an evidence entry: source, population, application limits,
implementation rule, configurable parameters and version. Keep product heuristics
labelled as heuristics. A rule can be useful without pretending it predicts biology.

Avoid changing the recommendation on every tiny sensor update. Define meaningful
invalidation events and stability rules, with a visible reason when the plan changes.
Replay a decision from captured inputs; record comparison output when a new policy
version changes it. This is essential for investigating future Walking incidents.

## Platform and UX constraints

HealthKit deliberately does not expose whether read access was denied. An empty
query may therefore be absence of accessible evidence, not proof of no exercise.
The existing manager's use of sharing authorization should not be presented as
proof of read access. Prefer observed-data status and user-actionable guidance.
[Apple HealthKit authorization](https://developer.apple.com/documentation/HealthKit/authorizing-access-to-health-data?changes=_2).[^8]

Apple's iOS 27 overview documents Dynamic Profiles, Evaluations and expanded App
Intents integration. These are opportunities for bounded request interpretation,
grounded explanation tests and actions on the current session. They do not supply
a training-science engine. API adoption still needs installed-SDK compilation and
device testing; cloud-provider support remains out of scope.
[Apple iOS 27 overview](https://developer.apple.com/ios/whats-new/).[^9]

Background task scheduling does not guarantee execution at the requested date.
Consequently, scheduled notifications cannot promise fresh on-device inference
at every chosen time. Prepare a valid session while execution is available; if its
inputs are stale, send a truthful check-in instead of confident obsolete advice.
[Apple background scheduling](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate?changes=_3).[^10]

For presentation, reserve Liquid Glass primarily for navigation and controls, and
keep prescriptions legible in the content layer. Apple explicitly warns against
stacking glass layers. Design for reduced transparency, increased contrast and
reduced motion from the start. [Apple design guidance](https://developer.apple.com/videos/play/wwdc2025/219/).[^11]

The proposed experience should lead with a specific session and goal connection,
not an AI badge. Show two goal progress lanes without pretending their units are
comparable. Preserve the widget's accomplishment emphasis. Reveal data freshness
and an adjustment action near the recommendation, while keeping technical traces
behind a detail disclosure. These are product recommendations, not proven conversion
or adherence improvements; validate them with actual usage.

## Executable checks and scenario evaluation

An isolated Swift harness compiled the actual new model and store with a synthetic
session provider and equipment enum. It used temporary UserDefaults data and no
production account. Eleven of twelve checks passed. This is not a full iOS build,
UI test, clinical evaluation or proof that the proposed engine works.

| Executed check | Result |
|---|---|
| Equal priorities survive validation | Pass |
| Unknown baseline remains absent | Pass |
| Codable round trip | Pass |
| Invalid calendar date rejected | Pass |
| DST-boundary local date accepted unchanged | Pass |
| Nonfinite target rejected | Pass |
| Incompatible strength baseline rejected | Pass |
| Own-account profile loads | Pass |
| In-memory profile clears immediately on account change | Fail |
| Cross-account write rejected | Pass |
| New account does not load old profile | Pass |
| Corrupt bytes are preserved | Pass |

The following are design scenarios, not executed engine tests. They define required
behavior and expose what the current foundation cannot yet evaluate.

| Scenario | Required behavior | Current gap |
|---|---|---|
| Two idle days, saved goals, unknown readiness | Goal-relevant feasible session or specific missing-data explanation | No connected new engine |
| Hard run planned yesterday but not completed | Do not count planned load as actual fatigue | Existing context fallback |
| Long run actually completed; legs sore | Consider different demands, including suitable upper-body work, without automatic heavy lifting | No localized demand model |
| Two primary disciplines exceed available time | Explain conflict; obtain a tradeoff | Legacy priority reduction |
| New lifter has no load history | Specific effort-based calibration, no invented weight | No observation-based prescription policy |
| Same exercise label, different machines | Do not transfer loads automatically | Missing equipment identity |
| Assisted pull-up goal | Distinguish assistance from added load | Initial schema insufficient |
| Session shortened to 25 minutes | Budget warm-up, work and rest; revise remaining week | No whole-session time solver |
| Running goal entered in kilometers | Preserve original unit and local race date | Model support only; routes untested |
| HealthKit yields no samples | Mark data unavailable/unknown, not inactive | Read semantics need integration review |
| Profile changes after notification prepared | Invalidate projection; open latest version with explanation | New decision store absent |
| Workout completed after a reminder | Suppress obsolete later prompts using current evidence | Depends on timely result sync |
| Sign-out during generation | Clear memory and reject stale result | Lifecycle integration absent |
| On-device model unavailable | Valid deterministic prescription and clear explanation | Must be tested end-to-end |
| Injury or symptoms outside supported scope | Avoid unsupported training advice; explain limits | Free-text limitations lack executable policy |

Passing this matrix means correctness against stated requirements, not proven
performance gains. Training quality additionally needs review by qualified running
and strength professionals and longitudinal athlete feedback.

## Revised build order

**First: repair trust boundaries and reshape the data.** Replace sensitive
UserDefaults persistence, wire account invalidation, and introduce typed goal
variants plus observation/result history. Preserve the existing unshipped slice as
migration input only where useful. Do not bolt UI onto it merely to show progress.

**Second: build a narrow executable coaching slice.** Choose a reviewed running
session family and a reviewed strength session family. Connect both to real goals,
available time, equipment and actual results. Test two idle days and the planned-
versus-completed distinction before adding more workout variety.

**Third: validate progression and fairness.** Test repeated weeks, insufficient
availability, partial sessions, equipment changes and explicit adjustments. Audit
whether either discipline is starved, rather than merely checking both labels exist.

**Fourth: unify presentation and explanations.** Use the same decision revision
on Today, Plan, details, widgets and notification projection. Introduce Apple model
explanations only after deterministic outputs are worth explaining.

**Fifth: evaluate real-device and real-athlete behavior.** Verify locked-screen
delivery, stale-data handling and account switching. Gather prescription relevance,
completion, adjustment and outcome feedback. Do not treat APNs acceptance, attractive
screens or passing unit tests as evidence of effective coaching.

Release gates are zero account-isolation failures, no invented measurements,
explicit handling of unknown data, preservation of dates/units/history, feasible
session timing, reproducible decisions and reviewed training policies. Latency,
battery use and explanation quality need device measurements before numerical
service targets are advertised.

## Evidence limits and unresolved decisions

No researched source establishes that this architecture is the absolute strongest
possible foundation. The recommendation is a defensible engineering direction,
not a scientifically proven product superiority claim. Training populations,
protocols and outcomes differ, and literature findings cannot be applied as universal
per-person rules.

The original Walking event still lacks a captured full input trace. A suspected
code path is not proof of its historical cause. The current audit did not access
production health records, run a full application build or modify app source.

Before implementation, settle the supported athlete population, the protection
policy for background-accessible data, and whether optional cloud profile sync is
part of the first release. Exact progression coefficients and any race forecasting
model require a focused evidence and validation pass rather than guessing.

## Sources

[^1]: Apple. [UserDefaults](https://developer.apple.com/documentation/Foundation/UserDefaults?changes=_3&language=objc) and [Protecting the User's Privacy](https://developer.apple.com/documentation/uikit/protecting-the-user-s-privacy). Living platform documentation, consulted September 2026. Storage and privacy recommendations.
[^2]: Schumann M, et al. [Compatibility of Concurrent Aerobic and Strength Training for Skeletal Muscle Size and Function](https://pubmed.ncbi.nlm.nih.gov/34757594/). Sports Medicine, 2022;52:601-612. DOI 10.1007/s40279-021-01587-7. Abstract accessed; 43-study meta-analysis.
[^3]: Currier BS, et al. [ACSM Position Stand: Resistance Training Prescription for Muscle Function, Hypertrophy, and Physical Performance in Healthy Adults](https://pubmed.ncbi.nlm.nih.gov/41843416/). Medicine & Science in Sports & Exercise, 2026;58:851-872. DOI 10.1249/MSS.0000000000003897. Abstract accessed; evidence search through October 2024.
[^4]: Graham T, Cleather DJ. [Autoregulation by repetitions in reserve leads to greater improvements in strength over a 12-week training program than fixed loading](https://research.stmarys.ac.uk/3067/3/Graham-Cleather-Autoregulation-Repetitions-in-Reserve.pdf). Journal of Strength and Conditioning Research; author manuscript, DOI 10.1519/JSC.0000000000003164. Original randomized study, full manuscript accessed.
[^5]: Vesterinen V, et al. [Individual Endurance Training Prescription with Heart Rate Variability](https://pubmed.ncbi.nlm.nih.gov/26909534/). Medicine & Science in Sports & Exercise, 2016;48:1347-1354. DOI 10.1249/MSS.0000000000000910. Original trial abstract accessed.
[^6]: Buist I, et al. [No effect of a graded training program on the number of running-related injuries in novice runners](https://pubmed.ncbi.nlm.nih.gov/17940147/). American Journal of Sports Medicine, 2008;36:33-39. DOI 10.1177/0363546507307505. Original randomized trial abstract accessed.
[^7]: [How much running is too much? Identifying high-risk running sessions in a 5200-person cohort study](https://pubmed.ncbi.nlm.nih.gov/40623829/). British Journal of Sports Medicine, 2025. DOI 10.1136/bjsports-2024-109380. Original cohort; indexed abstract information accessed, full PDF unavailable during this review.
[^8]: Apple. [Authorizing access to health data](https://developer.apple.com/documentation/HealthKit/authorizing-access-to-health-data?changes=_2). Living documentation, consulted September 2026. Read-access privacy semantics.
[^9]: Apple. [What's new in iOS 27](https://developer.apple.com/ios/whats-new/). Platform overview, consulted September 2026. Capability claims, not app-level implementation verification.
[^10]: Apple. [BGTaskRequest.earliestBeginDate](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate?changes=_3). Background task timing contract.
[^11]: Apple. [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/). WWDC25, 2025. Official design guidance; these principles predate iOS 27.

## Local evidence map

- `Runaway iOS/Models/AthleteTrainingProfile.swift`: new goals, measurements, validation and snapshot aggregate.
- `Runaway iOS/Services/AthleteTrainingProfileStore.swift`: ownership guard, local storage and explicit-only invalidation.
- `Runaway iOS/Models/TrainingProfile.swift`: single-primary validation and capacity reduction.
- `Runaway iOS/Models/TodayRecommendationPolicy.swift`: readiness thresholds, planned/completed context and candidate selection.
- `Runaway iOS/Models/WeeklyTrainingPlan.swift`: string-based exercise prescription and completion representation.
- `Runaway iOS/Services/TrainingPlanService.swift`: fixed-plan note generation.
- `Runaway iOS/Services/HealthKit/HealthKitDataReader.swift`: SDNN request.
- `Runaway iOS/Services/HealthKit/HealthKitManager.swift`: sharing-authorization status.
- `/tmp/runaway-foundation-audit/Probe.swift`: synthetic executable assertions; temporary supporting artifact, not checked-in test coverage.
