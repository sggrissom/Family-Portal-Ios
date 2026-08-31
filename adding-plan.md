# Family Portal iOS — Making Adding Easy

The app reads well and writes badly. Everything it shows is one or two taps
away; half of what it stores is four taps and a scroll away, behind a screen
whose job is to *show* that kind of record rather than to take a new one.

This plan is about the write path only. It adds no new record types, no new
procs, and nothing to the backend — every screen it touches already exists.

---

## 1. What adding costs today

| What | Path | Taps to a form |
| --- | --- | --- |
| Photo | Photos tab → `+` | 2 |
| Activity | Activities tab → `+` | 2 |
| Season | Activities tab → *Add Season* | 2 |
| Person | Settings → Family Management → `+` | 3 |
| **Measurement** | Family → person → scroll → *See All Measurements* → `+` | 4 + a scroll |
| **Milestone** | Family → person → scroll → *See All Milestones* → `+` | 4 + a scroll |

The two rows in bold are the ones a family enters week after week, and they are
the two buried deepest. Both sit behind a list screen — `MeasurementListView`,
`MilestoneListView` — that exists to *review* a person's history, complete with
a type picker, a chart, category chips and a search field. Reaching a new entry
means loading all of that first.

The depth is not an oversight in the navigation; it is structural. Both add
sheets take the person in `init` and bake them into a `@Query` predicate:

```swift
// Views/Milestones/AddMilestoneView.swift
init(personId: UUID) {
    _people = Query(filter: #Predicate<Person> { $0.id == personId })
}
```

A `@Query` predicate is fixed at init and cannot depend on `@State`, so the
sheet has no way to ask *who* — the caller must already know. That is why every
route to it runs through a person's own screens, and why there is no `+` on the
Family or Timeline tab: there would be nothing to open.

So the sheets have to become person-optional before any shortcut to them can
exist. That is phase 1, and the rest of the plan stacks on it.

---

## 2. Phase 1 — person-optional add sheets

`AddMilestoneView` and `AddMeasurementView` take `personId: UUID?`. Nil means
the sheet asks.

- The narrow `@Query` is replaced by `@Query(sort: \Person.name)` over the whole
  roster plus `@State selectedPersonId`, with `person` a computed lookup. The
  roster is a household — `TimelineView` and `AddPersonView` already query all
  of it — so nothing is paid for the breadth.
- Both forms gain a **For** picker as their first row, shown whether or not the
  caller named someone. A caller that named the wrong person is then fixable in
  place rather than by backing out to a different screen.
- `isValid` gains `person != nil`, so Save stays disabled until somebody is
  chosen.

Two things have to follow the person rather than outlive them:

- **`DateEntryPicker`** holds its own mode and age steppers, and `.age` resolves
  against the birthday it was handed. Changing the person mid-form leaves an age
  resolved against the previous person's birthday until the stepper is touched
  again. The picker is given `.id(person?.id)` at the call site, so a new person
  gets a fresh picker back on `.today` — a correct default, not just a safe one.
- **The milestone's photo selection.** `milestonePhotoChoices` is drawn from
  `person.photos`, so switching person changes the eligible set underneath a
  selection already made. `save()` already filters the selection through
  `photoChoices` and so cannot *send* a stale id, but the count beside *Attach
  Photos* would lie. The selection is cleared when the person changes.

Nothing about the save path changes: `syncService.addMilestone(_:for:photos:)`
and `addGrowthData(_:for:)` still take the person the form resolved.

---

## 3. Phase 2 — the photo importer comes out of the gallery

Adding a photo from anywhere but the Photos tab means running the import from
somewhere but `PhotoGalleryView`, and today the whole of it lives there as
private members: `importPicked`, `importOne`, `finishImport`, the `ImportProgress`
struct, the EXIF `captureDate` reader and its formatter.

It moves to a `@Observable PhotoImporter` that owns the progress and the loop and
takes a `ModelContext` and a `SyncService`. `PhotoGalleryView` keeps its
`safeAreaInset` progress bar and loses the mechanics. Three properties of the
import are worth keeping honest, and become the tests this phase brings:

- items are read **sequentially**, because twenty full-resolution decodes at once
  is the memory spike that gets an app killed mid-import;
- `settled = completed + failed`, so a partly-failed batch still finishes and
  still reports;
