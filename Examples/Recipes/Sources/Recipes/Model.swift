//
//  Model.swift
//  Recipes
//
//  The cookbook: its recipes, the one open, the servings each is scaled to,
//  the ingredients gathered and the steps done. `Cookbook` is the
//  `@Observable` model, changed only through its methods; a `Recipe`, its
//  `Ingredient`s and its `Step`s are the records inside it.
//

import NucleantUI
import Observation

struct Ingredient: Equatable {
    /// For the recipe's own servings; `nil` for "to taste".
    let amount: Double?
    /// "g", "ml", "tbsp" — empty for a count ("2 onions").
    let unit: String
    let name: String
}

struct Step: Equatable {
    let text: String
    /// How long it takes, for a step that is mostly waiting.
    let minutes: Int?
}

struct Recipe: Identifiable, Equatable {
    let id: Int
    let title: String
    let subtitle: String
    let cuisine: String
    /// The servings the amounts are written for.
    let servings: Int
    let minutes: Int
    /// The header: a field shading from `tint` to `shade`. Fixed colors —
    /// a recipe's colors are the same in the dark.
    let tint: Color
    let shade: Color
    let ingredients: [Ingredient]
    let steps: [Step]
}

@MainActor
@Observable
final class Cookbook {
    let recipes: [Recipe]

    private(set) var selectedID: Recipe.ID

    /// Servings a recipe is scaled to, where they differ from its own.
    private(set) var servings: [Recipe.ID: Int] = [:]

    /// Ingredients ticked off as gathered, and steps as done, by index.
    private(set) var gathered: [Recipe.ID: Set<Int>] = [:]
    private(set) var done: [Recipe.ID: Set<Int>] = [:]

    static let servingRange = 1...12

    init(recipes: [Recipe] = Recipe.book) {
        self.recipes = recipes
        selectedID = recipes[0].id
    }

    var selected: Recipe {
        recipes.first { $0.id == selectedID }!
    }

    func select(_ recipe: Recipe) {
        selectedID = recipe.id
    }

    func servings(of recipe: Recipe) -> Int {
        servings[recipe.id] ?? recipe.servings
    }

    func setServings(_ count: Int, for recipe: Recipe) {
        servings[recipe.id] = min(max(count, Self.servingRange.lowerBound), Self.servingRange.upperBound)
    }

    /// "400 g", "1½ tbsp", "3" — the amount for the servings chosen.
    func quantity(of ingredient: Ingredient, in recipe: Recipe) -> String {
        guard let amount = ingredient.amount else { return "to taste" }
        let scaled = amount * Double(servings(of: recipe)) / Double(recipe.servings)
        let number = Self.format(scaled)
        return ingredient.unit.isEmpty ? number : "\(number) \(ingredient.unit)"
    }

    /// Whole numbers whole, quarters and halves as fractions, the rest to
    /// one place — and whole above ten, where a fraction is noise.
    private static func format(_ value: Double) -> String {
        if value >= 10 { return "\(Int(value.rounded()))" }
        let whole = Int(value)
        let fraction = value - Double(whole)
        let glyphs: [(Double, String)] = [(0.25, "¼"), (0.5, "½"), (0.75, "¾")]
        if fraction < 0.05 { return "\(whole)" }
        if fraction > 0.95 { return "\(whole + 1)" }
        if let glyph = glyphs.first(where: { abs($0.0 - fraction) < 0.05 })?.1 {
            return whole == 0 ? glyph : "\(whole)\(glyph)"
        }
        let tenths = (value * 10).rounded() / 10
        return "\(tenths)"
    }

    func isGathered(_ index: Int, of recipe: Recipe) -> Bool {
        gathered[recipe.id]?.contains(index) ?? false
    }

    func toggleGathered(_ index: Int, of recipe: Recipe) {
        if isGathered(index, of: recipe) {
            gathered[recipe.id]?.remove(index)
        } else {
            gathered[recipe.id, default: []].insert(index)
        }
    }

    func gatheredCount(of recipe: Recipe) -> Int {
        gathered[recipe.id]?.count ?? 0
    }

    func isDone(_ index: Int, of recipe: Recipe) -> Bool {
        done[recipe.id]?.contains(index) ?? false
    }

    func toggleDone(_ index: Int, of recipe: Recipe) {
        if isDone(index, of: recipe) {
            done[recipe.id]?.remove(index)
        } else {
            done[recipe.id, default: []].insert(index)
        }
    }

    func doneCount(of recipe: Recipe) -> Int {
        done[recipe.id]?.count ?? 0
    }

    /// Clear the ticks, for cooking it again.
    func startOver(_ recipe: Recipe) {
        gathered[recipe.id] = nil
        done[recipe.id] = nil
    }
}
