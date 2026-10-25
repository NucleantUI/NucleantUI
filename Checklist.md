# Progress of Api compared to research/SwiftUI-api

Checked against `Sources/NucleantUI` on 2026-10-25. Tick a box in the same
change that adds the API.

## App & Scenes
- [x] App
- [x] Scene / SceneBuilder
- [x] WindowGroup
- [x] .defaultSize / .windowResizability / .windowIdealSize
- [ ] Window
- [ ] Settings
- [ ] MenuBarExtra
- [ ] DocumentGroup
- [x] Commands / CommandsBuilder
- [x] CommandMenu
- [x] CommandGroup
- [x] .commands
- [x] .keyboardShortcut
- [ ] openWindow / dismissWindow
- [ ] ScenePhase
- [x] #Preview

## View core
- [x] View
- [x] ViewBuilder
- [x] ViewModifier / ModifiedContent / .modifier
- [x] TupleView
- [x] EmptyView
- [x] AnyView
- [x] Group
- [x] ForEach
- [x] PreferenceKey / .preference / .transformPreference / .onPreferenceChange
- [ ] .overlayPreferenceValue / .backgroundPreferenceValue
- [ ] EquatableView / .equatable
- [ ] .id

## State & data flow
- [x] @State
- [x] @Binding / Binding.constant
- [x] @Environment / EnvironmentKey / EnvironmentValues
- [x] .environment(\.key, value)
- [x] EnvironmentValues: colorScheme, isEnabled, font, foregroundColor, tint,
      displayScale, lineLimit, multilineTextAlignment
- [ ] EnvironmentValues: dismiss, openURL, locale, layoutDirection,
      horizontalSizeClass
- [ ] @Environment(Model.self) / .environment(model)
- [x] @Observable models
- [x] @Bindable
- [x] DynamicProperty
- [x] @FocusState
- [ ] @GestureState
- [ ] @AppStorage / @SceneStorage
- [x] .onChange
- [x] .task / .task(id:)

## Layout containers
- [x] HStack
- [x] VStack
- [x] ZStack
- [x] Spacer
- [x] Divider
- [x] ScrollView
- [ ] ScrollViewReader / .scrollPosition
- [ ] .scrollIndicators / .scrollDisabled / .scrollTargetBehavior
- [x] LazyVStack / LazyHStack / pinnedViews
- [x] LazyVGrid / LazyHGrid / GridItem
- [x] Grid / GridRow
- [x] .gridCellColumns / .gridCellAnchor / .gridCellUnsizedAxes / .gridColumnAlignment
- [x] Layout protocol / LayoutValueKey / .layoutValue / ViewSpacing
- [x] AnyLayout / HStackLayout / VStackLayout / ZStackLayout
- [ ] GridLayout
- [ ] GeometryReader
- [ ] ViewThatFits
- [ ] .onGeometryChange

## Text & fonts
- [x] Text
- [x] Text .font / .fontWeight / .bold / .italic
- [x] Text .lineLimit (incl. ranges and `reservesSpace:`) / .multilineTextAlignment
- [ ] AttributedString / Text concatenation / Markdown
- [ ] .underline / .strikethrough / .monospaced / .kerning / .tracking
- [ ] .lineSpacing / .truncationMode / .minimumScaleFactor / .textCase
- [ ] .textSelection
- [x] Font — system, custom, text styles, weight, design

## Images
- [x] Image — from a `RasterImage`
- [x] .resizable / .aspectRatio / .scaledToFit / .scaledToFill
- [ ] Image("name") / Image(systemName:)
- [ ] .renderingMode / .interpolation
- [ ] AsyncImage

## Controls
- [x] Button
- [ ] .buttonStyle / ButtonStyle
- [ ] Label / .labelStyle
- [x] LabeledContent
- [x] .labelsHidden
- [x] Menu
- [x] DisclosureGroup / DisclosureGroupStyle
- [x] Toggle / .toggleStyle (switch, checkbox, button)
- [x] Slider
- [x] Stepper
- [x] Picker / .pickerStyle (menu, segmented, inline, radioGroup) / .tag
- [x] TextField / SecureField / TextEditor — incl. `prompt:`, `axis:`, `value:format:`
- [x] .textFieldStyle (plain, roundedBorder, squareBorder) / .textEditorStyle
- [ ] DatePicker / ColorPicker
- [ ] ProgressView / Gauge
- [ ] Link / ShareLink
- [ ] GroupBox / ControlGroup
- [ ] ContentUnavailableView
- [ ] .controlSize

## Collections
- [x] List — incl. selection
- [x] Section
- [x] Form / .formStyle (grouped, columns)
- [x] OutlineGroup
- [x] Table / TableColumn sorting / .tableStyle / .tableColumnHeaders
- [x] .listStyle (plain, inset, insetGrouped, grouped, sidebar, bordered)
- [x] .listRowBackground / .listRowInsets / .listRowSeparator / .listRowSeparatorTint
- [x] .badge
- [x] .selectionDisabled / .onDeleteCommand / .alternatingRowBackgrounds
- [x] .contextMenu(forSelectionType:)
- [ ] .onDelete / .onMove / EditButton
- [ ] .swipeActions
- [ ] .refreshable
- [ ] .searchable
- [ ] .listSectionSeparator / .headerProminence

