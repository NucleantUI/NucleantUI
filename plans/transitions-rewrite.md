# TRANSITIONS IS DONE ALL WRONG...

Transition is a freaking protoocol not a fucking enum...

how can claude be sooo stupid to make Transition as Enum


thats not how transitions works and also how on bloody earth would it allow custom transitions...

write Transition properly now as real protoocol and not some made up enum
* https://developer.apple.com/documentation/swiftui/transition

and AnyTransition is a Type Eraser not a placeholder for a fucking enum... 
* https://developer.apple.com/documentation/swiftui/anytransition
* https://developer.apple.com/documentation/swiftui/anytransition/init(_:)



NOW MAKE IT PROPER AND REMEMBER TO READ 
* research/SwiftUI-api/SwiftUI.swift
* research/SwiftUI-api/SwiftUICore.swift


I DIDNT ADD THEM FOR THEM TO BE FUCKING IGNORE AND THEY WHERE FUCKING IGNORED WHEN MAKING TRANSITIONS 100000000% ELSE THIS WOULDNT HAVE HAPPENED...

MAKE NOTES HERE IF NEEDED, ANYTHING THAT ENSURES THIS IS DONE RIGHT NOW... 

I DONT NEED LAZY SOLUTIONS, DONT BOTHER BE LAZY ABOUT I WILL JUST SAY YOU DIDNT DO A GOOD JOB... DONT TRY CUT CORNERS TO THINK YOU SATIFY ME WITH 
DOING SHORTCUTS... 

---

## Notes — how it is done (read before touching transitions)

### The API, from `research/SwiftUI-api/SwiftUICore.swift`

Everything below is in SwiftUICore; SwiftUI.swift only adds
`SymbolEffectTransition` (SF Symbols — nothing to build it on here).

- `protocol Transition` (`@MainActor @preconcurrency`): `associatedtype Body: View`,
  `@ViewBuilder func body(content: Content, phase: TransitionPhase) -> Body`,
  `static var properties: TransitionProperties`, `typealias Content = PlaceholderContentView<Self>`.
  Nothing else on it — no extra requirements (a requirement would be carried by
  every conformer, user ones included).
- `extension Transition`: `properties` default `TransitionProperties()`,
  `apply(content:phase:) -> some View`, `animation(_:) -> some Transition`,
  `combined(with:) -> some Transition`, and the statics
  `.identity .opacity .scale .scale(_:anchor:) .offset(_:) .offset(x:y:) .move(edge:) .slide .push(from:)`.
- Concrete structs: `IdentityTransition`, `OpacityTransition`, `OffsetTransition(offset)`,
  `MoveTransition(edge)`, `ScaleTransition(scale, anchor)`, `SlideTransition`,
  `PushTransition(edge)`, `AsymmetricTransition<Insertion, Removal>(insertion, removal)`.
- `enum TransitionPhase { willAppear, identity, didDisappear }` + `isIdentity`, `value` (-1 / 0 / 1).
- `struct TransitionProperties { init(hasMotion: Bool = true); var hasMotion }`.
- `struct PlaceholderContentView<Value>: View` — the stand-in a transition's body gets for the view.
- `struct AnyTransition` — a TYPE ERASER: `init<T: Transition>(_:)`. Its statics
  (`.identity .opacity .scale .scale(scale:anchor:) .offset .move(edge:) .slide .push(from:)
  .asymmetric(insertion:removal:) .modifier(active:identity:)`) and `.combined(with:)`,
  `.animation(_:)` all produce erased *transitions* — never cases of an enum.
- `View.transition(_ t: AnyTransition)` and `View.transition<T: Transition>(_:)`.

Not provided, and why — say so, never fake them:
- `BlurReplaceTransition` / `.blurReplace`: NucleantUI has no `.blur` yet (Checklist: `[ ] .blur`).
- `SymbolEffectTransition`: no SF Symbols / symbol effects.
- Reduce Motion (`hasMotion` → opacity): no accessibility setting reaches NucleantUI.

### How a transition runs

- A transition's body is REAL VIEWS built around the view: `body(content:phase:)` is
  evaluated and built like any body, so any modifier — `.opacity`, `.scaleEffect`,
  `.rotationEffect`, `.offset`, an `Animatable` `ViewModifier`, an overlay — works in a custom
  transition. The phase is what changes; the modifiers animate their own values.
- Insertion (into an `if`, `switch`, `ForEach` or `for`, in a container that stood before):
  body built at `.willAppear` without animation, then at `.identity` under the change's
  animation, in the same pass — every value starts at `willAppear` and animates to `identity`.
- Removal: body (re)built at `.didDisappear` under the animation; the view stays drawn where it
  was, out of layout and hit testing, until every animation that phase change started is over.
- Removed while arriving → `didDisappear` from wherever it is. Back while leaving → `identity`
  from wherever it is (no `willAppear`).
- `animation(_:)` on a transition: its animation drives the phase change, and the transition
  runs even when the change itself was not animated (`.transition(.opacity.animation(.slow))`
  with no `withAnimation`).
- Identity phase: "applied as long as the view is visible" — a user transition's body stays on
  the view at `.identity`. The framework's own transitions are no-ops at identity, so their body
  is only on the view while it arrives or leaves (nothing extra in every row of every list).
- `PlaceholderContentView` builds the content it stands for: the child of the container (already
  built at its own path — state never moves because of a transition) or the view handed to
  `apply(content:phase:)`.
- Paths: the child keeps its path `C+[i]`; its transition body is built at `C+[S, i]` (S is a
  reserved slot no container produces; `ForEach` steps around it).
- `.offset` animates its own value as a render transform (SwiftUI's offset is an animatable
  geometry effect): a transition built from `.offset` has nothing placed yet to animate from.
  `.move/.slide/.push` are offsets of the view's own size, also render transforms.
- What the containers need to know without building a body — "is identity a no-op", "does
  it bring its own animation" — is known only for the framework's own transitions, through
  an INTERNAL protocol (`BuiltinTransition`, Transition.swift) asked of the type. Nothing is
  added to `Transition`; a user's transition is taken at its word (body stays on, runs only
  under an animated change unless wrapped by `.animation(_:)`).
- A leaving view keeps its place in the drawing order: drawn just before the sibling that
  followed it, so a card leaving from under another stays under it.
- `Grid` rows and custom `Layout` spacing look through a slot to the child
  (`ViewNode.underTransition`), so a row arriving keeps its columns.

### Done right means

- tests in `Tests/NucleantUITests/TransitionTests.swift`: phases asked in order, custom
  transitions (incl. an `Animatable` modifier and the docs' `RotatingFadeTransition`), erasure,
  combined / asymmetric / attached animation, exits lasting exactly their animation, revival,
  identity removing at once, offset/move as transforms (hits, geometry), Grid rows in a ForEach.
- every existing test still green; examples still build (`.offset` changed under them).
- a real example app: `Examples/Slides` — a presentation app whose slides come in and go out
  with built-in and custom transitions (stored as `AnyTransition`), bullet builds, presenter mode.
