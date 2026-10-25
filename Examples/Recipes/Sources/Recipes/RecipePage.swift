//
//  RecipePage.swift
//  Recipes
//
//  One recipe, scrolled through while cooking: the header, what to gather,
//  and the method — with a bar over the top once the header has gone, that
//  says which step is being read and how far through the method that is.
//

import NucleantUI

/// The page. What it measures of its own layout — whether the header's
/// title has gone under the bar, how wide the column is, how tall the
/// visible part is, which steps have passed the reading line and where each
/// step's dot is — is its own transient state; what is gathered, done and
/// how many it serves is the cookbook's.
@View
struct RecipePage {
    let cookbook: Cookbook
    let recipe: Recipe

    @State private var showsBar = false
    @State private var columnWidth = 0.0
    @State private var viewportHeight = 0.0
    @State private var passed: Set<Int> = []
    @State private var dotCenters: [Int: Double] = [:]

    /// How high the bar is, and so how far up the header's title goes
    /// before it is under it.
    static let barHeight = 53.0

    /// The step being read: the last whose top has passed the reading line,
    /// or the first while none has.
    private var current: Int {
        passed.max() ?? 0
    }

    /// As many columns of ingredients as the column is wide enough for.
    private var columns: Int {
        columnWidth >= 640 ? 3 : columnWidth >= 380 ? 2 : 1
    }

    var body: some View {
        let titleLine = Self.barHeight + 36
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Hero(recipe: recipe)
                        .frame(height: 300)
                        .onGeometryChange(for: Bool.self) { proxy in
                            proxy.frame(in: .scrollView).maxY < titleLine
                        } action: { wasHidden, isHidden in
                            // Placed for the first time: nothing to animate.
                            guard wasHidden != isHidden else {
                                showsBar = isHidden
                                return
                            }
                            withAnimation(.easeOut(duration: 0.2)) { showsBar = isHidden }
                        }
                    VStack(alignment: .leading, spacing: 36) {
                        Summary(cookbook: cookbook, recipe: recipe)
                        IngredientList(cookbook: cookbook, recipe: recipe, columns: columns)
                        Method(
                            cookbook: cookbook,
                            recipe: recipe,
                            current: current,
                            passed: $passed,
                            dotCenters: $dotCenters
                        )
                    }
                    .padding(28)
                    .onGeometryChange(for: Double.self) { proxy in
                        proxy.size.width
                    } action: { width in
                        columnWidth = width
                    }
                    // Room after the method, so its last step can reach
                    // the reading line too.
                    Color.clear.frame(height: viewportHeight * 0.45)
                }
            }
            .onGeometryChange(for: Double.self) { proxy in
                proxy.size.height
            } action: { height in
                viewportHeight = height
            }
            CompactBar(recipe: recipe, current: current)
                .opacity(showsBar ? 1 : 0)
                .allowsHitTesting(showsBar)
        }
    }
}

/// The header: the recipe's colors, a plate, and its name. It reads where
/// it is in the scroll view, and as the page goes up, the plate and the
/// name go up slower — sliding down within the header, which clips them —
/// and fade.
@View
struct Hero {
    let recipe: Recipe

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let scrolled = max(0, -proxy.frame(in: .scrollView).minY)
            let fade = height > 0 ? max(0, 1 - scrolled / (height * 0.75)) : 1
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(.linearGradient(colors: [recipe.tint, recipe.shade], startPoint: .topLeading, endPoint: .bottomTrailing))
                Plate()
                    .frame(width: height * 0.95, height: height * 0.95)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .offset(x: height * 0.22, y: scrolled * 0.5)
                    .opacity(fade)
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.cuisine.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.75))
                    Text(recipe.title)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(Color.white)
                    Text(recipe.subtitle)
                        .font(.system(size: 15))
                        .foregroundColor(Color.white.opacity(0.85))
                }
                .padding(28)
                .offset(y: scrolled * 0.35)
                .opacity(fade)
            }
            .clipped()
        }
    }
}

/// A plate from above, in white over the header's colors.
@View
struct Plate {
    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.13))
            Circle().fill(Color.white.opacity(0.1)).padding(28)
            Circle().stroke(Color.white.opacity(0.28), lineWidth: 2).padding(48)
            Circle().fill(Color.white.opacity(0.16)).padding(110)
        }
    }
}

/// Time, steps, and the servings the amounts are scaled to.
@View
struct Summary {
    let cookbook: Cookbook
    let recipe: Recipe

    var body: some View {
        let servings = cookbook.servings(of: recipe)
        HStack(alignment: .bottom, spacing: 28) {
            Fact(label: "TIME", value: "\(recipe.minutes) min")
            Fact(label: "STEPS", value: "\(recipe.steps.count)")
            VStack(alignment: .leading, spacing: 4) {
                Text("SERVES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.faint)
                Stepper(
                    value: Binding(get: { servings }, set: { cookbook.setServings($0, for: recipe) }),
                    in: Cookbook.servingRange
                ) {
                    Text("\(servings)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
            Spacer()
            Button("Start Over") { cookbook.startOver(recipe) }
                .disabled(cookbook.doneCount(of: recipe) + cookbook.gatheredCount(of: recipe) == 0)
        }
    }
}

@View
struct Fact {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
    }
}

@View
struct SectionHeader {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .bottom) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Theme.faint)
        }
    }
}

/// What to gather, in `columns` columns, ticked off with a click.
@View
struct IngredientList {
    let cookbook: Cookbook
    let recipe: Recipe
    let columns: Int