- the capture date is read from the picked image's own EXIF rather than from
  `PHAsset`, which would need library authorization the picker does not.

This phase is a refactor and changes no behaviour. It exists so phase 3 has
something to call.

---

## 4. Phase 3 — the quick-add menu

A `+` in the navigation bar of **Family** and **Timeline**, opening a menu:

```
┌─────────────────────────┐
│ Family              [+] │
│                    ┌──────────────┐
│  Children          │ ⭐︎ Milestone  │
│  ● Ada             │ ￨ Measurement│
│  ● Iris            │ ⃞  Photos     │
│                    │ ⚇ Person     │
│  Parents           └──────────────┘
│  ● Steven               │
└─────────────────────────┘
```

A toolbar button rather than a centre tab or a floating button: it is what the
Photos and Activities tabs already put in that corner, it needs no interception
of a `TabView` selection to fire an action from a slot that is meant to be a
screen, and it covers nothing.

`QuickAddKind` (`milestone`, `measurement`, `photos`, `person`) and a
`QuickAddMenu` view live in `Views/Components/`, so the two hosts cannot drift
apart. Each host holds `@State var quickAdd: QuickAddKind?` and a
`.sheet(item:)` over it; **Photos** is not a sheet but
`.photosPicker(isPresented:selection:)` driven from the same state, handing what
comes back to the phase 2 importer.

Milestone and measurement open with no person, which is what phase 1 made
possible and what phase 4 makes quick.

**The Photos and Activities tabs keep the `+` they have.** Both already open the
one thing that tab adds, and replacing that with a menu would spend a tap on the
most common action to reach three that have a home elsewhere.

---

## 5. Phase 4 — remembering, and adding another

A quick-add that opens on "choose a person" has moved the taps rather than
removed them. Two defaults close that:

- **The last person written for**, in `UserDefaults` behind a small
  `QuickAddDefaults`. On open: the remembered person if the roster still holds
  them, else the only person if there is one, else the youngest generation's
  first member — `FamilyGroups` already bands the roster and its youngest band is
  always "Children", which is who a family logs. A remembered id that survives an
  account erase resolves to nobody and falls through to the same fallback, so
  `LocalDataReset` needs no new sweep.
- **The last measurement type and unit**, so a household that works in pounds is
  not handed kilograms every time. `AddMeasurementView` already defaults its unit
  from the type; the remembered unit wins when it is valid for the type.

And a **Save and add another** button beside Save on the measurement sheet:
height and weight are taken in the same minute for the same person, and today
that is two full trips through the sheet. It saves, keeps the person and the
date, clears the value, and leaves the keyboard up.

---

## 6. Phase 5 — adding where you already are

Standing on a person is the other half of the problem: the roster knows who, and
still sends you through two more screens to say anything about them.

- **`PersonDetailView`** gains a `+` menu beside its edit pencil — *Add
  Measurement*, *Add Milestone*, *Add Photos* — each opening the sheet with the
  person filled in. Two taps from the roster to a form.
- **The roster rows** in `FamilyRosterSections` gain a `.contextMenu` with the
  same three. A long press on Ada from the Family tab is two taps to a milestone
  for Ada, without opening her at all.

`FamilyRosterSections` is shared by `FamilyMembersView` and
`FamilyManagementView`, so the actions have to be given to it rather than built
into either, and the sheet has to be presented by the host that owns the
navigation stack.

This phase is independent of phase 4 — it always names a person, so it never
consults a default — and either can land first.

---

## 7. What this does not do

- **No new record types, procs or DTOs.** Every sheet this plan opens is one the
  app already ships.
- **The activities write path is left alone.** Scoring is deep — activity,
  season, competition, routine, result — but it is deep because the data is a
  tree, and each level is a thing you set up once and score against many times.
  A quick-add for a placement would have to name four parents before it named a
  rank. If a season proves to be logged as often as a measurement, that is its
  own plan.
- **No delete affordance is added anywhere.** The backend still has no
  `DeletePerson`, and a local delete is undone by the next pull.

---

## 8. Order

Phases 1 → 2 → 3 are a chain: the sheets have to ask who before a menu can open
them without knowing, and the importer has to be callable before the menu can
offer photos. Phases 4 and 5 both stack on 3 and are independent of each other.

One PR per phase, each based on the last.
