//
//  Recipes.swift
//  Recipes
//
//  The book: five recipes, each long enough to scroll through.
//

import NucleantUI

extension Recipe {
    static let book: [Recipe] = [
        Recipe(
            id: 1,
            title: "Shakshuka",
            subtitle: "Eggs poached in a smoky pepper and tomato sauce",
            cuisine: "North African",
            servings: 4,
            minutes: 40,
            tint: Color(hex: 0xD9502F),
            shade: Color(hex: 0x8E2A1E),
            ingredients: [
                Ingredient(amount: 2, unit: "tbsp", name: "olive oil"),
                Ingredient(amount: 1, unit: "", name: "onion, sliced"),
                Ingredient(amount: 2, unit: "", name: "red peppers, sliced"),
                Ingredient(amount: 3, unit: "", name: "garlic cloves"),
                Ingredient(amount: 1.5, unit: "tsp", name: "smoked paprika"),
                Ingredient(amount: 1, unit: "tsp", name: "ground cumin"),
                Ingredient(amount: 800, unit: "g", name: "chopped tomatoes"),
                Ingredient(amount: 6, unit: "", name: "eggs"),
                Ingredient(amount: 100, unit: "g", name: "feta"),
                Ingredient(amount: nil, unit: "", name: "parsley and bread, to serve"),
            ],
            steps: [
                Step(text: "Warm the oil in a wide, deep pan over a medium heat. Add the onion and peppers with a pinch of salt.", minutes: nil),
                Step(text: "Cook, stirring now and then, until soft and sweet and just starting to colour.", minutes: 12),
                Step(text: "Stir in the garlic, paprika and cumin and cook for a minute, until it smells toasty.", minutes: 1),
                Step(text: "Tip in the tomatoes, season, and simmer until thick enough that a spoon dragged through leaves a trail.", minutes: 10),
                Step(text: "Make six hollows in the sauce with the back of a spoon and crack an egg into each.", minutes: nil),
                Step(text: "Cover and cook on a low heat until the whites are set and the yolks still soft.", minutes: 7),
                Step(text: "Crumble over the feta, scatter with parsley, and bring the pan to the table with bread for mopping.", minutes: nil),
            ]
        ),
        Recipe(
            id: 2,
            title: "Mushroom Risotto",
            subtitle: "Creamy rice with browned mushrooms and parmesan",
            cuisine: "Italian",
            servings: 4,
            minutes: 45,
            tint: Color(hex: 0xB48A3C),
            shade: Color(hex: 0x5E4520),
            ingredients: [
                Ingredient(amount: 1.25, unit: "l", name: "hot vegetable stock"),
                Ingredient(amount: 400, unit: "g", name: "mixed mushrooms"),
                Ingredient(amount: 3, unit: "tbsp", name: "butter"),
                Ingredient(amount: 1, unit: "", name: "shallot, finely chopped"),
                Ingredient(amount: 2, unit: "", name: "garlic cloves"),
                Ingredient(amount: 320, unit: "g", name: "risotto rice"),
                Ingredient(amount: 150, unit: "ml", name: "dry white wine"),
                Ingredient(amount: 60, unit: "g", name: "parmesan, grated"),
                Ingredient(amount: nil, unit: "", name: "thyme leaves"),
            ],
            steps: [
                Step(text: "Keep the stock at a bare simmer in a pan at the back of the stove.", minutes: nil),
                Step(text: "Brown the mushrooms in a tablespoon of butter in a hot, dry pan, in batches so they fry rather than steam. Set aside.", minutes: 8),
                Step(text: "Melt another tablespoon of butter and soften the shallot and garlic without letting them colour.", minutes: 4),
                Step(text: "Add the rice and stir until every grain is glossy and the edges turn translucent.", minutes: 2),
                Step(text: "Pour in the wine and let it bubble away almost completely.", minutes: 2),
                Step(text: "Add the stock a ladle at a time, stirring, waiting until each is nearly absorbed before the next.", minutes: 18),
                Step(text: "When the rice is tender with a little bite, take it off the heat. Beat in the last of the butter and the parmesan.", minutes: nil),
                Step(text: "Fold through the mushrooms and thyme, cover, and rest for two minutes before serving.", minutes: 2),
            ]
        ),
        Recipe(
            id: 3,
            title: "Green Curry",
            subtitle: "Chicken and aubergine in a fragrant coconut sauce",
            cuisine: "Thai",
            servings: 4,
            minutes: 35,
            tint: Color(hex: 0x4E9A52),
            shade: Color(hex: 0x24562C),
            ingredients: [
                Ingredient(amount: 1, unit: "tbsp", name: "neutral oil"),
                Ingredient(amount: 3, unit: "tbsp", name: "green curry paste"),
                Ingredient(amount: 400, unit: "ml", name: "coconut milk"),
                Ingredient(amount: 500, unit: "g", name: "chicken thighs, sliced"),
                Ingredient(amount: 2, unit: "", name: "small aubergines, cubed"),
                Ingredient(amount: 4, unit: "", name: "makrut lime leaves"),
                Ingredient(amount: 1.5, unit: "tbsp", name: "fish sauce"),
                Ingredient(amount: 2, unit: "tsp", name: "palm sugar"),
                Ingredient(amount: nil, unit: "", name: "Thai basil and rice, to serve"),
            ],
            steps: [
                Step(text: "Spoon the thick cream off the top of the coconut milk into a hot wok with the oil.", minutes: nil),
                Step(text: "Fry the cream until the oil splits out of it, then add the curry paste and fry until fragrant.", minutes: 3),
                Step(text: "Add the chicken and turn it in the paste until it is coated and no longer pink outside.", minutes: 3),
                Step(text: "Pour in the rest of the coconut milk with the lime leaves and aubergine.", minutes: nil),
                Step(text: "Simmer until the chicken is cooked through and the aubergine is soft.", minutes: 12),
                Step(text: "Season with the fish sauce and sugar — it should be hot, salty and a little sweet.", minutes: nil),
                Step(text: "Tear in the basil and serve with jasmine rice.", minutes: nil),
            ]
        ),
        Recipe(
            id: 4,
            title: "Blueberry Pancakes",
            subtitle: "Thick, fluffy pancakes with lemon and berries",
            cuisine: "Breakfast",
            servings: 2,
            minutes: 25,
            tint: Color(hex: 0x4E6FC4),
            shade: Color(hex: 0x2A3B78),
            ingredients: [
                Ingredient(amount: 150, unit: "g", name: "plain flour"),
                Ingredient(amount: 1.5, unit: "tsp", name: "baking powder"),
                Ingredient(amount: 1, unit: "tbsp", name: "sugar"),
                Ingredient(amount: 0.25, unit: "tsp", name: "salt"),
                Ingredient(amount: 1, unit: "", name: "egg"),
                Ingredient(amount: 180, unit: "ml", name: "milk"),
                Ingredient(amount: 2, unit: "tbsp", name: "melted butter"),
                Ingredient(amount: 0.5, unit: "", name: "lemon, zested"),
                Ingredient(amount: 120, unit: "g", name: "blueberries"),
                Ingredient(amount: nil, unit: "", name: "maple syrup"),
            ],
            steps: [
                Step(text: "Whisk the flour, baking powder, sugar, salt and lemon zest together in a large bowl.", minutes: nil),
                Step(text: "Beat the egg into the milk and melted butter in a jug.", minutes: nil),
                Step(text: "Pour the wet into the dry and fold just until combined — a few lumps are what keep them light.", minutes: nil),
                Step(text: "Leave the batter to stand while the pan heats.", minutes: 5),
                Step(text: "Ladle rounds into a lightly buttered pan over a medium heat and drop a few blueberries onto each.", minutes: nil),
                Step(text: "Flip when bubbles cover the top and the edges look set, then cook the other side until golden.", minutes: 3),
                Step(text: "Keep them warm in a low oven while you cook the rest, and serve in a stack with maple syrup.", minutes: nil),
            ]
        ),
        Recipe(
            id: 5,
            title: "Miso Ramen",
            subtitle: "A rich miso broth with noodles, egg and greens",
            cuisine: "Japanese",
            servings: 2,
            minutes: 30,
            tint: Color(hex: 0xC27A2C),
            shade: Color(hex: 0x6B3B14),
            ingredients: [
                Ingredient(amount: 2, unit: "", name: "eggs"),
                Ingredient(amount: 1, unit: "tbsp", name: "sesame oil"),
                Ingredient(amount: 2, unit: "", name: "garlic cloves, grated"),
                Ingredient(amount: 1, unit: "tbsp", name: "ginger, grated"),
                Ingredient(amount: 900, unit: "ml", name: "chicken stock"),
                Ingredient(amount: 3, unit: "tbsp", name: "white miso"),
                Ingredient(amount: 1, unit: "tbsp", name: "soy sauce"),
                Ingredient(amount: 200, unit: "g", name: "ramen noodles"),
                Ingredient(amount: 2, unit: "", name: "pak choi, halved"),
                Ingredient(amount: nil, unit: "", name: "spring onion and chilli oil"),
            ],
            steps: [
                Step(text: "Lower the eggs into boiling water and cook for six and a half minutes, then cool them in iced water and peel.", minutes: 7),
                Step(text: "Warm the sesame oil in a pot and fry the garlic and ginger until fragrant.", minutes: 1),
                Step(text: "Pour in the stock and bring it to a simmer.", minutes: 5),
                Step(text: "Loosen the miso with a ladle of the hot stock in a bowl, then stir it back into the pot with the soy sauce. Don't let it boil from here.", minutes: nil),
                Step(text: "Cook the noodles, adding the pak choi for the last minute.", minutes: 3),
                Step(text: "Divide the noodles and greens between deep bowls and pour over the broth.", minutes: nil),
                Step(text: "Top with a halved egg, spring onion and a spoon of chilli oil.", minutes: nil),
            ]
        ),
    ]
}