    var body: some View {
        let count = recipe.ingredients.count
        let perColumn = (count + columns - 1) / columns
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Ingredients", detail: "\(cookbook.gatheredCount(of: recipe)) of \(count) gathered")
            HStack(alignment: .top, spacing: 24) {
                ForEach(0..<columns) { column in
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(min(count, column * perColumn)..<min(count, (column + 1) * perColumn)) { index in
                            IngredientRow(
                                quantity: cookbook.quantity(of: recipe.ingredients[index], in: recipe),
                                name: recipe.ingredients[index].name,
                                tint: recipe.tint,
                                isGathered: cookbook.isGathered(index, of: recipe)
                            )
                            .onTapGesture { cookbook.toggleGathered(index, of: recipe) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }
}

@View
struct IngredientRow {
    let quantity: String
    let name: String
    let tint: Color
    let isGathered: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().stroke(isGathered ? .color(tint) : Theme.track, lineWidth: 2)
                if isGathered {
                    Circle().fill(tint).padding(5)
                }
            }
            .frame(width: 18, height: 18)
            Text(quantity)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isGathered ? Theme.faint : Theme.ink)
            Text(name)
                .font(.system(size: 15))
                .foregroundStyle(isGathered ? Theme.faint : Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

/// The steps, each ticked off with a click, beside a rail that fills down
/// to the step being read.
///
/// Every row reports two things about where it is. Its dot's centre, in the
/// steps' own space — `.named("steps")`, given to the stack that holds the
/// rail and the rows — is where the rail is drawn to; it only changes when
/// the column does. Whether its top has passed the reading line — 40% down
/// the visible part of the scroll view, its frame there against the
/// scroll view's bounds — changes as the page scrolls.
@View
struct Method {
    let cookbook: Cookbook
    let recipe: Recipe
    let current: Int
    @Binding var passed: Set<Int>
    @Binding var dotCenters: [Int: Double]

    var body: some View {
        let dotOffset = StepRow.padding + StepRow.badgeSize / 2
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Method", detail: "\(cookbook.doneCount(of: recipe)) of \(recipe.steps.count) done")
            ZStack(alignment: .topLeading) {
                StepRail(
                    tint: recipe.tint,
                    first: dotCenters[0],
                    last: dotCenters[recipe.steps.count - 1],
                    reached: dotCenters[current],
                    x: dotOffset
                )
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<recipe.steps.count) { index in
                        StepRow(
                            number: index + 1,
                            step: recipe.steps[index],
                            tint: recipe.tint,
                            isDone: cookbook.isDone(index, of: recipe),
                            isCurrent: index == current
                        )
                        .onTapGesture { cookbook.toggleDone(index, of: recipe) }
                        .onGeometryChange(for: Double.self) { proxy in
                            proxy.frame(in: .named("steps")).minY + dotOffset
                        } action: { center in
                            dotCenters[index] = center
                        }
                        .onGeometryChange(for: Bool.self) { proxy in
                            let visible = proxy.bounds(of: .scrollView)?.height ?? 0
                            return proxy.frame(in: .scrollView).minY < visible * 0.4
                        } action: { isPast in
                            if isPast {
                                passed.insert(index)
                            } else {
                                passed.remove(index)
                            }
                        }
                    }
                }
            }
            .coordinateSpace(.named("steps"))
        }
    }
}

/// A line from the first step's dot to the last, filled down to the dot of
/// the step being read. Nothing until the dots have been measured.
@View
struct StepRail {
    let tint: Color
    let first: Double?
    let last: Double?
    let reached: Double?
    /// Across the steps' space, the dots' centre.
    let x: Double

    var body: some View {
        if let first, let last, last > first {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Theme.track)
                    .frame(width: 2, height: last - first)
                Rectangle()
                    .fill(tint)
                    .frame(width: 2, height: max(0, (reached ?? first) - first))
                    .animation(.easeOut(duration: 0.25), value: reached)
            }
            .offset(x: x - 1, y: first)
        }
    }
}

@View
struct StepRow {
    static let padding = 12.0
    static let badgeSize = 28.0

    let number: Int
    let step: Step
    let tint: Color
    let isDone: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(isDone ? .color(tint) : Theme.paper)
                Circle().stroke(isDone || isCurrent ? .color(tint) : Theme.track, lineWidth: 2)
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isDone ? .color(.white) : isCurrent ? .color(tint) : Theme.faint)
            }
            .frame(width: Self.badgeSize, height: Self.badgeSize)
            VStack(alignment: .leading, spacing: 8) {
                Text(step.text)
                    .font(.system(size: 16))
                    .foregroundStyle(isDone ? Theme.faint : Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let minutes = step.minutes {
                    Text("\(minutes) min")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tint)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(tint.opacity(0.14))
                        .cornerRadius(10)
                }
            }
            .padding(.top, 4)
        }
        .padding(Self.padding)
        .background(isCurrent ? tint.opacity(0.08) : Color.clear)
        .cornerRadius(12)
        .contentShape(Rectangle())
    }
}

/// Over the top of the page once its header has gone: the recipe, the
/// step being read, and how far through the method that is.
@View
struct CompactBar {
    let recipe: Recipe
    let current: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .fill(recipe.tint)
                    .frame(width: 10, height: 10)
                Text(recipe.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Step \(current + 1) of \(recipe.steps.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(recipe.tint)
            }
            .padding(.horizontal, 20)
            .frame(height: RecipePage.barHeight - 3)
            ProgressLine(fraction: Double(current + 1) / Double(recipe.steps.count), tint: recipe.tint)
                .frame(height: 3)
        }
        .background(Theme.bar)
    }
}

/// A track filled `fraction` of its width — the width read from a
/// `GeometryReader`.
@View
struct ProgressLine {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.track)
                Rectangle()
                    .fill(tint)
                    .frame(width: proxy.size.width * fraction)
                    .animation(.easeOut(duration: 0.25), value: fraction)
            }
        }
    }
}
