//
//  PlacementCache.swift
//  NucleantUI
//
//  Placing only what changed. Every pass places the tree from the root, but
//  most of a window draws the same commands it drew the pass before: one
//  knob turning, and every label and card around it placed again to append
//  what it appended last time.
//
//  A subtree made only of nodes that place purely (`NodeContent.placesPurely`
//  — stacks, padding, frames, decorations, opacity and transforms, text,
//  shapes, images) draws from its rect, its proposal, its context and its own
//  nodes alone. Placed again under the same three, with nothing in it
//  rebuilt since and nothing in it moving, it draws what it drew: the
//  commands it appended are kept on its node, and the next pass appends them
//  in one go instead of placing it.
//
//  What a pass places fresh tells, for each pure node:
//  - whether it is *clean*: nothing below it asked for another frame (an
//    animated value, a node's motion, a shape's data on its way) and nothing
//    read state while it was placed — counted as it is placed;
//  - whether it is *stable*: placed as it was the pass before.
//  A clean, stable node is kept by the highest such node above it — each
//  command copied once at most: the node itself, when nothing above it is
//  pure, or else the first node above it that is not clean or not stable,
//  which keeps each of its clean, stable children. A knob turning is then
//  placed with its ancestors, and everything beside them is appended.
//
//  What is kept goes when anything in the subtree changes: a graft, a child
//  replaced or leaving drops it from there up to the root (`ViewNode`). A
//  view leaving anywhere turns keeping off for the pass, and a forced
//  rebuild drops everything kept.
//
//  A kept subtree placed again at another origin — scrolled, or moved by a
//  stack around it — the same size, under the same proposal and context,
//  draws what it drew moved by as much: its commands are moved rather than
//  drawn again, and what placing left on its nodes (their frames, for hit
//  testing) is moved with them. Only while every clip it is drawn under is
//  the context's — one from outside, which stays where it is — and the
//  context's transform only moves: a clip of its own would move with it,
//  and a turned or scaled space would not move it as it moves its rect.
//
//  Each kept list has a number of its own (`DisplayList.version`). A render
//  boundary whose content is one kept subtree holds that list itself, in its
//  image's space, so the painter tells the image unchanged by the number,
//  not by comparing its commands.
//

/// What a pure node was last placed with, and what it drew then when it
/// may be drawn again.
struct PlacementRecord {
    let rect: Rect
    let proposal: ProposedSize
    let context: DrawContext
    let epoch: Int
    /// The commands it appended, in the list it appended them to; `nil`
    /// until it is known to be worth keeping.
    var list: DisplayList?
    /// Whether `list` may be drawn at another origin, moved: every clip in
    /// it is the context's, and the context's transform only moves.
    var isMovable = false

    /// How a placement under these compares with this one, the context
    /// compared once.
    enum Likeness {
        /// It draws what this one drew.
        case same
        /// It draws what this one drew, moved this far — and nothing placed
        /// somewhere new would start moving there, as under an animation.
        case moved(dx: Double, dy: Double)
        case different
    }

    func likeness(_ rect: Rect, _ proposal: ProposedSize, _ context: DrawContext, epoch: Int) -> Likeness {
        guard self.epoch == epoch, self.rect.size == rect.size, self.proposal == proposal else { return .different }
        let moved = self.rect.origin != rect.origin
        if moved, context.animation != nil { return .different }
        guard self.context.placesLike(context) else { return .different }
        return moved ? .moved(dx: rect.minX - self.rect.minX, dy: rect.minY - self.rect.minY) : .same
    }

    /// Whether a placement under these draws what this one drew.
    func matches(_ rect: Rect, _ proposal: ProposedSize, _ context: DrawContext, epoch: Int) -> Bool {
        if case .same = likeness(rect, proposal, context, epoch: epoch) { return true }
        return false
    }

    /// This record keeping `list`.
    func keeping(_ list: DisplayList) -> PlacementRecord {
        var kept = self
        kept.list = list
        kept.isMovable = context.transform.onlyMoves && list.states.allSatisfy { state in
            state.clip == context.clip
                && state.clipCornerRadius == context.clipCornerRadius
                && state.transformedClips == context.transformedClips
        }
        return kept
    }
}

extension Transform {
    /// Whether it moves and does nothing else: no scale, no turn.
    var onlyMoves: Bool { e11 == 1 && e12 == 0 && e21 == 0 && e22 == 1 }
}

/// The fresh placements of pure nodes under way, innermost last, and what
/// tells whether one was clean.
@MainActor
final class PlacementRecorder {
    static let shared = PlacementRecorder()

    /// Bumped to drop everything kept, wherever it is: a kept list is only
    /// replayed under the epoch it was made in.
    private(set) var epoch = 0

    /// How many things have asked for another frame or read state while
    /// being placed, ever. A placement that leaves it as it found it was
    /// clean.
    private(set) var disturbances = 0

    private struct Frame {
        /// Clean, stable children placed fresh, not kept yet: kept by this
        /// node if it is not kept itself.
        var pending: [(node: ViewNode, record: PlacementRecord, range: Range<Int>)] = []
    }

    private var frames: [Frame] = []

    /// The number the next kept list gets (`DisplayList.version`).
    private var nextKept = 0

    private init() {}

    /// Something animated asked for another frame, or state was read while
    /// the tree was placed.
    func noteDisturbance() {
        disturbances += 1
    }

    /// Drop everything kept.
    func invalidateAll() {
        epoch += 1
    }

