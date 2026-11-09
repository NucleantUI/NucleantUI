//
//  SpringTests.swift
//  NucleantUITests
//
//  `Spring` stored and evaluated as SwiftUI's is: its initializers, the
//  clamp to critical damping, and how long it takes to settle.
//

import Foundation
import Testing
@testable import NucleantUI

@Suite
struct SpringTests {

    private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    @Test func durationAndBounceRoundTrip() {
        for bounce in [-0.5, -0.2, 0, 0.15, 0.3, 0.7] {
            let spring = Spring(duration: 0.4, bounce: bounce)
            #expect(close(spring.duration, 0.4))
            #expect(close(spring.bounce, bounce))
        }
    }

    @Test func bounceMapsToTheDampingRatio() {
        #expect(close(Spring(duration: 1, bounce: 0).dampingRatio, 1))
        #expect(close(Spring(duration: 1, bounce: 0.3).dampingRatio, 0.7))
        #expect(close(Spring(duration: 1, bounce: -0.5).dampingRatio, 2))
        #expect(close(Spring(duration: 1, bounce: 2).dampingRatio, 0))
    }

    @Test func physicalParametersRoundTrip() {
        let spring = Spring(mass: 2, stiffness: 100, damping: 10)
        #expect(close(spring.mass, 2))
        #expect(close(spring.stiffness, 100))
        #expect(close(spring.damping, 10))
    }

    @Test func overdampingIsClampedToCriticalUnlessAllowed() {
        // ω₀ = 10, λ = 25: overdamped.
        let clamped = Spring(stiffness: 100, damping: 50)
        #expect(close(clamped.dampingRatio, 1))
        #expect(close(clamped.damping, 20))
        let allowed = Spring(stiffness: 100, damping: 50, allowOverDamping: true)
        #expect(close(allowed.dampingRatio, 2.5))
        #expect(close(allowed.damping, 50))
    }

    @Test func underdampedSettlingIsTheEnvelopeBound() {
        let spring = Spring(duration: 0.5, bounce: 0.3)
        let lambda = spring.dampingRatio * 2 * Double.pi / 0.5
        // A = |x| + |λx − v₀| with x = 1, v₀ = 0.
        #expect(close(spring.settlingDuration, -log(0.001 / (1 + lambda)) / lambda))
    }

    @Test func criticalAndOverdampedSettlingAreTenthsOfASecond() {
        for spring in [Spring(duration: 0.5, bounce: 0), Spring(duration: 0.5, bounce: -0.4)] {
            let tenths = spring.settlingDuration * 10
            #expect(close(tenths, tenths.rounded(), 1e-6))
            #expect(spring.settlingDuration > 0)
            // Within ε there, and from there on.
            let t = spring.settlingDuration
            #expect(abs(1 - spring.value(target: 1.0, time: t)) < 0.001)
            #expect(abs(1 - spring.value(target: 1.0, time: t + 1)) < 0.001)
        }
    }

    @Test func anUndampedSpringNeverSettles() {
        #expect(Spring(duration: 1, bounce: 1).settlingDuration == .infinity)
    }

    @Test func motionStartsAtZeroAndEndsAtTheTarget() {
        for spring in [Spring.smooth, .snappy, .bouncy, Spring(duration: 0.5, bounce: -0.5)] {
            #expect(close(spring.value(target: 3.0, time: 0), 0))
            #expect(close(spring.velocity(target: 3.0, time: 0), 0))
            #expect(close(spring.value(target: 3.0, time: 20), 3, 1e-6))
        }
    }

    @Test func velocityIsTheRateOfChangeOfValue() {
        for spring in [Spring.bouncy, .smooth, Spring(duration: 0.5, bounce: -0.5)] {
            let t = 0.2, h = 1e-6
            let slope = (spring.value(target: 1.0, initialVelocity: 2.0, time: t + h)
                - spring.value(target: 1.0, initialVelocity: 2.0, time: t - h)) / (2 * h)
            #expect(close(spring.velocity(target: 1.0, initialVelocity: 2.0, time: t), slope, 1e-4))
        }
    }

    @Test func updateFollowsTheSameMotion() {
        let spring = Spring.bouncy
        var value = 0.0, velocity = 0.0
        for _ in 0..<30 {
            spring.update(value: &value, velocity: &velocity, target: 1.0, deltaTime: 1.0 / 60)
        }
        #expect(close(value, spring.value(target: 1.0, time: 0.5), 1e-9))
    }

    @Test func theDefaultAnimationIsABouncelessHalfSecondSpring() {
        guard case .spring(let spring, _, _) = Animation.default.curve else {
            Issue.record("not a spring")
            return
        }
        #expect(close(spring.response, 0.5))
        #expect(close(spring.dampingRatio, 1))
    }

    @Test func aRunningAnimationEndsWhenTheMotionDoesNotAtTheBound() {
        for spring in [Spring(duration: 0.5, bounce: 0.3), Spring(duration: 0.5, bounce: 0.15), Spring(duration: 0.5), Spring(duration: 0.4, bounce: -0.3)] {
            let end = spring.endOfMotion(target: 1.0, epsilon: 0.001)
            let bound = spring.settlingDuration(target: 1.0, initialVelocity: 0.0, epsilon: 0.001)
            #expect(end <= bound)
            // A thousandth or more out a 120 Hz step before the end…
            #expect(abs(spring.value(target: 1.0, time: end - 1.0 / 120) - 1) >= 0.001)
            // …and within it from the end on.
            for step in 0..<240 {
                let time = end + Double(step) / 120
                #expect(abs(spring.value(target: 1.0, time: time) - 1) < 0.001)
            }
        }
        // A bounce of 0.3 over 0.5 s: the bound is a fifth past the motion.
        let bouncy = Spring(duration: 0.5, bounce: 0.3)
        #expect(bouncy.endOfMotion(target: 1.0, epsilon: 0.001) < 0.85)
        #expect(bouncy.settlingDuration > 1)
    }
}