## Navigation & presentation
- [x] NavigationStack
- [x] NavigationLink
- [x] .navigationTitle
- [x] .navigationDestination(for:) / NavigationPath / NavigationLink(value:)
- [ ] .navigationDestination(isPresented:) / (item:)
- [ ] NavigationSplitView
- [ ] TabView
- [x] .toolbar(_:for:) / .toolbarVisibility — hiding the bar
- [ ] .toolbar { ToolbarItem } — toolbar content
- [x] .popover
- [x] .contextMenu
- [ ] .sheet / .fullScreenCover
- [ ] .alert / .confirmationDialog
- [ ] .inspector
- [ ] .fileImporter / .fileExporter

## Shapes & drawing
- [x] Shape
- [x] Rectangle / RoundedRectangle / Circle / Ellipse / Capsule
- [ ] UnevenRoundedRectangle
- [x] Path — lines, curves, arcs, rects, ellipses, addPath, applying
- [x] .fill / .stroke / StrokeStyle
- [ ] .trim / .inset / .strokeBorder / shape .rotation / .offset
- [x] Color
- [x] Gradient
- [x] ShapeStyle — a closed enum here: color, linearGradient, radialGradient
- [ ] LinearGradient / RadialGradient as views
- [ ] AngularGradient / EllipticalGradient
- [ ] Material
- [x] Canvas / GraphicsContext — fill, stroke, clip, transforms, drawLayer
- [ ] GraphicsContext draw(Text) / draw(Image) / resolve / filters
- [x] .drawingGroup
- [x] Shader / ShaderLibrary / .shader
- [x] ImageRenderer — as `renderImage(size:scale:)` / `.image(size:scale:)`,
      a `RasterImage` drawn with no window and no GPU
- [ ] .visualEffect

## Layout modifiers
- [x] .frame (fixed and min/ideal/max)
- [x] .padding
- [x] .offset
- [x] .position
- [ ] .fixedSize
- [ ] .layoutPriority
- [ ] .zIndex
- [ ] .alignmentGuide
- [ ] .ignoresSafeArea / .safeAreaInset / .safeAreaPadding
- [ ] .containerRelativeFrame

## Appearance modifiers
- [x] .background
- [x] .overlay
- [x] .border
- [x] .opacity
- [x] .hidden
- [x] .foregroundColor / .foregroundStyle — foregroundStyle takes a `Color`
- [x] .tint
- [x] .colorScheme
- [x] .clipped / .clipShape / .cornerRadius
- [x] .rotationEffect / .scaleEffect
- [ ] .rotation3DEffect
- [ ] .shadow
- [ ] .blur
- [ ] .blendMode / .compositingGroup / .mask
- [ ] .brightness / .contrast / .saturation / .grayscale / .hueRotation
- [ ] .preferredColorScheme

## Interaction
- [x] .onTapGesture
- [x] .onLongPressGesture
- [x] DragGesture / .gesture
- [x] TapGesture / LongPressGesture / MagnifyGesture / RotateGesture
- [ ] SpatialTapGesture
- [ ] Gesture .simultaneously / .sequenced / .exclusively
- [x] .simultaneousGesture / .highPriorityGesture
- [x] .onHover
- [ ] .onContinuousHover / .hoverEffect
- [x] .disabled
- [x] .draggable / .dropDestination / Transferable / UTType
- [x] .allowsHitTesting / .contentShape
- [x] .focused / .focusable / .onSubmit / .submitScope / .onKeyPress
- [x] .onAppear
- [x] .onDisappear
- [ ] .help
- [ ] .sensoryFeedback

## Animation
- [x] withAnimation — incl. completion
- [x] .animation
- [x] Animation curves / spring / smooth / snappy / bouncy / delay / speed / repeat
- [x] CustomAnimation
- [x] Animatable / AnimatablePair / VectorArithmetic
- [x] Transaction / withTransaction / .transaction
- [x] .transition / AnyTransition (opacity, scale, offset, move, slide, push,
      asymmetric, combined)
- [ ] matchedGeometryEffect
- [ ] .phaseAnimator / .keyframeAnimator
- [ ] .contentTransition
- [x] TimelineView (animation, periodic, everyMinute, explicit)

## Accessibility
- [ ] .accessibilityLabel / .accessibilityHint / etc.

## NucleantUI only — no SwiftUI equivalent
- `@View` — goes on every view struct
- `RenderTexture` / `renderTexture` / `.texture` — a view tree rendered into a
  GPU image a model holds, shown with `tex.view()`, shaded with
  `tex.shader(_:)`, and handed to another shader by name (`textures:`)
- `ShaderProtocol` / `ShaderInput` / `ShaderValue` — any SPIR-V module as a
  shader, compiled from PyShader, with an `@Observable` model as its input
- `TextureView` / `TextureSource` — a view whose pixels are written into its
  own GPU texture from outside the view tree, with pointer and key input
  passed to the source
- `.relativeSize(width:height:)` — a fraction of the space the parent offers
- `.framed(_:alignment:)` — `.frame` and `.position` from one `Rect`
- `PathShape` — a shape from a `(Size) -> Path` closure
- `Color.dynamic(light:dark:)`
- `FontRegistry.register(path:as:)` — a font file as a `Font.custom` family