    /// Place `node` — a node whose subtree places purely — keeping what it
    /// draws, or appending what it kept.
    func place(
        _ node: ViewNode,
        in rect: Rect,
        proposal: ProposedSize,
        context: DrawContext,
        into list: inout DisplayList,
        fresh: (inout DisplayList) -> Void
    ) {
        let likeness = node.placed?.likeness(rect, proposal, context, epoch: epoch) ?? .different
        if let record = node.placed, let kept = record.list {
            switch likeness {
            case .same:
                list.append(contentsOf: kept)
                if PerfTrace.isEnabled { PerfTrace.placementsKept += 1 }
                return
            case .moved(let dx, let dy) where record.isMovable:
                // Placed at another origin: what it drew, moved there.
                var moved = kept.moving(dx: dx, dy: dy)
                nextKept += 1
                moved.markKept(nextKept)
                list.append(contentsOf: moved)
                node.movePlacement(dx: dx, dy: dy)
                node.placed = PlacementRecord(rect: rect, proposal: proposal, context: context, epoch: epoch).keeping(moved)
                if PerfTrace.isEnabled { PerfTrace.placementsMoved += 1 }
                return
            default:
                break
            }
        }
        let start = list.commands.count
        let mark = disturbances
        frames.append(Frame())
        fresh(&list)
        let frame = frames.removeLast()
        let record = PlacementRecord(rect: rect, proposal: proposal, context: context, epoch: epoch)
        node.placed = record
        let range = start..<list.commands.count
        // Placed as it was, or only moved: worth keeping either way — a
        // moved one is drawn moved the next time it moves.
        let stable: Bool
        switch likeness {
        case .same, .moved: stable = true
        case .different: stable = false
        }

        if disturbances == mark && stable {
            if frames.isEmpty {
                // Nothing above it places purely: it keeps itself.
                node.placed = record.keeping(keep(range, of: list))
            } else {
                // The node above decides: it keeps itself, this with it, or
                // this alone.
                frames[frames.count - 1].pending.append((node, record, range))
            }
            return
        }
        // Something below it moves, or it was placed somewhere new: what
        // below it stood still where it stood is kept on its own.
        for child in frame.pending {
            child.node.placed = child.record.keeping(keep(child.range, of: list))
        }
    }

    /// The commands in `range` of `list`, kept: a list of their own, with a
    /// number no other kept list has.
    private func keep(_ range: Range<Int>, of list: DisplayList) -> DisplayList {
        var kept = list.slice(range)
        nextKept += 1
        kept.markKept(nextKept)
        return kept
    }
}

extension DrawContext {
    /// Whether a pure subtree placed under `other` draws what it drew under
    /// this context. Every field but the animation: that only says how a
    /// node placed somewhere new starts to move, and a subtree whose rects
    /// are the ones it had moves nowhere.
    func placesLike(_ other: DrawContext) -> Bool {
        opacity == other.opacity
            && transform == other.transform
            && clip == other.clip
            && clipCornerRadius == other.clipCornerRadius
            && flattensRenderNodes == other.flattensRenderNodes
            && nodeClip == other.nodeClip
            && freezesMotion == other.freezesMotion
            && frozenTransitionContent == other.frozenTransitionContent
            && (shared === other.shared || (
                transformedClips == other.transformedClips
                    && shaderCanvasInput === other.shaderCanvasInput
                    && coordinateSpaces == other.coordinateSpaces
            ))
    }
}

// MARK: - The kinds that place purely

// Each of these draws from the rect, proposal and context it is placed with
// and its own values alone, and places its children into the list it was
// given. Animated values they read ask for a frame while they move, which
// keeps them from being kept meanwhile.

extension StackContent { static var placesPurely: Bool { true } }
extension ZStackContent { static var placesPurely: Bool { true } }
extension GroupContent { static var placesPurely: Bool { true } }
extension PaddingContent { static var placesPurely: Bool { true } }
extension FrameContent { static var placesPurely: Bool { true } }
extension FramedContent { static var placesPurely: Bool { true } }
extension RelativeSizeContent { static var placesPurely: Bool { true } }
extension PositionContent { static var placesPurely: Bool { true } }
extension AspectRatioContent { static var placesPurely: Bool { true } }
extension BackgroundContent { static var placesPurely: Bool { true } }
extension OverlayContent { static var placesPurely: Bool { true } }
extension OpacityContent { static var placesPurely: Bool { true } }
extension OffsetContent { static var placesPurely: Bool { true } }
extension RotationContent { static var placesPurely: Bool { true } }
extension ScaleContent { static var placesPurely: Bool { true } }
extension ClipContent { static var placesPurely: Bool { true } }
extension EnvironmentContent { static var placesPurely: Bool { true } }
extension TextContent { static var placesPurely: Bool { true } }
extension ShapeContent { static var placesPurely: Bool { true } }
extension ImageContent { static var placesPurely: Bool { true } }
extension SvgContent { static var placesPurely: Bool { true } }
extension SpacerContent { static var placesPurely: Bool { true } }
extension DividerContent { static var placesPurely: Bool { true } }

// These place their child as it is (`NodeContent`'s own `place`); what they
// add is for input, which reads the frames placing left on the nodes.
extension HitTestingContent { static var placesPurely: Bool { true } }
extension InteractionContent { static var placesPurely: Bool { true } }
extension HoverContent { static var placesPurely: Bool { true } }
extension GestureContent { static var placesPurely: Bool { true } }
extension CountedTapContent { static var placesPurely: Bool { true } }
extension FocusableContent { static var placesPurely: Bool { true } }
extension FocusBindingContent { static var placesPurely: Bool { true } }
extension KeyPressContent { static var placesPurely: Bool { true } }
extension DropTargetContent { static var placesPurely: Bool { true } }
extension ContextMenuContent { static var placesPurely: Bool { true } }
extension TransitionTraitContent { static var placesPurely: Bool { true } }
