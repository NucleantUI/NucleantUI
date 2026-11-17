//
//  UnitCurveTests.swift
//  NucleantUITests
//

import Foundation
import Testing
@testable import NucleantUI

struct UnitCurveTests {

    static let curves: [UnitCurve] = [
        .linear, .easeIn, .easeOut, .easeInOut,
        .circularEaseIn, .circularEaseOut, .circularEaseInOut,
        .bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.8), endControlPoint: UnitPoint(x: 0.9, y: 0.1)),
    ]

    @Test(arguments: UnitCurveTests.curves)
    func everyCurveRunsFromZeroToOne(curve: UnitCurve) {
        #expect(abs(curve.value(at: 0)) < 1e-6)
        #expect(abs(curve.value(at: 1) - 1) < 1e-6)
    }

    @Test(arguments: UnitCurveTests.curves)
    func progressOutsideZeroToOneIsClamped(curve: UnitCurve) {
        #expect(curve.value(at: -2) == curve.value(at: 0))
        #expect(curve.value(at: 3) == curve.value(at: 1))
    }

    @Test(arguments: UnitCurveTests.curves, [0.1, 0.35, 0.6, 0.9])
    func theInverseUndoesTheCurve(curve: UnitCurve, progress: Double) {
        let value = curve.value(at: progress)
        #expect(abs(curve.inverse.value(at: value) - progress) < 1e-4)
    }

    @Test func theLinearCurveIsItsInputAtSpeedOne() {
        #expect(UnitCurve.linear.value(at: 0.37) == 0.37)
        #expect(abs(UnitCurve.linear.velocity(at: 0.5) - 1) < 1e-6)
    }

    @Test func easingInIsBehindLinearEarlyAndEasingOutAhead() {
        #expect(UnitCurve.easeIn.value(at: 0.25) < 0.25)
        #expect(UnitCurve.easeOut.value(at: 0.25) > 0.25)
        #expect(UnitCurve.circularEaseIn.value(at: 0.25) < 0.25)
        #expect(UnitCurve.circularEaseOut.value(at: 0.25) > 0.25)
    }

    @Test(arguments: [UnitCurve.easeInOut, .circularEaseInOut])
    func easingInAndOutIsHalfwayAtHalfTimeAndSymmetric(curve: UnitCurve) {
        #expect(abs(curve.value(at: 0.5) - 0.5) < 1e-6)
        #expect(abs(curve.value(at: 0.2) + curve.value(at: 0.8) - 1) < 1e-6)
    }

    @Test func easingInStartsSlowerThanItEnds() {
        #expect(UnitCurve.easeIn.velocity(at: 0.05) < UnitCurve.easeIn.velocity(at: 0.95))
    }

    @Test func controlPointsOutsideZeroToOneAcrossAreClamped() {
        let clamped = UnitCurve.bezier(startControlPoint: UnitPoint(x: -1, y: 0), endControlPoint: UnitPoint(x: 2, y: 1))
        #expect(clamped == .bezier(startControlPoint: UnitPoint(x: 0, y: 0), endControlPoint: UnitPoint(x: 1, y: 1)))
    }
}
