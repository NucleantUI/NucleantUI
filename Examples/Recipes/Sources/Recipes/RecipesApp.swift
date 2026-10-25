//
//  RecipesApp.swift
//  Recipes
//
//  A cookbook whose layout comes from where things are, through the
//  geometry API:
//
//  * The window is a `GeometryReader`: wide enough, the recipes are a
//    sidebar beside the page; narrower, they are a strip of chips over it.
//    Drag the window's edge across 760 points and it rearranges.
//  * The page's header reads its own frame in the scroll view
//    (`proxy.frame(in: .scrollView)`) and draws its art and title sliding
//    up slower than the page, fading as they go.
//  * A compact bar fades in once the header's title has scrolled under the
//    top edge — `.onGeometryChange` handing old and new, so the change is
//    animated and the first placement is not.
//  * The ingredients are as many columns as the page's measured width
//    holds, and the page ends with room enough for the last step to reach
//    the reading line — both measured with `.onGeometryChange`.
//  * The step being read is the last one whose top has passed a line 40%
//    down the visible part of the scroll view (`frame(in: .scrollView)`
//    against `bounds(of: .scrollView)`); the bar counts it, and a rail
//    beside the steps fills down to its dot — each dot measured in the
//    steps' own named space, `.coordinateSpace(.named("steps"))`.
//

import NucleantUI

enum Theme {
    static let paper = Color.dynamic(light: Color(hex: 0xFAF7F2), dark: Color(hex: 0x17181B))
    static let sidebar = Color.dynamic(light: Color(hex: 0xF0EBE3), dark: Color(hex: 0x1F2024))
    static let card = Color.dynamic(light: Color.white, dark: Color(hex: 0x24262B))
    static let ink = Color.dynamic(light: Color(hex: 0x2B2723), dark: Color(hex: 0xE3DED6))
    static let faint = Color.dynamic(light: Color(white: 0, opacity: 0.45), dark: Color(white: 1, opacity: 0.45))
    static let track = Color.dynamic(light: Color(hex: 0xE3DED6), dark: Color(hex: 0x34363B))
    static let bar = Color.dynamic(light: Color(hex: 0xFAF7F2, opacity: 0.97), dark: Color(hex: 0x17181B, opacity: 0.97))
}

@main
struct RecipesApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Recipes") {
            RootView()
        }
        .defaultSize(width: 980, height: 760)
        .commands { AppearanceCommands() }
    }
}

/// Owns the cookbook, lays the window out for its width, and applies the
/// chosen appearance under itself.
@View
struct RootView {
    @State private var cookbook = Cookbook()
    @Environment(\.colorScheme) private var system

    /// Wide enough for the list beside the page.
    static let sidebarWidth = 760.0

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= Self.sidebarWidth {
                HStack(spacing: 0) {
                    RecipeList(cookbook: cookbook)
                        .frame(width: 290)
                    Divider()
                    OpenRecipe(cookbook: cookbook)
                }
            } else {
                VStack(spacing: 0) {
                    RecipeStrip(cookbook: cookbook)
                    Divider()
                    OpenRecipe(cookbook: cookbook)
                }
            }
        }
        .background(Theme.paper)
        .colorScheme(AppearanceModel.shared.appearance.scheme ?? system)
    }
}

/// The selected recipe's page — a fresh one for each recipe, through a
/// one-element `ForEach` keyed by it, so a newly opened recipe starts at
/// its top.
@View
struct OpenRecipe {
    let cookbook: Cookbook

    var body: some View {
        ForEach([cookbook.selected]) { recipe in
            RecipePage(cookbook: cookbook, recipe: recipe)
        }
    }
}

/// The recipes down the side.
@View
struct RecipeList {
    let cookbook: Cookbook

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recipes")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(cookbook.recipes) { recipe in
                        RecipeRow(recipe: recipe, isSelected: recipe.id == cookbook.selectedID)
                            .onTapGesture { cookbook.select(recipe) }
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .background(Theme.sidebar)
    }
}

@View
struct RecipeRow {
    let recipe: Recipe
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.linearGradient(colors: [recipe.tint, recipe.shade], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                Text("\(recipe.cuisine) · \(recipe.minutes) min")
                    .font(.footnote)
                    .foregroundColor(Theme.faint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(isSelected ? Theme.card : Color.clear)
        .cornerRadius(10)
        .contentShape(Rectangle())
    }
}

/// The recipes as a row of chips, for a window too narrow for the list.
@View
struct RecipeStrip {
    let cookbook: Cookbook

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(cookbook.recipes) { recipe in
                    RecipeChip(recipe: recipe, isSelected: recipe.id == cookbook.selectedID)
                        .onTapGesture { cookbook.select(recipe) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: 60)
        .background(Theme.sidebar)
    }
}

@View
struct RecipeChip {
    let recipe: Recipe
    let isSelected: Bool

    var body: some View {
        Text(recipe.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(isSelected ? Color.white : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(isSelected ? recipe.tint : Theme.card)
            .cornerRadius(17)
    }
}
